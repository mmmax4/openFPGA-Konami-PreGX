`default_nettype none
// Paired actual public interfaces. Only namespace tokens in the old drawer
// and its embedded row cache are changed by the runner.
module m3_vio14_rgb_top(
 input logic clk,reset,start,mystic,violent,
 input logic [15:0] words[7],input logic[31:0] order,
 input logic[8:0] line,px,input logic[9:0] list_count,
 input logic[63:0] rom_q,input logic[15:0] rom_fifth,input logic rom_ack,
 input logic tile_we,palette_we,input logic[1:0]setup_layer,input logic[10:0]setup_addr,input logic[23:0]setup_data,
 input logic[7:0]k55regs[48],input logic[15:0]k38regs[16],input logic[3:0]tile_nonempty,
 output wire[1:0]consumer_ready,consumer_order_ready,consumer_busy,
 output wire[8:0]tile_x[2],output wire[10:0]palette_addr[2],output wire[23:0]rgb[2],output wire[3:0]admission[2],
 output wire[1:0] busy,rom_req,order_valid,order_deferred,valid,shadow,
 output wire[19:0] rom_addr[2],output wire[7:0] order_priority[2],
 output wire[8:0] x[2],output wire[11:0] pen[2],
 output wire[9:0] level[2],output wire[1:0] shadow_table[2],condition[2],
 output wire[7:0] z[2],priority_code[2],
 output wire[1:0] opaque,scan_shadow,overlap,
 output wire[11:0] scan_pen[2],output wire[7:0] scan_pri[2],scan_shpri[2],
 output wire[1:0] scan_effect[2],scan_table[2],
 output wire[9:0] list_idx[2],output wire[7:0] yr_addr[2],
 output wire[10:0] ram_addr[2],output wire[31:0] objects[2],rows[2],columns[2],writes[2]);
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
 .alpha1(10'd128),.alpha2(10'd96),.alpha3(10'd64),.stream_enable(1'b1),
 .order_valid(order_valid[0]),.order_priority(order_priority[0]),.order_deferred(order_deferred[0]),.order_ready(consumer_order_ready[0]),
 .fragment_valid(valid[0]),.fragment_ready(consumer_ready[0]),.fragment_x(x[0]),.fragment_pen(pen[0]),
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
 .alpha1(10'd128),.alpha2(10'd96),.alpha3(10'd64),.stream_enable(1'b1),
 .order_valid(order_valid[1]),.order_priority(order_priority[1]),.order_deferred(order_deferred[1]),.order_ready(consumer_order_ready[1]),
 .fragment_valid(valid[1]),.fragment_ready(consumer_ready[1]),.fragment_x(x[1]),.fragment_pen(pen[1]),
 .fragment_level(level[1]),.fragment_shadow(shadow[1]),.fragment_table(shadow_table[1]),.fragment_condition(condition[1]),.fragment_z(z[1]),.fragment_pri(priority_code[1]),
 .list_idx(list_idx[1]),.list_q(list_q1),.list_count(list_count),.yr_addr(yr_addr[1]),.yr_q(yr_q1),.ram_addr(ram_addr[1]),.ram_q(ram_q1),
 .rom_req(rom_req[1]),.rom_addr(rom_addr[1]),.rom_ack(rom_ack),.rom_q(rom_q),
 .zoom_addr(za1),.zoom_q(zq1),.recip_addr(rca1),.recip_q(rcq1),
 .px(px),.out_opaque(opaque[1]),.out_pen(scan_pen[1]),.out_pri(scan_pri[1]),.out_effect(scan_effect[1]),.out_shadow(scan_shadow[1]),.out_shtab(scan_table[1]),.out_shpri(scan_shpri[1]),
 .shadow_overlap(overlap[1]),.dbg_objs(objects[1]),.dbg_rows(rows[1]),.dbg_cols(columns[1]),.dbg_pxw(writes[1]));

 // Actual synchronous completed tile-line and palette ports; no hierarchy access.
 logic [15:0]tiles[4][512];logic[23:0]palette[2048];
 wire[11:0]tile_pen[2][4];wire[3:0]tile_opaque[2];wire[1:0]tile_category[2][4];
 logic[15:0]tile_q[2][4];logic[23:0]palette_q[2];
 always_ff @(posedge clk) begin
  if(tile_we)tiles[setup_layer][setup_addr[8:0]]<=setup_data[15:0];
  if(palette_we)palette[setup_addr]<=setup_data;
  for(int i=0;i<2;i++)begin
   palette_q[i]<=palette[palette_addr[i]];
   for(int l=0;l<4;l++)tile_q[i][l]<=tiles[l][tile_x[i]];
  end
 end
 for(genvar i=0;i<2;i++)begin:tile_ports
  for(genvar l=0;l<4;l++)begin:layers
   assign tile_pen[i][l]=tile_q[i][l][11:0];
   assign tile_opaque[i][l]=tile_q[i][l][12];
   assign tile_category[i][l]=tile_q[i][l][14:13];
  end
 end
 pregx_mystic_compositor comp0(
 .clk(clk),.reset(reset),.line_start(start),.violent(violent),.last_mix(2'd0),
 .k55regs(k55regs),.k38regs(k38regs),.alpha1(10'd128),.alpha2(10'd96),.alpha3(10'd64),
 .sprite_busy(busy[0]),.order_valid(order_valid[0]),.order_priority(order_priority[0]),.order_deferred(order_deferred[0]),.order_ready(consumer_order_ready[0]),
 .fragment_valid(valid[0]),.fragment_ready(consumer_ready[0]),.fragment_x(x[0]),.fragment_pen(pen[0]),.fragment_level(level[0]),
 .fragment_shadow(shadow[0]),.fragment_table(shadow_table[0]),.fragment_condition(condition[0]),.fragment_z(z[0]),.fragment_pri(priority_code[0]),
 .tile_x(tile_x[0]),.tile_pen(tile_pen[0]),.tile_opaque(tile_opaque[0]),.tile_nonempty(tile_nonempty),.tile_category(tile_category[0]),
 .palette_addr(palette_addr[0]),.palette_q(palette_q[0]),.scan_x(px),.rgb(rgb[0]),.busy(consumer_busy[0]),.audit_admission(admission[0]));
 pregx_mystic_compositor_baseline comp1(
 .clk(clk),.reset(reset),.line_start(start),.violent(violent),.last_mix(2'd0),
 .k55regs(k55regs),.k38regs(k38regs),.alpha1(10'd128),.alpha2(10'd96),.alpha3(10'd64),
 .sprite_busy(busy[1]),.order_valid(order_valid[1]),.order_priority(order_priority[1]),.order_deferred(order_deferred[1]),.order_ready(consumer_order_ready[1]),
 .fragment_valid(valid[1]),.fragment_ready(consumer_ready[1]),.fragment_x(x[1]),.fragment_pen(pen[1]),.fragment_level(level[1]),
 .fragment_shadow(shadow[1]),.fragment_table(shadow_table[1]),.fragment_condition(condition[1]),.fragment_z(z[1]),.fragment_pri(priority_code[1]),
 .tile_x(tile_x[1]),.tile_pen(tile_pen[1]),.tile_opaque(tile_opaque[1]),.tile_nonempty(tile_nonempty),.tile_category(tile_category[1]),
 .palette_addr(palette_addr[1]),.palette_q(palette_q[1]),.scan_x(px),.rgb(rgb[1]),.busy(consumer_busy[1]),.audit_admission(admission[1]));
endmodule
