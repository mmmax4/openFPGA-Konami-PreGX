//------------------------------------------------------------------------------
// Raster timing for Gaiapolis: the K053252's job, at this board's settings.
//
// 8 MHz pixel clock, 512 x 264 raster, visible 376 x 224 at origin (40, 16),
// 59.1856 Hz (docs/hardware.md section 1). The cabinet is ROT90; the Pocket
// rotates the output, so this scans the raster natively -- one raster line
// per output line.
//
// Each visible line is rendered into the line buffers during the line before
// it: at the start of raster line r this pulses `line_start` for line r+1,
// and the renderers have the full 512-pixel line (6,144 clocks) to finish.
// If any is still busy at the next pulse, `overrun` pulses for that line -- that is the
// budget in docs/hardware.md section 11 being exceeded, and it must never be
// silent.
//
// Scan-out is pipelined by one pixel: the line buffers and mixer need four
// clocks after `px` changes, so the colour presented at a cen_pix tick belongs
// to the previous px, and de/hs/vs are delayed to match.
//------------------------------------------------------------------------------
`default_nettype none

module gaia_video #(
    parameter int HTOTAL = 512,
    parameter int VTOTAL = 264,
    parameter int VIS_W  = 376,
    parameter int VIS_H  = 224,
    parameter int VIS_X0 = 40,
    parameter int VIS_Y0 = 16,
    parameter int HS_START = 448,     // hsync window inside hblank
    parameter int HS_LEN   = 32,
    parameter int VS_START = 248,     // vsync window inside vblank
    parameter int VS_LEN   = 3
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        mystic,         // stable through video reset/run
    output logic        scanline_start, // all native lines, for board IRQ2/4
    input  logic        cen_pix,        // 8 MHz

    // to the renderers
    output logic        line_start,
    output logic  [8:0] render_line,
    output logic        prestart,       // one pulse a few raster lines before the visible area (the ROZ plane pre-renders)
    input  logic  [2:0] renderers_busy, // {tilemap, ROZ, sprites}
    output logic        overrun,
    output logic  [2:0] overrun_src,    // which of them, with the pulse

    // scan-out
    output logic  [8:0] px,             // visible pixel index, valid with px_valid
    output logic        px_valid,
    output logic  [8:0] hcount,
    output logic  [8:0] vcount,

    // timing, one pixel behind px (aligned with the mixer's rgb)
    output logic        hsync,
    output logic        vsync,
    output logic        de,
    output logic        hblank,         // the Analogizer's scandoubler times lines from it
    output logic        vblank,
    output logic        vblank_rise     // one clk pulse at the start of vblank
);
    wire [8:0] hlast = mystic ? 9'd383 : 9'(HTOTAL-1);
    wire [8:0] xfirst = mystic ? 9'd24 : 9'(VIS_X0);
    wire [8:0] xend = mystic ? 9'd312 : 9'(VIS_X0+VIS_W);
    // Mystic porches follow the pinned MAME raw timing proposal. Physical
    // sync/clock/DDR and Analogizer CRT remain separately qualified.
    wire [8:0] hsfirst = mystic ? 9'd328 : 9'(HS_START);
    wire [8:0] hsend = mystic ? 9'd360 : 9'(HS_START+HS_LEN);
    wire [8:0] vsfirst = mystic ? 9'd256 : 9'(VS_START);
    wire [8:0] vsend = mystic ? 9'd264 : 9'(VS_START+VS_LEN);
    logic in_active_x, in_active_y;
    assign in_active_x = (hcount >= xfirst) && (hcount < xend);
    assign in_active_y = (vcount >= 9'(VIS_Y0)) && (vcount < 9'(VIS_Y0 + VIS_H));

    logic hs_r, vs_r, de_r, hb_r, vb_r;
    logic vb_prev;

    always_ff @(posedge clk) begin
        line_start  <= 1'b0;
        scanline_start <= 1'b0;
        prestart    <= 1'b0;
        vblank_rise <= 1'b0;
        if (reset) begin
            hcount <= '0; vcount <= '0; overrun <= 1'b0; overrun_src <= '0;
            hsync <= 1'b0; vsync <= 1'b0; de <= 1'b0; hblank <= 1'b1; vblank <= 1'b1; vb_prev <= 1'b1;
            // Reset both timing stages: the Analogizer must remain blank
            // on the first pixel after reset, before a prior pixel exists.
            hs_r <= 1'b0; vs_r <= 1'b0; de_r <= 1'b0; hb_r <= 1'b1; vb_r <= 1'b1;
            px <= '0; px_valid <= 1'b0; render_line <= '0;
        end else if (cen_pix) begin
            // raster counters
            if (hcount == hlast) begin
                hcount <= '0;
                vcount <= (vcount == 9'(VTOTAL - 1)) ? 9'd0 : vcount + 9'd1;
            end else hcount <= hcount + 9'd1;

            // start rendering the next line as this one begins
            if (hcount == 9'd0) begin
                logic [8:0] nxt;
                scanline_start <= 1'b1;
                nxt = (vcount == 9'(VTOTAL - 1)) ? 9'd0 : vcount + 9'd1;
                // ... including the pulse after the last visible line, so the
                // renderers hand over their last buffer as they do every other
                if (nxt >= 9'(VIS_Y0) && nxt <= 9'(VIS_Y0 + VIS_H)) begin
                    line_start  <= 1'b1;
                    render_line <= nxt;
                    overrun <= |renderers_busy;     // one pulse per overrunning line
                    overrun_src <= renderers_busy;
                end
                if (!mystic && vcount == 9'(VIS_Y0 - 6)) prestart <= 1'b1;
            end

            // scan-out address for this pixel
            px       <= hcount - xfirst;
            px_valid <= in_active_x && in_active_y;

            // timing outputs, delayed one pixel to line up with rgb
            de_r <= in_active_x && in_active_y;
            hs_r <= (hcount >= hsfirst) && (hcount < hsend);
            vs_r <= (vcount >= vsfirst) && (vcount < vsend);
            hb_r <= !in_active_x;
            vb_r <= !in_active_y;
            de <= de_r; hsync <= hs_r; vsync <= vs_r; hblank <= hb_r; vblank <= vb_r;

            vb_prev <= vb_r;
            if (vb_r && !vb_prev) vblank_rise <= 1'b1;
        end
    end
endmodule
