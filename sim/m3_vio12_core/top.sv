`default_nettype none
// Paired actual public interfaces. Only namespace tokens in the old drawer
// and its embedded row cache are changed by the runner.
module m3_vio12_core_top(
 input logic clk,reset,start,mystic,violent,
 input logic [15:0] words[7],input logic[31:0] order,
 input logic[8:0] line,px,input logic[9:0] list_count,
 input logic[63:0] rom_q,input logic[15:0] rom_fifth,input logic rom_ack,
 input logic ready,order_ready,
 output wire[1:0] busy,rom_req,order_valid,order_deferred,valid,shadow,
 output wire[19:0] rom_addr[2],output wire[7:0] order_priority[2],
 output wire[8:0] x[2],output wire[11:0] pen[2],
 output wire[9:0] level[2],output wire[1:0] shadow_table[2],condition[2],
 output wire[7:0] z[2],priority_code[2],
 output wire[1:0] opaque,scan_shadow,overlap,
 output wire[11:0] scan_pen[2],output wire[7:0] scan_pri[2],scan_shpri[2],
 output wire[1:0] scan_effect[2],scan_table[2],
 output wire[9:0] list_idx[2],output wire[7:0] yr_addr[2],
 output wire[10:0] ram_addr[2],output wire[31:0] objects[2],rows[2],columns[2],writes[2],
 input logic rctrl_we,input logic[3:0]rctrl_addr,input logic[15:0]rctrl_data,
 input logic rclip_we,rclip_addr,input logic[15:0]rclip_data,
 input logic rcfg_we,r_enable,input logic[7:0]rpalbase,
 input logic rmap_we,input logic[18:0]rmap_waddr,input logic[15:0]rmap_wdata,
 input logic rchr_we,input logic[19:0]rchr_waddr,input logic[15:0]rchr_wdata,
 input logic rprestart,rstart,input logic[8:0]rline,rpx,
 output wire[1:0]rbusy,ropaque,runsupported,rprotocol,rmap_req,rblk_req,
 output wire[19:0]rmap_addr[2],output wire[15:0]rblk_addr[2],
 output wire[11:0]rpix[2],output wire[3:0]rlead[2],
 output wire[31:0]rmap_transactions[2],rblock_transactions[2]);
 wire[1:0]draw_enable;
 core_profile_candidate profile0(.clk(clk),.reset(reset),.mystic(mystic),.violent(violent),.prestart(1'b0),.line_start(start),.draw_enable(draw_enable[0]),.roz_reset(),.roz_prestart(),.roz_line_start());
 core_profile_baseline profile1(.clk(clk),.reset(reset),.mystic(mystic),.violent(violent),.prestart(1'b0),.line_start(start),.draw_enable(draw_enable[1]),.roz_reset(),.roz_prestart(),.roz_line_start());

wire[9:0] za0;wire[10:0] rca0;wire[23:0] zq0,rcq0;
 logic[15:0] ram_q0;logic[31:0] list_q0;logic[21:0] yr_q0;
 always_ff @(posedge clk) begin
  ram_q0 <= ram_addr[0][2:0]<7 ? words[ram_addr[0][2:0]] : 16'd0;
  list_q0<=order;yr_q0<={11'd0,11'd263};
 end
 sprite_tables #(.HEXDIR("rtl/data")) tab0(.clk(clk),.zoom_addr(za0),.zoom_q(zq0),.recip_addr(rca0),.recip_q(rcq0));
 k053247_draw dut0(.clk(clk),.reset(reset),.violent(violent),.mystic(mystic),
 .rom_fifth(rom_fifth),.line_start(start),.line(line),.busy(busy[0]),
 .k46r5(8'd0),.k46_offx(16'd0),.k46_offy(16'd0),.opset(16'd0),.colorbase(8'd0),
 .alpha1(10'd128),.alpha2(10'd96),.alpha3(10'd64),.stream_enable(draw_enable[0]),
 .order_valid(order_valid[0]),.order_priority(order_priority[0]),.order_deferred(order_deferred[0]),.order_ready(order_ready),
 .fragment_valid(valid[0]),.fragment_ready(ready),.fragment_x(x[0]),.fragment_pen(pen[0]),
 .fragment_level(level[0]),.fragment_shadow(shadow[0]),.fragment_table(shadow_table[0]),.fragment_condition(condition[0]),.fragment_z(z[0]),.fragment_pri(priority_code[0]),
 .list_idx(list_idx[0]),.list_q(list_q0),.list_count(list_count),.yr_addr(yr_addr[0]),.yr_q(yr_q0),.ram_addr(ram_addr[0]),.ram_q(ram_q0),
 .rom_req(rom_req[0]),.rom_addr(rom_addr[0]),.rom_ack(rom_ack),.rom_q(rom_q),
 .zoom_addr(za0),.zoom_q(zq0),.recip_addr(rca0),.recip_q(rcq0),
 .px(px),.out_opaque(opaque[0]),.out_pen(scan_pen[0]),.out_pri(scan_pri[0]),.out_effect(scan_effect[0]),.out_shadow(scan_shadow[0]),.out_shtab(scan_table[0]),.out_shpri(scan_shpri[0]),
 .shadow_overlap(overlap[0]),.dbg_objs(objects[0]),.dbg_rows(rows[0]),.dbg_cols(columns[0]),.dbg_pxw(writes[0]));
wire[9:0] za1;wire[10:0] rca1;wire[23:0] zq1,rcq1;
 logic[15:0] ram_q1;logic[31:0] list_q1;logic[21:0] yr_q1;
 always_ff @(posedge clk) begin
  ram_q1 <= ram_addr[1][2:0]<7 ? words[ram_addr[1][2:0]] : 16'd0;
  list_q1<=order;yr_q1<={11'd0,11'd263};
 end
 sprite_tables #(.HEXDIR("rtl/data")) tab1(.clk(clk),.zoom_addr(za1),.zoom_q(zq1),.recip_addr(rca1),.recip_q(rcq1));
 k053247_draw_baseline dut1(.clk(clk),.reset(reset),.violent(violent),.mystic(mystic),
 .rom_fifth(rom_fifth),.line_start(start),.line(line),.busy(busy[1]),
 .k46r5(8'd0),.k46_offx(16'd0),.k46_offy(16'd0),.opset(16'd0),.colorbase(8'd0),
 .alpha1(10'd128),.alpha2(10'd96),.alpha3(10'd64),.stream_enable(draw_enable[1]),
 .order_valid(order_valid[1]),.order_priority(order_priority[1]),.order_deferred(order_deferred[1]),.order_ready(order_ready),
 .fragment_valid(valid[1]),.fragment_ready(ready),.fragment_x(x[1]),.fragment_pen(pen[1]),
 .fragment_level(level[1]),.fragment_shadow(shadow[1]),.fragment_table(shadow_table[1]),.fragment_condition(condition[1]),.fragment_z(z[1]),.fragment_pri(priority_code[1]),
 .list_idx(list_idx[1]),.list_q(list_q1),.list_count(list_count),.yr_addr(yr_addr[1]),.yr_q(yr_q1),.ram_addr(ram_addr[1]),.ram_q(ram_q1),
 .rom_req(rom_req[1]),.rom_addr(rom_addr[1]),.rom_ack(rom_ack),.rom_q(rom_q),
 .zoom_addr(za1),.zoom_q(zq1),.recip_addr(rca1),.recip_q(rcq1),
 .px(px),.out_opaque(opaque[1]),.out_pen(scan_pen[1]),.out_pri(scan_pri[1]),.out_effect(scan_effect[1]),.out_shadow(scan_shadow[1]),.out_shtab(scan_table[1]),.out_shpri(scan_shpri[1]),
 .shadow_overlap(overlap[1]),.dbg_objs(objects[1]),.dbg_rows(rows[1]),.dbg_cols(columns[1]),.dbg_pxw(writes[1]));
source_roz_candidate r0(.clk(clk),.reset(reset),.mystic(mystic),.violent(violent),.variable_latency(1'b1),
 .ctrl_we(rctrl_we),.ctrl_addr(rctrl_addr),.ctrl_data(rctrl_data),.clip_we(rclip_we),.clip_addr(rclip_addr),.clip_data(rclip_data),
 .cfg_we(rcfg_we),.roz_enable_i(r_enable),.palbase_i(rpalbase),
 .map_we(rmap_we),.map_waddr(rmap_waddr),.map_wdata(rmap_wdata),.chr_we(rchr_we),.chr_waddr(rchr_waddr),.chr_wdata(rchr_wdata),
 .prestart(rprestart),.line_start(rstart),.line(rline),.px(rpx),.pix(rpix[0]),.opaque(ropaque[0]),.busy(rbusy[0]),.unsupported(runsupported[0]),.lead(rlead[0]),
 .map_transactions(rmap_transactions[0]),.block_transactions(rblock_transactions[0]),
 .map_latency_min(),.map_latency_max(),.block_latency_min(),.block_latency_max(),.protocol_error(rprotocol[0]),.observed_map_req(rmap_req[0]),.observed_map_addr(rmap_addr[0]),.observed_blk_req(rblk_req[0]),.observed_blk_addr(rblk_addr[0]));
source_roz_baseline r1(.clk(clk),.reset(reset),.mystic(mystic),.violent(violent),.variable_latency(1'b1),
 .ctrl_we(rctrl_we),.ctrl_addr(rctrl_addr),.ctrl_data(rctrl_data),.clip_we(rclip_we),.clip_addr(rclip_addr),.clip_data(rclip_data),
 .cfg_we(rcfg_we),.roz_enable_i(r_enable),.palbase_i(rpalbase),
 .map_we(rmap_we),.map_waddr(rmap_waddr),.map_wdata(rmap_wdata),.chr_we(rchr_we),.chr_waddr(rchr_waddr),.chr_wdata(rchr_wdata),
 .prestart(rprestart),.line_start(rstart),.line(rline),.px(rpx),.pix(rpix[1]),.opaque(ropaque[1]),.busy(rbusy[1]),.unsupported(runsupported[1]),.lead(rlead[1]),
 .map_transactions(rmap_transactions[1]),.block_transactions(rblock_transactions[1]),
 .map_latency_min(),.map_latency_max(),.block_latency_min(),.block_latency_max(),.protocol_error(rprotocol[1]),.observed_map_req(rmap_req[1]),.observed_map_addr(rmap_addr[1]),.observed_blk_req(rblk_req[1]),.observed_blk_addr(rblk_addr[1]));
endmodule
