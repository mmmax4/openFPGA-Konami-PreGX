//------------------------------------------------------------------------------
// Clock enables from the 96 MHz system clock (docs/rtl-conventions.md).
//   cen_16m : 96 / 6   68000
//   cen_8m  : 96 / 12  Z80
//   cen_pix : Gaia 96/12, Mystic 96/16; independent pixel enable
//   cen_48k : 96 / 2000 K054539 sample rate (18.432 MHz / 384)
//
// pix_sync pins the pixel phase to the platform's 8 MHz video clock: a pulse
// in the clock after that clock's edge is seen (core_top's synchroniser)
// restarts the pixel divider so cen_pix falls one clock before the next edge
// and the colour stage (k055555_mixer, phase 9) lands two clocks before the
// video clock samples it. Tied low, the divider free-runs (the benches).
//------------------------------------------------------------------------------
`default_nettype none

module clk_enables (
    input  logic clk,
    input  logic reset,
    input  logic pix_sync,
    input  logic mystic, // stable while reset: native 6 MHz pixels, CPU rates unchanged
    output logic cen_16m,
    output logic cen_8m,
    output logic cen_pix,
    output logic cen_48k
);
    logic [3:0] div, pix_div;
    logic [10:0] sdiv;
    always_ff @(posedge clk) begin
        if (reset) begin div <= '0; pix_div <= '0; cen_pix <= 1'b0; sdiv <= '0; cen_16m <= 1'b0; cen_8m <= 1'b0; cen_48k <= 1'b0; end
        else begin
            sdiv    <= (sdiv == 11'd1999) ? 11'd0 : sdiv + 11'd1;
            cen_48k <= (sdiv == 11'd1999);
            // Preserve the exact original Gaia phase adjustment. Mystic video
            // must not re-phase the independent 16/8 MHz CPU enables.
            div <= (pix_sync && !mystic) ? 4'd3 : (div == 4'd11) ? 4'd0 : div + 4'd1;
            // Same synchronization latency and one tick before the next
            // video edge. Period changes, reload phase stays at three.
            pix_div <= pix_sync ? 4'd3 : (pix_div == 4'd15) ? 4'd0 : pix_div + 4'd1;
            cen_pix <= mystic ? (pix_div == 4'd15) : (div == 4'd11);
            cen_16m <= (div == 4'd11) || (div == 4'd5);
            cen_8m  <= (div == 4'd11);
        end
    end
endmodule
