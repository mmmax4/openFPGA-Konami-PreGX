// Actual CE/raster/mixer producer and native video-clock sampling contract.
`default_nettype none
module tb_m2_overlay(input wire clk,clk_vid,reset,mystic,
 output wire [23:0] actual,expected,bypass,rgb,output wire de);
 reg vt,vs,vd;
 always @(posedge clk_vid)vt<=~vt;
 always @(posedge clk)begin vs<=vt;vd<=vs;end
 wire cp;wire scan,ls,pre,over,hs,vblank,hb;wire [8:0]rl,px,hc,vc;wire pv;wire [2:0]ovsrc;
 clk_enables ce(.clk(clk),.reset(reset),.pix_sync(vs^vd),.mystic(mystic),.cen_16m(),.cen_8m(),.cen_pix(cp),.cen_48k());
 gaia_video raster(.clk(clk),.reset(reset),.mystic(mystic),.cen_pix(cp),.scanline_start(scan),
 .line_start(ls),.render_line(rl),.prestart(pre),.renderers_busy(3'd0),.overrun(over),.overrun_src(ovsrc),
 .px(px),.px_valid(pv),.hcount(hc),.vcount(vc),.hsync(hs),.vsync(vblank),.de(de),.hblank(hb),.vblank(),.vblank_rise());
 reg [7:0]k55[48];reg[15:0]k38[16];reg[11:0]pens[4];wire[10:0]addr;
 reg[95:0]status;
 initial begin
  vt=0;status=96'h1298fedc_01234567_89abcdef;
  for(integer i=0;i<48;i=i+1)k55[i]=0;
  for(integer i=0;i<16;i=i+1)k38[i]=0;
  for(integer i=0;i<4;i=i+1)pens[i]=0;
  k38[0]=16'h0041;k38[1]=16'h82c3;
 end
 always @(posedge clk)begin
  status<={status[94:0],~status[95]};
  if(cp)begin k38[0]<=k38[0]+1'b1;k38[1]<=k38[1]+16'h0103;end
 end
 k055555_mixer mixer(.clk(clk),.reset(reset),.cen_pix(cp),.tm_pen(pens),.tm_opq(4'd0),
 .roz_pen(12'd0),.roz_opq(1'b0),.spr_opq(1'b0),.spr_pen(12'd0),.spr_pri(8'd0),
 .spr_shadow(1'b0),.spr_shtab(2'd0),.spr_shpri(8'd0),.k55regs(k55),.k38regs(k38),
 .roz_enable(1'b0),.pal_addr(addr),.pal_q(24'd0),.rgb(rgb));
 dbg_overlay candidate(.clk(clk),.cen_pix(cp),.enable(1'b1),.de(de),.vsync(vblank),
 .r_in(rgb[23:16]),.g_in(rgb[15:8]),.b_in(rgb[7:0]),.status(status),
`ifndef OLD_OVERLAY
 .mystic(mystic),
`endif
 .r_out(actual[23:16]),.g_out(actual[15:8]),.b_out(actual[7:0]));
 dbg_overlay off_path(.clk(clk),.cen_pix(cp),.enable(1'b0),.de(de),.vsync(vblank),
 .r_in(rgb[23:16]),.g_in(rgb[15:8]),.b_in(rgb[7:0]),.status(status),
`ifndef OLD_OVERLAY
 .mystic(mystic),
`endif
 .r_out(bypass[23:16]),.g_out(bypass[15:8]),.b_out(bypass[7:0]));
 dbg_overlay_reference reference(.clk(clk),.cen_pix(cp),.enable(1'b1),.de(de),.vsync(vblank),
 .r_in(rgb[23:16]),.g_in(rgb[15:8]),.b_in(rgb[7:0]),.status(status),.mystic(mystic),
 .r_out(expected[23:16]),.g_out(expected[15:8]),.b_out(expected[7:0]));
endmodule
`default_nettype wire
