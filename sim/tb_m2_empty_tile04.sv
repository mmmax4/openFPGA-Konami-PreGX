// Actual tile producer; all setup and memory use its public ports.
`default_nettype none
module tb_m2_empty_tile04 (
 input logic clk,reset,line_start,reg_we,cb_we,
 input logic [8:0] line,px,
 input logic [4:0] reg_addr,input logic [15:0] reg_data,
 input logic [1:0] cb_addr,input logic [7:0] cb_data,
 output wire busy,unsupported,
 output wire vreq,output wire [15:0] vaddr,input logic vack,input logic [15:0] vq,
 output wire rreq,output wire [18:0] raddr,input logic rack,input logic [31:0] rq,input logic [7:0] fifth,
 output wire [3:0] summary,
 output wire [14:0] packed0,packed1,packed2,packed3
);
 logic [15:0] regs[32];
 logic [7:0] cb[4];
 always_ff @(posedge clk) begin
  if(reg_we)regs[reg_addr]<=reg_data;
  if(cb_we)cb[cb_addr]<=cb_data;
 end
 wire [11:0] pen[4];wire [1:0] category[4];wire [3:0] opaque;
 k056832_tilemap tile(.clk(clk),.reset(reset),.mystic(1'b1),
  .line_start(line_start),.line(line),.busy(busy),.regs(regs),.colorbase(cb),
  .vram_req(vreq),.vram_addr(vaddr),.vram_ack(vack),.vram_q(vq),
  .rom_req(rreq),.rom_addr(raddr),.rom_ack(rack),.rom_q(rq),.rom_fifth(fifth),
  .px(px),.pix(pen),.opaque(opaque),.category(category),.line_nonempty(summary),.unsupported(unsupported));
 assign packed0={category[0],opaque[0],pen[0]};
 assign packed1={category[1],opaque[1],pen[1]};
 assign packed2={category[2],opaque[2],pen[2]};
 assign packed3={category[3],opaque[3],pen[3]};
endmodule
`default_nettype wire
