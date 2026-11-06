`default_nettype none
module m3_sprite_top(input logic clk,reset,start,input logic [15:0] words[7],
 input logic [31:0] order,input logic [8:0] line,input logic [63:0] rom_q,
 input logic rom_ack,output logic rom_req,output logic [19:0] rom_addr,
 input logic ready,output logic valid,output logic [8:0] x,
 output logic [11:0] pen,output logic busy);
 wire [9:0] list_idx,za;wire[7:0] yr_addr;wire[10:0] ra,rca;
 logic[15:0] ram_q;logic[31:0] list_q;logic[21:0] yr_q;
 wire[23:0] zq,rcq;
 always_ff @(posedge clk) begin
  ram_q <= ra[2:0]<7 ? words[ra[2:0]] : 16'd0;
  list_q<=order;yr_q<={11'd0,11'd263};
 end
 sprite_tables #(.HEXDIR("rtl/data")) tab(.clk(clk),.zoom_addr(za),.zoom_q(zq),.recip_addr(rca),.recip_q(rcq));
 k053247_draw dut(.clk(clk),.reset(reset),.violent(1'b1),.mystic(1'b0),
 .rom_fifth(16'd0),.line_start(start),.line(line),.busy(busy),
 .k46r5(8'd0),.k46_offx(16'd0),.k46_offy(16'd0),.opset(16'd0),.colorbase(8'd0),
 .alpha1(10'd255),.alpha2(10'd255),.alpha3(10'd255),.stream_enable(1'b1),
 .order_valid(),.order_priority(),.order_deferred(),.order_ready(1'b1),
 .fragment_valid(valid),.fragment_ready(ready),.fragment_x(x),.fragment_pen(pen),
 .fragment_level(),.fragment_shadow(),.fragment_table(),.fragment_condition(),.fragment_z(),.fragment_pri(),
 .list_idx(list_idx),.list_q(list_q),.list_count(10'd1),.yr_addr(yr_addr),.yr_q(yr_q),.ram_addr(ra),.ram_q(ram_q),
 .rom_req(rom_req),.rom_addr(rom_addr),.rom_ack(rom_ack),.rom_q(rom_q),
 .zoom_addr(za),.zoom_q(zq),.recip_addr(rca),.recip_q(rcq),
 .px(9'd0),.out_opaque(),.out_pen(),.out_pri(),.out_effect(),.out_shadow(),.out_shtab(),.out_shpri(),
 .shadow_overlap(),.dbg_objs(),.dbg_rows(),.dbg_cols(),.dbg_pxw());
endmodule
