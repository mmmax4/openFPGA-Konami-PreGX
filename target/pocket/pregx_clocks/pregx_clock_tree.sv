// M2 clock candidate. Both video sources originate from the same PLL as sys.
// Keep core_pll_inst so source-bound timing constraints retain that hierarchy.
// The two muxes can settle at different times: hold video/DDR consumers blank
// through profile selection, then qualify both modes and the actual fitted PHY.
`default_nettype none
module pregx_clock_tree (
    input wire refclk,rst,mystic,
    output wire outclk_0,outclk_1,outclk_2,outclk_3,outclk_4,locked
);
    wire vid8,vid8q,vid6,vid6q;
    // Dedicated launch registers keep the slow-clock select paths separate
    // from the ROM profile's many machine consumers. Do not merge these two
    // identical registers: each belongs near its own SDK clock-control block.
    // Stage on the rising sys edge, then launch on its falling edge. PLL
    // video edges share that VCO phase, giving a full sys cycle for setup
    // into the SDK select path; same-edge hold still needs fitted checks.
    // Consumers wait 256 sys cycles after identification in reset/blank.
    (* preserve, dont_merge *) reg video_select = 1'b0;
    (* preserve, dont_merge *) reg videoq_select = 1'b0;
    always @(posedge outclk_0) begin
        video_select <= mystic;
        videoq_select <= mystic;
    end
    (* preserve, dont_merge *) reg video_launch = 1'b0;
    (* preserve, dont_merge *) reg videoq_launch = 1'b0;
    always @(negedge outclk_0) begin
        video_launch <= video_select;
        videoq_launch <= videoq_select;
    end
    pregx_pll7 core_pll_inst (
        .refclk(refclk),.rst(rst),.locked(locked),
        .outclk_0(outclk_0),.outclk_1(vid8),.outclk_2(vid8q),
        .outclk_3(outclk_3),.outclk_4(outclk_4),.outclk_5(vid6),.outclk_6(vid6q)
    );
    // Cyclone V clock-select inputs0/1 accept clock pins, inputs2/3 PLLs.
    // SDK glitch-free logic powers select_reg up at0, so a real reference
    // clock on input0 is needed to clock the initial handover to2/3. Both
    // consumers remain reset/blank until profile detection and settling.
    pregx_vidmux video_mux(.ena(1'b1),.clkselect({1'b1,video_launch}),
        .inclk0x(refclk),.inclk1x(refclk),.inclk2x(vid8),.inclk3x(vid6),.outclk(outclk_1));
    pregx_vidmux videoq_mux(.ena(1'b1),.clkselect({1'b1,videoq_launch}),
        .inclk0x(refclk),.inclk1x(refclk),.inclk2x(vid8q),.inclk3x(vid6q),.outclk(outclk_2));
endmodule
`default_nettype wire
