`include "define.v"
module RS(
    //control signals
    input wire clk,
    input wire rst,
    input wire rdy,
    input wire jump_wrong,
    
    //from decoder
    input wire decode_success,
    input wire [`ROBINDEX] decode_rs1_rename,
    input wire [`ROBINDEX] decode_rs2_rename,
    input wire [`DATALEN] decode_rs1_value,
    input wire [`DATALEN] decode_rs2_value,
    input wire [`IMMLEN] decode_imm,
    input wire [`ROBINDEX] decode_rd_rename,
    input wire [`OPLEN] decode_op,
    input wire [`ADDR] decode_pc,
    input wire decoder_enable,

    //monitor the updated renaming from the cbd
    //input the number and renaming from alu
    input wire alu_broadcast,
    input wire [`DATALEN] alu_cbd_value,
    input wire [`ROBINDEX] alu_update_rename,
    //like add/sub these will directly get answer from the alu
    input wire lsb_broadcast,
    input wire [`DATALEN] lsb_cbd_value,
    input wire [`ROBINDEX] lsb_update_rename,
    //load get answer from the lsb, load data to the reg
    input wire rob_broadcast,
    input wire [`DATALEN] rob_cbd_value,
    input wire [`ROBINDEX] rob_update_rename,
    //get answer from the rob, such as put the answer from the rob

    output reg alu_enable,
    output reg [`ROBINDEX] to_alu_rd_renaming,
    output reg [`DATALEN] to_alu_rs1_value,
    output reg [`DATALEN] to_alu_rs2_value,
    output reg [`OPLEN] to_alu_op,
    output reg [`IMMLEN] to_alu_imm,
    output reg [`ADDR] to_alu_pc,

    output reg rs_full//如果rs满了的话就要停下if
);
reg [`OPLEN] opcode[`RSSIZE];
reg [`DATALEN] rs1_value[`RSSIZE];
reg [`DATALEN] rs2_value[`RSSIZE];
reg [`ROBINDEX] rs1_rename[`RSSIZE];//如果rename成了ROBNOTRENAME就表示已经ready了可以进行计算了
reg [`ROBINDEX] rs2_rename[`RSSIZE];
reg [`ROBINDEX] rd_rename[`RSSIZE];
reg [`IMMLEN] imm[`RSSIZE];
wire ready[`RSSIZE];
reg busy[`RSSIZE];
reg [`ADDR] pc[`RSSIZE];
wire [`RSINDEX] free_index;//表示的是哪一个RS是空的可以用的
reg [`RSINDEX] ready_index; //表达说的是哪一个RS已经ready了可以进行计算了
wire stall_IF;
wire [`RSINDEX] issue_index;

assign stall_IF                       = (free_index == `RSNOTFOUND);//如果找不到空的RS，则说明RS满了，那么就应该停IF。
assign free_index                     = ~busy[0] ? 0:  
                        ~busy[1] ? 1 :
                            ~busy[2] ? 2 : 
                                ~busy[3] ? 3 :
                                    ~busy[4] ? 4 :
                                        ~busy[5] ? 5 : 
                                            ~busy[6] ? 6 :
                                                ~busy[7] ? 7 :
                                                    ~busy[8] ? 8 : 
                                                        ~busy[9] ? 9 :
                                                            ~busy[10] ? 10 :
                                                                ~busy[11] ? 11 :
                                                                    ~busy[12] ? 12 :
                                                                        ~busy[13] ? 13 :
                                                                            ~busy[14] ? 14 : 
                                                                                ~busy[15] ? 15 : `RSNOTFOUND;
assign issue_index                    = ready[0] ? 0:  
                        ready[1] ? 1 :
                            ready[2] ? 2 : 
                                ready[3] ? 3 :
                                    ready[4] ? 4 :
                                        ready[5] ? 5 : 
                                            ready[6] ? 6 :
                                                ready[7] ? 7 :
                                                    ready[8] ? 8 : 
                                                        ready[9] ? 9 :
                                                            ready[10] ? 10 :
                                                                ready[11] ? 11 :
                                                                    ready[12] ? 12 :
                                                                        ready[13] ? 13 :
                                                                            ready[14] ? 14 : 
                                                                                ready[15] ? 15 : `RSNOTFOUND;
genvar j;
generate
    for(j=0;j<16;j=j+1) begin
        assign ready[j] = ((busy[j]==`TRUE) && (rs1_rename[j]==`ROBNOTRENAME) && (rs2_rename[j]==`ROBNOTRENAME)); 
    end
endgenerate
wire [`ROBINDEX] debug_check_rs1_rename;
assign debug_check_rs1_rename = rs1_rename[0];
wire debug_check_busy;
assign debug_check_busy = busy[0];
wire [`ROBINDEX] debug_check_rs2_rename;
assign debug_check_rs2_rename = rs2_rename[0];
initial begin
    rs_full <= `FALSE;
end
integer i;
integer debug_alu_not_busy;
reg alu_busy;
always @(posedge clk) begin
    if(rst==`TRUE || jump_wrong==`TRUE) begin
        alu_enable                    <=  `FALSE;
        for(i=0;i<32;i=i+1) begin
            busy[i]                   <= `FALSE;
            opcode[i]                 <= 6'b000000;
        end
        alu_busy <= `FALSE;
        debug_alu_not_busy <= 0;
    end else if (rdy == `TRUE) begin
        // 如果在RS中又ready的index；
        // 发布到alu中进行计算
        if(issue_index != `RSNOTFOUND && alu_busy == `FALSE) begin
            alu_enable                <= `TRUE;
            to_alu_op                 <= opcode[issue_index[3:0]];
            to_alu_rs1_value          <= rs1_value[issue_index[3:0]];
            to_alu_rs2_value          <= rs2_value[issue_index[3:0]];
            to_alu_imm                <= imm[issue_index[3:0]];
            to_alu_rd_renaming        <= rd_rename[issue_index[3:0]];
            to_alu_pc                 <= pc[issue_index[3:0]];
            busy[issue_index[3:0]]         <= `FALSE;//这条rs就可以使用了
            alu_busy <= `TRUE;
        end else begin
            alu_enable                <= `FALSE;
            alu_busy                  <= `FALSE;
        end
        //如果decode这边成功解码，并且有空位置，添加一条指令
        if(decode_success==`TRUE && free_index!=`RSNOTFOUND &&decoder_enable==`TRUE) begin
                busy[free_index[3:0]]          <= `TRUE;
                rd_rename[free_index[3:0]]     <= decode_rd_rename;
                opcode[free_index[3:0]]        <= decode_op;
                imm[free_index[3:0]]           <= decode_imm;
                pc[free_index[3:0]]            <= decode_pc;
            if(rob_broadcast==`TRUE)begin//防止broadcast的时间冲突造成更新不成功
                if(rob_update_rename == decode_rs1_rename)begin
                    rs1_value[free_index[3:0]] <= rob_cbd_value;
                    rs1_rename[free_index[3:0]] <= `ROBNOTRENAME;
                end else begin
                    rs1_value[free_index[3:0]]     <= decode_rs1_value;
                    rs1_rename[free_index[3:0]]    <= decode_rs1_rename;
                end
                if(rob_update_rename == decode_rs2_rename)begin
                    rs2_value[free_index[3:0]] <= rob_cbd_value;
                    rs2_rename[free_index[3:0]] <= `ROBNOTRENAME;
                end else begin
                    rs2_value[free_index[3:0]]     <= decode_rs2_value;
                    rs2_rename[free_index[3:0]]    <= decode_rs2_rename;
                end 
            end else if(alu_broadcast == `TRUE) begin
                if(alu_update_rename == decode_rs1_rename)begin
                    rs1_value[free_index[3:0]] <= alu_cbd_value;
                    rs1_rename[free_index[3:0]] <= `ROBNOTRENAME;
                end else begin
                    rs1_value[free_index[3:0]]     <= decode_rs1_value;
                    rs1_rename[free_index[3:0]]    <= decode_rs1_rename;
                end
                if(alu_update_rename == decode_rs2_rename)begin
                    rs2_value[free_index[3:0]] <= alu_cbd_value;
                    rs2_rename[free_index[3:0]] <= `ROBNOTRENAME;
                end else begin
                    rs2_value[free_index[3:0]]     <= decode_rs2_value;
                    rs2_rename[free_index[3:0]]    <= decode_rs2_rename;
                end 
            end else if(lsb_broadcast == `TRUE) begin
                if(lsb_update_rename == decode_rs1_rename)begin
                    rs1_value[free_index[3:0]] <= lsb_cbd_value;
                    rs1_rename[free_index[3:0]] <= `ROBNOTRENAME;
                end else begin
                    rs1_value[free_index[3:0]]     <= decode_rs1_value;
                    rs1_rename[free_index[3:0]]    <= decode_rs1_rename;
                end
                if(lsb_update_rename == decode_rs2_rename)begin
                    rs2_value[free_index[3:0]] <= lsb_cbd_value;
                    rs2_rename[free_index[3:0]] <= `ROBNOTRENAME;
                end else begin
                    rs2_value[free_index[3:0]]     <= decode_rs2_value;
                    rs2_rename[free_index[3:0]]    <= decode_rs2_rename;
                end 
            end else begin
                rs1_value[free_index[3:0]]     <= decode_rs1_value;
                rs2_value[free_index[3:0]]     <= decode_rs2_value;
                rs1_rename[free_index[3:0]]    <= decode_rs1_rename;
                rs2_rename[free_index[3:0]]    <= decode_rs2_rename;
            end
        //monitor alu lsb and rob 
    end
end
end
always @(posedge alu_broadcast) begin
    if(jump_wrong==`FALSE && rdy == `TRUE && rst == `FALSE)begin
            alu_busy <= `FALSE;
            debug_alu_not_busy <= debug_alu_not_busy + 1;
            for(i=0;i<16;i=i+1) begin
                if(busy[i]==`TRUE) begin
                    if(rs1_rename[i]==alu_update_rename) begin
                        //说明这个要被替换掉了
                        rs1_rename[i] <= `ROBNOTRENAME;
                        rs1_value[i]  <= alu_cbd_value;
                    end else if(rs2_rename[i]==alu_update_rename) begin
                        rs2_rename[i] <= `ROBNOTRENAME;
                        rs2_value[i]  <= alu_cbd_value;
                    end
                end
            end
    end
end
always @(posedge lsb_broadcast) begin
    if(jump_wrong==`FALSE && rdy == `TRUE && rst==`FALSE) begin
            for(i=0;i<16;i=i+1) begin
                if(busy[i]==`TRUE) begin
                    if(rs1_rename[i]==lsb_update_rename) begin
                        rs1_rename[i] <= `ROBNOTRENAME;
                        rs1_value[i]  = lsb_cbd_value;
                    end else if(rs2_rename[i]==lsb_update_rename) begin
                        rs2_rename[i] <= `ROBNOTRENAME;
                        rs2_value[i]  <= lsb_cbd_value;
                    end
                end
            end
    end
end
always @(posedge rob_broadcast) begin
    if(jump_wrong==`FALSE && rdy == `TRUE && rst==`FALSE)begin
            for(i=0;i<16;i=i+1) begin
                    if(busy[i]) begin
                        if(rs1_rename[i]==rob_update_rename) begin
                            rs1_rename[i] <= `ROBNOTRENAME;
                            rs1_value[i]  <= rob_cbd_value;
                        end
                        if(rs2_rename[i]==rob_update_rename) begin
                            rs2_rename[i] <= `ROBNOTRENAME;
                            rs2_value[i]  <= rob_cbd_value;
                        end
                end
            end
        end
end
endmodule