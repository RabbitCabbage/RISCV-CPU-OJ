`include "define.v"

// get instructions from if, 
//and then decode them and send them to rs
module Decoder(
    // control signals
    input wire clk,
    input wire rst,
    input wire rdy,
    // from and to IFetch
    input wire IF_success,
    input wire [`INSTRLEN] instr,
    input wire[`ADDR] fetch_pc,
    input wire stall_decoder,

    //raw information decoded
    // to RS
    output reg decode_success,// after decoding it requires rs to add the instr.
    output wire [`ROBINDEX] to_rs_rs1_rename,
    output wire [`ROBINDEX] to_rs_rs2_rename,
    output reg [`ROBINDEX] to_rs_rd_rename,
    output reg [`DATALEN] to_rs_imm,
    output wire [`DATALEN] to_rs_rs1_value,
    output wire [`DATALEN] to_rs_rs2_value,
    output wire [`OPLEN] to_rs_op,
    output reg [`ADDR] decode_pc,

    // to lsb
    output wire [`ROBINDEX] to_lsb_rs1_rename,
    output wire [`ROBINDEX] to_lsb_rs2_rename,
    output reg [`ROBINDEX] to_lsb_rd_rename,
    output wire [`DATALEN] to_lsb_rs1_value,
    output wire [`DATALEN] to_lsb_rs2_value,
    output reg [`IMMLEN] to_lsb_imm,
    output wire [`OPLEN] to_lsb_op,

    //from regfile
    //from regfile ask the information about registers
    input wire [`ROBINDEX] from_reg_rs1_rob_rename,
    input wire [`ROBINDEX] from_reg_rs2_rob_rename,
    input wire [`DATALEN] reg_rs1_value,
    input wire [`DATALEN] reg_rs2_value,
    input wire reg_rs1_renamed,
    input wire reg_rs2_renamed, 
    output reg [`REGINDEX] to_reg_rs1_index,
    output reg [`REGINDEX] to_reg_rs2_index,
    output reg [`ROBINDEX] to_reg_rd_rename,
    output reg [`REGINDEX] to_reg_rd_index,
    output reg to_reg_need_rs1,
    output reg to_reg_need_rs2,
    // from ROB, asking for the free index for the rd renaming
    // ask for the value of issued results
    input wire [`ROBINDEX] rob_free_tag,
    output reg [`ROBINDEX] to_rob_rd_rename,
    output reg [`INSTRLEN] to_rob_instr,
    input wire [`DATALEN] rob_fetch_rs1_value,
    input wire rob_rs1_ready,
    input wire [`DATALEN] rob_fetch_rs2_value,
    input wire rob_rs2_ready,
    output wire [`ROBINDEX] rob_fetch_rs1_index,
    output wire [`ROBINDEX] rob_fetch_rs2_index,
    output wire [`OPLEN] to_rob_op,
    output reg [`REGINDEX] to_rob_destination_reg_index,
    output reg instr_need_fill_rd,
    output reg enable_rs,
    output reg enable_lsb,
    input wire jump_wrong
);
//todo 把freetag赋值的时间点明显不对

//记下decode的结果
//不能这样写，这样写会有一个周期的延迟
 reg [`OPLEN] op;
// reg [`REGINDEX] rs1;
// reg [`REGINDEX] rs2;
// reg [`REGINDEX] rd;
// reg [`DATALEN] imm;
// wire [`DATALEN] rs1_value;
// wire [`DATALEN] rs2_value;
// wire [`ROBINDEX] rs1_rename;
// wire [`ROBINDEX] rs2_rename;
// wire [`OPCODE] opcode;

//assign to_reg_rs1_index                      = rs1;//从instr中读出来的rs1，送给regfile
//assign to_reg_rs2_index                      = rs2;//从instr中读出rs2，送给regfile
assign rob_fetch_rs1_index                   = from_reg_rs1_rob_rename;//regfile送回来rename
assign rob_fetch_rs2_index                   = from_reg_rs2_rob_rename;//regfile送回来rename
//assign to_reg_rd_rename                      = rob_free_tag;//rob空的tag赋给rd作为rename
assign to_lsb_rs1_value                             = (to_reg_rs1_index==0?0:((reg_rs1_renamed==`FALSE)?reg_rs1_value:(rob_rs1_ready==`TRUE)?rob_fetch_rs1_value:`NULL32));
assign to_rs_rs1_value                             = (to_reg_rs1_index==0?0:((reg_rs1_renamed==`FALSE)?reg_rs1_value:(rob_rs1_ready==`TRUE)?rob_fetch_rs1_value:`NULL32));
assign to_lsb_rs2_value                             = (to_reg_rs2_index==0?0:((reg_rs2_renamed==`FALSE)?reg_rs2_value:(rob_rs2_ready==`TRUE)?rob_fetch_rs2_value:`NULL32));
assign to_rs_rs2_value                             = (to_reg_rs2_index==0?0:((reg_rs2_renamed==`FALSE)?reg_rs2_value:(rob_rs2_ready==`TRUE)?rob_fetch_rs2_value:`NULL32));
assign to_rs_rs1_rename                            = (to_reg_rs1_index==0?`ROBNOTRENAME:((reg_rs1_renamed==`FALSE)?`ROBNOTRENAME:((rob_rs1_ready==`TRUE)?`ROBNOTRENAME:from_reg_rs1_rob_rename)));
assign to_lsb_rs1_rename                            = (to_reg_rs1_index==0?`ROBNOTRENAME:((reg_rs1_renamed==`FALSE)?`ROBNOTRENAME:((rob_rs1_ready==`TRUE)?`ROBNOTRENAME:from_reg_rs1_rob_rename)));
assign to_rs_rs2_rename                            = (to_reg_rs2_index==0?`ROBNOTRENAME:((reg_rs2_renamed==`FALSE)?`ROBNOTRENAME:(rob_rs2_ready==`TRUE)?`ROBNOTRENAME:from_reg_rs2_rob_rename));
assign to_lsb_rs2_rename                            = (to_reg_rs2_index==0?`ROBNOTRENAME:((reg_rs2_renamed==`FALSE)?`ROBNOTRENAME:(rob_rs2_ready==`TRUE)?`ROBNOTRENAME:from_reg_rs2_rob_rename));
//assign opcode = instr[`OPCODE];
assign to_rob_op = op;
assign to_rs_op = op;
assign to_lsb_op = op;
always @(posedge clk) begin
    //rst has nothing on this module, because this module has nothing stored in itself.
    if(rst == `TRUE || jump_wrong == `TRUE || stall_decoder==`TRUE) begin
        enable_lsb <= `FALSE;
        enable_rs <= `FALSE;
        decode_success <= `FALSE;
    end else if(rdy==`TRUE && IF_success==`TRUE) begin
        decode_success                       <= `TRUE;
        to_reg_rd_rename                      <= rob_free_tag;
        to_rob_rd_rename                      <= rob_free_tag;
        to_rob_instr                          <= instr;
        decode_pc                             <= fetch_pc;
        case(instr[`OPCODE])
            7'b0000011: begin
                case(instr[`FUNC3])
                    3'b000: op               <= `LB;
                    3'b001: op               <= `LH;
                    3'b010: op               <= `LW;
                    3'b100: op               <= `LBU;
                    3'b101: op               <= `LHU;
                    default:begin end
                endcase
                to_reg_rs1_index              <= instr[19:15];
                to_reg_need_rs1              <= `TRUE;
                to_reg_need_rs2              <= `FALSE;
                //rd                           <= instr[11:7];
                //imm                          <= {{21{instr[31]}},instr[30:20]};
                //把得到的结果传给lsb
                //to_rob_op                    <= op;
                //to_lsb_op                    <= op;
                to_lsb_imm                   <= {{21{instr[31]}},instr[30:20]};
                to_lsb_rd_rename             <= rob_free_tag;
                //to_lsb_rs1_value             <= rs1_value;
                to_rob_destination_reg_index <= instr[11:7];
                instr_need_fill_rd             <= `TRUE;
                to_reg_rd_index                <= instr[11:7];
                enable_lsb                     <= `TRUE;
                enable_rs                      <= `FALSE;
            end
            7'b0010011: begin
                case(instr[`FUNC3])
                    3'b000: op               <= `ADDI;
                    3'b001: op               <= `SLLI;
                    3'b010: op               <= `SLTI;
                    3'b011: op               <= `SLTIU;
                    3'b100: op               <= `XORI;
                    3'b101: begin
                        case(instr[`FUNC7])
                            7'b0000000: op   <= `SRLI;
                            7'b0100000: op   <= `SRAI;
                            default:begin end
                        endcase
                    end
                    3'b110: op               <= `ORI;
                    3'b111: op               <= `ANDI;
                    default:begin end
                endcase
                to_reg_rs1_index             <= instr[19:15];
                to_reg_need_rs1              <= `TRUE;
                to_reg_need_rs2              <= `FALSE;
                //rd                           <= instr[11:7];
                //imm                          <= {{21{instr[31]}},instr[30:20]};
                //吧得到的结果传给rs
                //to_rs_op                     <= op;
                //to_rob_op                    <= op;
                to_rs_imm                    <= {{21{instr[31]}},instr[30:20]};
                //to_rs_rs1_value              <= rs1_value;
                to_rs_rd_rename              <= rob_free_tag;
                to_rob_destination_reg_index <= instr[11:7];
                instr_need_fill_rd             <= `TRUE;
                to_reg_rd_index                <= instr[11:7];
                enable_lsb                     <= `FALSE;
                enable_rs                    <= `TRUE;
            end
            7'b0010111: begin
                op                           <= `AUIPC;
                //rd                           <= instr[11:7];
                //imm                          <= {instr[31:12],12'b0};
                to_rs_rd_rename              <= rob_free_tag;
                to_rs_imm                    <= {instr[31:12],12'b0};
                //to_rs_op                     <= op;
                //to_rob_op                    <= op;
                to_rob_destination_reg_index <= instr[11:7];
                instr_need_fill_rd             <= `TRUE;
                to_reg_rd_index                <= instr[11:7];
                to_reg_need_rs1              <= `FALSE;
                to_reg_need_rs2              <= `FALSE;
                enable_rs                    <= `TRUE;
                enable_lsb                   <= `FALSE;
            end
            7'b0100011: begin
                case(instr[`FUNC3])
                    3'b000: op               <= `SB;
                    3'b001: op               <= `SH;
                    3'b010: op               <= `SW;
                    default:begin end
                endcase
                to_reg_rs1_index              <= instr[19:15];
                to_reg_need_rs1              <= `TRUE;
                to_reg_rs2_index             <= instr[24:20];
                to_reg_need_rs2              <= `TRUE;
                //imm                          <= {{21{instr[31]}},instr[30:25],instr[11:7]};
                //to_rob_op                    <= op;
                //to_lsb_op                    <= op;
                to_lsb_imm                   <= {{21{instr[31]}},instr[30:25],instr[11:7]};
                //to_lsb_rs1_value             <= rs1_value;
                //to_lsb_rs2_value             <= rs2_value;
                instr_need_fill_rd             <= `FALSE;
                enable_lsb                     <= `TRUE;
                enable_rs                      <= `FALSE;
                to_lsb_rd_rename               <= rob_free_tag;
            end
            7'b0110011: begin
                case(instr[`FUNC3])
                    3'b000:
                        case(instr[`FUNC7])
                            7'b0000000: op   <= `ADD;
                            7'b0100000: op   <= `SUB;
                            default:begin end
                        endcase
                    3'b001: op               <= `SLL;
                    3'b010: op               <= `SLT;
                    3'b011: op               <= `SLTU;
                    3'b100: op               <= `XOR;
                    3'b101: begin
                        case(instr[`FUNC7])
                            7'b0000000: op   <= `SRL;
                            7'b0100000: op   <= `SRA;
                            default:begin end
                        endcase
                    end
                    3'b110: op               <= `OR;
                    3'b111: op               <= `AND;
                    default:begin end
                endcase
                to_reg_rs1_index             <= instr[19:15];
                to_reg_need_rs1              <= `TRUE;
                to_reg_rs2_index             <= instr[24:20];
                to_reg_need_rs2              <= `TRUE;
                //rd                           <= instr[11:7];
                //to_rs_rs1_value              <= rs1_value;
                //to_rs_rs2_value              <= rs2_value;
                to_rs_rd_rename              <= rob_free_tag;
                //to_rs_op                     <= op;
                //to_rob_op                    <= op;
                to_rob_destination_reg_index <= instr[11:7];
                instr_need_fill_rd             <= `TRUE;
                to_reg_rd_index                <= instr[11:7];
                enable_rs                    <= `TRUE;
                enable_lsb                   <= `FALSE;
            end
            7'b0110111: begin
                op                           <= `LUI;
                //rd                           <= instr[11:7];
                //imm                          <= {instr[31:12],12'b0};
                to_rs_imm                    <= {instr[31:12],12'b0};
                //to_rob_op                    <= op;
                //to_rs_op                     <= op;
                to_rs_rd_rename              <= rob_free_tag;
                to_rob_destination_reg_index <= instr[11:7];
                instr_need_fill_rd             <= `TRUE;
                to_reg_rd_index                <= instr[11:7];
                to_reg_need_rs1              <= `FALSE;
                to_reg_need_rs2              <= `FALSE;
                enable_rs                    <= `TRUE;
                enable_lsb                   <= `FALSE;
            end
            7'b1100011: begin
                case(instr[`FUNC3])
                    3'b000: op               <= `BEQ;
                    3'b001: op               <= `BNE;
                    3'b100: op               <= `BLT;
                    3'b101: op               <= `BGE;
                    3'b110: op               <= `BLTU;
                    3'b111: op               <= `BGEU;
                    default:begin end
                endcase
                to_reg_rs1_index              <= instr[19:15];
                to_reg_need_rs1              <= `TRUE;
                to_reg_rs2_index              <= instr[24:20];
                to_reg_need_rs2              <= `TRUE;
                //imm                          <= {{20{instr[31]}},instr[7],instr[30:25],instr[11:8],1'b0};
                //to_rs_rs1_value              <= rs1_value;
                //to_rs_rs2_value              <= rs2_value;
                to_rs_imm                    <= {{20{instr[31]}},instr[7],instr[30:25],instr[11:8],1'b0};
                //to_rs_op                     <= op;
                //to_rob_op                    <= op;
                instr_need_fill_rd             <= `FALSE;
                enable_rs                    <= `TRUE;
                enable_lsb                   <= `FALSE;
                to_rs_rd_rename              <= rob_free_tag;
            end
            7'b1100111: begin
                op                           <= `JALR;
                to_reg_rs1_index             <= instr[19:15];
                to_reg_need_rs1              <= `TRUE;
                to_reg_need_rs2              <= `FALSE;
                //rd                           <= instr[11:7];
                //imm                          <= {{21{instr[31]}},instr[30:20]};
                //to_rs_rs1_value              <= rs1_value;
                to_rs_rd_rename                 <= rob_free_tag;
                to_rs_imm                    <= {{21{instr[31]}},instr[30:20]};
                //to_rs_op                     <= op;
                //to_rob_op                    <= op;
                to_rob_destination_reg_index <= instr[11:7];
                instr_need_fill_rd             <= `TRUE;
                to_reg_rd_index                <= instr[11:7];
                enable_rs                    <= `TRUE;
                enable_lsb                   <= `FALSE;
            end
            7'b1101111: begin
                op                           <= `JAL;
                //imm                          <= {{12{instr[31]}},instr[19:12],instr[20],instr[30:21],1'b0};
                //rd                           <= instr[11:7];
                to_rs_rd_rename                 <= rob_free_tag;
                to_rs_imm                    <=  {{12{instr[31]}},instr[19:12],instr[20],instr[30:21],1'b0};
                //to_rs_op                     <= op;
                //to_rob_op                    <= op;
                to_rob_destination_reg_index <= instr[11:7];
                instr_need_fill_rd             <= `TRUE;
                to_reg_rd_index                <= instr[11:7];
                to_reg_need_rs1              <= `FALSE;
                to_reg_need_rs2              <= `FALSE;
                enable_rs                    <= `TRUE;
                enable_lsb                   <= `FALSE;
            end
            default:begin end
         endcase
    end else begin
        decode_success                       <= `FALSE;
        instr_need_fill_rd                   <= `FALSE;
    end
end
endmodule