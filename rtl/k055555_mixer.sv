//------------------------------------------------------------------------------
// K055555 priority encoder + K054338 colour stage for Gaiapolis.
//
// Built the way the silicon works -- every input compared per pixel -- rather
// than as MAME's sort-and-paint. tools/mixer_experiment.py shows the two agree
// on every frozen-state frame, shadows included, under these rules:
//
//   * the visible pixel is the enabled, opaque input with the smallest
//     priority; among equal layer priorities the lower layer index wins
//     (A over B over C over D over SUB1), and a sprite loses a tie to a layer
//     -- both derived from konamigx_mixer's sort order and checked by brute
//     force over 40,186 random priority sets;
//   * a shadow marked on the sprite line buffer darkens the visible pixel
//     unless a layer won with priority <= the shadow's, i.e. was painted after
//     it. When the sprite itself wins, the flag alone is proof the shadow was
//     painted after the solid pixel.
//
// Not modelled, because nothing in the corpus exercises it: per-layer alpha
// (V_INMIX / OS_INMIX are 0 in every frame) and brightness (V_BRI only ever
// selects the 0xff level). See docs/hardware.md section 11.
//
// LOCAL pre-GX timing: snapshot pixel data/config at phase 2, encode by phase
// 5, capture palette/shadow operands at phase 7, add at phase 8 and clamp at
// phase 9. The output phase is unchanged. Only the explicit phase-2 snapshot
// -> phase-5 address path is multicycle; phase/s2/add/clamp remain single-cycle.
//------------------------------------------------------------------------------
`default_nettype none

module k055555_mixer (
    input  logic        clk,
    input  logic        reset,
    input  logic        cen_pix,        // the pixel tick the phases count from

    // per-pixel inputs, all valid together
    input  logic [11:0] tm_pen [4],
    input  logic  [3:0] tm_opq,
    input  logic [11:0] roz_pen,
    input  logic        roz_opq,
    input  logic        spr_opq,
    input  logic [11:0] spr_pen,
    input  logic  [7:0] spr_pri,
    input  logic        spr_shadow,
    input  logic  [1:0] spr_shtab,
    input  logic  [7:0] spr_shpri,

    // chip registers
    input  logic  [7:0] k55regs [48],
    input  logic [15:0] k38regs [16],
    input  logic        roz_enable,

    // palette: 2048 x xRGB888, registered read
    output logic [10:0] pal_addr,
    input  logic [23:0] pal_q,

    output logic [23:0] rgb
);
    logic [3:0] phase;
    always_ff @(posedge clk) phase <= cen_pix ? 4'd0 : (phase == 4'd15 ? 4'd15 : phase + 4'd1);
    wire cen_mix = (phase == 4'd5);
    wire cen_rgb = (phase == 4'd9);

    // All inputs to the priority encoder now have a real, fixed launch edge.
    // Include MMIO configuration: CPU writes are not aligned to pixel clocks.
    (* preserve *) logic [11:0] p_tm_pen [4], p_roz_pen, p_spr_pen;
    (* preserve *) logic [3:0] p_tm_opq;
    (* preserve *) logic p_roz_opq, p_spr_opq, p_spr_shadow, p_roz_enable;
    (* preserve *) logic [1:0] p_spr_shtab;
    (* preserve *) logic [7:0] p_spr_pri, p_spr_shpri, p_enables, p_pri [5];
    (* preserve *) logic [15:0] p_k38 [16];
    always_ff @(posedge clk) if (phase == 4'd2) begin
        for (int i = 0; i < 4; i++) p_tm_pen[i] <= tm_pen[i];
        p_tm_opq <= tm_opq; p_roz_pen <= roz_pen; p_roz_opq <= roz_opq;
        p_roz_enable <= roz_enable; p_spr_pen <= spr_pen; p_spr_opq <= spr_opq;
        p_spr_pri <= spr_pri; p_spr_shadow <= spr_shadow;
        p_spr_shtab <= spr_shtab; p_spr_shpri <= spr_shpri;
        p_enables <= k55regs[45];
        p_pri[0] <= k55regs[7]; p_pri[1] <= k55regs[10];
        p_pri[2] <= k55regs[13]; p_pri[3] <= k55regs[14]; p_pri[4] <= k55regs[16];
        for (int i = 0; i < 16; i++) p_k38[i] <= k38regs[i];
    end
    // K055555 register map (k055555.h). SUB2/SUB3 enables are not wired on
    // this board; pens are 11-bit into the 2048-entry palette; shadow deltas
    // occupy the low 9 bits of their registers.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] enables = p_enables;
    wire [7:0] pri_lyr [5];
    assign pri_lyr[0] = p_pri[0];      // A
    assign pri_lyr[1] = p_pri[1];     // B
    assign pri_lyr[2] = p_pri[2];     // C
    assign pri_lyr[3] = p_pri[3];     // D
    assign pri_lyr[4] = p_pri[4];     // SUB1

    wire [4:0] lyr_opq = {p_roz_opq & p_roz_enable & enables[5], p_tm_opq & enables[3:0]};
    wire [11:0] lyr_pen [5];
    assign lyr_pen[0] = p_tm_pen[0];
    assign lyr_pen[1] = p_tm_pen[1];
    assign lyr_pen[2] = p_tm_pen[2];
    assign lyr_pen[3] = p_tm_pen[3];
    assign lyr_pen[4] = p_roz_pen;

    // ------------------------------------------------------ stage 0: select
    logic        have_lyr;
    logic  [7:0] best_pri;
    logic [11:0] best_pen;
    /* verilator lint_on UNUSEDSIGNAL */
    logic        win_spr, win_any, darken;
    always_comb begin
        have_lyr = 1'b0; best_pri = 8'hff; best_pen = '0;
        // strict less-than in index order: the lowest index keeps a tie
        for (int l = 0; l < 5; l++) begin
            if (lyr_opq[l] && (!have_lyr || pri_lyr[l] < best_pri)) begin
                have_lyr = 1'b1; best_pri = pri_lyr[l]; best_pen = lyr_pen[l];
            end
        end
        // a sprite only beats a layer outright, never on a tie
        win_spr = p_spr_opq & enables[4] & (!have_lyr || (p_spr_pri < best_pri));
        win_any = have_lyr | win_spr;
        if (win_spr) best_pen = p_spr_pen;
        // shadow painted after the winner?  layer winner: only if its priority
        // is strictly above the shadow's.  sprite winner or nothing: always.
        darken = p_spr_shadow & enables[4]
               & !(have_lyr & !win_spr & (p_spr_shpri >= best_pri));
    end

    // ------------------------------------------- stage 1: palette address
    logic        s1_any, s1_darken, s2_any, s2_darken;
    logic  [1:0] s1_tab, s2_tab;
    always_ff @(posedge clk) begin
        if (cen_mix) begin
            pal_addr  <= best_pen[10:0];
            s1_any    <= win_any;  s1_darken <= darken;  s1_tab <= p_spr_shtab;
        end
        s2_any    <= s1_any;   s2_darken <= s1_darken; s2_tab <= s1_tab;
    end

    // ---------------------------------------------- stage 3: shadow / bg
    wire [23:0] backdrop = {p_k38[0][7:0], p_k38[1]};
    wire        noclip   = p_k38[15][5];

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic signed [9:0] shd_delta(input logic [15:0] r);
        // 9-bit two's complement in the register's low bits
        return r[8] ? $signed({1'b1, r[8:0]}) : $signed({1'b0, r[8:0]});
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */
    logic signed [9:0] dr, dg, db;
    always_comb begin
        case (s2_tab)
            2'd3: begin dr = -10'sd80; dg = -10'sd80; db = -10'sd80; end
            default: begin
                dr = shd_delta(p_k38[2 + {2'd0, s2_tab} * 3]);
                dg = shd_delta(p_k38[3 + {2'd0, s2_tab} * 3]);
                db = shd_delta(p_k38[4 + {2'd0, s2_tab} * 3]);
            end
        endcase
    end

    function automatic logic [7:0] pal5(input logic [4:0] v);
        return {v, v[4:2]};
    endfunction
    function automatic logic [7:0] clampd(input logic signed [9:0] v, input logic nc);
        if (nc) return v[7:0];
        return (v < 0) ? 8'd0 : (v > 10'sd255 ? 8'd255 : v[7:0]);
    endfunction

    logic [23:0] c_base;
    logic c_noclip, c_darken;
    logic signed [9:0] c_dr, c_dg, c_db, r5, g5, b5;
    always_ff @(posedge clk) begin
        if (phase == 4'd7) begin
            c_base <= s2_any ? pal_q : backdrop;
            c_noclip <= noclip; c_darken <= s2_darken;
            c_dr <= dr; c_dg <= dg; c_db <= db;
        end
        if (phase == 4'd8) begin
            r5 <= $signed({2'd0, pal5(c_base[23:19])}) + c_dr;
            g5 <= $signed({2'd0, pal5(c_base[15:11])}) + c_dg;
            b5 <= $signed({2'd0, pal5(c_base[7:3])}) + c_db;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) rgb <= '0;
        else if (cen_rgb) rgb <= c_darken ? {clampd(r5, c_noclip), clampd(g5, c_noclip), clampd(b5, c_noclip)}
                                         : c_base;
    end
endmodule
