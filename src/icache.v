`include "define.v"

//从mem中预取指令，然后按照pc把指令取给IF
module ICache (
    //control signals
    input wire clk,
    input wire rst,
    input wire rdy,

    //IF module
    //IF requires, and ICache gives
    input wire if_enable,
    input wire jump_wrong,
    input  wire [`ADDR] require_addr,
    output reg [`INSTRLEN] IF_instr,
    output reg fetch_success,

    //RAM module(actually is mem_ctrl module)
    //ICache requires, and RAM gives
    input  wire [`INSTRLEN] mem_instr,
    output reg [`ADDR] mem_addr,
    output reg mem_enable,//需要在mem中进行查找
    input  wire mem_fetch_success
);
  reg [`INSTRLEN] icache[`ICSIZE];
  reg [`ICSIZE] valid;
  reg [`ICTAG] tag[`ICSIZE];
  integer debug_hit;
  initial begin
    fetch_success <= `FALSE;
    mem_enable <=`FALSE;
    mem_addr <= `NULL32;
    debug_hit <= 0;
  end
integer i;
  always @(posedge clk) begin
    if (rst==`TRUE) begin
      fetch_success                              <= `FALSE;
      mem_enable <= `FALSE;
      for(i=0;i<`ICSIZESCALAR;i=i+1) begin
        valid[i]                                 <=`FALSE;
      end
    // end else if(jump_wrong == `TRUE) begin
    //   fetch_success <= `FALSE;//这里只有不成功后面才不会有隐患，要不然拿到if说成功了if就会给predictor，就会传回jump_pc让if出错
    end else if(rdy==`TRUE && if_enable==`TRUE && jump_wrong == `FALSE) begin
          if (valid[require_addr[`ICINDEX]] && (tag[require_addr[`ICINDEX]]==require_addr[`ICTAG])) begin
                IF_instr                         <= icache[require_addr[`ICINDEX]];
                fetch_success                    <= `TRUE;
                debug_hit <= 1;
          end else begin
              //否则就miss掉了，需要到memory中进行查找
              debug_hit<= 0;
              if(mem_fetch_success == `TRUE) begin
                  valid[require_addr[`ICINDEX]]  <= `TRUE;
                  tag[require_addr[`ICINDEX]]    <= require_addr[`ICTAG];
                  icache[require_addr[`ICINDEX]] <= mem_instr;
                  fetch_success                  <= `TRUE;
                  IF_instr                       <= mem_instr;
                  mem_enable                     = `FALSE;
              end else begin
                mem_addr                         <= require_addr;
                mem_enable                       <= `TRUE;
                fetch_success                    <= `FALSE;
                IF_instr                         <= `NULL32;
              end
          end
    end
    else begin
      mem_enable                                 <= `FALSE;
      fetch_success                              <= `FALSE;
    end
  end
endmodule
