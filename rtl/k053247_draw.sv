//------------------------------------------------------------------------------
// K053247 sprite rasterizer for Gaiapolis.
//
// Walks the ordered object list from k053247_objlist once per display line and
// rasterizes whatever covers it into a line buffer with a per-pixel Z buffer,
// as zdrawgfxzoom32GP does. Semantics follow tools/render_model.py; the design
// notes are in docs/sprite-rasterizer.md.
//
// Only one output line is produced per pass, and tile rows tile the destination
// exactly, so at most one tile row of a sprite can cover a given line. That
// collapses the destination rectangle to a single scanline and keeps the
// per-tile cost to one ROM fetch plus a DDA.
//------------------------------------------------------------------------------
`default_nettype none

module k053247_draw #(
    parameter int VIS_W  = 376,
    parameter int VIS_X0 = 40,
    parameter int VIS_Y0 = 16,
    parameter int VIS_H  = 224,
    parameter int LB_AW  = 9,
    // k055673 set_config(K055673_LAYOUT_RNG, -61, -22) for gaiapolis
    parameter int DX = -61,
    parameter int DY = -22
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        mystic,        // stable profile through render/scanout

    input  logic        line_start,
    input  logic  [8:0] line,
    output logic        busy,

    // Only a few bits of each register matter here: k46r5[1:0] is screen flip,
    // opset[6] selects the wrap size, list_q[3:2] is unused drawmode padding.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic  [7:0] k46r5,          // k053246 register 5: screen flip
    input  logic [15:0] k46_offx,       // (regs[0] << 8) | regs[1]
    input  logic [15:0] k46_offy,       // (regs[2] << 8) | regs[3]
    input  logic [15:0] opset,          // k053247 register 0x0c
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [9:0] alpha1, alpha2, alpha3, // current K054338 value incl additive/MIXPRI
    // Optional ordered RGB consumer. Legacy line-buffer mode keeps this0.
    input logic stream_enable,
    output logic order_valid,
    output wire [7:0] order_priority,
    output wire order_deferred,
    input logic order_ready,
    output logic fragment_valid,
    input logic fragment_ready,
    output wire [LB_AW-1:0] fragment_x,
    output wire [11:0] fragment_pen,
    output wire [9:0] fragment_level,
    output wire fragment_shadow,
    output wire [1:0] fragment_table, fragment_condition,
    output wire [7:0] fragment_z, fragment_pri,
    input  logic  [7:0] colorbase,      // sprite colour base, pre-masked

    output wire   [9:0] list_idx,
    output wire   [7:0] yr_addr,        // the entry's line range from the list builder
    input  logic [21:0] yr_q,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] list_q,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic  [9:0] list_count,

    output wire  [10:0] ram_addr,
    input  logic [15:0] ram_q,

    // sprite ROM: address is the 16-pixel row index, code*16 + row.
    // rom_q[63:56] is the lowest byte of the eight.
    output logic        rom_req,
    output logic [19:0] rom_addr,
    input  logic        rom_ack,
    input  logic [63:0] rom_q,
    input  logic [15:0] rom_fifth,     // same ACK: left byte high, right byte low

    output logic  [9:0] zoom_addr,
    input  logic [23:0] zoom_q,
    output logic [10:0] recip_addr,
    input  logic [23:0] recip_q,

    input  logic [LB_AW-1:0] px,
    output logic        out_opaque,
    output logic [11:0] out_pen,
    output logic  [7:0] out_pri,
    output logic  [1:0] out_effect,
    output logic        out_shadow,
    output logic  [1:0] out_shtab,
    output logic  [7:0] out_shpri,      // the shadow object's priority, for the mixer

    output logic        shadow_overlap,

    // diagnostics for the frozen-state bench
    output logic [31:0] dbg_objs, dbg_rows, dbg_cols, dbg_pxw
);
    // Nearly every value here is a field carved out of a 16-bit chip register
    // or a wide intermediate that is then truncated, so unused bits are the
    // normal case rather than a mistake. Waived once for the whole module
    // instead of nineteen times.
    /* verilator lint_off UNUSEDSIGNAL */

    wire signed [17:0] DXS = mystic ? -18'sd48 : 18'(DX);
    wire signed [17:0] DYS = mystic ? -18'sd24 : 18'(DY);
    wire signed [17:0] CLS = mystic ? 18'sd24 : 18'(VIS_X0);
    wire signed [17:0] CRS = mystic ? 18'sd311 : 18'(VIS_X0 + VIS_W - 1);
    wire [LB_AW-1:0] last_visible = mystic ? LB_AW'(287) : LB_AW'(VIS_W - 1);
    localparam logic signed [17:0] CTS = 18'(VIS_Y0);
    localparam logic signed [17:0] CBS = 18'(VIS_Y0 + VIS_H - 1);

    // ------------------------------------------------------------ buffers
    logic        bank;
    // The physical RAM already rounds up to this depth. A power-of-two
    // stride makes the bank a high address bit, rather than bank*VIS_W in
    // every read/write address. Only the VIS_W visible entries are used.
    localparam int LB_DEPTH = 1 << LB_AW;
    logic [17:0] solid [2][LB_DEPTH];   // {opaque, palette12, priority_code3, effect2}
    logic [10:0] shade [2][LB_DEPTH];   // {flag, table[1:0], priority[7:0]}
    logic  [7:0] zbuf  [VIS_W];
    logic [15:0] szbuf [VIS_W];         // {z, priority}

    logic [17:0] rd_solid;
    logic [10:0] rd_shade;
    always_ff @(posedge clk) begin
        rd_solid <= solid[~bank][px];
        rd_shade <= shade[~bank][px];
    end
    assign out_opaque = rd_solid[17];
    assign out_pen    = rd_solid[16:5];
    assign out_pri    = {rd_solid[4:2], 5'd0};
    assign out_effect = rd_solid[1:0];
    assign out_shadow = rd_shade[10];
    assign out_shtab  = rd_shade[9:8];
    assign out_shpri  = rd_shade[7:0];

    function automatic logic [5:0] xoffset(input logic [2:0] i);
        case (i)
            3'd0: return 6'd0;  3'd1: return 6'd1;  3'd2: return 6'd4;  3'd3: return 6'd5;
            3'd4: return 6'd16; 3'd5: return 6'd17; 3'd6: return 6'd20; default: return 6'd21;
        endcase
    endfunction
    function automatic logic [5:0] yoffset(input logic [2:0] i);
        case (i)
            3'd0: return 6'd0;  3'd1: return 6'd2;  3'd2: return 6'd8;  3'd3: return 6'd10;
            3'd4: return 6'd32; 3'd5: return 6'd34; 3'd6: return 6'd40; default: return 6'd42;
        endcase
    endfunction

    typedef enum logic [5:0] {
        D_IDLE, D_CLR, D_OBJ, D_OBJW,
        D_R0, D_R1, D_R2, D_R3, D_R4, D_R5, D_R6, D_LAT,
        D_ZY, D_ZYW, D_ZY2, D_ZXW, D_ZX2, D_GEOM, D_GEOM2,
        D_TY, D_TYC, D_SY1, D_SY2, D_SY3, D_SY4,
        D_TX, D_TXC, D_SX1, D_SX2, D_SX2B, D_SX3, D_ROWW, D_PIX,
        D_NEXTTX, D_NEXTOBJ, D_ZY_FAST
    } state_t;
    state_t st;

    logic  [9:0] obj_i;
    logic  [7:0] ent, zcode, opri;
    logic  [3:0] drawmode;
    logic  [1:0] shtab;
    logic [1:0] shadow_condition;
    logic [9:0] object_level;
    logic [15:0] w0, w1, w2, w3, w4, w5, w6;
    logic [23:0] zoomx, zoomy;
    logic  [9:0] scalex, scaley;
    logic        nozoom;
    logic signed [17:0] ox, oy, sy, sx, pxl, pxr, cur_px;
    logic  [3:0] width, height;
    logic  [2:0] ty, tx, xa, ya;
    // Eight tiles at the maximum 0x800000 zoom need 27 bits including
    // the final endpoint. A 24-bit accumulator wrapped every two tiles.
    logic [26:0] yacc, xacc;
    logic [23:0] stride_x, stride_y;
    logic [12:0] zh, zw;
    logic [31:0] ddax;
    logic  [7:0] color;
    logic        flipx, flipy, mirrorx, mirrory, fx, fy;
    logic [15:0] codebase, tempcode_y, tempcode;
    logic  [3:0] src_row;
    logic  [4:0] shdpen;
    logic  [1:0] effect;
    logic [63:0] rowdata;
    logic [15:0] rowfifth;
    logic [LB_AW-1:0] clr_i;

    wire tile_solid = (drawmode < 4'd4);
    wire [9:0] object_alpha = (w6[9:8] == 2'd1) ? alpha1 :
                              (w6[9:8] == 2'd2) ? alpha2 :
                              (w6[9:8] == 2'd3) ? alpha3 : 10'd255;

    // ------------------------------------------------------- geometry (comb)
    // Screen flip is wired through but unexercised: k053246 register 5 reads
    // 0x20 in every captured frame, so both flip bits are clear.
    wire [3:0] szc  = w0[11:8];
    wire [4:0] gwsh = 5'd13 - {3'd0, szc[1:0]};
    wire [4:0] ghsh = 5'd13 - {3'd0, szc[3:2]};
    wire [23:0] gwshift = zoomx >> gwsh;
    wire [23:0] ghshift = zoomy >> ghsh;

    wire [17:0] wrapsz  = opset[6] ? 18'd512 : 18'd1024;
    wire [17:0] wrapmsk = wrapsz - 18'd1;
    wire [17:0] xwlim   = opset[6] ? 18'd448 : 18'd640;
    wire [17:0] ywlim   = opset[6] ? 18'd384 : 18'd512;

    wire signed [17:0] oxr = $signed({8'd0, w3[9:0]});
    wire signed [17:0] ox1 = (k46r5[0] ? -oxr : oxr) + DXS;
    wire signed [17:0] ox2 = (ox1 - $signed({2'd0, k46_offx})) & $signed(wrapmsk);
    // Y wraps modulo512/1024. Keep ten-bit offset arithmetic separate
    // so the global-flip selector feeds just the final addition.
    wire [9:0] oy_raw = k46r5[1] ? w2[9:0] : (10'd0 - w2[9:0]);
    wire [9:0] oy_offset = 10'(DYS) - k46_offy[9:0];
    wire signed [17:0] oy2 = $signed({8'd0, (oy_raw + oy_offset) & wrapmsk[9:0]});
    // registered half-way (D_GEOM), the wrap and the zoom offset follow (D_GEOM2):
    // the whole chain from the K053246 offset registers was a -1.6 ns path
    logic signed [17:0] ox2_r, oy2_r;
    wire signed [17:0] ox3 = (ox2_r >= $signed(xwlim)) ? ox2_r - $signed(wrapsz) : ox2_r;
    wire signed [17:0] oy3 = (oy2_r >= $signed(ywlim)) ? oy2_r - $signed(wrapsz) : oy2_r;
    wire signed [17:0] gox = ox3 - $signed({4'd0, gwshift[13:0]});
    wire signed [17:0] goy = oy3 - $signed({4'd0, ghshift[13:0]});

    // ------------------------------------------------------ tile row / column
    wire [26:0] ysum0 = yacc + 27'd2048;
    wire [26:0] ysum1 = yacc + {3'd0, zoomy} + 27'd2048;
    wire signed [17:0] sy_c = oy + $signed({3'd0, ysum0[26:12]});
    wire [12:0] zh_c = nozoom ? 13'd16 : 13'(ysum1[26:12] - ysum0[26:12]);

    wire [26:0] xsum0 = xacc + 27'd2048;
    wire [26:0] xsum1 = xacc + {3'd0, zoomx} + 27'd2048;
    wire signed [17:0] sx_c = ox + $signed({3'd0, xsum0[26:12]});
    wire [12:0] zw_c = nozoom ? 13'd16 : 13'(xsum1[26:12] - xsum0[26:12]);

    // mirroring, per k053247_draw_yxloop_gx
    wire [3:0] tx2 = {1'b0, tx} << 1;
    wire [3:0] ty2 = {1'b0, ty} << 1;
    wire xmir_alt = (~flipx) ^ (tx2 < width);
    wire ymir_alt = (~flipy) ^ (ty2 >= height);
    wire [2:0] xrev = width[2:0]  - 3'd1 - tx + xa;
    wire [2:0] xfwd = tx + xa;
    wire [2:0] yrev = height[2:0] - 3'd1 - ty + ya;
    wire [2:0] yfwd = ty + ya;
    wire [2:0] xsel = mirrorx ? (xmir_alt ? xrev : xfwd) : (flipx ? xrev : xfwd);
    // the same for the column after this one: its row is asked for as soon as
    // this column's arrives, so the burst runs under this column's pixel loop
    wire [2:0] tx_n = tx + 3'd1;
    wire [3:0] tx2_n = {1'b0, tx_n} << 1;
    wire xmir_alt_n = (~flipx) ^ (tx2_n < width);
    wire [2:0] xrev_n = width[2:0] - 3'd1 - tx_n + xa;
    wire [2:0] xfwd_n = tx_n + xa;
    wire [2:0] xsel_n = mirrorx ? (xmir_alt_n ? xrev_n : xfwd_n) : (flipx ? xrev_n : xfwd_n);
    wire has_next = ({1'b0, tx} + 4'd1) < width;
    logic        pf_valid, pf_have;     // a prefetch is out for the next column; its row has arrived
    logic [63:0] rowdata_pf;
    logic [15:0] rowfifth_pf;
    wire [2:0] ysel = mirrory ? (ymir_alt ? yrev : yfwd) : (flipy ? yrev : yfwd);
    wire fx_c = mirrorx ? xmir_alt : flipx;
    wire fy_c = mirrory ? ymir_alt : flipy;

    // this line's source row, and the clipped destination span for this tile
    // the source row: line - sy, times the row's reciprocal stride, in three
    // registered steps (as one clock the multiply missed the cold corner)
    wire signed [17:0] lsy = $signed({9'd0, line}) - sy;
    logic  [8:0] lsy_r;
    logic [32:0] ymul_r;
    wire  [3:0] yoff = ymul_r[22:19];

    wire signed [17:0] sxz    = sx + $signed({5'd0, zw}) - 18'sd1;
    wire signed [17:0] pxl_c  = (sx  > CLS) ? sx  : CLS;
    wire signed [17:0] pxr_c  = (sxz < CRS) ? sxz : CRS;
    // the first drawn pixel's offset into the column, then its source
    // position: a subtract and a multiply, one state each (together they
    // were a -2.2 ns path at 96 MHz)
    logic [9:0] pxoff;
    wire [33:0] xmul = {24'd0, pxoff} * {10'd0, stride_x};

    wire row_covers  = (zh != 13'd0) && (lsy >= 18'sd0) && (lsy < $signed({5'd0, zh}))
                    && (sy <= CBS) && ((sy + $signed({5'd0, zh}) - 18'sd1) >= CTS);
    wire col_visible = (zw != 13'd0) && (sx <= CRS) && (sxz >= CLS);

    // ---- pixel extraction from the fetched 16-pixel row ----
    wire [3:0] x_off  = ddax[22:19];
    // Apply X reflection once when the fetched row enters its register.
    // The per-pixel path then needs only the source-column selection; fx
    // no longer crosses pen classification and stream backpressure logic.
    function automatic logic [7:0] reverse_byte(input logic [7:0] value);
        for (int b=0;b<8;b++) reverse_byte[b] = value[7-b];
    endfunction
    function automatic logic [63:0] reflected_row(input logic [63:0] value);
        for (int p=0;p<4;p++) begin
            reflected_row[p*8+:8] = reverse_byte(value[(p+4)*8+:8]);
            reflected_row[(p+4)*8+:8] = reverse_byte(value[p*8+:8]);
        end
    endfunction
    function automatic logic [15:0] reflected_fifth(input logic [15:0] value);
        return {reverse_byte(value[7:0]),reverse_byte(value[15:8])};
    endfunction
    wire [3:0] srccol = x_off;
    // Plane p of pixel c sits at bit planeoffset[p] + xoffset[c], and
    // xoffset jumps from 7 to 32 at pixel 8 -- so the upper half's planes run
    // through bytes 7,6,5,4 while the lower half's run through 3,2,1,0. The
    // byte order reverses across the halves; it does not simply shift.
    wire [7:0] pl0 = srccol[3] ? rowdata[ 7: 0] : rowdata[39:32];   // MSB plane
    wire [7:0] pl1 = srccol[3] ? rowdata[15: 8] : rowdata[47:40];
    wire [7:0] pl2 = srccol[3] ? rowdata[23:16] : rowdata[55:48];
    wire [7:0] pl3 = srccol[3] ? rowdata[31:24] : rowdata[63:56];   // LSB plane
    wire [2:0] plb = 3'd7 - srccol[2:0];
    wire [7:0] pl4 = srccol[3] ? rowfifth[7:0] : rowfifth[15:8];
    wire [4:0] pen = {mystic && pl4[plb], pl0[plb], pl1[plb], pl2[plb], pl3[plb]};

    // GX uses 32768 codes; reduce the completed code, including tile offsets.
    function automatic logic [19:0] row_address(input logic [15:0] code, input logic [3:0] row);
        return {mystic ? {1'b0, code[14:0]} : code, row};
    endfunction

    // Track the line-buffer column locally instead of subtracting the
    // visible origin from the signed screen coordinate on every pixel.
    logic [LB_AW-1:0] lbi;

    // The Z buffers and the shadow flag are block RAM read a pixel ahead: the
    // word for the pixel being decided was addressed the cycle before -- the
    // row's first pixel while its ROM row is fetched, then each next pixel as
    // the previous one is written. Consecutive pixels of a row have distinct
    // x and rows are several states apart, so a read never meets a write to
    // the same address. (As registers with per-pixel muxes these three were
    // 16K ALUTs, most of the device.)
    wire signed [17:0] lbis_first = pxl - CLS;
    wire solid_candidate = tile_solid && (pen!=5'd0) &&
        !(drawmode[1:0]!=2'd0 && pen>=shdpen) && (zb_q>=zcode);
    wire shadow_candidate = !tile_solid && (pen>=shdpen);
    wire streaming = mystic && stream_enable;
    logic [9:0] legacy_list_idx;
    logic [7:0] legacy_yr_addr;
    logic [10:0] legacy_ram_addr;
    wire [9:0] queued_list_idx;
    wire [7:0] queued_yr_addr;
    wire queued_valid, queued_done;
    wire [31:0] queued_entry;
    wire raw_ready;
    wire [10:0] cached_ram_addr;
    wire [15:0] cached_words[7];
    wire consume_header = st==D_OBJ && order_ready && queued_valid && raw_ready;
    pregx_sprite_word_cache word_cache(
        .clk(clk),.reset(reset || !streaming),.line_start(line_start),
        .head_valid(queued_valid),.head_ent(queued_entry[15:8]),.consume(consume_header),
        .ram_addr(cached_ram_addr),.ram_q(ram_q),.ready(raw_ready),.words(cached_words)
    );
    pregx_sprite_line_queue line_queue(
        .clk(clk),.reset(reset || !streaming),.line_start(line_start),.line(line),
        .list_count(list_count),.list_idx(queued_list_idx),.list_q(list_q),
        .yr_addr(queued_yr_addr),.yr_q(yr_q),.valid(queued_valid),.entry(queued_entry),
        .ready(st==D_OBJ && order_ready && raw_ready),.scan_done(queued_done)
    );
    assign list_idx = streaming ? queued_list_idx : legacy_list_idx;
    assign yr_addr = streaming ? queued_yr_addr : legacy_yr_addr;
    assign ram_addr = streaming ? cached_ram_addr : legacy_ram_addr;
    assign order_valid=streaming && st==D_OBJ && queued_valid && raw_ready;
    assign order_priority=queued_entry[31:24];
    assign order_deferred=queued_entry[3:2]==2'd1 || queued_entry[3:2]==2'd2;
    assign fragment_valid=streaming && st==D_PIX && (solid_candidate || shadow_candidate);
    assign fragment_x=lbi;
    assign fragment_pen=mystic ? {color[6:0],pen} : {color,pen[3:0]};
    assign fragment_level=drawmode[1] ? object_level : 10'd255;
    assign fragment_shadow=!tile_solid;
    assign fragment_table=shtab;
    assign fragment_condition=shadow_condition;
    assign fragment_z=zcode;
    assign fragment_pri=opri;
    // Keep pixel-data classification out of the stream-ready feedback.
    wire advance_pixel=!streaming || fragment_ready;
    wire [LB_AW-1:0] rd_lbi = (st==D_PIX) ?
        (advance_pixel ? lbi + 1'b1 : lbi) : lbis_first[LB_AW-1:0];
    logic  [7:0] zb_q;
    logic [15:0] szb_q;
    logic [10:0] sh_q;
    always_ff @(posedge clk) begin
        zb_q  <= zbuf[rd_lbi];
        szb_q <= szbuf[rd_lbi];
        sh_q  <= shade[bank][rd_lbi];
    end
    wire [7:0] szb_z = szb_q[15:8];
    wire [7:0] szb_p = szb_q[7:0];
    // the decided pixel, one cycle ahead of its write
    logic            px_valid_a, solid_a, shade_a, ovl_a;
    logic [LB_AW-1:0] lbi_a;
    logic      [4:0] pen_a;
    wire [11:0] palette_a = mystic ? {color[6:0], pen_a} : {color, pen_a[3:0]};

    /* verilator lint_on UNUSEDSIGNAL */

    // -------------------------------------------------------------------- FSM
    always_ff @(posedge clk) begin
        px_valid_a <= 1'b0;
        if (reset) begin
            st <= D_IDLE; busy <= 1'b0; bank <= 1'b0;
            rom_req <= 1'b0; shadow_overlap <= 1'b0; pf_valid <= 1'b0; pf_have <= 1'b0;
            dbg_objs <= '0; dbg_rows <= '0; dbg_cols <= '0; dbg_pxw <= '0;
        end else if (line_start && st != D_IDLE) begin
            // the previous line overran its budget: abandon it and start this
            // one, as the hardware would -- whatever was drawn is what shows
            bank <= ~bank; busy <= 1'b1;
            rom_req <= 1'b0; pf_valid <= 1'b0; pf_have <= 1'b0; clr_i <= '0; st <= D_CLR;
        end else begin
            // a prefetched row arriving while the pixel loop runs
            if (pf_valid && !pf_have && rom_ack && st != D_ROWW) begin
                rowdata_pf <= rom_q; rowfifth_pf <= rom_fifth; rom_req <= 1'b0; pf_have <= 1'b1;
            end
            case (st)
                D_IDLE: begin
                    busy <= 1'b0;
                    if (line_start) begin
                        bank <= ~bank; busy <= 1'b1; clr_i <= '0; st <= D_CLR;
                    end
                end

                D_CLR: begin
                    // clear the bank we are about to render into, not the one
                    // being scanned out (the writes are in the chain below)
                    if (clr_i == last_visible) begin
                        obj_i <= '0;
                        if (!streaming && list_count == 10'd0) begin st <= D_IDLE; busy <= 1'b0; end
                        else st <= D_OBJ;
                    end else clr_i <= clr_i + 1'd1;
                end

                D_OBJ: begin
                    if (streaming) begin
                        // Only Y-visible headers enter the RGB ordering path.
                        // Prefetch runs during clear and the current object's
                        // pixel work; preserve every bit and original order.
                        if (consume_header) begin
                            ent <= queued_entry[15:8];
                            zcode <= queued_entry[23:16];
                            opri <= queued_entry[31:24];
                            drawmode <= queued_entry[7:4];
                            shtab <= queued_entry[1:0];
                            shadow_condition <= queued_entry[3:2];
                            shdpen <= (queued_entry[7:4] == 4'd5) ? 5'd1 : 5'd31;
                            w0<=cached_words[0];w1<=cached_words[1];w2<=cached_words[2];
                            w3<=cached_words[3];w4<=cached_words[4];w5<=cached_words[5];
                            w6<=cached_words[6];
                            dbg_objs <= dbg_objs + 1'd1;
                            st <= D_ZY_FAST;
                        end else if (queued_done && !queued_valid) begin
                            st <= D_IDLE; busy <= 1'b0;
                        end
                    end else begin
                        legacy_list_idx <= obj_i; dbg_objs <= dbg_objs + 1'd1; st <= D_OBJW;
                    end
                end
                D_OBJW: st <= D_R0;

                D_R0: if(!streaming || order_ready) begin
                    ent      <= list_q[15:8];
                    legacy_yr_addr <= list_q[15:8];
                    zcode    <= list_q[23:16];
                    opri     <= list_q[31:24];
                    drawmode <= list_q[7:4];
                    shtab    <= list_q[1:0];
                    shadow_condition<=list_q[3:2];
                    shdpen   <= (list_q[7:4] == 4'd5) ? 5'd1 : (mystic ? 5'd31 : 5'd15);
                    legacy_ram_addr <= {list_q[15:8], 3'd0};
                    st <= D_R1;
                end
                // The address register and the RAM read are both registered, so
                // ram_q lags the address by two states: word 0 arrives in D_R2.
                D_R1:  begin legacy_ram_addr <= {ent, 3'd1};                st <= D_R2;  end
                // the builder's line range for this entry (asked for in D_R0) is
                // here now: an object that misses the line costs five clocks
                D_R2:  begin
                    legacy_ram_addr <= {ent, 3'd2}; w0 <= ram_q;
                    if (!streaming &&
                        ($signed({9'd0, line}) < $signed({{7{yr_q[21]}}, yr_q[21:11]}) ||
                         $signed({9'd0, line}) > $signed({{7{yr_q[10]}}, yr_q[10:0]}))) st <= D_NEXTOBJ;
                    else st <= D_R3;
                end
                D_R3:  begin legacy_ram_addr <= {ent, 3'd3}; w1 <= ram_q;   st <= D_R4;  end
                D_R4:  begin legacy_ram_addr <= {ent, 3'd4}; w2 <= ram_q;   st <= D_R5;  end
                D_R5:  begin legacy_ram_addr <= {ent, 3'd5}; w3 <= ram_q;   st <= D_R6;  end
                D_R6:  begin legacy_ram_addr <= {ent, 3'd6}; w4 <= ram_q;   st <= D_LAT; end
                D_LAT: begin w5 <= ram_q;                            st <= D_ZY;  end

                D_ZY: begin
                    w6 <= ram_q;
                    scaley <= w4[9:0]; zoom_addr <= w4[9:0];
                    st <= D_ZYW;
                end
                D_ZY_FAST: begin
                    // Streaming raw words were prefetched from the immutable
                    // visible-frame SRAM snapshot while the previous object ran.
                    scaley <= w4[9:0]; zoom_addr <= w4[9:0]; st <= D_ZYW;
                end
                D_ZYW: st <= D_ZY2;
                D_ZY2: begin
                    zoomy     <= zoom_q;
                    scalex    <= w0[14] ? scaley : w5[9:0];
                    zoom_addr <= w0[14] ? scaley : w5[9:0];
                    st <= D_ZXW;
                end
                D_ZXW: st <= D_ZX2;
                D_ZX2: begin zoomx <= zoom_q; st <= D_GEOM; end

                D_GEOM: begin
                    object_level<=object_alpha;
                    // Keep raw mode2/3 in the ordered list; alpha gating is
                    // a draw operation, before writing any object Z/pixel.
                    if (mystic && drawmode[1] && object_alpha == 10'd255)
                        drawmode <= drawmode & 4'hd;
                    nozoom  <= (scalex == 10'h40) && (scaley == 10'h40);
                    mirrorx <= w6[14];
                    mirrory <= w6[15];
                    flipx   <= w6[14] ? 1'b0    : (w0[12] ^ k46r5[0]);
                    flipy   <= w6[15] ? w0[13]  : (w0[13] ^ k46r5[1]);
                    // gaiapols_sprite_callback
                    color   <= colorbase | {2'd0, !mystic && w6[9], 5'd0} | {3'd0, w6[4:0]};
                    effect  <= mystic ? w6[9:8] : 2'b00;
                    width   <= 4'd1 << szc[1:0];
                    height  <= 4'd1 << szc[3:2];
                    xa <= {2'd0, w1[0]} + {1'd0, w1[2], 1'b0} + {w1[4], 2'd0};
                    ya <= {2'd0, w1[1]} + {1'd0, w1[3], 1'b0} + {w1[5], 2'd0};
                    codebase <= w1 & ~16'h003f;
                    ox2_r <= ox2;
                    oy2_r <= oy2;
                    st <= (mystic && drawmode[1] && object_alpha == 10'd0) ? D_NEXTOBJ : D_GEOM2;
                end
                D_GEOM2: begin
                    ox <= gox;
                    oy <= goy;
                    ty <= 3'd0; yacc <= '0;
                    st <= D_TY;
                end

                // ---- find the tile row covering this line ----
                D_TY:  begin sy <= sy_c; zh <= zh_c; st <= D_TYC; end
                D_TYC: begin
                    if (row_covers) begin
                        dbg_rows <= dbg_rows + 1'd1;
                        recip_addr <= zh[10:0];
                        fy         <= fy_c;
                        tempcode_y <= codebase + {10'd0, yoffset(ysel)};
                        st <= D_SY1;
                    end else if (ty == height[2:0] - 3'd1) begin
                        st <= D_NEXTOBJ;
                    end else begin
                        ty <= ty + 3'd1; yacc <= yacc + {3'd0, zoomy}; st <= D_TY;
                    end
                end
                D_SY1: begin lsy_r <= lsy[8:0]; st <= D_SY2; end
                D_SY2: begin stride_y <= recip_q; st <= D_SY3; end
                D_SY3: begin ymul_r <= {24'd0, lsy_r} * {9'd0, stride_y}; st <= D_SY4; end
                D_SY4: begin
                    src_row <= fy ? (~yoff) : yoff;
                    tx <= 3'd0; xacc <= '0;
                    st <= D_TX;
                end

                // ---- walk the tiles across that row ----
                D_TX:  begin sx <= sx_c; zw <= zw_c; st <= D_TXC; end
                D_TXC: begin
                    if (col_visible) begin
                        dbg_cols <= dbg_cols + 1'd1;
                        recip_addr <= zw[10:0];
                        fx         <= fx_c;
                        tempcode   <= tempcode_y + {10'd0, xoffset(xsel)};
                        st <= D_SX1;
                    end else begin
                        if (pf_valid) begin rom_req <= 1'b0; pf_valid <= 1'b0; pf_have <= 1'b0; end   // not wanted after all
                        st <= D_NEXTTX;
                    end
                end
                D_SX1: st <= D_SX2;
                D_SX2: begin
                    stride_x <= recip_q;
                    pxl <= pxl_c; pxr <= pxr_c;
                    st <= D_SX2B;
                end
                D_SX2B: begin
                    pxoff <= 10'(pxl - sx);      // at most a tile column's width
                    st <= D_SX3;
                end
                D_SX3: begin
                    ddax     <= xmul[31:0];
                    cur_px   <= pxl;
                    lbi      <= lbis_first[LB_AW-1:0];
                    if (pf_valid && pf_have) begin              // this column's row came early
                        rowdata <= fx ? reflected_row(rowdata_pf) : rowdata_pf;
                        rowfifth <= fx ? reflected_fifth(rowfifth_pf) : rowfifth_pf; pf_have <= 1'b0;
                        if (has_next) begin rom_addr <= row_address(tempcode_y + {10'd0, xoffset(xsel_n)}, src_row); rom_req <= 1'b1; end
                        else pf_valid <= 1'b0;
                        st <= D_PIX;
                    end else if (pf_valid) begin                // still on its way
                        st <= D_ROWW;
                    end else begin
                        rom_addr <= row_address(tempcode, src_row);
                        rom_req  <= 1'b1;
                        st <= D_ROWW;
                    end
                end
                // (a prefetched row can land on the clock the wait begins: then it
                // is already in rowdata_pf)
                D_ROWW: if (rom_ack || (pf_valid && pf_have)) begin
                    rowdata <= fx ? reflected_row((pf_valid && pf_have) ? rowdata_pf : rom_q)
                                  : ((pf_valid && pf_have) ? rowdata_pf : rom_q);
                    rowfifth <= fx ? reflected_fifth((pf_valid && pf_have) ? rowfifth_pf : rom_fifth)
                                   : ((pf_valid && pf_have) ? rowfifth_pf : rom_fifth);
                    if (has_next) begin                         // ask for the next column's row now
                        rom_addr <= row_address(tempcode_y + {10'd0, xoffset(xsel_n)}, src_row); rom_req <= 1'b1;
                        pf_valid <= 1'b1; pf_have <= 1'b0;
                    end else begin rom_req <= 1'b0; pf_valid <= 1'b0; end
                    st <= D_PIX;
                end

                // The pixel loop is two stages: this state decides pixel n
                // (its pen, the Z and shadow compares) into registers while
                // the block below writes pixel n-1 -- the decision straight
                // into the line-buffer write enables was the design's tightest
                // path. A row's last write lands in the D_NEXTTX cycle.
                D_PIX: if(advance_pixel) begin
                    px_valid_a <= 1'b1;
                    lbi_a <= lbi; pen_a <= pen; ovl_a <= sh_q[10];
                    // drawmode 1 also rejects the shadow pen
                    solid_a <= solid_candidate;
                    shade_a <= !tile_solid && (pen >= shdpen) && (szb_z >= zcode) && (szb_p > opri);
                    ddax <= ddax + {8'd0, stride_x};
                    lbi <= lbi + 1'b1;
                    if (cur_px >= pxr) st <= D_NEXTTX;
                    else cur_px <= cur_px + 18'sd1;
                end

                D_NEXTTX: begin
                    if (tx == width[2:0] - 3'd1) st <= D_NEXTOBJ;
                    else begin tx <= tx + 3'd1; xacc <= xacc + {3'd0, zoomx}; st <= D_TX; end
                end

                D_NEXTOBJ: begin
                    if (streaming) begin obj_i <= obj_i + 10'd1; st <= D_OBJ; end
                    else if (obj_i + 10'd1 == list_count) begin st <= D_IDLE; busy <= 1'b0; end
                    else begin obj_i <= obj_i + 10'd1; st <= D_OBJ; end
                end

                default: st <= D_IDLE;
            endcase

            // ---- one write per buffer per cycle: the pixel decided last
            // cycle, else the line clear. One statement chain per RAM, so
            // Quartus sees one write port (two, and every buffer became
            // registers: 25K ALUTs)
            if (px_valid_a && solid_a) begin
                dbg_pxw <= dbg_pxw + 1'd1;
                zbuf[lbi_a]         <= zcode;
                // Solid objects from the actual builder have pri=w6&E0.
                // Shadow/szbuf keep their full 8-bit priority, including shdpri.
                solid[bank][lbi_a]  <= {1'b1, palette_a, opri[7:5], effect};
                shade[bank][lbi_a]  <= 11'd0;  // a later solid clears the shadow
            end else if (px_valid_a && shade_a) begin
                szbuf[lbi_a]        <= {zcode, opri};
                shade[bank][lbi_a]  <= {1'b1, shtab, opri};
                if (ovl_a) shadow_overlap <= 1'b1;
            end else if (st == D_CLR) begin
                solid[bank][clr_i] <= '0;
                shade[bank][clr_i] <= '0;
                zbuf[clr_i]  <= 8'hff;
                szbuf[clr_i] <= 16'hffff;
            end
        end
    end
endmodule
