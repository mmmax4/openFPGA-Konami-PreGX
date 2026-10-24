`default_nettype none
module tb_m2_raster_top (
    input logic clk, reset, mystic,
    input logic [2:0] renderers_busy,
    output logic line_start,prestart,scanline_start,overrun,
    output logic [2:0] overrun_src,
    output logic [8:0] render_line,px,hcount,vcount,
    output logic px_valid,hsync,vsync,de,hblank,vblank,vblank_rise
);
    logic cen_pix;
    clk_enables u_ce(.clk(clk),.reset(reset),.pix_sync(1'b0),.mystic(mystic),
        .cen_16m(),.cen_8m(),.cen_pix(cen_pix),.cen_48k());
`ifdef OLD_RASTER
    assign scanline_start=1'b0;
`endif
    gaia_video u_vid(
`ifndef OLD_RASTER
        .mystic(mystic),.scanline_start(scanline_start),
`endif
        .clk(clk),.reset(reset),.cen_pix(cen_pix),.line_start(line_start),.render_line(render_line),
        .prestart(prestart),.renderers_busy(renderers_busy),.overrun(overrun),.overrun_src(overrun_src),
        .px(px),.px_valid(px_valid),.hcount(hcount),.vcount(vcount),.hsync(hsync),.vsync(vsync),.de(de),
        .hblank(hblank),.vblank(vblank),.vblank_rise(vblank_rise)
    );
endmodule
`default_nettype wire
