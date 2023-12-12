`ifndef MemCtrl
`define MemCtrl
`include "define.v"

module MemCtrl (
    // control signals
    input wire clk,
    input wire rdy,
    input wire rst,
    // When the ROB jump wrong, the reading or writing should be halted
    input wire jump_wrong,

    // from and to LSB
    // LSB write and read memory, separately using two signals
    input wire lsb_write_signal,
    input wire lsb_read_signal,
    input wire [`ADDR] lsb_addr,
    input wire [`LSBINSTRLEN] lsb_len,//表示的是这个ls指令涉及了多少位，32、16、8分别对应3、2、1
    input wire [`DATALEN] lsb_write_data,
    output reg [`DATALEN] lsb_read_data,
    output reg lsb_load_success,
    output reg lsb_store_success,

    //from ICache
    // ICache read from memory
    //一次读一个byte，所以一个地址读四次
    //发现的bug是cache到memctrl的address传达的不及时，根本问题是start_addr传的不及时
    input wire [`ADDR] icache_addr,
    input wire icache_read_signal,
    output reg [`INSTRLEN] icache_read_instr,
    output reg icache_success,

    // from and to RAM
    input wire io_buffer_full,
    output reg [`ADDR] mem_addr,
    output reg [`BYTELEN] mem_byte_write,
    input wire [`BYTELEN] mem_byte_read,
    output reg read_write,
    output reg mem_enable
    );

reg working;
reg for_lsb_ic;//0 for lsb, 1 for icache;
reg [`ADDR] start_addr;
reg [`ADDR] new_addr;
reg [`LSBINSTRLEN]requiring_len;
reg [`DATALEN] ultimate_data;//storing the result while processing
reg [2:0] finished;//result processed,00,01,10,11
reg  new_addr_assigned_to_start_addr;
reg [`ADDR] tmp_check_new_addr;
reg [`BYTELEN]debug_byte_read;
integer debug_enable_mem;
integer debug_wr_change;
integer count_after_finish;
always @(posedge clk) begin
    if(rst == `TRUE || jump_wrong==`TRUE) begin
        working <= `FALSE;
        mem_enable <= `FALSE;
        icache_success <= `FALSE;
        lsb_load_success <= `FALSE;
        lsb_store_success <= `FALSE;
         new_addr_assigned_to_start_addr <= `FALSE;
        icache_success <= `FALSE;//这里只有不成功后面才不会有隐患，要不然拿到if说成功了if就会给predictor，就会传回jump_pc让if出错
        count_after_finish <= 0;
    end else if (rdy == `TRUE) begin
        // There is an instruction on operation so it cannot begin a new instruction.
        tmp_check_new_addr = new_addr;
        new_addr = ((lsb_read_signal==`TRUE||lsb_write_signal==`TRUE)?lsb_addr:((icache_read_signal==`TRUE)?icache_addr:`NULL32));
        if(new_addr != tmp_check_new_addr) begin
             new_addr_assigned_to_start_addr = `FALSE;//新的这个addr还没有完成
        end
        if(working==`TRUE) begin
            // 如果是向IO进行读写就不应该再把地址加一加二操作了。
            if(mem_addr[17:16]==2'b11) begin
                if(lsb_read_signal==`TRUE) begin //I/O read
                //load word/half word/ byte
                    if(finished == requiring_len) begin
                        //requiring length has been read
                        if(for_lsb_ic == 0) begin 
                            if(requiring_len == `REQUIRE8)begin
                                ultimate_data[7:0] <= mem_byte_read;
                                lsb_read_data[7:0] <= mem_byte_read;
                                lsb_read_data[31:8] <= 24'b0;
                                ultimate_data[31:8] <= 24'b0;
                            end else if(requiring_len == `REQUIRE16) begin
                                ultimate_data[15:8] <= mem_byte_read;
                                lsb_read_data[7:0]            <= ultimate_data[7:0];
                                lsb_read_data[15:8]            <= mem_byte_read;
                                lsb_read_data[31:16] <= 16'b0;
                                ultimate_data[31:16] <= 16'b0;
                            end else begin
                                ultimate_data[31:24] <= mem_byte_read;
                                lsb_read_data[23:0]            <= ultimate_data[23:0];
                                lsb_read_data[31:24]            <= mem_byte_read;
                            end
                            lsb_load_success              <= `TRUE;
                            icache_success           <= `FALSE;
                        end else begin
                            ultimate_data[31:24] <= mem_byte_read;
                            icache_read_instr[23:0]        <= ultimate_data[23:0];
                            icache_read_instr[31:24]       <= mem_byte_read;
                            debug_byte_read          <= mem_byte_read;
                            icache_success           <= `TRUE;
                            lsb_load_success              <= `FALSE;
                        end
                        working                      <= `FALSE;
                        //mem_addr                     = start_addr;
                        mem_enable                   <= `FALSE;
                        //ultimate_data                = `NULL32;
                        mem_byte_write               <= `NULL8;
                    end else begin
                        lsb_load_success                  <= `FALSE;
                        icache_success               <= `FALSE;
                        mem_byte_write               <= `NULL8;
                        case(finished)
                            3'b000: begin
                                mem_enable           <= `TRUE;
                            end
                            3'b001: begin
                                ultimate_data[7:0]   <= mem_byte_read;
                                mem_enable           <= `TRUE;
                            end
                            3'b010: begin
                                ultimate_data[15:8]  <= mem_byte_read;
                                mem_enable           <= `TRUE;
                            end
                            3'b011: begin
                                //mem_addr             <= start_addr;
                                ultimate_data[23:16] <= mem_byte_read;
                                mem_enable           <= `FALSE;
                            end
                            default: begin end
                        endcase
                        finished                     <= finished + 1;
                    end
                end else begin //I/O write, that is lsb wirte into memory
                //Store word/half word/byte
                    if(finished == requiring_len - 3'b001) begin
                        if(count_after_finish == 0) begin
                            icache_success <= `FALSE;
                            lsb_store_success <= `FALSE;
                            lsb_load_success <= `FALSE;
                            working <= `TRUE;
                            mem_enable <= `FALSE;
                            mem_byte_write <= `NULL8;
                            count_after_finish <= 1;
                        end else if(count_after_finish == 1) begin
                            icache_success <= `FALSE;
                            lsb_store_success <= `FALSE;
                            lsb_load_success <= `FALSE;
                            working <= `TRUE;
                            mem_enable <= `FALSE;
                            mem_byte_write <= `NULL8;
                            count_after_finish <= 2;
                        end else if(count_after_finish == 2)begin
                            icache_success               <= `FALSE;
                            lsb_store_success                  <= `TRUE;
                            lsb_load_success <= `FALSE;
                            working                      <= `FALSE;
                            //mem_addr                     <= start_addr;
                            mem_enable                   <= `FALSE;
                            mem_byte_write               <= `NULL8;
                            ultimate_data                <= `NULL32;
                            count_after_finish <= 0;
                        end
                    end else begin
                        lsb_store_success            <= `FALSE;
                        case(finished)
                            3'b000: begin
                                mem_byte_write       <= lsb_write_data[15:8];
                                mem_enable           <= `TRUE;
                            end
                            3'b001: begin
                                mem_byte_write       <= lsb_write_data[23:16];
                                mem_enable           <= `TRUE;
                            end
                            3'b010: begin
                                mem_byte_write       <= lsb_write_data[31:24];
                                mem_enable           <= `FALSE;
                            end
                            default: begin end
                        endcase
                        finished                     <= finished + 3'b001;
                    end
                end
            end
            else begin
                if(read_write == `READ) begin //read
                    if(finished == requiring_len) begin
                        //requiring length has been read
                        if(for_lsb_ic == 0) begin 
                            if(requiring_len == `REQUIRE8)begin
                                ultimate_data[7:0] <= mem_byte_read;
                                lsb_read_data[7:0] <= mem_byte_read;
                                lsb_read_data[31:8] <= 24'b0;
                                ultimate_data[31:8] <= 24'b0;
                            end else if(requiring_len == `REQUIRE16) begin
                                ultimate_data[15:8] <= mem_byte_read;
                                lsb_read_data[7:0]            <= ultimate_data[7:0];
                                lsb_read_data[15:8]            <= mem_byte_read;
                                lsb_read_data[31:16] <= 16'b0;
                                ultimate_data[31:16] <= 16'b0;
                            end else begin
                                ultimate_data[31:24] <= mem_byte_read;
                                lsb_read_data[23:0]            <= ultimate_data[23:0];
                                lsb_read_data[31:24]            <= mem_byte_read;
                            end
                            lsb_load_success              <= `TRUE;
                            icache_success           <= `FALSE;
                        end else begin
                            ultimate_data[31:24] <= mem_byte_read;
                            icache_read_instr[23:0]        <= ultimate_data[23:0];
                            icache_read_instr[31:24]       <= mem_byte_read;
                            debug_byte_read          <= mem_byte_read;
                            icache_success           <= `TRUE;
                            lsb_load_success              <= `FALSE;
                        end
                        working                      <= `FALSE;
                        //mem_addr                     = start_addr;
                        mem_enable                   <= `FALSE;
                        //ultimate_data                = `NULL32;
                        mem_byte_write               <= `NULL8;
                    end else begin
                        lsb_load_success                  <= `FALSE;
                        icache_success               <= `FALSE;
                        mem_byte_write               <= `NULL8;
                        case(finished)
                            3'b000: begin
                                mem_addr             <= start_addr + 1;
                                mem_enable           <= `TRUE;
                            end
                            3'b001: begin
                                ultimate_data[7:0]   <= mem_byte_read;
                                mem_addr             <= start_addr + 2; 
                                mem_enable           <= `TRUE;
                            end
                            3'b010: begin
                                ultimate_data[15:8]  <= mem_byte_read;
                                mem_addr             <= start_addr + 3; 
                                mem_enable           <= `TRUE;
                            end
                            3'b011: begin
                                ultimate_data[23:16] <= mem_byte_read;
                                //mem_addr             <= `NULL32;
                                mem_enable           <= `FALSE;
                            end
                            default: begin end
                        endcase
                        finished                     <= finished + 1;
                    end
                end else begin //write
                    if(finished == requiring_len - 3'b001) begin
                        icache_success               <= `FALSE;
                        lsb_store_success                  <= `TRUE;
                        working                      <= `FALSE;
                        //mem_addr                     <= start_addr
                        mem_enable                   <= `FALSE;
                        //mem_byte_write               <= `NULL8;
                    end else begin
                        case(finished)
                            3'b000: begin
                                mem_byte_write       <= lsb_write_data[15:8];
                                mem_addr             <= start_addr + 1;
                                mem_enable           <= `TRUE;
                            end
                            3'b001: begin
                                mem_byte_write       <= lsb_write_data[23:16];
                                mem_addr             <= start_addr + 2;
                                mem_enable           <= `TRUE;
                            end
                            3'b010: begin
                                mem_byte_write       <= lsb_write_data[31:24];
                                mem_addr             <= start_addr + 3;
                                mem_enable           <= `TRUE;
                            end
                            default: begin end
                        endcase
                        finished                     <= finished + 1;
                    end
                end
            end
        end
        // Begin a new instruction.
        else begin
            if((lsb_read_signal == `TRUE || lsb_write_signal == `TRUE) && lsb_load_success == `FALSE && lsb_store_success == `FALSE &&  new_addr_assigned_to_start_addr == `FALSE) begin
                // if(lsb_addr==196608)begin
                //     $write("mem_ctrl get\t");
                // end
                if(lsb_read_signal == `TRUE) begin
                    ultimate_data                    <= `NULL32;
                    working                          <= `TRUE;
                    for_lsb_ic                       <= 1'b0;
                    //start_addr                       <= lsb_addr;
                    mem_addr                         <= new_addr;
                    start_addr                       <= new_addr;
                    new_addr_assigned_to_start_addr  <= `TRUE;
                    mem_enable                       <= `TRUE;
                    read_write                       <= `READ;
                    debug_wr_change <= 2;
                    //先读进来一个byte
                    requiring_len                    <= lsb_len;
                    finished                         <= 3'b000;
                    icache_success                   <= `FALSE;
                    lsb_load_success                      <= `FALSE;
                    lsb_store_success                     <= `FALSE;
                end else begin
                    //ultimate_data                    <= `NULL32;
                    working                          <= `TRUE;
                    for_lsb_ic                       <= 1'b0;
                    //start_addr                       <= lsb_addr;
                    read_write                       <= `WRITE;
                    debug_wr_change <= 3;
                    requiring_len                    <= lsb_len;
                    finished                         <= 3'b000;
                    icache_success                   <= `FALSE;
                    lsb_load_success                      <= `FALSE;
                    lsb_store_success                     <= `FALSE;
                    mem_addr                         <= new_addr;
                    start_addr                       <= new_addr;
                    new_addr_assigned_to_start_addr  <= `TRUE;
                    mem_enable                       <= `TRUE;
                    mem_byte_write                   <= lsb_write_data[7:0];
                    //先写入一个byte
                end
            end
            else if(icache_read_signal == `TRUE &&  new_addr_assigned_to_start_addr == `FALSE) begin
                icache_read_instr                    <= `NULL32;
                ultimate_data                        <= `NULL32;
                working                              <= `TRUE;
                for_lsb_ic                           <= 1'b1;//working for icache;
                //start_addr                           <= icache_addr;
                read_write                           <= `READ;
                mem_addr                             <= new_addr;//先读进来一个byte
                start_addr                           <= new_addr;
                new_addr_assigned_to_start_addr      <= `TRUE;
                mem_enable                           <= `TRUE;
                requiring_len                        <= `REQUIRE32;
                finished                             <= 3'b000;
                icache_success                       <= `FALSE;
                lsb_load_success                      <= `FALSE;
                lsb_store_success                     <= `FALSE;
            end
            else begin
                icache_success                       <= `FALSE;
                lsb_load_success                      <= `FALSE;
                lsb_store_success                     <= `FALSE;
                mem_addr                             <= `NULL32;
                mem_enable                           <= `FALSE;
                mem_byte_write                       <= `NULL8;
            end
        end
    end
end
endmodule
`endif
