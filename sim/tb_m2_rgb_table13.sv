// Paired actual modules: shared public inputs; only public outputs observed.
`default_nettype none
module tb_m2_rgb_table13 (
    input logic clk, reset, line_start,
    input logic [23:0] backdrop,
    input logic [8:0] shadow_delta [9],
    input logic noclip,
    output wire busy,
    input logic fragment_valid,
    output wire fragment_ready,
    input logic [8:0] fragment_x, probe_x,
    output wire probe_ready,
    input logic [10:0] fragment_pen,
    input logic [9:0] fragment_level,
    input logic fragment_tile,
    input logic [7:0] fragment_toppri,
    input logic fragment_shadow,
    input logic [1:0] fragment_table, fragment_condition,
    input logic [7:0] fragment_z, fragment_pri,
    output wire [10:0] palette_addr,
    input logic [23:0] palette_q,
    input logic [8:0] scan_x,
    output wire [23:0] scan_rgb,
    output wire old_busy, old_fragment_ready, old_probe_ready,
    output wire [10:0] old_palette_addr,
    output wire [23:0] old_scan_rgb
);
    pregx_rgb_line candidate (
        .fragment_brightness(8'hff),
        .clk(clk),.reset(reset),.line_start(line_start),.backdrop(backdrop),
        .shadow_delta(shadow_delta),.noclip(noclip),.busy(busy),
        .fragment_valid(fragment_valid),.fragment_ready(fragment_ready),
        .fragment_x(fragment_x),.probe_x(probe_x),.probe_ready(probe_ready),
        .fragment_pen(fragment_pen),.fragment_level(fragment_level),
        .fragment_tile(fragment_tile),.fragment_toppri(fragment_toppri),
        .fragment_shadow(fragment_shadow),.fragment_table(fragment_table),
        .fragment_condition(fragment_condition),.fragment_z(fragment_z),.fragment_pri(fragment_pri),
        .palette_addr(palette_addr),.palette_q(palette_q),.scan_x(scan_x),.scan_rgb(scan_rgb)
    );
    pregx_rgb_line_old baseline (
        .clk(clk),.reset(reset),.line_start(line_start),.backdrop(backdrop),
        .shadow_delta(shadow_delta),.noclip(noclip),.busy(old_busy),
        .fragment_valid(fragment_valid),.fragment_ready(old_fragment_ready),
        .fragment_x(fragment_x),.probe_x(probe_x),.probe_ready(old_probe_ready),
        .fragment_pen(fragment_pen),.fragment_level(fragment_level),
        .fragment_tile(fragment_tile),.fragment_toppri(fragment_toppri),
        .fragment_shadow(fragment_shadow),.fragment_table(fragment_table),
        .fragment_condition(fragment_condition),.fragment_z(fragment_z),.fragment_pri(fragment_pri),
        .palette_addr(old_palette_addr),.palette_q(palette_q),.scan_x(scan_x),.scan_rgb(old_scan_rgb)
    );
endmodule
`default_nettype wire
