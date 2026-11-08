// Actual M4 tile/LVC/shared-video-RAM/five-plane compositor coupling.
// Road CPU/DMA state is local here; the production external PSRAM state has a separate gate.
`default_nettype none
module m4_rgb_top(
 input logic clk,reset,tile_start,road_start,rgb_start,frame_tick,latch,
 input logic[8:0]tile_line,native_line,scan_x,
 input logic[15:0]k56[32],k38[16],input logic[7:0]k55[48],k50[8],
 input logic cpu_we,input logic[12:0]cpu_addr,input logic[1:0]cpu_be,input logic[15:0]cpu_wdata,
 input logic spr_busy,order_valid,order_deferred,fragment_valid,fragment_shadow,
 input logic[7:0]order_priority,fragment_z,fragment_pri,
 input logic[8:0]fragment_x,input logic[11:0]fragment_pen,input logic[9:0]fragment_level,
 input logic[1:0]fragment_table,fragment_condition,output wire order_ready,fragment_ready,
 input logic pal_we,input logic[11:0]pal_addr,input logic[15:0]pal_data,
 output wire dma_busy,road_busy,row_busy,tile_busy,rgb_busy,unsupported,
 output wire vram_req,output wire[15:0]vram_addr,input logic vram_ack,input logic[15:0]vram_q,
 output wire tile_req,output wire[18:0]tile_addr,input logic tile_ack,input logic[31:0]tile_q,
 output wire road_req,output wire[14:0]road_addr,input logic road_ack,input logic[63:0]road_q,
 output wire[8:0]tile_x,output wire[10:0]road_pen,output wire road_opaque,
 output wire[23:0]rgb
);
 logic[15:0]palette[4096];wire[10:0]palette_addr;logic[23:0]palette_q;
 always_ff @(posedge clk)begin
  if(pal_we)palette[pal_addr]<=pal_data;
  palette_q<={palette[{palette_addr,1'b0}][7:0],palette[{palette_addr,1'b1}]};
 end
 logic[7:0]colorbase[4];
 always_comb for(int l=0;l<4;l++)colorbase[l]={k55[23+l][3:0],4'd0};
 wire[11:0]tile_pen[4];wire[3:0]tile_opaque,tile_nonempty;wire[1:0]category[4],last_mix;
 k056832_tilemap tile(.clk(clk),.reset(reset),.metam(1'b1),.mystic(1'b0),.violent(1'b0),
 .line_start(tile_start),.line(tile_line),.busy(tile_busy),.regs(k56),.colorbase(colorbase),
 .vram_req(vram_req),.vram_addr(vram_addr),.vram_ack(vram_ack),.vram_q(vram_q),
 .rom_req(tile_req),.rom_addr(tile_addr),.rom_ack(tile_ack),.rom_q(tile_q),.rom_fifth(8'd0),
 .px(tile_x),.pix(tile_pen),.opaque(tile_opaque),.category(category),.last_mix(last_mix),.line_nonempty(tile_nonempty),.unsupported(unsupported));
 wire f_we,c_we,group_we,line_we;
 wire[10:0]f_wa,f_ra;wire[15:0]f_wdata,f_q;
 wire[8:0]c_wa,c_ra,group_wa,group_ra;wire[52:0]c_wdata,c_q;wire[79:0]group_wdata,group_q;
 wire[11:0]line_wa,line_ra;wire[8:0]line_wdata,line_q;
 pregx_video_ram actual_video_ram(.clk(clk),.metam(1'b1),
 .g_we(1'b0),.g_wa(13'd0),.g_ra(13'd0),.g_wdata(16'd0),.g_q(),
 .f_we(f_we),.f_wa(f_wa),.f_ra(f_ra),.f_wdata(f_wdata),.f_q(f_q),
 .c_we(c_we),.c_wa(c_wa),.c_ra(c_ra),.c_wdata(c_wdata),.c_q(c_q),
 .cache_we(group_we),.cache_wa(group_wa),.cache_ra(group_ra),.cache_wdata(group_wdata),.cache_q(group_q),
 .g_lb_we(1'b0),.g_lb_wa(12'd0),.g_lb_ra(12'd0),.g_lb_wdata(12'd0),.g_lb_q(),
 .r_lb_we(line_we),.r_lb_wa(line_wa),.r_lb_ra(line_ra),.r_lb_wdata(line_wdata),.r_lb_q(line_q));
 k053250_lvc #(.RUN_AHEAD(1'b1),.COMPOSITOR_READ(1'b1),.EXTERNAL_VIDEO(1'b1),.EXTERNAL_STATE(1'b0)) road(
 .clk(clk),.reset(reset),.regs(k50),.cpu_we(cpu_we),.cpu_addr(cpu_addr),.cpu_be(cpu_be),.cpu_wdata(cpu_wdata),.cpu_rq(),.dma_busy(dma_busy),
 .frame_tick(frame_tick),.latch(latch),.line_start(road_start),.line(native_line),.busy(road_busy),.row_busy(row_busy),
 .rom_req(road_req),.rom_addr(road_addr),.rom_ack(road_ack),.rom_q(road_q),.palbase(k55[28]),.px(tile_x),.pix(road_pen),.opaque(road_opaque),
 .f_we(f_we),.f_wa(f_wa),.f_ra(f_ra),.f_wdata(f_wdata),.f_q(f_q),
 .c_we(c_we),.c_wa(c_wa),.c_ra(c_ra),.c_wdata(c_wdata),.c_q(c_q),
 .group_we(group_we),.group_wa(group_wa),.group_ra(group_ra),.group_wdata(group_wdata),.group_q(group_q),
 .line_we(line_we),.line_wa(line_wa),.line_ra(line_ra),.line_wdata(line_wdata),.line_q(line_q),
 .external_dma_busy(1'b0),.snapshot_allowed(1'b1),.snapshot_begin(),.snapshot_active(),.snapshot_req(),.snapshot_addr(),.snapshot_ack(1'b0),.snapshot_q(16'd0));
 function automatic logic[9:0]alpha(input logic[1:0]effect);
  logic[7:0]v;logic[4:0]l;
  case(effect)1:v=k38[13][7:0];2:v=k38[14][15:8];3:v=k38[14][7:0];default:v=0;endcase
  l=v[5]?v[4:0]:5'd31-v[4:0];return effect==0?10'd255:{k38[15][1],v[5],l,l[4:2]};
 endfunction
 pregx_mystic_compositor compositor(.clk(clk),.reset(reset),.line_start(rgb_start),.metam(1'b1),.violent(1'b0),
 .road_pen(road_pen),.road_opaque(road_opaque),.road_ready(!row_busy),.last_mix(last_mix),.k55regs(k55),.k38regs(k38),
 .alpha1(alpha(1)),.alpha2(alpha(2)),.alpha3(alpha(3)),.sprite_busy(spr_busy),.order_valid(order_valid),.order_priority(order_priority),.order_deferred(order_deferred),.order_ready(order_ready),
 .fragment_valid(fragment_valid),.fragment_ready(fragment_ready),.fragment_x(fragment_x),.fragment_pen(fragment_pen),.fragment_level(fragment_level),.fragment_shadow(fragment_shadow),
 .fragment_table(fragment_table),.fragment_condition(fragment_condition),.fragment_z(fragment_z),.fragment_pri(fragment_pri),
 .tile_x(tile_x),.tile_pen(tile_pen),.tile_opaque(tile_opaque),.tile_nonempty(tile_nonempty),.tile_category(category),
 .palette_addr(palette_addr),.palette_q(palette_q),.scan_x(scan_x),.rgb(rgb),.busy(rgb_busy));
endmodule
`default_nettype wire
