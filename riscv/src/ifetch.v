`ifndef IF
`define IF
`include "define.v"
module IF(
    input wire clk,
    input wire rst,
    input wire rdy,
    // with regard to jumping
    // from ROB
    input wire jump_wrong,
    input wire[`ADDR] jump_pc_from_rob,
    
    // fetch instr from ICache
    // give out an addr and get an instr
    output reg icache_enable,
    output reg [`ADDR] pc_to_fetch,
    input wire [`INSTRLEN] instr_fetched,
    input wire icache_success,

    // send instr to decoder
    // send out instr and wether jumping
    // if lsb or rob is full, then fetching should be stalled
    input wire stall_IF,
    output wire [`INSTRLEN] instr_to_decode,
    output reg [`ADDR] pc_to_decoder,
    output wire IF_success,

    // from predictor
    input predictor_enable,
    output wire[`ADDR] instr_to_predictor,
    output reg [`ADDR] instr_pc_to_predictor,
    input wire is_jump_instr,
    input wire jump_prediction,
    input wire [`ADDR] jump_pc_from_predictor,
    //表示的是上一个指令是否是跳转指令，以及predict是否跳转
    output reg ifetch_jump_change_success
);
reg [`ADDR] pc;

assign IF_success = (icache_success==`TRUE && stall_IF==`FALSE);
assign instr_to_decode = instr_fetched;
assign instr_to_predictor = instr_fetched;
always @(posedge IF_success) begin
    if(rst== `FALSE && jump_wrong == `FALSE && rdy == `TRUE)begin
        instr_pc_to_predictor <= pc;
    end
end

integer begin_flag;
reg wait_flag;
integer debug_check_pc_change;
always @(posedge jump_wrong) begin
    pc <= jump_pc_from_rob;
    pc_to_fetch <= jump_pc_from_rob;
    debug_check_pc_change <= 0;
    ifetch_jump_change_success <= `TRUE;
    icache_enable <= `TRUE;// todo stall if
    wait_flag <= `FALSE;
end
always @(posedge predictor_enable) begin
    if(rst == `FALSE && rdy == `TRUE)begin
        wait_flag <= `TRUE;//目的是为了让predictor算出来的地址只被计算一次，不会重复计算
    end
end
always @(posedge IF_success)begin
    if(rst== `FALSE && jump_wrong == `FALSE && rdy == `TRUE)begin//如果之前已经fetch成功了
        pc_to_decoder <= pc;
        icache_enable <= `FALSE;
    end
end

always @(posedge clk) begin
    if (rst == `TRUE) begin
        icache_enable <= `FALSE;
        pc <= `NULL32;
        begin_flag <= 0;
        wait_flag <= `FALSE;
    end else if(rdy==`TRUE && stall_IF==`FALSE && jump_wrong == `FALSE)begin
            ifetch_jump_change_success <= `FALSE;
            if(predictor_enable ==`TRUE && wait_flag == `TRUE) begin
                if(is_jump_instr==`TRUE) begin
                if(jump_prediction==`TRUE)begin
                    pc <= jump_pc_from_predictor;
                    pc_to_fetch <= jump_pc_from_predictor;
                    debug_check_pc_change <= 1;
                end else begin
                    pc <= pc + 4;
                    pc_to_fetch <= pc+4;
                    debug_check_pc_change <= 2;
                end
                end else begin
                    pc <= pc + 4;
                    pc_to_fetch <= pc+4;
                    debug_check_pc_change <= 3;
                end
                icache_enable <= `TRUE;
                wait_flag <= `FALSE;//这之后就不会再计算一次了
            end else if(begin_flag == 0) begin
                begin_flag <= 1;
                icache_enable <= `TRUE;
                pc_to_fetch <= pc;
                debug_check_pc_change <= 5;
            end
        end
    end

endmodule
`endif