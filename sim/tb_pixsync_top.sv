// The pixel-phase pin (clk_enables pix_sync, core_top's synchroniser): with
// clk_vid rising half a system cycle after a system edge, check where cen_8m
// and the mixer's colour latch (phase 9) fall relative to the clk_vid edge.
`default_nettype none
module tb_pixsync_top (input logic clk, input logic clk_vid, input logic reset,
                       output logic cen_8m, output logic cen_rgb, output logic pix_sync);
    logic vt, vt_s, vt_d, cen_16m, cen_48k;
    initial vt = 1'b0;
    always @(posedge clk_vid) vt <= ~vt;
    always @(posedge clk) begin vt_s <= vt; vt_d <= vt_s; end
    assign pix_sync = vt_s ^ vt_d;
    clk_enables u_cen (.clk(clk), .reset(reset), .pix_sync(pix_sync), .mystic(1'b0), .cen_pix(), .cen_16m(cen_16m), .cen_8m(cen_8m), .cen_48k(cen_48k));
    // the mixer's phase counter (k055555_mixer.sv)
    logic [3:0] phase;
    always_ff @(posedge clk) phase <= cen_8m ? 4'd0 : (phase == 4'd15 ? 4'd15 : phase + 4'd1);
    assign cen_rgb = (phase == 4'd9);
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{cen_16m, cen_48k};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
