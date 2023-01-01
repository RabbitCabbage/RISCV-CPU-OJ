`ifndef ROB
`define ROB
`include"define.v"
module ROB(
    //control signals
    input wire clk,
    input wire rdy,
    input wire rst,
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

    output reg rob_full,
    output reg jump_wrong,
    output reg [`ADDR] jumping_pc,

    output reg to_predictor_enable,
    output reg to_predictor_jump,
    output reg [`PREDICTORINDEX] to_predictor_pc,
    input wire ifetch_jump_change_success
);
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
reg alu_need_update;
reg lsb_need_update;
// integer out_file;

initial begin
    // out_file <= $fopen("../tmp.txt","w");
    rob_full <= `FALSE;
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
    alu_need_update <= `FALSE;
    lsb_need_update <= `FALSE;
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
        rob_full = (next == head && occupied == 16);
       if(ready[head[3:0]]==`TRUE && occupied != 0 && rob_enable_lsb_write==`FALSE && rob_broadcast == `FALSE) begin//同时要检查这个rob不空
            debug_rob_commit <= debug_rob_commit + 1;
           // $write(debug_rob_commit,"\n");
           case(op[head[3:0]])
               `SB: begin
                    to_lsb_size <= `REQUIRE8;
                    to_lsb_addr <= destination_mem_addr[head[3:0]];
                    to_lsb_value <= rd_value[head[3:0]];
                    rob_enable_lsb_write <= `TRUE;
                    commit_store_instr <= instr[head[3:0]];
                    enable_reg <=  `FALSE;
               end
               `SH: begin
                    to_lsb_size <= `REQUIRE16;
                    to_lsb_addr <= destination_mem_addr[head[3:0]];
                    to_lsb_value <= rd_value[head[3:0]];
                    rob_enable_lsb_write <= `TRUE;
                    commit_store_instr <= instr[head[3:0]];
                    enable_reg <=  `FALSE;
               end
               `SW: begin
                    // debug_rob_commit <= debug_rob_commit + 1;
                    to_lsb_size <= `REQUIRE32;
                    to_lsb_addr <= destination_mem_addr[head[3:0]];
                    to_lsb_value <= rd_value[head[3:0]];
                    rob_enable_lsb_write <= `TRUE;
                    commit_store_instr <= instr[head[3:0]];
                    enable_reg <=  `FALSE;
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
                // case(op[head[3:0]])
                //     `LB: begin
                //         $fdisplay(out_file,"%h\tlb\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `LH: begin
                //         $fdisplay(out_file,"%h\tlh\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `LW: begin
                //         $fdisplay(out_file,"%h\tlw\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `LBU: begin
                //         $fdisplay(out_file,"%h\tlbu\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `LHU: begin
                //         $fdisplay(out_file,"%h\tlhu\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SB: begin
                //         $fdisplay(out_file,"%h\tsb\t%d",instr[head[3:0]],destination_mem_addr[head[3:0]]);
                //     end
                //     `SH: begin
                //         $fdisplay(out_file,"%h\tsh\t%d",instr[head[3:0]],destination_mem_addr[head[3:0]]);
                //     end
                //     `SW: begin
                //         $fdisplay(out_file,"%h\tsw\t%d",instr[head[3:0]],destination_mem_addr[head[3:0]]);
                //     end
                //     `LUI: begin
                //         $fdisplay(out_file,"%h\tlui\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `AUIPC: begin
                //         $fdisplay(out_file,"%h\tauipc\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SUB: begin
                //         $fdisplay(out_file,"%h\tsub\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `ADD: begin
                //         $fdisplay(out_file,"%h\tadd\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `ADDI: begin
                //         $fdisplay(out_file,"%h\taddi\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `XOR: begin
                //         $fdisplay(out_file,"%h\txor\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `XORI: begin
                //         $fdisplay(out_file,"%h\txori\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `OR: begin
                //         $fdisplay(out_file,"%h\tor\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `ORI: begin
                //         $fdisplay(out_file,"%h\tori\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `AND: begin
                //         $fdisplay(out_file,"%h\tand\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `ANDI: begin
                //         $fdisplay(out_file,"%h\tandi\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SLL: begin
                //         $fdisplay(out_file,"%h\tsll\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SLLI: begin
                //         $fdisplay(out_file,"%h\tslli\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SRL: begin
                //         $fdisplay(out_file,"%h\tsrl\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SRLI: begin
                //         $fdisplay(out_file,"%h\tsrli\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SRA: begin
                //         $fdisplay(out_file,"%h\tsra\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SRAI: begin
                //         $fdisplay(out_file,"%h\tsrai\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SLTI: begin
                //         $fdisplay(out_file,"%h\tslti\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SLTIU: begin
                //         $fdisplay(out_file,"%h\tsltiu\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SLT: begin
                //         $fdisplay(out_file,"%h\tslt\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `SLTU: begin
                //         $fdisplay(out_file,"%h\tsltu\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                //     end
                //     `BEQ: begin
                //         $fdisplay(out_file,"%h\tbeq",instr[head[3:0]]);
                //     end
                //     `BNE: begin
                //         $fdisplay(out_file,"%h\tbne",instr[head[3:0]]);
                //     end
                //     `BLT: begin
                //         $fdisplay(out_file,"%h\tblt",instr[head[3:0]]);
                //     end
                //     `BGE: begin
                //         $fdisplay(out_file,"%h\tbge",instr[head[3:0]]);
                //     end
                //     `BLTU: begin
                //         $fdisplay(out_file,"%h\tbltu",instr[head[3:0]]);
                //     end
                //     `BGEU: begin
                //         $fdisplay(out_file,"%h\tbgeu",instr[head[3:0]]);
                //     end
                //     `JAL: begin
                //         $fdisplay(out_file,"%h\tjal",instr[head[3:0]]);
                //     end
                //     `JALR: begin
                //         $fdisplay(out_file,"%h\tjalr",instr[head[3:0]]);
                //     end      
                //     default begin
                //     end
                // endcase
                    // case(op[head[3:0]])
                    //     `LB: begin
                    //         $display("%h\tlb\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `LH: begin
                    //         $display("%h\tlh\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `LW: begin
                    //         $display("%h\tlw\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `LBU: begin
                    //         $display("%h\tlbu\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `LHU: begin
                    //         $display("%h\tlhu\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SB: begin
                    //         $display("%h\tsb\t%d",instr[head[3:0]],destination_mem_addr[head[3:0]]);
                    //     end
                    //     `SH: begin
                    //         $display("%h\tsh\t%d",instr[head[3:0]],destination_mem_addr[head[3:0]]);
                    //     end
                    //     `SW: begin
                    //         $display("%h\tsw\t%d",instr[head[3:0]],destination_mem_addr[head[3:0]]);
                    //     end
                    //     `LUI: begin
                    //         $display("%h\tlui\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `AUIPC: begin
                    //         $display("%h\tauipc\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SUB: begin
                    //         $display("%h\tsub\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `ADD: begin
                    //         $display("%h\tadd\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `ADDI: begin
                    //         $display("%h\taddi\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `XOR: begin
                    //         $display("%h\txor\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `XORI: begin
                    //         $display("%h\txori\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `OR: begin
                    //         $display("%h\tor\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `ORI: begin
                    //         $display("%h\tori\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `AND: begin
                    //         $display("%h\tand\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `ANDI: begin
                    //         $display("%h\tandi\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SLL: begin
                    //         $display("%h\tsll\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SLLI: begin
                    //         $display("%h\tslli\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SRL: begin
                    //         $display("%h\tsrl\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SRLI: begin
                    //         $display("%h\tsrli\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SRA: begin
                    //         $display("%h\tsra\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SRAI: begin
                    //         $display("%h\tsrai\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SLTI: begin
                    //         $display("%h\tslti\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SLTIU: begin
                    //         $display("%h\tsltiu\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SLT: begin
                    //         $display("%h\tslt\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `SLTU: begin
                    //         $display("%h\tsltu\t%d\t%d",instr[head[3:0]],destination_reg_index[head[3:0]],rd_value[head[3:0]]);
                    //     end
                    //     `BEQ: begin
                    //         $display("%h\tbeq",instr[head[3:0]]);
                    //     end
                    //     `BNE: begin
                    //         $display("%h\tbne",instr[head[3:0]]);
                    //     end
                    //     `BLT: begin
                    //         $display("%h\tblt",instr[head[3:0]]);
                    //     end
                    //     `BGE: begin
                    //         $display("%h\tbge",instr[head[3:0]]);
                    //     end
                    //     `BLTU: begin
                    //         $display("%h\tbltu",instr[head[3:0]]);
                    //     end
                    //     `BGEU: begin
                    //         $display("%h\tbgeu",instr[head[3:0]]);
                    //     end
                    //     `JAL: begin
                    //         $display("%h\tjal",instr[head[3:0]]);
                    //     end
                    //     `JALR: begin
                    //         $display("%h\tjalr",instr[head[3:0]]);
                    //     end      
                    //     default begin
                    //     end
                    // endcase
                
           ready[head[3:0]] <= `FALSE;
           head <= (head + 1) % `ROBNOTRENAME;
           occupied <= occupied - 1;
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
       if(alu_broadcast == `TRUE && alu_need_update==`TRUE) begin
           rd_value[alu_update_rename[3:0]] <= alu_cbd_value;
           ready[alu_update_rename[3:0]] <= `TRUE;
           jump_pc[alu_update_rename[3:0]] <= alu_jumping_pc;
           debug_alu_update <= debug_alu_update + 1;
           alu_need_update <= `FALSE;
       end 
       if(lsb_broadcast == `TRUE&&lsb_need_update==`TRUE) begin//lsb广播的是lsb load得到的数据
           rd_value[lsb_update_rename[3:0]] <= lsb_cbd_value;
           ready[lsb_update_rename[3:0]] <= `TRUE;
           lsb_need_update<=`FALSE;
       end
    end
end
always @(posedge decoder_input_enable) begin
    if(jump_wrong==`FALSE && occupied!=16 && rst==`FALSE &&rdy == `TRUE)begin
           pc[next] <= decoder_pc;
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
           occupied <= occupied + 1;
        end
end
always @(posedge alu_broadcast) begin
    alu_need_update <= `TRUE;  
end 
always @(posedge lsb_broadcast) begin//lsb广播的是lsb load得到的数据
    lsb_need_update <= `TRUE;
end
endmodule
`endif