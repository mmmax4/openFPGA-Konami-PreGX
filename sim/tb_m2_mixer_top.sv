// Independent frozen-state integration fixture. Public setup and request/ACK
// clients only; production tile/list/draw/compositor/controllers are unmodified.
`default_nettype none
module tb_m2_mixer_top(
 input logic clk,clk_vid,init,reset,vid_reset,
 input logic dl_we,input logic[24:0] dl_addr,input logic[7:0] dl_data,
 output logic ready,
 input logic setup_we,input logic[2:0] setup_bank,input logic[11:0] setup_addr,input logic[15:0] setup_data,
 input logic vsetup_mode,vsetup_req,input logic[15:0] vsetup_addr,vsetup_data,output logic vsetup_ack,
 input logic build,output logic build_done,output logic[9:0] object_count,
 input logic c_treq,c_sreq,c_vreq,c_preq,c_areq,
 input logic[18:0] c_taddr,input logic[19:0] c_saddr,input logic[15:0] c_vaddr,
 input logic[21:0] c_paddr,c_aaddr,
 output logic c_tack,c_sack,c_vack,c_pack,c_aack,
 output logic[23:0] rgb,
 output logic cen_pix,de,sample_valid,
 output wire [23:0] pocket_rgb, output wire pocket_de,
 output wire analog_capture, output wire [27:0] analog_pixel,
 output logic[8:0] scan_x,scan_y,hcount,vcount,
 output logic tile_start,sprite_start,
 output logic tile_busy,sprite_busy,compositor_busy,
 output logic order_valid,order_ready,fragment_valid,fragment_ready,
 output logic[8:0] fragment_x,
 output logic[31:0] protocol_errors,
 output logic overrun,unsupported,overflow,
 output logic observed_tack,observed_sack,observed_vack,
 output logic[31:0] draw_pixels
);
 logic[15:0] k56[32],k38[16],k47[8],sram[2048],palette_words[4096];
 logic[7:0] k55[48],k46[8];
 always_ff @(posedge clk) if(setup_we) case(setup_bank)
  0:k56[setup_addr[4:0]]<=setup_data;
  1:if(setup_addr<48) k55[setup_addr[5:0]]<=setup_data[7:0];
  2:k38[setup_addr[3:0]]<=setup_data;
  3:k46[setup_addr[2:0]]<=setup_data[7:0];
  4:k47[setup_addr[2:0]]<=setup_data;
  5:sram[setup_addr[10:0]]<=setup_data;
  6:palette_words[setup_addr]<=setup_data;
  default:;
 endcase
 logic[10:0] palette_addr;
 logic[23:0] palette_q;
 always_ff @(posedge clk) palette_q<={palette_words[{palette_addr,1'b0}][7:0],palette_words[{palette_addr,1'b1}]};
 function automatic logic[9:0] alpha_level(input logic[1:0] e);
  logic[7:0] control;logic[4:0] level;
  case(e) 1:control=k38[13][7:0];2:control=k38[14][15:8];3:control=k38[14][7:0];default:control=0;endcase
  level=control[5]?control[4:0]:(5'd31-control[4:0]);
  return e==0?10'd255:{k38[15][1],control[5],level,level[4:2]};
 endfunction
 logic[9:0] alpha1,alpha2,alpha3;
 assign alpha1=alpha_level(1);assign alpha2=alpha_level(2);assign alpha3=alpha_level(3);
 logic[7:0] cb[4],shdpri[3];logic[2:0] shadowon;
 always_comb begin
  for(int l=0;l<4;l++) cb[l]={k55[23+l][3:0],4'd0};
  for(int t=0;t<3;t++) begin
   shadowon[t]=0;shdpri[t]=k55[37+t];
   for(int c=0;c<3;c++) begin
    logic[8:0] d;d=k38[2+t*3+c][8:0];
    if(d[8]?(d<9'h1f9):(d>9'd7)) shadowon[t]=1;
   end
  end
 end
 logic cen16,cen8,cen48,prestart,px_valid,scanline_start;
 wire pix_sync,ga_hs,ga_vs,ga_hb,ga_vb;
 wire [7:0] ovl_r,ovl_g,ovl_b;
 dbg_overlay overlay(.clk(clk),.cen_pix(cen_pix),.enable(1'b0),.de(de),.vsync(ga_vs),
  .r_in(rgb[23:16]),.g_in(rgb[15:8]),.b_in(rgb[7:0]),.status(96'd0),
  .mystic(1'b1),.r_out(ovl_r),.g_out(ovl_g),.b_out(ovl_b));
 source_pocket_consumer pocket(.clk_sys(clk),.clk_vid(clk_vid),.profile_clock_ready(!vid_reset),
  .ovl_r(ovl_r),.ovl_g(ovl_g),.ovl_b(ovl_b),.ga_hs(ga_hs),.ga_vs(ga_vs),.ga_de(de),
  .pix_sync(pix_sync),.pocket_rgb(pocket_rgb),.pocket_de(pocket_de));
 source_analog_capture analog(.clk_src(clk),.src_pix_ce(cen_pix),.src_rgb({ovl_r,ovl_g,ovl_b}),
  .src_hs(ga_hs),.src_vs(ga_vs),.src_hb(ga_hb),.src_vb(ga_vb),
  .captured(analog_capture),.h_pix(analog_pixel));
 logic[8:0] render_line,px;
 logic[2:0] overrun_src;
 clk_enables cen(.clk(clk),.reset(vid_reset),.pix_sync(pix_sync),.mystic(1'b1),.cen_pix(cen_pix),.cen_16m(cen16),.cen_8m(cen8),.cen_48k(cen48));
 gaia_video video(.clk(clk),.reset(vid_reset),.mystic(1'b1),.cen_pix(cen_pix),.scanline_start(scanline_start),
  .line_start(sprite_start),.render_line(render_line),.prestart(prestart),.renderers_busy({tile_busy,1'b0,sprite_busy|compositor_busy}),
  .overrun(overrun),.overrun_src(overrun_src),.px(px),.px_valid(px_valid),.hcount(hcount),.vcount(vcount),
  .hsync(ga_hs),.vsync(ga_vs),.de(de),.hblank(ga_hb),.vblank(ga_vb),.vblank_rise());
 logic[8:0] tile_line;
 always_ff @(posedge clk) begin
  tile_start<=0;
  if(vid_reset)tile_line<=0;
  else if(scanline_start && vcount>=14 && vcount<=239) begin tile_start<=1;tile_line<=vcount+9'd2;end
 end
 // Consumer sample after the real registered scanout RAM; output DE alignment
 // is separately exposed for the application-level observation.
 logic sample_pending;
 always_ff @(posedge clk) begin
  sample_pending<=cen_pix && !vid_reset;
  sample_valid<=sample_pending && px_valid && !vid_reset;
  scan_x<=px;scan_y<=vcount-9'd16;
 end
 logic vreq,vack,tvreq,tvack,vwe;logic[15:0] va,vq,vwd,tva;logic[1:0] vbe;
 logic tr,ta,sr,sa,mtreq,mtack,msreq,msack;
 logic[18:0] taddr,mtaddr;logic[19:0] saddr,msaddr;
 logic[31:0] tq;logic[63:0] sq;logic[7:0] tfifth;logic[15:0] sfifth;
 logic[11:0] tile_pen[4];logic[1:0] category[4];logic[3:0] opaque,tile_nonempty;
 logic[8:0] tile_x;
 k056832_tilemap tile(.clk(clk),.reset(reset),.mystic(1'b1),.rom_fifth(tfifth),.category(category),
  .line_nonempty(tile_nonempty),
  .line_start(tile_start),.line(tile_line),.busy(tile_busy),.regs(k56),.colorbase(cb),
  .vram_req(tvreq),.vram_addr(tva),.vram_ack(tvack),.vram_q(vq),
  .rom_req(tr),.rom_addr(taddr),.rom_ack(ta),.rom_q(tq),.px(tile_x),.pix(tile_pen),.opaque(opaque),.unsupported(unsupported));
 ram_arb2 #(.AW(16),.DW(16)) varb(.clk(clk),.reset(reset),
  .c0_req(tvreq),.c0_we(1'b0),.c0_addr(tva),.c0_be(2'b11),.c0_wdata(16'd0),.c0_ack(tvack),
  .c1_req(c_vreq),.c1_we(1'b0),.c1_addr(c_vaddr),.c1_be(2'b11),.c1_wdata(16'd0),.c1_ack(c_vack),
  .m_req(vreq),.m_we(vwe),.m_addr(va),.m_be(vbe),.m_wdata(vwd),.m_ack(vack && !vsetup_mode));
 rom_arb2 #(.AW(19),.DW(32)) tarb(.clk(clk),.reset(reset),.c0_req(tr),.c0_addr(taddr),.c0_ack(ta),
  .c1_req(c_treq),.c1_addr(c_taddr),.c1_ack(c_tack),.m_req(mtreq),.m_addr(mtaddr),.m_ack(mtack),.m_q(tq),.q());
 rom_arb2 #(.AW(20),.DW(64)) sarb(.clk(clk),.reset(reset),.c0_req(sr),.c0_addr(saddr),.c0_ack(sa),
  .c1_req(c_sreq),.c1_addr(c_saddr),.c1_ack(c_sack),.m_req(msreq),.m_addr(msaddr),.m_ack(msack),.m_q(sq),.q());
 logic ol_busy;logic[10:0] ol_ra,dr_ra;logic[15:0] ram_q;
 always_ff @(posedge clk) ram_q<=sram[ol_busy?ol_ra:dr_ra];
 logic[9:0] list_idx,ol_za,dr_za,zoom_addr;logic[31:0] list_q;
 logic[7:0] yr_addr;logic[21:0] yr_q;logic[10:0] recip_addr;logic[23:0] zoom_q,recip_q;
 assign zoom_addr=ol_busy?ol_za:dr_za;
 sprite_tables #(.HEXDIR("snapshot/rtl/data")) tables(.clk(clk),.zoom_addr(zoom_addr),.zoom_q(zoom_q),.recip_addr(recip_addr),.recip_q(recip_q));
 k053247_objlist objects(.clk(clk),.reset(reset),.mystic(1'b1),.stream_enable(1'b1),.shdprisel(k55[41][5:0]),
  .start(build),.done(build_done),.busy(ol_busy),.opset(k47[6]),.objset1(k46[5]),.shadowon(shadowon),.shdpri(shdpri),
  .k46_offy({k46[2],k46[3]}),.zoom_addr(ol_za),.zoom_q(zoom_q),.yr_addr(yr_addr),.yr_q(yr_q),
  .ram_addr(ol_ra),.ram_q(ram_q),.list_idx(list_idx),.list_q(list_q),.count(object_count),.overflow(overflow));
 logic[7:0] order_priority,fragment_z,fragment_pri;logic order_deferred,fragment_shadow;
 logic[11:0] fragment_pen;logic[9:0] fragment_level;logic[1:0] fragment_table,fragment_condition;
 k053247_draw draw(.clk(clk),.reset(reset),.mystic(1'b1),.rom_fifth(sfifth),.out_effect(),
  .line_start(sprite_start),.line(render_line),.busy(sprite_busy),
  .k46r5(k46[5]),.k46_offx({k46[0],k46[1]}),.k46_offy({k46[2],k46[3]}),.opset(k47[6]),.colorbase({k55[27][2:0],5'd0}),
  .alpha1(alpha1),.alpha2(alpha2),.alpha3(alpha3),.stream_enable(1'b1),
  .order_valid(order_valid),.order_priority(order_priority),.order_deferred(order_deferred),.order_ready(order_ready),
  .fragment_valid(fragment_valid),.fragment_ready(fragment_ready),.fragment_x(fragment_x),.fragment_pen(fragment_pen),
  .fragment_level(fragment_level),.fragment_shadow(fragment_shadow),.fragment_table(fragment_table),.fragment_condition(fragment_condition),.fragment_z(fragment_z),.fragment_pri(fragment_pri),
  .list_idx(list_idx),.list_q(list_q),.list_count(object_count),.yr_addr(yr_addr),.yr_q(yr_q),.ram_addr(dr_ra),.ram_q(ram_q),
  .rom_req(sr),.rom_addr(saddr),.rom_ack(sa),.rom_q(sq),.zoom_addr(dr_za),.zoom_q(zoom_q),.recip_addr(recip_addr),.recip_q(recip_q),
  .px(px),.out_opaque(),.out_pen(),.out_pri(),.out_shadow(),.out_shtab(),.out_shpri(),.shadow_overlap(),
  .dbg_objs(),.dbg_rows(),.dbg_cols(),.dbg_pxw(draw_pixels));
 pregx_mystic_compositor compositor(.clk(clk),.reset(reset),.line_start(sprite_start),.k55regs(k55),.k38regs(k38),
  .alpha1(alpha1),.alpha2(alpha2),.alpha3(alpha3),.sprite_busy(sprite_busy),
  .order_valid(order_valid),.order_priority(order_priority),.order_deferred(order_deferred),.order_ready(order_ready),
  .fragment_valid(fragment_valid),.fragment_ready(fragment_ready),.fragment_x(fragment_x),.fragment_pen(fragment_pen),.fragment_level(fragment_level),
  .fragment_shadow(fragment_shadow),.fragment_table(fragment_table),.fragment_condition(fragment_condition),.fragment_z(fragment_z),.fragment_pri(fragment_pri),
  .tile_x(tile_x),.tile_pen(tile_pen),.tile_opaque(opaque),.tile_nonempty(tile_nonempty),.tile_category(category),.palette_addr(palette_addr),.palette_q(palette_q),.scan_x(px),.rgb(rgb),.busy(compositor_busy));
 assign vsetup_ack=vsetup_mode && vack;
 assign observed_tack=ta;assign observed_sack=sa;assign observed_vack=tvack;
 tb_m2_mem_top memory(.clk(clk),.init(init),.mystic(1'b1),.ready(ready),.rd_late(1'b1),.burst_slow(1'b0),
  .ps_slow(1'b0),.sram_slow(1'b0),.sram_slow_wr(1'b0),.tile_fifth(tfifth),.spr_fifth(sfifth),.test_mask(),.sd_read_pulse(),.sd_read_word(),.sd_protocol_errors(protocol_errors),
  .test_start(1'b0),.test_run(),.test_done(),.test_ok(),.test_stable(),.vram_ok(),.vram_bad(),
  .dl_we(dl_we),.dl_addr(dl_addr),.dl_data(dl_data),.eep_we(),.eep_addr(),.eep_data(),
  .prog_req(c_preq),.prog_addr(c_paddr),.prog_ack(c_pack),.prog_q(),
  .tile_req(mtreq),.tile_addr(mtaddr),.tile_ack(mtack),.tile_q(tq),
  .map_req(1'b0),.map_addr(20'd0),.map_ack(),.map_q(),
  .blk_req(1'b0),.blk_addr(16'd0),.blk_wr(),.blk_idx(),.blk_data(),.blk_ack(),
  .spr_req(msreq),.spr_addr(msaddr),.spr_ack(msack),.spr_q(sq),
  .snd_req(1'b0),.snd_addr(18'd0),.snd_ack(),.snd_q(),
  .pcm_req(c_areq),.pcm_addr(c_aaddr),.pcm_ack(c_aack),.pcm_q(),
  .vram_req(vsetup_mode?vsetup_req:vreq),.vram_we(vsetup_mode?1'b1:vwe),.vram_addr(vsetup_mode?vsetup_addr:va),
  .vram_be(vsetup_mode?2'b11:vbe),.vram_wdata(vsetup_mode?vsetup_data:vwd),.vram_ack(vack),.vram_q(vq));
endmodule
`default_nettype wire
