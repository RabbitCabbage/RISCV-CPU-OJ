`ifndef LSB
`define LSB
`include "define.v"
`timescale 1ps/1ps
module LSB(
    //control signals
    input wire clk,
    input wire rdy,
    input wire rst,
    input wire jump_wrong,
    //to mem_ctrl 
    output reg lsb_read_signal,
    output reg lsb_write_signal,
    input wire[`INSTRLEN] commit_store_instr,
    output reg[`LSBINSTRLEN] requiring_length,
    output reg[`DATALEN] to_mem_data,
    output reg[`ADDR] to_mem_addr,
    input wire mem_load_success,
    input wire mem_store_success,
    input wire [`DATALEN] from_mem_data,

    //interact with decoder
    input wire decode_signal,
    input wire [`ROBINDEX] decoder_rs1_rename,
    input wire [`ROBINDEX] decoder_rs2_rename,
    input wire [`ROBINDEX] decoder_rd_rename,
    input wire [`DATALEN] decoder_rs1_value,
    input wire [`DATALEN] decoder_rs2_value,
    input wire [`IMMLEN] decoder_imm,
    input wire [`OPLEN] decoder_op,
    input wire decoder_enable,
    input wire [`ADDR] decoder_pc,

    //rob let lsb commit
    //todo
    //input wire rob_enable_lsb_read,
    input wire rob_enable_lsb_write,
    input wire [`ADDR] from_rob_addr,
    input wire [`LSBINSTRLEN] from_rob_length,
    input wire [`DATALEN] from_rob_data_to_store,
    output reg [`DATALEN] to_rob_data_loaded,

    //to rob, tell rob the addr has been calculated
    output reg lsb_calculated_addr_signal,
    output reg [`ADDR]lsb_destination_addr_to_rob,
    output reg [`ROBINDEX] lsb_rename_to_rob_for_the_calculated_instr,

    output reg lsb_store_instr_ready,
    output reg[`ROBINDEX] lsb_ready_store_instr_rename,
    output reg[`DATALEN] lsb_store_value,

    //from alu cbd
    input wire alu_broadcast,
    input wire [`DATALEN] alu_cbd_value,
    input wire [`ROBINDEX] alu_update_rename,
    //from rob cbd
    input wire rob_broadcast,
    input wire [`DATALEN] rob_cbd_value,
    input wire [`ROBINDEX] rob_update_rename,
    // 将自己load结果发到cbd
    output reg lsb_broadcast,
    output reg [`DATALEN] lsb_cbd_value,
    output reg [`ROBINDEX] lsb_update_rename,
    output reg lsb_full
);
reg                 busy[`LSBSIZE];
reg [`ADDR]         pc[`LSBSIZE];
reg [`ROBINDEX]     rob_index[`LSBSIZE];
reg [`ADDR]         destination_mem_addr[`LSBSIZE];
reg                 addr_ready[`LSBSIZE];
reg [`OPLEN]        op[`LSBSIZE];
reg [`IMMLEN]       imms[`LSBSIZE];
reg [`DATALEN]      rs1_value[`LSBSIZE];
reg [`DATALEN]      rs2_value[`LSBSIZE];
reg [`ROBINDEX]     rs1_rename[`LSBSIZE];
reg [`ROBINDEX]     rs2_rename[`LSBSIZE];
reg                 store_instr_sent_to_rob[`LSBSIZE];//标记这个store是不是被送过去了
wire                 calculate_ready[`LSBSIZE];
wire                 issue_ready[`LSBSIZE];

//rob的数据结构应该是一个循环队列，记下头尾,记住顺序
reg [`LSBINDEX]   head;
reg [`LSBPOINTER]   next;
integer occupied;
wire [`LSBINDEX]     to_calculate;
wire debug_head_ready;
wire debug_head_addr_ready;
wire [`ROBINDEX]debug_head_rs2_rename;
wire debug_head_busy;
wire debug_head_calculate_ready;
assign debug_head_calculate_ready = calculate_ready[head[3:0]];
wire [`OPLEN] debug_head_op;
assign debug_head_op = op[head[3:0]];
assign debug_head_busy = busy[head[3:0]];
assign debug_head_addr_ready = addr_ready[head[3:0]];
assign debug_head_rs2_rename = rs2_rename[head[3:0]];
assign debug_head_ready = issue_ready[head[3:0]];
wire [`ROBINDEX]debug_head_rs1_rename;
assign debug_head_rs1_rename=rs1_rename[head[3:0]];
assign to_calculate = (calculate_ready[0] ? 0 :(
                            calculate_ready[1] ? 1 : (
                                calculate_ready[2] ? 2 : (
                                    calculate_ready[3] ? 3: (
                                        calculate_ready[4] ? 4 : (
                                            calculate_ready[5] ? 5 : (
                                                calculate_ready[6] ? 6 : (
                                                    calculate_ready[7] ? 7 : (
                                                        calculate_ready[8] ? 8 : (
                                                            calculate_ready[9] ? 9 :(
                                                                calculate_ready[10] ? 10 :(
                                                                    calculate_ready[11] ? 11 :(
                                                                        calculate_ready[12] ? 12 :(
                                                                            calculate_ready[13] ? 13 :(
                                                                                calculate_ready[14] ? 14 :(
                                                                                    calculate_ready[15]? 15 : `LSBNOTRENAME
                                                                                    ))))))))))))))));
genvar i;
generate 
    for(i=0;i<`LSBSIZESCALAR;i=i+1) begin
        assign issue_ready[i] = (rst == `FALSE && jump_wrong == `FALSE &&busy[i]==`TRUE && addr_ready[i]==`TRUE && rs2_rename[i] == `ROBNOTRENAME);
        assign calculate_ready[i] = (rst == `FALSE && jump_wrong == `FALSE && busy[i]==`TRUE && addr_ready[i]==`FALSE && rs1_rename[i] == `ROBNOTRENAME);//一旦addr计算好了，这个calculate ready也变成了false，这样to_calculate就可以不重复算
    end
endgenerate
integer j;
integer out_file;
initial begin
    out_file = $fopen("../tmp.txt","w");
    lsb_full <= `FALSE;
end
//从decoder送过来是有顺序的，执行的时候也应该是有顺序的，因此每次只能执行最首的那个
//执行store的时候要向rob进行交互，而load只要lsb觉得OK就可以做，做完告诉robcommit就行，
//因此store分两个阶段，分别是告诉rob和robcommit,load就自己load完了broadcast一下就好
always @(posedge clk) begin
    if(rst == `TRUE || (rdy == `TRUE && jump_wrong == `TRUE)) begin
        head <= 0;
        next <= 0;
        occupied <= 0;
        lsb_write_signal <= `FALSE;
        lsb_read_signal <= `FALSE;
        lsb_full <= `FALSE;
        for(j=0;j<`LSBSIZESCALAR;j=j+1)begin
            busy[j] <= `FALSE;
            addr_ready [j] <= `FALSE;
            destination_mem_addr[j] <= `NULL32;
        end
    end else if(rdy == `TRUE && jump_wrong == `FALSE)begin
        if(issue_ready[head[3:0]] == `TRUE  && occupied != 0) begin
            case(op[head[3:0]])
                `SB,`SH,`SW: begin
                    // lsb_write_signal <= `TRUE;
                    // lsb_read_signal <= `FALSE;
                    // to_mem_addr <= destination_mem_addr[head[3:0]];
                    // to_mem_data <= rs2_value[head[3:0]];
                    // busy[head[3:0]] <= `FALSE;
                    // addr_ready[head[3:0]] <= `FALSE;
                    // lsb_update_rename <= rob_index[head[3:0]];
                    if(rob_enable_lsb_write==`TRUE && lsb_write_signal == `FALSE) begin
                        // case(op[head[3:0]])
                        //     `SB: begin
                        //         $display(out_file,"%h\tsb\t%d\t%d",commit_store_instr,rs2_value[head[3:0]],destination_mem_addr[head[3:0]]);
                        //     end
                        //     `SH: begin
                        //         $display(out_file,"%h\tsh\t%d\t%d",commit_store_instr,rs2_value[head[3:0]],destination_mem_addr[head[3:0]]);
                        //     end
                        //     `SW: begin
                        //         $display(out_file,"%h\tsw\t%d\t%d",commit_store_instr,rs2_value[head[3:0]],destination_mem_addr[head[3:0]]);
                        //     end
                        // endcase
                        // if(destination_mem_addr[head[3:0]]==196608)begin
                        //     $write("\nascii ",rs2_value[head[3:0]],"\t");
                        //     case(op[head[3:0]])
                        //     `SB:begin $write("\tsb\t");end
                        //     `SH:begin $write("\tsh\t");end
                        //     `SW:begin $write("\tsw\t");end
                        //     endcase
                        // end
                        lsb_write_signal <= `TRUE;
                        lsb_read_signal <= `FALSE;
                        //lsb_write_signed <= ;//todo 表示是否是signed，或者你就处理好直接拿给memctrl就可以写
                        to_mem_addr <= destination_mem_addr[head[3:0]];
                        to_mem_data <= rs2_value[head[3:0]];
                        case(op[head[3:0]])
                            `SB: begin requiring_length <= `REQUIRE8; end
                            `SH: begin requiring_length <= `REQUIRE16; end
                            `SW: begin requiring_length <= `REQUIRE32; end
                        endcase
                        busy[head[3:0]] <= `FALSE;
                        addr_ready[head[3:0]] <= `FALSE;
                        lsb_update_rename <= rob_index[head[3:0]];
                    end else begin
                        if(store_instr_sent_to_rob[head[3:0]]==`FALSE) begin
                            store_instr_sent_to_rob[head[3:0]] <= `TRUE;
                            lsb_store_instr_ready <= `TRUE;
                            lsb_ready_store_instr_rename <= rob_index[head[3:0]];
                            lsb_store_value <= rs2_value[head[3:0]];
                        end
                    end
                end
                `LB,`LBU,`LH,`LHU,`LW: begin
                    if(lsb_read_signal == `FALSE)begin
                        busy[head[3:0]] <= `FALSE;
                        addr_ready[head[3:0]] <= `FALSE;
                        lsb_write_signal <= `FALSE;
                        lsb_read_signal <= `TRUE;
                        lsb_update_rename <= rob_index[head[3:0]];
                        to_mem_addr <= destination_mem_addr[head[3:0]];
                        lsb_store_instr_ready <= `FALSE;
                        case(op[head[3:0]])
                            `LB,`LBU: begin 
                                requiring_length <= `REQUIRE8; 
                            end
                            `LH,`LHU: begin 
                                requiring_length <= `REQUIRE16;
                            end
                            default: begin
                                requiring_length <= `REQUIRE32;
                            end
                        endcase
                    end
                end
                default: begin 
                    lsb_store_instr_ready <= `FALSE;
                end
            endcase
        end else begin
            lsb_store_instr_ready <= `FALSE;
        end
        if(mem_load_success==`TRUE) begin
            lsb_broadcast <= `TRUE;
            lsb_update_rename <= rob_index[head[3:0]];
            busy[head[3:0]] <= `FALSE;
            addr_ready[head[3:0]] <= `FALSE;
            occupied <= occupied - 1;
            head <= (head + 1) % `ROBNOTRENAME;
            lsb_read_signal <= `FALSE;
            lsb_cbd_value <= (op[head[3:0]]==`LHU || op[head[3:0]]==`LBU)? $unsigned(from_mem_data) : $signed(from_mem_data);
            // load_signed <= (op[head[3:0]]==`LHU || op[head[3:0]]==`LBU)? `FALSE : `TRUE;
        end else begin
            lsb_broadcast <= `FALSE;
        end
        if(mem_store_success == `TRUE) begin
            lsb_write_signal <= `FALSE;
            head <= (head + 1)%`ROBNOTRENAME;
            occupied <= occupied - 1;
        end
        //calculate the required address
        if(to_calculate != `LSBNOTRENAME) begin
            destination_mem_addr[to_calculate[3:0]] <= rs1_value[to_calculate[3:0]] + $signed(imms[to_calculate[3:0]]);
            addr_ready[to_calculate[3:0]] <=  `TRUE;
            lsb_destination_addr_to_rob <= rs1_value[to_calculate[3:0]] + imms[to_calculate[3:0]];
            lsb_calculated_addr_signal <= `TRUE;
            lsb_rename_to_rob_for_the_calculated_instr <= rob_index[to_calculate[3:0]];
        end else begin
            lsb_calculated_addr_signal <= `FALSE;
        end
        
    end
end
always @(posedge decode_signal)begin
    // add an entry to lsb
    //todo 如果lsb满了会不会来不及通知decoder，导致decoder会有信息发不出去？
    if(rst==`FALSE && rdy==`TRUE && jump_wrong == `FALSE && occupied != 16 && decoder_enable==`TRUE) begin
            #1 busy[next] <= `TRUE;
            rob_index[next] <= decoder_rd_rename;
            store_instr_sent_to_rob[next] <= `FALSE;
            if(alu_broadcast == `TRUE && alu_update_rename==decoder_rs1_rename)begin 
                rs1_rename[next] <= `ROBNOTRENAME; 
                rs1_value[next] <= alu_cbd_value;
            end else if(rob_broadcast == `TRUE && rob_update_rename==decoder_rs1_rename)begin 
                rs1_rename[next] <= `ROBNOTRENAME; 
                rs1_value[next] <= rob_cbd_value;
            end else begin
                rs1_rename[next] <= decoder_rs1_rename;
                rs1_value[next] <= decoder_rs1_value;
            end
            if(alu_broadcast == `TRUE && alu_update_rename==decoder_rs2_rename)begin 
                rs2_rename[next] <= `ROBNOTRENAME; 
                rs2_value[next] <= alu_cbd_value;
            end else if(rob_broadcast == `TRUE && rob_update_rename==decoder_rs2_rename)begin 
                rs2_rename[next] <= `ROBNOTRENAME; 
                rs2_value[next] <= rob_cbd_value;
            end else begin
                rs2_rename[next] <= decoder_rs2_rename;
                rs2_value[next] <= decoder_rs2_value;
            end
            imms[next] <= decoder_imm;
            pc[next] <= decoder_pc;
            op[next] <= decoder_op;
            next <= next + 1;
            occupied <= occupied + 1;
        end
end
always @(posedge alu_broadcast,rob_broadcast) begin
    if(jump_wrong==`FALSE && rdy == `TRUE && rst==`FALSE)begin
    for(j=0;j<`LSBSIZESCALAR;j=j+1)begin
            if(alu_broadcast== `TRUE) begin
                if(alu_update_rename==rs1_rename[j]) begin
                    rs1_value[j] <= alu_cbd_value;
                    rs1_rename[j] <= `ROBNOTRENAME;
                end
                if(alu_update_rename==rs2_rename[j]) begin
                    rs2_value[j] <= alu_cbd_value;
                    rs2_rename[j] <= `ROBNOTRENAME;
                end
            end
            if(rob_broadcast==`TRUE) begin
                if(rob_update_rename==rs1_rename[j]) begin
                    rs1_value[j] <= rob_cbd_value;
                    rs1_rename[j] <= `ROBNOTRENAME;
                end
                if(rob_update_rename==rs2_rename[j]) begin
                    rs2_value[j] <= rob_cbd_value;
                    rs2_rename[j] <= `ROBNOTRENAME;
                end
            end
        end
    end
end
endmodule
`endif