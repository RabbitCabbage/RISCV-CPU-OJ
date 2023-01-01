`include "define.v"
module RegFile(
    //control signals
    input wire clk,
    input wire rst,
    input wire rdy,
    input wire jump_wrong,
    //interact with decoder
    input wire decoder_success,
    input wire [`REGINDEX] from_decoder_rs1_index,
    input wire [`REGINDEX] from_decoder_rs2_index,
    input wire [`REGINDEX] from_decoder_rd_index,
    input wire decoder_need_rs1,
    input wire decoder_need_rs2,
    input wire decoder_have_rd_waiting,//有一些指令本身不需要rd，那么这时候的reg也不应该将记下发过来的rename
    //这个rename是这条指令在rob中的编号，无论有没有rd在等结果都会发过来，所以需要记下来
    input wire [`ROBINDEX] decoder_rd_rename,
    output reg rs1_renamed,
    output reg rs2_renamed,
    output reg [`DATALEN] to_decoder_rs1_value,
    output reg [`DATALEN] to_decoder_rs2_value,
    output reg [`ROBINDEX] to_decoder_rs1_rename,
    output reg [`ROBINDEX] to_decoder_rs2_rename,

    // from ROB
    input wire rob_enable,
    input wire [`REGINDEX] rob_commit_index,
    input wire [`ROBINDEX] rob_commit_rename,
    input wire [`DATALEN] rob_commit_value
);
reg [`DATALEN] reg_value [`REGSIZE];
reg renamed[`REGSIZE];
reg [`ROBINDEX] reg_rename [`REGSIZE];//用RS的标号来rename用这条指令作为结果的寄存器
integer i;
wire[`DATALEN] debug_check;
wire [`ROBINDEX] debug_rename_check;
assign debug_check=reg_value[10];
assign debug_rename_check = reg_rename[10];
wire[`DATALEN] debug_check_;
wire [`ROBINDEX] debug_rename_check_;
assign debug_check_=reg_value[13];
assign debug_rename_check_ = reg_rename[13];
always @(posedge clk)begin
    if(rst==`TRUE) begin
        for(i=0;i<`REGSIZESCALAR;i=i+1)begin
            reg_value[i] <= `NULL32;
            renamed[i] <= `FALSE;
            reg_rename[i] <= `ROBNOTRENAME;
        end
    end else begin
        if(rdy==`TRUE) begin
            if(jump_wrong==`TRUE)begin
                for(i=0;i<`REGSIZESCALAR;i=i+1)begin
                    //reg_value[i] <= `NULL32;
                    renamed[i] <= `FALSE;
                    reg_rename[i] <= `ROBNOTRENAME;
                end
            end else begin
                if(rob_enable == `TRUE) begin
                    //如果commit的是这条reg在等的最后结果才能说不被重命名，要不然你不保证reg正在被这条commit之后的指令重命名，你没有这个权限去改别人的重命名
                    if(rob_commit_rename==reg_rename[rob_commit_index])begin
                        reg_rename[rob_commit_index] <= `ROBNOTRENAME;
                        renamed[rob_commit_index] <= `FALSE;
                    end
                    if(rob_commit_index==0) begin reg_value[0] <= `NULL32;end
                    else begin reg_value[{27'b0, rob_commit_index}] <= rob_commit_value; end                
                end
            end
        end
    end
end
//下面是回答decoder的问题，但是要先拿值再记下重命名
//防止出现用rs1=x，rd=x，这样就会自己重命名自己没有意义
always @(posedge decoder_success)begin
    if(rdy==`TRUE && jump_wrong == `FALSE) begin
                    to_decoder_rs1_value <= reg_value[from_decoder_rs1_index];
                    //如果本身这条指令不用rs1的值，那就直接说没有rename
                    to_decoder_rs1_rename <= (decoder_need_rs1? reg_rename[from_decoder_rs1_index] : `ROBNOTRENAME);
                    rs1_renamed <= (decoder_need_rs1? renamed[from_decoder_rs1_index] : `FALSE);
                    to_decoder_rs2_value <= reg_value[from_decoder_rs2_index];
                    to_decoder_rs2_rename <= (decoder_need_rs2 ? reg_rename[from_decoder_rs2_index] : `ROBNOTRENAME);
                    rs2_renamed <= (decoder_need_rs2 ? renamed[from_decoder_rs2_index] : `FALSE);
                    if(decoder_have_rd_waiting==`TRUE) begin
                        reg_rename[from_decoder_rd_index] <= decoder_rd_rename;
                        renamed[from_decoder_rd_index] <= `TRUE;
                    end
                end
end
endmodule