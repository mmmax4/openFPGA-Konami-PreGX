//------------------------------------------------------------------------------
// K053936-class PSAC2 rotate/zoom plane for Gaiapolis.
//
// A 512x512 grid of 16x16 4bpp tiles -- an 8192x8192 virtual plane -- sampled
// through an affine transform. The tile map lives in ROM (gfx4) rather than
// RAM, three bytes per tile; the characters are in gfx3. See docs/hardware.md
// section 5, and tools/render_model.py for the reference semantics.
//
// Only "simple" mode is implemented (ctrl[7] bit 6 clear), which is all the
// frozen-state corpus uses; "super" (per-line) mode raises `unsupported`.
//
// Memory strategy. A raster line walks a straight path across the plane; at
// this game's transforms (zoom 0.5-2.7, any angle: the character-select water
// rotates) it crosses 25-90 tiles, and the next line, one source pixel over,
// crosses nearly the same ones. So the unit of fetch is a whole tile -- its
// 64 words in one burst from the platform's memory, stored column-major at
// load time -- into a 128-entry fully associative cache with round-robin
// replacement. Hits need no map read either: the entry keeps the tile's
// colour bits. What remains bursty is the line on which the walk moves to a
// new tile row and every tile changes at once (9,000+ clocks at zoom 1.9);
// the renderer therefore keeps 8 line buffers and runs up to 7 lines ahead
// of the display, so such a line borrows from its cheap neighbours (the
// average is 1,400-3,200 clocks a line). tools/roz_fetches.py models the
// walk; the frame bench measures the lead actually used.
//
// Deliberate divergence from MAME: K053936GP_copyroz32clip advances its
// destination row before the loop body, so MAME paints raster row N with the
// transform for row N-1 and never writes the first visible row. That reads as
// a porting artefact rather than silicon behaviour, so this module does not
// copy it; sim/run_roz.sh compares against the model with the resulting
// one-line offset applied. docs/hardware.md section 10.
//------------------------------------------------------------------------------
`default_nettype none

module k053936_roz #(
    parameter int VIS_W  = 376,
    parameter int VIS_H  = 224,
    parameter int VIS_X0 = 40,
    parameter int VIS_Y0 = 16,
    parameter int LB_AW  = 9,
    // K053936GP_set_offset(0, -10, 0) for gaiapolis
    parameter int OFFS_X = -10,
    parameter int OFFS_Y = 0,
    parameter int NENT   = 128,         // production capacity:128, fixed32-set layout
    parameter bit EXTERNAL_RAM = 1'b0   // shared physical ROZ/road allocation
) (
    input  logic        clk,
    input  logic        reset,

    // Pacing from gaia_video. prestart pulses a few raster lines before the
    // visible area and begins the frame's rendering; line_start pulses at the
    // start of raster line r with line = r+1, the line the display shows
    // next. busy: that line is not rendered yet (sampled at the next pulse
    // for the overrun count). The renderer runs ahead of the display by up
    // to NBANK-1 lines and never writes the buffer being displayed; if it is
    // ever behind at a pulse, the line in progress is abandoned, as before.
    input  logic        prestart,
    input  logic        line_start,
    input  logic  [8:0] line,
    output logic        busy,
    output logic  [3:0] lead,           // lines rendered beyond the one due, saturating (benches)

    input  logic [15:0] ctrl [16],      // 0x460000 control block (only 0-7 used)
    input  logic [15:0] clip [2],       // 0x484000 clip window
    input  logic        roz_enable,     // 0x6c0000 bit 8
    // K055555 SUB1 palette base. Only the low nibble reaches the colour --
    // the model shifts the register left 4 into an 8-bit field.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic  [7:0] palbase,
    /* verilator lint_on UNUSEDSIGNAL */

    // tile map ROM (gfx4). Byte address; map_q is the containing 16-bit word.
    output logic        map_req,
    output logic [19:0] map_addr,
    input  logic        map_ack,
    input  logic [15:0] map_q,

    // character ROM (gfx3): a level request for tile blk_addr, its 64 words
    // streamed back with blk_wr/blk_idx/blk_data (idx = {word column, row},
    // the load-time layout), then blk_ack for a request still standing with
    // the same address
    output logic        blk_req,
    output logic [15:0] blk_addr,
    input  logic        blk_wr,
    input  logic  [5:0] blk_idx,
    input  logic [15:0] blk_data,
    input  logic        blk_ack,

    input  logic [LB_AW-1:0] px,
    output logic [11:0] pix,
    output logic        opaque,

    output logic        unsupported,

    output wire cache_we, output wire [12:0] cache_wa, cache_ra,
    output wire [15:0] cache_wdata, input wire [15:0] cache_q,
    output wire line_we, output wire [11:0] line_wa, line_ra,
    output wire [11:0] line_wdata, input wire [11:0] line_q
);
    // ------------------------------------------------------------- transform
    function automatic logic signed [31:0] sx16(input logic [15:0] v);
        return {{16{v[15]}}, v};
    endfunction

    // Keep these stage registers outside DSP input cells: the fitted
    // FF-to-DSP clock skew otherwise violates fast-corner hold. This local
    // implementation hint leaves the registered equations/cycles unchanged.
    (* altera_attribute = "-name QII_AUTO_PACKED_REGISTERS OFF" *)
    logic signed [31:0] incxx, incxy, incyx, incyy;
    logic        [31:0] startx, starty;      // 16.16, wraps as uint32 like MAME

    // --------------------------------------------------------- line buffers
    // 8 banks of 384 (a bank's base is bank*384: two shifted adds); a pixel
    // is {colour, pen}, and pen 0 is transparent, so no opaque bit is kept
    localparam int NBANK = 8, LB_STRIDE = 384;
    function automatic logic [11:0] bank_base(input logic [2:0] b);
        return {1'b0, b, 8'd0} + {2'b0, b, 7'd0};
    endfunction
    logic [11:0] rd, rd_base, wa;
    assign pix    = rd;
    assign opaque = |rd[3:0];

    // ------------------------------------------------------- frame pacing
    logic signed [9:0] disp;            // the line the display shows now (-1 before the first)
    logic        [8:0] need, rline;     // the line due at the next pulse; the next line to render
    logic              need_v;
    wire signed  [9:0] disp_new = $signed({1'b0, line}) - $signed(10'(VIS_Y0 + 1));
    // Equivalent over all 9-bit line/rline values. Keep the constant add on
    // local rline: line no longer traverses a subtract and compare before
    // the RAM write-enable. Ten bits retain the carry at the upper boundary.
    wire               behind   = line_start && ({1'b0, line} >= ({1'b0, rline} + 10'(VIS_Y0 + 1)));
    wire               abandon  = prestart || behind;
    assign busy = need_v && (need < 9'(VIS_H)) && (rline <= need);
    wire [9:0] lead_w = {1'b0, rline} - {1'b0, need};
    assign lead = lead_w[9] ? 4'd0 : (lead_w > 10'd15) ? 4'd15 : lead_w[3:0];

    // ------------------------------------------------------------- clipping
    wire        clip_en = clip[1][8];
    wire [ 5:0] clip_x  = clip[0][5:0];
    wire [ 5:0] clip_y  = clip[0][11:6];
    wire [ 1:0] csx     = clip[0][13:12];
    wire [ 1:0] csy     = clip[0][15:14];
    function automatic logic [2:0] clipsize(input logic [1:0] v);
        case (v) 2'd3: return 3'd1; 2'd2: return 3'd2; default: return 3'd4; endcase
    endfunction
    wire [12:0] minx = {clip_x, 7'd0};
    wire  [5:0] clip_ex = clip_x + {3'd0, clipsize(csx)};
    wire [12:0] maxx = {clip_ex, 7'd0} - 13'd1;
    wire [12:0] miny = {clip_y, 7'd0};
    wire  [5:0] clip_ey = clip_y + {3'd0, clipsize(csy)};
    wire [12:0] maxy = {clip_ey, 7'd0} - 13'd1;

    // ------------------------------------------------------------ tile cache
    // 128 tiles, four ways in32sets. Hash both tile coordinates; GF(32)
    // multiplier7 was selected from original-state miss traffic before native
    // testing. Two 64x19 true-dual-port valid+tag+colour RAMs replace the register
    // CAM and old attribute RAM. Capacity and three-clock hits are retained;
    // tree-PLRU replacement changes miss traffic.
    logic [31:0] cx, cy;
    logic [12:0] srcx, srcy;
    wire  [17:0] ti_now = {cy[28:20], cx[28:20]};     // {row, column} of the tile on the plane

    logic [2:0] replace_tree[32];
    logic [6:0] fill_ent, victim_pending;
    logic [15:0]     tmem_rd;
    wire   [4:0]    attr_rd;
    logic  [7:0]     d1, d2, d3;
    logic [17:0]     ti;

    function automatic logic [4:0] gf32_x(input logic [4:0] row);
        return {row[3:0],1'b0} ^ (row[4] ? 5'h05 : 5'h00);
    endfunction
    function automatic logic [4:0] cache_set(input logic [17:0] tile);
        // In GF(32), 7*r = r XOR x*r XOR x*x*r; x^5+x^2+1.
        return tile[4:0] ^ tile[13:9] ^ gf32_x(tile[13:9]) ^ gf32_x(gf32_x(tile[13:9]));
    endfunction
    function automatic logic [2:0] touch_way(input logic [2:0] tree,input logic [1:0] way);
        logic [2:0] result;
        result=tree;
        result[2]=!way[1];
        if(way[1]) result[1]=!way[0];
        else result[0]=!way[0];
        return result;
    endfunction
    // PCB palette packing: even tile low nibble, odd tile high nibble.
    // plasticbugs932df6b0 / decoryah ebcb5932; keep the local timing repair.
    wire [3:0] nib_now = ti[0] ? d1[7:4] : d1[3:0];

    typedef enum logic [3:0] {
        R_IDLE, R_SETUP, R_SETUP2, R_PIX, R_LOOK, R_CHK,
        R_M1W, R_M2, R_M2W, R_M3, R_M3W, R_FILL, R_FILLW
    } state_t;
    state_t st;

    wire [18:0] tag_q[4];
    logic [4:0] lookup_set;
    logic [12:0] lookup_tag;
    // Clear both metadata banks in parallel after reset. Pending prestart is
    // retained by rline; R_IDLE waits only64clocks before rendering can start.
    // This fits within the real video consumer's prestart/first-line interval.
    logic [6:0] tag_clear_at;
    wire tag_ready=tag_clear_at[6];
    wire tag_clearing=reset || !tag_ready;
    always_ff @(posedge clk) begin
        if(reset) tag_clear_at<=7'd0;
        else if(!tag_ready) tag_clear_at<=tag_clear_at+7'd1;
    end
    wire tag_write_slot = st == R_FILLW && blk_ack;
    wire tag_invalidate_slot = st == R_FILL;
    wire [6:0] tag_write_ent=tag_invalidate_slot ? victim_pending : fill_ent;
    genvar tb;
    generate
    for(tb=0;tb<2;tb=tb+1) begin: tag_banks
        // Cancellation gates the write strobe, not the address/data of a
        // disabled write. No tag read is consumed while abandoning a line;
        // the next R_PIX/R_LOOK launches fresh addresses before comparison.
        wire write_bank=(tag_write_slot || tag_invalidate_slot) && tag_write_ent[6]==1'(tb);
        wire [5:0] tag_a=tag_clearing ? (reset ? 6'd0 : tag_clear_at[5:0]) :
                         write_bank ? tag_write_ent[5:0] : {1'b0,cache_set(ti_now)};
        wire [5:0] tag_b={1'b1,cache_set(ti_now)};
        wire [18:0] write_data=!tag_clearing && tag_write_slot ? {1'b1,d2[7],nib_now,ti[17:5]} : 19'd0;
        // Use the supported physical macro directly. Both read addresses
        // are captured on clock0; unregistered macro outputs give exactly
        // one read clock, matching the renderer pipeline. Collision outputs
        // are unconsumed during clear/invalidate/fill, until fresh reads.
        pregx_roz_tag_ram tag_mem(.clk(clk),.we(tag_clearing || (!reset && !abandon && write_bank)),
            .addr_a(tag_a),.addr_b(tag_b),.data(write_data),
            .q_a(tag_q[2*tb]),.q_b(tag_q[2*tb+1]));
    end
    endgenerate
    always_ff @(posedge clk) begin
        lookup_set<=cache_set(ti_now);
        lookup_tag<=ti_now[17:5];
    end
    wire [3:0] tag_hit;
    genvar tw;
    generate
    for(tw=0;tw<4;tw=tw+1) begin: tag_compare
        assign tag_hit[tw]=tag_ready && tag_q[tw][18] && tag_q[tw][12:0]==lookup_tag;
    end
    endgenerate
    wire [1:0] hit_way=tag_hit[0] ? 2'd0 : tag_hit[1] ? 2'd1 : tag_hit[2] ? 2'd2 : 2'd3;
    wire [6:0] ent_now={hit_way,lookup_set};
    assign attr_rd=tag_q[hit_way][17:13];
    wire [4:0] fill_set=cache_set(ti);
    wire [2:0] victim_tree=replace_tree[fill_set];
    wire [1:0] victim_way=!tag_q[0][18] ? 2'd0 :
                          !tag_q[1][18] ? 2'd1 :
                          !tag_q[2][18] ? 2'd2 :
                          !tag_q[3][18] ? 2'd3 :
                          {victim_tree[2],victim_tree[2] ? victim_tree[1] : victim_tree[0]};

    assign cache_we=blk_wr;
    assign cache_wa={fill_ent,blk_idx};
    assign cache_wdata=blk_data;
    assign cache_ra={ent_now,srcx[3:2],srcy[3:0]};
    // Keep the bank-selection mux separate from nibble/opacity and the shared
    // line-RAM input mux. Commit a completed pixel one clock later while the
    // unchanged three-clock renderer starts the next pixel. Capture every
    // associated control/address at the old commit edge, including MMIO data.
    logic line_pending, line_visible;
    logic [15:0] line_word;
    logic [1:0] line_select;
    logic [7:0] line_colour;
    logic [11:0] line_address;
    always_ff @(posedge clk) begin
        line_pending<=!reset && !abandon && st==R_CHK && !(roz_enable && !hit);
        line_word<=tmem_rd;
        line_select<=pix_sel;
        line_colour<=colour;
        line_visible<=roz_enable && !clipped;
        line_address<=wa;
    end
    assign line_we=!reset && !abandon && line_pending;
    assign line_wa=line_address;
    assign line_ra=rd_base+12'(px);
    assign line_wdata=(line_visible && |pen) ? {line_colour,pen} : 12'd0;
    generate
    if(EXTERNAL_RAM) begin: shared_storage
        assign tmem_rd=cache_q;
        assign rd=line_q;
    end else begin: local_storage
        logic [15:0] tmem[NENT*64];
        logic [11:0] lbuf[NBANK*LB_STRIDE];
        always_ff @(posedge clk) begin
            if(cache_we) tmem[cache_wa]<=cache_wdata;
            tmem_rd<=tmem[cache_ra];
            if(line_we) lbuf[line_wa]<=line_wdata;
            rd<=lbuf[line_ra];
        end
    end
    endgenerate
    // ------------------------------------------------------------------ FSM
    logic [LB_AW-1:0] cur_x;
    logic        hit, clipped;
    logic  [1:0] pix_sel;
    logic [31:0] pyx, pyy;

    wire [3:0] pen = (line_select == 2'd0) ? line_word[15:12] : (line_select == 2'd1) ? line_word[11:8]
                   : (line_select == 2'd2) ? line_word[7:4]   : line_word[3:0];
    // palbase occupies bits 7:4 and the attribute's bit 7 adds bit 4; they
    // never collide for this game's base
    wire [7:0] colour = {palbase[3:0], 4'd0} | {3'd0, attr_rd[4], 4'd0} | {4'd0, attr_rd[3:0]};

    always_ff @(posedge clk) begin
        if (reset) begin
            st <= R_IDLE; map_req <= 1'b0; blk_req <= 1'b0; unsupported <= 1'b0;
            for(int rs=0;rs<32;rs++) replace_tree[rs]<='0;
            rline <= 9'(VIS_H); need <= '0; need_v <= 1'b0; disp <= -10'sd1; rd_base <= '0;
        end else begin
            if (prestart) begin
                rline <= '0; disp <= -10'sd1; need_v <= 1'b0;
            end else if (line_start) begin
                need <= line - 9'(VIS_Y0); need_v <= 1'b1;
                disp <= disp_new; rd_base <= bank_base(disp_new[2:0]);
                if (behind) rline <= line - 9'(VIS_Y0);
            end

            if (abandon) begin
                st <= R_IDLE; map_req <= 1'b0; blk_req <= 1'b0;
            end else case (st)
                R_IDLE: begin
                    if (tag_ready && rline < 9'(VIS_H) && $signed({1'b0, rline}) <= disp + 10'(NBANK - 1)) begin
                        st <= R_SETUP;
                        if (ctrl[7][6]) unsupported <= 1'b1;    // "super" mode
                    end
                end

                R_SETUP: begin
                    cur_x <= '0;
                    wa    <= bank_base(rline[2:0]);
                    // startx/starty already fold in the visible-area origin, so
                    // the per-line advance counts visible lines, not raster ones;
                    // the multiply and the add are two cycles (one path was -6.6 ns)
                    pyx <= $unsigned(incyx) * {23'd0, rline};
                    pyy <= $unsigned(incyy) * {23'd0, rline};
                    st <= R_SETUP2;
                end
                R_SETUP2: begin
                    cx <= startx + pyx;
                    cy <= starty + pyy;
                    st <= R_PIX;
                end

                // three clocks a pixel on a hit: the source position, then the
                // tag compare (registered above from cx/cy), then the data
                R_PIX: begin
                    srcx <= cx[28:16];
                    srcy <= cy[28:16];
                    ti   <= ti_now;
                    st   <= R_LOOK;
                end
                R_LOOK: begin
                    hit     <= |tag_hit;
                    if (|tag_hit) replace_tree[lookup_set] <= touch_way(replace_tree[lookup_set],hit_way);
                    clipped <= clip_en & ((srcx < minx) | (srcx > maxx)
                                        | (srcy < miny) | (srcy > maxy));
                    pix_sel <= srcx[1:0];
                    st <= R_CHK;
                end
                R_CHK: begin
                    if (roz_enable && !hit) begin
                        // colour nibbles are packed two tiles per byte
                        map_addr <= {3'd0, ti[17:1]};
                        map_req  <= 1'b1;
                        st <= R_M1W;
                    end else begin
                        wa <= wa + 12'd1;
                        cx <= cx + $unsigned(incxx);
                        cy <= cy + $unsigned(incxy);
                        if (cur_x == VIS_W[LB_AW-1:0] - 1) begin
                            st <= R_IDLE; rline <= rline + 9'd1;
                        end else begin
                            cur_x <= cur_x + 1'd1;
                            st <= R_PIX;
                        end
                    end
                end

                // a miss: the tile's three map bytes, then its 64 words into
                // the round-robin victim
                R_M1W: if (map_ack) begin
                    d1 <= map_addr[0] ? map_q[7:0] : map_q[15:8];
                    map_req <= 1'b0;
                    st <= R_M2;
                end
                R_M2: begin
                    map_addr <= 20'h20000 + {2'd0, ti};
                    map_req  <= 1'b1;
                    st <= R_M2W;
                end
                R_M2W: if (map_ack) begin
                    d2 <= map_addr[0] ? map_q[7:0] : map_q[15:8];
                    map_req <= 1'b0;
                    st <= R_M3;
                end
                R_M3: begin
                    map_addr <= 20'h60000 + {2'd0, ti};
                    map_req  <= 1'b1;
                    st <= R_M3W;
                end
                R_M3W: if (map_ack) begin
                    d3 <= map_addr[0] ? map_q[7:0] : map_q[15:8];
                    map_req <= 1'b0;
                    // ti, tag-valid outputs and replacement state have been
                    // stable throughout the three map reads. Register the
                    // victim before the high-fanout metadata write decoder.
                    // Keep fill_ent's original R_FILL update: late words from
                    // an abandoned block must not target the next victim early.
                    victim_pending <= {victim_way,fill_set};
                    st <= R_FILL;
                end
                R_FILL: begin
                    fill_ent <= victim_pending;
                    blk_addr <= {2'd0, d2[5:0], d3};
                    blk_req  <= 1'b1;
                    st <= R_FILLW;
                end
                R_FILLW: if (blk_ack) begin
                    blk_req <= 1'b0;
                    replace_tree[fill_ent[4:0]] <= touch_way(replace_tree[fill_ent[4:0]],fill_ent[6:5]);
                    st <= R_PIX;                       // now a hit
                end
                default: st <= R_IDLE;
            endcase
        end
    end

    // control-register decode, registered in three short stages every cycle
    // so a mid-frame write still takes effect on the next line rendered (up
    // to NBANK-1 lines before it shows), without the shifts, constant
    // multiplies and adds forming one long path
    logic signed [31:0] ixx, ixy, iyx, iyy, sx0, sy0, sx, sy;
    logic        [31:0] pxx, pxy;
    always_ff @(posedge clk) begin
        // stage 1: sign extension and the x256 modes
        ixx <= ctrl[6][6]  ? (sx16(ctrl[4]) <<< 8) : sx16(ctrl[4]);
        ixy <= ctrl[6][6]  ? (sx16(ctrl[5]) <<< 8) : sx16(ctrl[5]);
        iyx <= ctrl[6][14] ? (sx16(ctrl[2]) <<< 8) : sx16(ctrl[2]);
        iyy <= ctrl[6][14] ? (sx16(ctrl[3]) <<< 8) : sx16(ctrl[3]);
        sx0 <= sx16(ctrl[0]) <<< 8;
        sy0 <= sx16(ctrl[1]) <<< 8;
        // stage 2: the layer offsets and the 16.16 increments
        sx <= sx0 - OFFS_Y * iyx - OFFS_X * ixx;
        sy <= sy0 - OFFS_Y * iyy - OFFS_X * ixy;
        incxx <= ixx <<< 5; incxy <= ixy <<< 5;
        incyx <= iyx <<< 5; incyy <= iyy <<< 5;
        pxx <= $unsigned(ixx <<< 5) * VIS_X0; pxy <= $unsigned(ixy <<< 5) * VIS_X0;
        // stage 3: the visible-area origin folded in
        startx <= $unsigned(sx <<< 5) + pxx + $unsigned(incyx) * VIS_Y0;
        starty <= $unsigned(sy <<< 5) + pxy + $unsigned(incyy) * VIS_Y0;
    end

    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{d2[6], ctrl[8], ctrl[9], ctrl[10], ctrl[11], ctrl[12], ctrl[13], ctrl[14], ctrl[15],
                    clip[1][15:9], clip[1][7:0], cx[31:29], cx[15:0], cy[31:29], cy[15:0]};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule

// Intel M10K true-dual-port metadata storage. Quartus supplies the synthesis
// primitive; functional tests compile the pinned installed altera_mf model.
module pregx_roz_tag_ram (
    input wire clk,we,input wire[5:0]addr_a,addr_b,input wire[18:0]data,
    output wire[18:0]q_a,q_b
);
    altsyncram #(
        .operation_mode("BIDIR_DUAL_PORT"),.intended_device_family("Cyclone V"),
        .ram_block_type("M10K"),.lpm_type("altsyncram"),
        .width_a(19),.widthad_a(6),.numwords_a(64),.width_byteena_a(1),
        .width_b(19),.widthad_b(6),.numwords_b(64),.width_byteena_b(1),
        .address_reg_b("CLOCK0"),.rdcontrol_reg_b("CLOCK0"),
        .indata_reg_b("CLOCK0"),.wrcontrol_wraddress_reg_b("CLOCK0"),.byteena_reg_b("CLOCK0"),
        .outdata_reg_a("UNREGISTERED"),.outdata_reg_b("UNREGISTERED"),
        .clock_enable_input_a("BYPASS"),.clock_enable_input_b("BYPASS"),
        .clock_enable_output_a("BYPASS"),.clock_enable_output_b("BYPASS"),
        .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized("TRUE")
    ) ram(.clock0(clk),.clock1(),.clocken0(1'b1),.clocken1(1'b1),
        .clocken2(1'b1),.clocken3(1'b1),.aclr0(1'b0),.aclr1(1'b0),
        .address_a(addr_a),.address_b(addr_b),.addressstall_a(1'b0),.addressstall_b(1'b0),
        .wren_a(we),.wren_b(1'b0),.rden_a(1'b1),.rden_b(1'b1),
        .data_a(data),.data_b(19'd0),.byteena_a(1'b1),.byteena_b(1'b1),
        .q_a(q_a),.q_b(q_b),.eccstatus());
endmodule
