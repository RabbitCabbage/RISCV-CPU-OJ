// RISCV32I CPU top module
// port modification allowed for debugging purposes
`include "define.v"
`include "alu.v"
`include "decoder.v"
`include "icache.v"
`include "ifetch.v"
`include "lsb.v"
`include "mem_ctrl.v"
`include "reg_file.v"
`include "rob.v"
`include "rs.v"
`include "predictor.v"

module cpu(
  input  wire                 clk_in,     // system clock signal
  input  wire                 rst_in,     // reset signal
  input  wire                 rdy_in,     // ready signal, pause cpu when low

  input  wire [ 7:0]          mem_din,    // data input bus
  output wire [ 7:0]          mem_dout,   // data output bus
  output wire [31:0]          mem_a,      // address bus (only 17:0 is used)//todo
  output wire                 mem_wr,     // write/read signal (1 for write)//todo
  
  input  wire                 io_buffer_full, // 1 if uart buffer is full
  
  output wire [31:0]      dbgreg_dout   // cpu register output (debugging demo)//todo
);

// implementation goes here

// Specifications:
// - Pause cpu(freeze pc, registers, etc.)//todo when rdy_in is low
// - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)//todo
// - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
// - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)//todo
// - 0x30000 read: read a byte from input
// - 0x30000 write: write a byte to output (write 0x00 is ignored)//todo
// - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)//todo
// - 0x30004 write: indicates program stop (will output '\0' through uart tx)//todo
//control auguments
wire jump_wrong;
wire rs_full;
wire rob_full;
wire lsb_full;
wire stall_IF;
wire stall_decoder;
wire [`ROBINDEX] rob_head;


//icache and ifetch
wire if_enable_icache;
wire [`ADDR]if_pc_to_icache;
wire [`INSTRLEN] icache_instr_to_if;
wire icache_success_to_if;

//icache and mem_ctrl
wire [`ADDR] icache_addr_to_memctrl;
wire [`INSTRLEN] memctrl_instr_to_icache;
wire icache_enable_memctrl;
wire memctrl_success_to_icache;

//ifetch and decoder
wire [`INSTRLEN] if_instr_to_decoder;
wire [`ADDR] if_pc_to_decoder;
wire if_success_to_decoder;
wire if_success_to_predictor;

//decoder and rs
wire [`DATALEN]decoder_rs1_value_to_rs;
wire [`DATALEN]decoder_rs2_value_to_rs;
wire [`ROBINDEX]decoder_rs1_rename_to_rs;
wire [`ROBINDEX]decoder_rs2_rename_to_rs;
wire [`ROBINDEX]decoder_rd_rename_to_rs;
wire [`DATALEN]decoder_imm_to_rs;
wire [`OPLEN]decoder_op_to_rs;
wire [`ADDR] decoder_pc_out;
wire decoder_success_out;
wire decoder_enable_rs;

//decoder and lsb
wire [`DATALEN]decoder_rs1_value_to_lsb;
wire [`DATALEN]decoder_rs2_value_to_lsb;
wire [`ROBINDEX]decoder_rs1_rename_to_lsb;
wire [`ROBINDEX]decoder_rs2_rename_to_lsb;
wire [`ROBINDEX]decoder_rd_rename_to_lsb;
wire [`DATALEN]decoder_imm_to_lsb;
wire [`OPLEN]decoder_op_to_lsb;
wire decoder_enable_lsb;

//decoder and regfile
wire [`ROBINDEX] reg_rs1_rename_to_decoder;
wire [`ROBINDEX] reg_rs2_rename_to_decoder;
wire [`DATALEN] reg_rs1_value_to_decoder;
wire [`DATALEN] reg_rs2_value_to_decoder;
wire reg_rs1_renamed_to_decoder;
wire reg_rs2_renamed_to_decoder;
wire [`REGINDEX] decoder_rs1_index_to_reg;
wire [`REGINDEX] decoder_rs2_index_to_reg;
wire [`REGINDEX] decoder_rd_index_to_reg;
wire [`ROBINDEX] decoder_rd_rename_to_reg;
wire decoder_instr_need_rs1_to_reg;
wire decoder_instr_need_rs2_to_reg;

//decoder and rob
wire [`ROBINDEX] decoder_rd_rename_to_rob;
wire [`ROBINDEX] rob_free_tag_to_decoder;
wire [`DATALEN] rob_rs1_value_to_decoder;
wire [`DATALEN] rob_rs2_value_to_decoder;
wire rob_rs1_ready_to_decoder;
wire rob_rs2_ready_to_decoder;
wire [`REGINDEX] decoder_rs1_index_to_rob;
wire [`REGINDEX] decoder_rs2_index_to_rob;
wire [`OPLEN] decoder_op_to_rob;
wire [`REGINDEX] decoder_rd_index_to_rob;
wire decode_instr_need_rd;
wire [`INSTRLEN] decoder_instr_to_rob;
//reg and rob
wire [`REGINDEX] rob_rd_index_to_reg;
wire [`ROBINDEX] rob_rd_rename_to_reg;
wire [`DATALEN] rob_rd_value_to_reg;
wire rob_enable_regfile;
//memctrl and ram
wire memctrl_enable_ram;

//memctrl and lsb
wire lsb_read_signal_to_memctrl;
wire lsb_write_signal_to_memctrl;
wire [`LSBINSTRLEN]lsb_requiring_length_to_memctrl;
wire [`DATALEN] lsb_store_data_to_memctrl;
wire [`ADDR] lsb_addr_to_memctrl;
wire memctrl_load_success_to_lsb;
wire [`DATALEN] memctrl_load_data_to_lsb;
wire memctrl_store_success_to_lsb;
// alu out
wire alu_broadcast;
wire [`ROBINDEX]alu_broadcast_rd_rename;
wire [`DATALEN]alu_broadcast_result;
wire [`DATALEN] alu_broadcast_jump_pc;
//alu and rs
wire [`ROBINDEX] rs_rd_rename_to_alu;
wire [`DATALEN] rs_rs1_value_to_alu;
wire [`DATALEN] rs_rs2_value_to_alu;
wire [`OPLEN] rs_op_to_alu;
wire [`IMMLEN] rs_imm_to_alu;
wire [`ADDR] rs_addr_to_alu;
wire rs_enable_alu;
//lsb out
wire lsb_broadcast;
wire [`DATALEN] lsb_broadcast_result;
wire [`ROBINDEX] lsb_broadcast_rename;
wire rob_broadcast;
wire [`DATALEN] rob_broadcast_result;
wire [`ROBINDEX] rob_broadcast_rename;
// rob and lsb
//这个表示的是rob最后让lsb的commit，关于ram的commit由lsb代做
//wire rob_enable_lsb_read;
wire rob_enable_lsb_write;
wire [`DATALEN]rob_store_data_to_lsb;
wire [`ADDR] rob_addr_to_lsb;
wire [`DATALEN] lsb_load_data_to_rob;
wire [`LSBINSTRLEN] rob_length_lsb;
wire lsb_store_instr_ready_to_rob;
wire [`ROBINDEX] lsb_ready_store_instr_rename_to_rob;
wire [`DATALEN] lsb_store_value_to_rob;
//下面表示的是rob从lsb那里得到计算出来的目标destination mem addr
wire lsb_enable_calculated_addr_to_rob;
wire [`ADDR] lsb_calculated_destination_addr_to_rob;
wire [`ROBINDEX] lsb_calculated_instr_rd_rename_to_rob;
wire [`INSTRLEN] rob_commit_store_instr_to_lsb;

//rob out jumping information
// predictor and rob&if
wire [`INSTRLEN]if_instr_to_ask_for_prediction;
wire predictor_is_jump_instr_to_if;
wire predictor_predicted_jump;
wire [`ADDR] predictor_jump_pc_to_if;
wire [`ADDR] if_instr_pc_to_predictor;

wire rob_real_jump_to_predictor;
wire [`PREDICTORINDEX] rob_branch_instr_pc_itself;
wire [`ADDR] rob_real_destination_pc;
wire rob_enable_predictor;
wire predictor_stall_if;
wire [`OPLEN]alu_broadcast_op;
wire predictor_enable_if;
assign stall_IF = (rs_full==`TRUE || rob_full==`TRUE || lsb_full==`TRUE || predictor_stall_if==`TRUE);
assign stall_decoder = (rs_full==`TRUE || rob_full==`TRUE || lsb_full==`TRUE);
wire ifetch_jump_change_success_to_rob;

// initial begin
//   assign rs_full = `FALSE;
//   assign rob_full = `FALSE;
//   assign lsb_full = `FALSE;
// end
wire reg_finished_for_decoder;

ROB rob_
    (
      .clk                           (clk_in),
      .rdy                           (rdy_in),
      .rst                           (rst_in),
      .io_buffer_full(io_buffer_full),
      .rob_enable_lsb_write          (rob_enable_lsb_write),
      .commit_store_instr            (rob_commit_store_instr_to_lsb),
      .to_lsb_value                  (rob_store_data_to_lsb),
      .to_lsb_size                   (rob_length_lsb),
      .to_lsb_addr                   (rob_addr_to_lsb),
      //.rob_enable_lsb_read           (rob_enable_lsb_read),
      .from_lsb_data                 (lsb_load_data_to_rob),
      .to_reg_rd                     (rob_rd_index_to_reg),
      .to_reg_value                  (rob_rd_value_to_reg),
      .to_reg_rename                 (rob_rd_rename_to_reg),
      .rob_free_tag                  (rob_free_tag_to_decoder),
      .enable_reg                    (rob_enable_regfile),
      .decoder_input_enable          (decoder_success_out),
      .decoder_rd_rename             (decoder_rd_rename_to_rob),
      .decoder_instr                 (decoder_instr_to_rob),
      .decoder_fetch_rs1_index       (decoder_rs1_index_to_rob),
      .decoder_fetch_rs2_index       (decoder_rs2_index_to_rob),
      .to_decoder_rs1_ready          (rob_rs1_ready_to_decoder),
      .to_decoder_rs2_ready          (rob_rs2_ready_to_decoder),
      .to_decoder_rs1_value          (rob_rs1_value_to_decoder),
      .to_decoder_rs2_value          (rob_rs2_value_to_decoder),
      .decoder_op                    (decoder_op_to_rob),
      .decoder_pc                    (decoder_pc_out),
      .predicted_jump                (predictor_predicted_jump),
      .lsb_destination_mem_addr      (lsb_calculated_destination_addr_to_rob),
      .lsb_input_addr_enable              (lsb_enable_calculated_addr_to_rob),
      .from_lsb_rename               (lsb_calculated_instr_rd_rename_to_rob),
      .decoder_destination_reg_index (decoder_rd_index_to_rob),
      .alu_broadcast                 (alu_broadcast),
      .alu_cbd_value                 (alu_broadcast_result),
      .alu_jumping_pc                (alu_broadcast_jump_pc),
      .alu_update_rename             (alu_broadcast_rd_rename),
      .lsb_broadcast                 (lsb_broadcast),
      .lsb_cbd_value                 (lsb_broadcast_result),
      .lsb_update_rename             (lsb_broadcast_rename),
      .lsb_store_instr_ready         (lsb_store_instr_ready_to_rob),
      .lsb_ready_store_instr_rename        (lsb_ready_store_instr_rename_to_rob),
      .lsb_store_value(lsb_store_value_to_rob),
      .lsb_store_success(memctrl_store_success_to_lsb),
      .rob_broadcast                 (rob_broadcast),
      .rob_update_rename             (rob_broadcast_rename),
      .rob_cbd_value                 (rob_broadcast_result),
      .rob_full                      (rob_full),
      .jump_wrong                    (jump_wrong),//输出跳错的信息给到各个部分
      .jumping_pc                    (rob_real_destination_pc),//输出发生跳错的指令真正要跳的pc
      .to_predictor_enable           (rob_enable_predictor),//通知predictor要告诉它情况了
      .to_predictor_jump             (rob_real_jump_to_predictor),//告诉predictor真实的情况
      .to_predictor_pc               (rob_branch_instr_pc_itself),//输出跳错的指令本身的pc
      .ifetch_jump_change_success    (ifetch_jump_change_success_to_rob),
      .rob_head(rob_head)    
    );
IF if_
    (
      .clk             (clk_in),
      .rst             (rst_in),
      .rdy             (rdy_in),
      .jump_wrong      (jump_wrong),
      .jump_pc_from_rob         (rob_real_destination_pc),
      .icache_enable   (if_enable_icache),
      .pc_to_fetch     (if_pc_to_icache),
      .instr_fetched   (icache_instr_to_if),
      .icache_success  (icache_success_to_if),
      .stall_IF        (stall_IF),
      .instr_to_decode (if_instr_to_decoder),
      .pc_to_decoder   (if_pc_to_decoder),
      .if_success_to_decoder      (if_success_to_decoder),
      .if_success_to_predictor(if_success_to_predictor),
      .instr_pc_to_predictor(if_instr_pc_to_predictor),
      .instr_to_predictor(if_instr_to_ask_for_prediction),
      .is_jump_instr   (predictor_is_jump_instr_to_if),
      .jump_prediction (predictor_predicted_jump),
      .jump_pc_from_predictor(predictor_jump_pc_to_if),
      .predictor_enable(predictor_enable_if),
      .ifetch_jump_change_success(ifetch_jump_change_success_to_rob)
    );
ICache icache_
    (
      .clk               (clk_in),
      .rst               (rst_in),
      .rdy               (rdy_in),
      .if_enable         (if_enable_icache),
      .require_addr      (if_pc_to_icache),
      .IF_instr          (icache_instr_to_if),
      .fetch_success     (icache_success_to_if),
      .mem_instr         (memctrl_instr_to_icache),
      .mem_addr          (icache_addr_to_memctrl),
      .mem_enable        (icache_enable_memctrl),
      .mem_fetch_success (memctrl_success_to_icache),
      .jump_wrong        (jump_wrong)
    );
Decoder decoder_
    (
      .clk                          (clk_in),
      .rst                          (rst_in),
      .rdy                          (rdy_in),
      .stall_decoder                (stall_decoder),
      .IF_success                   (if_success_to_decoder),
      .instr                        (if_instr_to_decoder),
      .fetch_pc                     (if_pc_to_decoder),
      .decode_success               (decoder_success_out),
      .to_rs_rs1_rename             (decoder_rs1_rename_to_rs),
      .to_rs_rs2_rename             (decoder_rs2_rename_to_rs),
      .to_rs_rd_rename              (decoder_rd_rename_to_rs),
      .to_rs_imm                    (decoder_imm_to_rs),
      .to_rs_rs1_value              (decoder_rs1_value_to_rs),
      .to_rs_rs2_value              (decoder_rs2_value_to_rs),
      .to_rs_op                     (decoder_op_to_rs),
      .decode_pc                    (decoder_pc_out),
      .to_lsb_rs1_rename            (decoder_rs1_rename_to_lsb),
      .to_lsb_rs2_rename            (decoder_rs2_rename_to_lsb),
      .to_lsb_rd_rename             (decoder_rd_rename_to_lsb),
      .to_lsb_rs1_value             (decoder_rs1_value_to_lsb),
      .to_lsb_rs2_value             (decoder_rs2_value_to_lsb),
      .to_lsb_imm                   (decoder_imm_to_lsb),
      .to_lsb_op                    (decoder_op_to_lsb),
      .from_reg_rs1_rob_rename      (reg_rs1_rename_to_decoder),
      .from_reg_rs2_rob_rename      (reg_rs2_rename_to_decoder),
      .reg_rs1_value                (reg_rs1_value_to_decoder),
      .reg_rs2_value                (reg_rs2_value_to_decoder),
      .reg_rs1_renamed                 (reg_rs1_renamed_to_decoder),
      .reg_rs2_renamed                 (reg_rs2_renamed_to_decoder),
      .reg_finished_for_decoder        (reg_finished_for_decoder),
      .to_reg_rs1_index             (decoder_rs1_index_to_reg),
      .to_reg_rs2_index             (decoder_rs2_index_to_reg),
      .to_reg_rd_rename             (decoder_rd_rename_to_reg),
      .to_reg_rd_index              (decoder_rd_index_to_reg),
      .to_reg_need_rs1              (decoder_instr_need_rs1_to_reg),
      .to_reg_need_rs2              (decoder_instr_need_rs2_to_reg),
      .rob_free_tag                 (rob_free_tag_to_decoder),
      .to_rob_rd_rename             (decoder_rd_rename_to_rob),
      .to_rob_instr                 (decoder_instr_to_rob),
      .rob_fetch_rs1_value          (rob_rs1_value_to_decoder),
      .rob_rs1_ready                (rob_rs1_ready_to_decoder),
      .rob_fetch_rs2_value          (rob_rs2_value_to_decoder),
      .rob_rs2_ready                (rob_rs2_ready_to_decoder),
      .rob_fetch_rs1_index          (decoder_rs1_index_to_rob),
      .rob_fetch_rs2_index          (decoder_rs2_index_to_rob),
      .to_rob_op                    (decoder_op_to_rob),
      .to_rob_destination_reg_index (decoder_rd_index_to_rob),
      .instr_need_fill_rd             (decode_instr_need_rd),
      .enable_lsb                    (decoder_enable_lsb),
      .enable_rs                     (decoder_enable_rs),
      .jump_wrong                   (jump_wrong)
    );
RegFile regfile_
    (
      .clk                    (clk_in),
      .rst                    (rst_in),
      .rdy                    (rdy_in),
      .decoder_success        (decoder_success_out),
      .jump_wrong             (jump_wrong),
      .from_decoder_rs1_index (decoder_rs1_index_to_reg),
      .from_decoder_rs2_index (decoder_rs2_index_to_reg),
      .from_decoder_rd_index  (decoder_rd_index_to_reg),
      .decoder_need_rs1       (decoder_instr_need_rs1_to_reg),
      .decoder_need_rs2       (decoder_instr_need_rs2_to_reg),
      .decoder_have_rd_waiting(decode_instr_need_rd),
      .decoder_rd_rename      (decoder_rd_rename_to_reg),
      .rs1_renamed            (reg_rs1_renamed_to_decoder),
      .rs2_renamed            (reg_rs2_renamed_to_decoder),
      .to_decoder_rs1_value   (reg_rs1_value_to_decoder),
      .to_decoder_rs2_value   (reg_rs2_value_to_decoder),
      .to_decoder_rs1_rename  (reg_rs1_rename_to_decoder),
      .to_decoder_rs2_rename  (reg_rs2_rename_to_decoder),
      .rob_enable             (rob_enable_regfile),
      .rob_commit_index       (rob_rd_index_to_reg),
      .rob_commit_rename      (rob_rd_rename_to_reg),
      .rob_commit_value       (rob_rd_value_to_reg),
      .reg_finished_for_decoder(reg_finished_for_decoder)
    );
// RAM ram_
//   (
//       .clk_in  (clk_in),
//       .en_in   (memctrl_enable_ram),
//       .r_nw_in (memctrl_read_write_to_ram),
//       .a_in    (memctrl_addr_to_ram[16:0]),
//       .d_in    (memctrl_store_byte_to_ram),
//       .d_out   (ram_load_byte_to_memctrl)
//     );
MemCtrl memctrl_
    (
      .clk                (clk_in),
      .rdy                (rdy_in),
      .rst                (rst_in),
      .jump_wrong         (jump_wrong),
      .lsb_write_signal   (lsb_write_signal_to_memctrl),
      .lsb_read_signal    (lsb_read_signal_to_memctrl),
      .lsb_addr           (lsb_addr_to_memctrl),
      .lsb_len            (lsb_requiring_length_to_memctrl),
      .lsb_write_data     (lsb_store_data_to_memctrl),
      .lsb_read_data      (memctrl_load_data_to_lsb),
      .lsb_load_success        (memctrl_load_success_to_lsb),
      .lsb_store_success       (memctrl_store_success_to_lsb),
      .icache_addr        (icache_addr_to_memctrl),
      .icache_read_signal (icache_enable_memctrl),
      .icache_read_instr  (memctrl_instr_to_icache),
      .icache_success     (memctrl_success_to_icache),
      .io_buffer_full     (io_buffer_full),
      .mem_addr           (mem_a),
      .mem_byte_write     (mem_dout),
      .mem_byte_read      (mem_din),
      .read_write         (mem_wr),
      .mem_enable         (memctrl_enable_ram)//todo
    );
ALU alu_
    (
      .clk           (clk_in),
      .rdy           (rdy_in),
      .rst           (rst_in),
      .alu_enable    (rs_enable_alu),
      .in_rd_rename  (rs_rd_rename_to_alu),
      .instr_pc      (rs_addr_to_alu),
      .imm           (rs_imm_to_alu),
      .rs1_value     (rs_rs1_value_to_alu),
      .rs2_value     (rs_rs2_value_to_alu),
      .op            (rs_op_to_alu),
      .result        (alu_broadcast_result),
      .alu_broadcast (alu_broadcast),
      .out_rd_rename (alu_broadcast_rd_rename),
      .jumping_pc    (alu_broadcast_jump_pc),
      .alu_broadcast_op(alu_broadcast_op),
      .jump_wrong    (jump_wrong)
    );
RS rs_
    (
      .clk                (clk_in),
      .rst                (rst_in),
      .rdy                (rdy_in),
      .jump_wrong         (jump_wrong),
      .decode_success     (decoder_success_out),
      .decode_rs1_rename  (decoder_rs1_rename_to_rs),
      .decode_rs2_rename  (decoder_rs2_rename_to_rs),
      .decode_rs1_value   (decoder_rs1_value_to_rs),
      .decode_rs2_value   (decoder_rs2_value_to_rs),
      .decode_imm         (decoder_imm_to_rs),
      .decode_rd_rename   (decoder_rd_rename_to_rs),
      .decode_op          (decoder_op_to_rs),
      .decode_pc          (decoder_pc_out),
      .decoder_enable     (decoder_enable_rs),
      .alu_broadcast      (alu_broadcast),
      .alu_cbd_value      (alu_broadcast_result),
      .alu_update_rename  (alu_broadcast_rd_rename),
      .lsb_broadcast      (lsb_broadcast),
      .lsb_cbd_value      (lsb_broadcast_result),
      .lsb_update_rename  (lsb_broadcast_rename),
      .rob_broadcast      (rob_broadcast),
      .rob_cbd_value      (rob_broadcast_result),
      .rob_update_rename  (rob_broadcast_rename),
      .alu_enable         (rs_enable_alu),
      .to_alu_rd_renaming (rs_rd_rename_to_alu),
      .to_alu_rs1_value   (rs_rs1_value_to_alu),
      .to_alu_rs2_value   (rs_rs2_value_to_alu),
      .to_alu_op          (rs_op_to_alu),
      .to_alu_imm         (rs_imm_to_alu),
      .to_alu_pc          (rs_addr_to_alu),
      .rs_full            (rs_full)
    );
LSB lsb_
    (
      .clk                (clk_in),
      .rdy                (rdy_in),
      .rst                (rst_in),
      .jump_wrong         (jump_wrong),
      .io_buffer_full     (io_buffer_full),
      .lsb_read_signal    (lsb_read_signal_to_memctrl),
      .lsb_write_signal   (lsb_write_signal_to_memctrl),
      .commit_store_instr (rob_commit_store_instr_to_lsb),
      .requiring_length   (lsb_requiring_length_to_memctrl),
      .to_mem_data        (lsb_store_data_to_memctrl),
      .to_mem_addr        (lsb_addr_to_memctrl),
      .mem_load_success   (memctrl_load_success_to_lsb),
      .mem_store_success  (memctrl_store_success_to_lsb),
      .from_mem_data      (memctrl_load_data_to_lsb),
      .decode_signal      (decoder_success_out),
      .decoder_rs1_rename (decoder_rs1_rename_to_lsb),
      .decoder_rs2_rename (decoder_rs2_rename_to_lsb),
      .decoder_rd_rename  (decoder_rd_rename_to_lsb),
      .decoder_rs1_value  (decoder_rs1_value_to_lsb),
      .decoder_rs2_value  (decoder_rs2_value_to_lsb),
      .decoder_imm        (decoder_imm_to_lsb),
      .decoder_op         (decoder_op_to_lsb),
      .decoder_enable     (decoder_enable_lsb),
      .decoder_pc         (decoder_pc_out),
      //.rob_enable_lsb_read(rob_enable_lsb_read),
      .rob_enable_lsb_write(rob_enable_lsb_write),
      .from_rob_addr      (rob_addr_to_lsb),
      .from_rob_length    (rob_length_lsb),
      .from_rob_data_to_store(rob_store_data_to_lsb),
      .to_rob_data_loaded (lsb_load_data_to_rob),
      .alu_broadcast      (alu_broadcast),
      .alu_cbd_value      (alu_broadcast_result),
      .alu_update_rename  (alu_broadcast_rd_rename),
      .rob_broadcast      (rob_broadcast),
      .rob_cbd_value      (rob_broadcast_result),
      .rob_update_rename  (rob_broadcast_rename),
      .lsb_broadcast      (lsb_broadcast),
      .lsb_cbd_value      (lsb_broadcast_result),
      .lsb_update_rename  (lsb_broadcast_rename),
      .lsb_store_instr_ready(lsb_store_instr_ready_to_rob),
      .lsb_ready_store_instr_rename(lsb_ready_store_instr_rename_to_rob),
      .lsb_store_value(lsb_store_value_to_rob),
      .lsb_full           (lsb_full),
      .lsb_destination_addr_to_rob(lsb_calculated_destination_addr_to_rob),
      .lsb_calculated_addr_signal (lsb_enable_calculated_addr_to_rob),
      .lsb_rename_to_rob_for_the_calculated_instr          (lsb_calculated_instr_rd_rename_to_rob),
      .rob_head(rob_head)
      );
Predictor predictor_
    (
      .clk                        (clk_in),
      .rst                        (rst_in),
      .rdy                        (rdy_in),
      .if_success                 (if_success_to_predictor),
      .if_instr_to_ask_for_prediction(if_instr_to_ask_for_prediction),
      .if_instr_pc_itself         (if_instr_pc_to_predictor),
      .rob_enable_predictor       (rob_enable_predictor),
      .is_jump_instr              (predictor_is_jump_instr_to_if),
      .predicted_jump             (predictor_predicted_jump),
      .predict_jump_pc(predictor_jump_pc_to_if),
      .real_jump_or_not           (rob_real_jump_to_predictor),
      .instr_pc                   (rob_branch_instr_pc_itself),
      .jump_to_pc_from_rob        (rob_real_destination_pc),
      .predictor_stall_if         (predictor_stall_if),
      .alu_broadcast              (alu_broadcast),
      .alu_broadcast_op           (alu_broadcast_op),
      .alu_jumping_pc             (alu_broadcast_jump_pc),
      .predictor_enable_if        (predictor_enable_if),
      .jump_wrong                 (jump_wrong)
    );

endmodule