//------------------------------------------------------------------------------
// Diagnostic overlay (METHODOLOGY section 4): when enabled, the bottom 12
// visible lines show three rows of 32 squares (11 px wide so all 32 fit a
// 376-px line, 4 px tall). Bit set = green, clear = dark grey, so a hang can
// be read off the panel without a debugger. The rows' meaning is the
// platform's (target/pocket/core_top.sv).
//------------------------------------------------------------------------------
`default_nettype none

module dbg_overlay (
    input  logic        clk,
    input  logic        cen_pix,
    input  logic        enable,
    input  logic        de, vsync,
    input  logic [7:0]  r_in, g_in, b_in,
    input  logic [95:0] status,        // [95:64] row 0, [63:32] row 1, [31:0] row 2 (bit 31 leftmost)
    output logic [7:0]  r_out, g_out, b_out,
    input logic mystic // stable profile; Mystic32cells at8px fit288 pixels
);
    logic [3:0] sq;                   // pixel within the square, 0..10
    logic [5:0] col;                  // square within the line
    logic [8:0] y;
    logic       de_d, vs_d;
    logic [8:0] height;               // visible lines counted in the previous frame
    // LOCAL pre-GX: break the live CPU-address -> status mux -> video-clock
    // path at real system-clock registers. Both stages are single-cycle;
    // the normal RGB pixel has already settled before the Pocket sample.
    logic [95:0] status_q;
    always_ff @(posedge clk) status_q <= status;

    always_ff @(posedge clk) begin
        if (cen_pix) begin
            de_d <= de; vs_d <= vsync;
            if (vsync && !vs_d) begin height <= y; y <= 9'd0; end
            else if (de && !de_d) begin sq <= 4'd0; col <= 6'd0; end
            else if (de) begin
                if (sq == (mystic ? 4'd7 : 4'd10)) begin sq <= 4'd0; col <= col + 6'd1; end else sq <= sq + 4'd1;
            end
            if (!de && de_d) y <= y + 9'd1;            // end of a visible line
        end
    end

    // Pixel coordinates are held for12/16 sys clocks. Pipeline geometry
    // independently of RGB/status, which retain their original one-clock
    // output latency. All geometry settles before the native video sample.
    logic [8:0] y_from_bottom;
    logic in_band,gap;
    logic [1:0] row;
    logic [5:0] col_q;
    always_ff @(posedge clk) begin
        y_from_bottom <= height-y;
        in_band <= enable && de && (y_from_bottom<=9'd12) && (y_from_bottom>=9'd1);
        row <= (y_from_bottom>9'd8) ? 2'd0 : (y_from_bottom>9'd4) ? 2'd1 : 2'd2;
        gap <= (sq == (mystic ? 4'd7 : 4'd10)) ||
               (y_from_bottom==9'd12) || (y_from_bottom==9'd8) || (y_from_bottom==9'd4);
        col_q <= col;
    end
    wire [31:0] word = (row==2'd0) ? status_q[95:64] : (row==2'd1) ? status_q[63:32] : status_q[31:0];
    wire bitv = word[5'd31-col_q[4:0]];

    always_ff @(posedge clk) begin
        if (in_band && col_q < 6'd32) begin
            if (gap)      {r_out, g_out, b_out} <= 24'h000000;
            else if (bitv){r_out, g_out, b_out} <= 24'h20e020;
            else          {r_out, g_out, b_out} <= 24'h303030;
        end else begin
            {r_out, g_out, b_out} <= {r_in, g_in, b_in};
        end
    end
endmodule
