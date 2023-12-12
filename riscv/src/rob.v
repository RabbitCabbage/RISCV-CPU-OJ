`ifndef ROB
`define ROB
`include"define.v"
module ROB(
    //control signals
    input wire clk,
    input wire rdy,
    input wire rst,
    input wire io_buffer_full,
    //commit to lsb, let lsb commit and perform the instr
    output reg rob_enable_lsb_write,
    output reg[`INSTRLEN] commit_store_instr,
    output reg [`DATALEN] to_lsb_value,
    output reg [`LSBINSTRLEN] to_lsb_size,
    output reg [`ADDR] to_lsb_addr,
    //不用rob enable，如果lsb需要读的话会在得到地址值之后及时去读，不会等rob
    //output reg rob_enable_lsb_read,
    input wire [`DATALEN] from_lsb_data,
    //commit to register file
    output reg [`REGINDEX] to_reg_rd,
    output reg [`DATALEN] to_reg_value,
    output reg [`ROBINDEX] to_reg_rename,
    output reg enable_reg,

    //interact with decoder
    //tell decoder the rob line free
    output wire [`ROBINDEX] rob_free_tag,
    input wire decoder_input_enable,
    input wire [`ROBINDEX] decoder_rd_rename,
    input wire [`INSTRLEN] decoder_instr,
    // decoder fetches value from rob
    input wire [`ROBINDEX] decoder_fetch_rs1_index,
    input wire [`ROBINDEX] decoder_fetch_rs2_index,
    output wire to_decoder_rs1_ready,
    output wire to_decoder_rs2_ready,
    output wire [`DATALEN] to_decoder_rs1_value,
    output wire [`DATALEN] to_decoder_rs2_value,
    input wire [`OPLEN] decoder_op,
    input wire [`ADDR] decoder_pc,
    input wire predicted_jump,
    input wire [`REGINDEX] decoder_destination_reg_index,//from decoder


    input wire [`ADDR] lsb_destination_mem_addr,//from lsb 如果lsb算出来了一个destination就会送过来
    input wire lsb_input_addr_enable,
    input wire [`ROBINDEX] from_lsb_rename,

    input wire alu_broadcast,
    input wire [`DATALEN] alu_cbd_value,
    input wire [`DATALEN] alu_jumping_pc,
    input wire [`ROBINDEX] alu_update_rename,

    input wire lsb_broadcast,
    input wire [`DATALEN] lsb_cbd_value,
    input wire [`ROBINDEX] lsb_update_rename,
    input wire lsb_store_instr_ready,
    input wire [`ROBINDEX] lsb_ready_store_instr_rename,
    input wire [`DATALEN] lsb_store_value,
    input wire lsb_store_success,

    output reg rob_broadcast,
    output reg [`ROBINDEX] rob_update_rename,
    output reg [`DATALEN] rob_cbd_value,

    output wire rob_full,
    output reg jump_wrong,
    output reg [`ADDR] jumping_pc,

    output reg to_predictor_enable,
    output reg to_predictor_jump,
    output reg [`PREDICTORINDEX] to_predictor_pc,
    input wire ifetch_jump_change_success,
    output wire[`ROBINDEX] rob_head
);
integer last_pc_from_decoder;
reg [`ADDR] pc[`ROBSIZE];
reg [`DATALEN] rd_value[`ROBSIZE];
reg [`ADDR] destination_mem_addr[`ROBSIZE];
reg [`REGINDEX] destination_reg_index[`ROBSIZE];
reg ready[`ROBSIZE];
reg [`OPLEN] op[`ROBSIZE];
reg [`ADDR] jump_pc[`ROBSIZE];
reg predictor_jump[`ROBSIZE];
reg is_store[`ROBSIZE];

//rob的数据结构应该是一个循环队列，记下头尾,记住顺序
reg [`ROBINDEX] head;
reg [`ROBPOINTER] next;
reg [`INSTRLEN] instr[`ROBSIZE];

//因为decoder送进来的是4：0的index，有一位用作了表示无重命名
//所以这里要取后面的3位作为indexing的下标
assign to_decoder_rs1_value = rd_value[decoder_fetch_rs1_index[3:0]];
assign to_decoder_rs2_value = rd_value[decoder_fetch_rs2_index[3:0]];
assign to_decoder_rs1_ready = ready[decoder_fetch_rs1_index[3:0]];
assign to_decoder_rs2_ready = ready[decoder_fetch_rs2_index[3:0]];
assign rob_free_tag = (rob_full==`FALSE)? {1'b0,next}: 16;
assign rob_full = (head==next && occupied == 16); 
assign rob_head = head;

integer i;
integer debug_alu_update;
integer debug_rob_commit;
integer occupied;
wire debug_head_ready;
wire debug_9_ready;
assign debug_9_ready = ready[9];
assign debug_head_ready = ready[head[3:0]];
wire[`INSTRLEN] debug_instr;
assign debug_instr = instr[head[3:0]];
integer out_file;

initial begin
    out_file <= $fopen("../test.txt","w");
    last_pc_from_decoder <= -1;
    // rob_full <= `FALSE;
    head <= 0;//定一个很特殊的初始状态
    next <= 0;
    debug_alu_update <= 0;
    debug_rob_commit <= 0;
    occupied <= 0;
    to_reg_rd <= `NULL5;
        enable_reg <=  `FALSE;
        rob_enable_lsb_write <= `FALSE;
        rob_broadcast <= `FALSE;
        rob_update_rename <= `NULL5;
        rob_cbd_value <= `NULL32;
        jump_wrong <= `FALSE;
        jumping_pc <= `NULL32;
end
//store 操作需要addr以及相关的数据，也就是rs2，所以一个store操作只要有了addr有了rs2就可以执行了
always @(posedge clk) begin
    if(rst == `TRUE ||(rdy == `TRUE && jump_wrong == `TRUE)) begin
        head <= 0;
        next <= 0;
        occupied <= 0;
        rob_broadcast <= `FALSE;
         for(i=0;i<`ROBSIZESCALAR;i=i+1) begin
            rd_value[i] <= `NULL32;
            ready[i] <= `FALSE;
            is_store[i] <= `FALSE;
            predictor_jump[i] <= `FALSE;
        end
        if (ifetch_jump_change_success == `TRUE) begin
            jump_wrong <= `FALSE;
        end
        last_pc_from_decoder <= -1;
        //jump wrong 的时候这些信息得记下来，因为指令还得执行，不能赋成null
        // to_reg_rd <= `NULL5;
        // enable_reg <=  `FALSE;
        // rob_enable_lsb_write <= `FALSE;
        // jump_wrong <= `FALSE;
        // rob_broadcast <= `FALSE;
        // rob_update_rename <= `NULL5;
        // rob_cbd_value <= `NULL32;
        // jump_wrong <= `FALSE;
        //jumping_pc <= `NULL32;
    end else if(rdy == `TRUE && jump_wrong == `FALSE) begin
        //commit the first instr;
        // rob_full = (next == head && occupied == 16);
       if(ready[head[3:0]]==`TRUE && occupied != 0 && rob_enable_lsb_write==`FALSE && rob_broadcast == `FALSE) begin//同时要检查这个rob不空
           // $write(debug_rob_commit,"\n");
           case(op[head[3:0]])
               `SB: begin
                    if(io_buffer_full == `TRUE && (destination_mem_addr[head[3:0]]==196608||destination_mem_addr[head[3:0]]==196612))begin end else begin
                    to_lsb_size <= `REQUIRE8;
                    to_lsb_addr <= destination_mem_addr[head[3:0]];
                    to_lsb_value <= rd_value[head[3:0]];
                    rob_enable_lsb_write <= `TRUE;
                    commit_store_instr <= instr[head[3:0]];
                    enable_reg <=  `FALSE;
                    end
               end
               `SH: begin
                    if(io_buffer_full == `TRUE && (destination_mem_addr[head[3:0]]==196608||destination_mem_addr[head[3:0]]==196612))begin end else begin
                    to_lsb_size <= `REQUIRE16;
                    to_lsb_addr <= destination_mem_addr[head[3:0]];
                    to_lsb_value <= rd_value[head[3:0]];
                    rob_enable_lsb_write <= `TRUE;
                    commit_store_instr <= instr[head[3:0]];
                    enable_reg <=  `FALSE;
                    end
               end
               `SW: begin
                    if(io_buffer_full == `TRUE && (destination_mem_addr[head[3:0]]==196608||destination_mem_addr[head[3:0]]==196612))begin end else begin
                    // debug_rob_commit <= debug_rob_commit + 1;
                    to_lsb_size <= `REQUIRE32;
                    to_lsb_addr <= destination_mem_addr[head[3:0]];
                    to_lsb_value <= rd_value[head[3:0]];
                    rob_enable_lsb_write <= `TRUE;
                    commit_store_instr <= instr[head[3:0]];
                    enable_reg <=  `FALSE;
                    end
               end
               `JALR: begin
                    to_reg_rd <= destination_reg_index[head[3:0]];
                    to_reg_value <= rd_value[head[3:0]];
                    to_reg_rename <= {1'b0,head[3:0]};
                    jumping_pc <= jump_pc[head[3:0]];
                    //jump_wrong <= `TRUE;
                    enable_reg <=  `TRUE;
                    rob_broadcast <= `TRUE;
                    rob_cbd_value <= rd_value[head[3:0]];
                    rob_update_rename <= {1'b0,head[3:0]};
               end
               `BEQ,`BNE,`BLT,`BGE,`BLTU,`BGEU:begin
                    to_predictor_pc <= pc[head[3:0]][`PREDICTORHASH];
                    to_predictor_jump <= rd_value[head[3:0]][0];//记下到底是jump还是not jump
                    to_predictor_enable <= `TRUE;
                    if(rd_value[head[3:0]][0] != predictor_jump[head[3:0]]) begin
                        if(rd_value[head[3:0]]=={31'b0,1'b1}) begin
                            jump_wrong <= `FALSE;
                            jumping_pc <= jump_pc[head[3:0]];
                        end else begin
                            jump_wrong <= `TRUE;
                            jumping_pc <= pc[head[3:0]]+4;
                        end
                    end
                    enable_reg <=  `FALSE;       
               end
               default: begin
                    to_reg_rd <= destination_reg_index[head[3:0]];
                    to_reg_value <= rd_value[head[3:0]];
                    to_reg_rename <= {1'b0,head[3:0]};
                    jumping_pc <= jump_pc[head[3:0]];
                    jump_wrong <= `FALSE;
                    enable_reg <=  `TRUE;
                    rob_broadcast <= `TRUE;
                    rob_cbd_value <= rd_value[head[3:0]];
                    rob_update_rename <= {1'b0,head[3:0]};
               end
           endcase
           if((op[head[3:0]]==`SW || op[head[3:0]]==`SB || op[head[3:0]]==`SH) && io_buffer_full==`TRUE && (destination_mem_addr[head[3:0]]==196608||destination_mem_addr[head[3:0]]==196612)) begin 

           end else begin
                ready[head[3:0]] <= `FALSE;
                head <= (head + 1) % `ROBNOTRENAME;
                debug_rob_commit <= debug_rob_commit + 1;
           end
           //occupied <= occupied - 1;
       end else begin
        enable_reg <=  `FALSE;
        rob_broadcast <= `FALSE;
       end
       
       if(lsb_store_success == `TRUE) begin
            rob_enable_lsb_write <= `FALSE;//需要得到反馈之后再拉低
       end
       
        if(lsb_input_addr_enable == `TRUE) begin//lsb input放进来的是lsb计算得到的store的地址
            destination_mem_addr[from_lsb_rename[3:0]] <= lsb_destination_mem_addr;
        end
        if(lsb_store_instr_ready == `TRUE) begin
            ready[lsb_ready_store_instr_rename] <= `TRUE;
            rd_value[lsb_ready_store_instr_rename] <= lsb_store_value;
        end
       if(alu_broadcast == `TRUE) begin
           rd_value[alu_update_rename[3:0]] <= alu_cbd_value;
           ready[alu_update_rename[3:0]] <= `TRUE;
           jump_pc[alu_update_rename[3:0]] <= alu_jumping_pc;
           debug_alu_update <= debug_alu_update + 1;
       end 
       if(lsb_broadcast == `TRUE) begin//lsb广播的是lsb load得到的数据
           rd_value[lsb_update_rename[3:0]] <= lsb_cbd_value;
           ready[lsb_update_rename[3:0]] <= `TRUE;
       end
       if(decoder_input_enable == `TRUE &&occupied!=16 && last_pc_from_decoder != decoder_pc)begin
           pc[next] <= decoder_pc;
           last_pc_from_decoder <= decoder_pc;
           destination_reg_index[next] <= decoder_destination_reg_index;
           op[next] <= decoder_op;
           instr[next] <= decoder_instr;
           ready[next] <= `FALSE;
           predictor_jump[next] <= predicted_jump;
           if(decoder_op == `SW || decoder_op == `SH || decoder_op == `SB) begin
               is_store[next] <= `TRUE;
           end else begin
               is_store[next] <= `FALSE;
           end
           next <= next + 1;
           //occupied <= occupied + 1;
        end
        if(ready[head[3:0]]==`TRUE && occupied != 0 && rob_enable_lsb_write==`FALSE && rob_broadcast == `FALSE) begin
            if(decoder_input_enable == `FALSE || occupied == 16||last_pc_from_decoder== decoder_pc) begin//那么就不能放进去
                occupied <= occupied - 1;
            end
        end else begin
            if(decoder_input_enable == `TRUE &&occupied!=16 && last_pc_from_decoder != decoder_pc) begin
                occupied <= occupied + 1;
            end
        end
    end
end
endmodule
`endif