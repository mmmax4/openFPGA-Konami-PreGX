`default_nettype none
module tb_m2_clocks(input wire clk,clk_vid,reset,mystic,
 output wire c16,c8,cp,c48, output wire r16,r8,r48, output wire pix_sync);
 reg vt=0,vs,vd;
 always @(posedge clk_vid) vt<=~vt;
 always @(posedge clk) begin vs<=vt;vd<=vs;end
 assign pix_sync=vs^vd;
 clk_enables candidate(.clk(clk),.reset(reset),.pix_sync(pix_sync),.mystic(mystic),
  .cen_16m(c16),.cen_8m(c8),.cen_48k(c48),.cen_pix(cp));
 // Identical baseline in Gaia; independent free-running CPU reference in Mystic.
 clk_enables_baseline reference_clock(.clk(clk),.reset(reset),.pix_sync(mystic?1'b0:pix_sync),
  .cen_16m(r16),.cen_8m(r8),.cen_48k(r48));
endmodule
