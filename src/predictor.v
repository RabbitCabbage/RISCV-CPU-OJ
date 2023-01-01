`include "define.v"
`timescale 1ns/1ns
module Predictor(
    //control signals
    input wire clk,
    input wire rst,
    input wire rdy,
    input wire if_success,
    input wire [`ADDR] if_instr_pc_itself,
    input wire[`INSTRLEN] if_instr_to_ask_for_prediction,
    input wire rob_enable_predictor,//每当一次跳完之后，不论是否错都要给predictor一个反馈
    output reg is_jump_instr,
    output reg predicted_jump,
    output reg [`ADDR] predict_jump_pc,
    input wire real_jump_or_not,
    input wire [`PREDICTORINDEX]instr_pc,
    input wire[`ADDR] jump_to_pc_from_rob,
    output reg predictor_stall_if,
    input alu_broadcast,
    input [`OPLEN]alu_broadcast_op,
    input [`ADDR] alu_jumping_pc,
    output reg predictor_enable_if,
    input wire jump_wrong
);

always @(posedge clk) begin
    if(rst == `TRUE)begin
        is_jump_instr <= `FALSE;
        predicted_jump <= `FALSE;
        predictor_stall_if <= `FALSE;
        predictor_enable_if <= `FALSE;
    end else if(rdy == `TRUE) begin
        if(jump_wrong == `TRUE) begin
            predictor_enable_if <= `FALSE;//都跳错了，后面的东西都不算数了，你predictor就不能再让if按照你算出来的addr走了
            predictor_stall_if <= `FALSE;
        end else begin
            if(if_success == `TRUE) begin
                if (if_instr_to_ask_for_prediction[`OPCODE]==7'd111) begin//jal
                        is_jump_instr <= `TRUE;
                        predicted_jump <= `TRUE;
                        predict_jump_pc <= if_instr_pc_itself + {{12{if_instr_to_ask_for_prediction[31]}},if_instr_to_ask_for_prediction[19:12],if_instr_to_ask_for_prediction[20],if_instr_to_ask_for_prediction[30:21],1'b0};
                end else if(if_instr_to_ask_for_prediction[`OPCODE]== 7'd103) begin//jalr
                        is_jump_instr <= `TRUE;
                        predicted_jump <= `TRUE;
                        predictor_stall_if <= `TRUE;
                end else if(if_instr_to_ask_for_prediction[`OPCODE]== 7'd99) begin//branch
                        is_jump_instr <= `TRUE;
                        predicted_jump <= `TRUE;//todo 这里写的是都跳转
                        predict_jump_pc <= if_instr_pc_itself + {{20{if_instr_to_ask_for_prediction[31]}},if_instr_to_ask_for_prediction[7],if_instr_to_ask_for_prediction[30:25],if_instr_to_ask_for_prediction[11:8],1'b0};
                end else begin
                        is_jump_instr <= `FALSE;
                        predicted_jump <= `FALSE;
                        predict_jump_pc <= if_instr_pc_itself+ 4;
                end
                predictor_enable_if <= `TRUE;//predictor让if进行下一步了
            end else begin
                predictor_enable_if <= `FALSE;
            end
            if(alu_broadcast==`TRUE && alu_broadcast_op==`JALR) begin
                is_jump_instr <= `TRUE;
                predict_jump_pc <= alu_jumping_pc;
                predicted_jump <= `TRUE;
                predictor_stall_if <= `FALSE;
                predictor_enable_if <= `TRUE;
            end
        end
    end
end
endmodule