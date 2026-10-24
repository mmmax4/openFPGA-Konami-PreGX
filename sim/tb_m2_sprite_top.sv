// Independent M2 consumer fixture, derived from the preserved upstream wrapper.
// Original/explicit constructed inputs are public setup; no DUT hierarchy force.
// Frozen-state bench wrapper: object list + rasterizer, with the sprite ROM,
// sprite RAM and the two reciprocal ROMs.
`default_nettype none

module tb_m2_sprite_top (
    input  logic        clk,
    input  logic        reset, init, mystic,
    output logic ready,
    input logic dl_we,
    input logic [24:0] dl_addr,
    input logic [7:0] dl_data,
    input logic inspect_list,
    input logic [9:0] inspect_idx,
    output logic [31:0] inspect_q,
    output logic [63:0] packed_pixel,
    output logic observed_rom_req, observed_rom_ack,
    output logic [19:0] observed_rom_addr,
    output logic [31:0] protocol_errors,

    input  logic        ram_we,
    input  logic [10:0] ram_waddr,
    input  logic [15:0] ram_wdata,
    input  logic        tab_we,
    input  logic        tab_sel,        // 0: zoom, 1: recip
    input  logic [10:0] tab_waddr,
    input  logic [23:0] tab_wdata,

    input  logic        cfg_we,
    input  logic [15:0] opset_i,
    input  logic  [7:0] objset1_i,
    input  logic  [2:0] shadowon_i,
    input  logic  [7:0] shdpri0_i, shdpri1_i, shdpri2_i,
    input  logic  [7:0] k46r5_i,
    input  logic [15:0] k46offx_i, k46offy_i,
    input  logic  [7:0] colorbase_i,
    input  logic  [9:0] alpha1_i, alpha2_i, alpha3_i,

    input  logic        build,
    output logic        build_done,
    output logic  [9:0] count,
    output logic        overflow,

    input  logic        line_start,
    input  logic  [8:0] line,
    output logic        busy,
    input  logic  [8:0] px,
    output logic        out_opaque,
    output logic [11:0] out_pen,
    output logic  [7:0] out_pri,
    output logic  [1:0] out_effect,
    output logic        out_shadow,
    output logic  [1:0] out_shtab,
    output logic  [7:0] out_shpri,
    output logic        shadow_overlap,
    output logic [31:0] dbg_objs, dbg_rows, dbg_cols, dbg_pxw
);
    logic [15:0] opset, k46offx, k46offy;
    logic  [7:0] objset1, k46r5, colorbase;
    logic  [2:0] shadowon;
    logic  [7:0] shdpri [3];
    logic  [9:0] alpha1, alpha2, alpha3;
    always_ff @(posedge clk) if (cfg_we) begin
        opset <= opset_i; objset1 <= objset1_i; shadowon <= shadowon_i;
        shdpri[0] <= shdpri0_i; shdpri[1] <= shdpri1_i; shdpri[2] <= shdpri2_i;
        k46r5 <= k46r5_i; k46offx <= k46offx_i; k46offy <= k46offy_i;
        colorbase <= colorbase_i;
        alpha1 <= alpha1_i; alpha2 <= alpha2_i; alpha3 <= alpha3_i;
    end

    // sprite RAM, shared: the object list owns it while building, the
    // rasterizer while drawing
    logic [15:0] ram [2048];
    logic [10:0] ol_ram_addr, dr_ram_addr, ram_addr;
    logic [15:0] ram_q;
    logic        ol_busy;
    assign ram_addr = ol_busy ? ol_ram_addr : dr_ram_addr;
    always_ff @(posedge clk) begin
        if (ram_we) ram[ram_waddr] <= ram_wdata;
        ram_q <= ram[ram_addr];
    end

    logic rom_req, rom_ack;
    logic [19:0] rom_addr;
    logic [63:0] rom_q;
    logic [15:0] rom_fifth;
    assign observed_rom_req = rom_req;
    assign observed_rom_ack = rom_ack;
    assign observed_rom_addr = rom_addr;
    assign packed_pixel = {22'd0,out_shpri,out_shtab,out_shadow,8'd0,out_effect,out_pri,out_opaque,out_pen};
    // Existing independently passed memory fixture, production controllers and
    // chip models. Only original sprite bytes enter through public download.
    tb_m2_mem_top memory (
        .clk(clk), .init(init), .mystic(mystic), .ready(ready), .rd_late(1'b1), .burst_slow(1'b0),
        .ps_slow(1'b0), .sram_slow(1'b0), .sram_slow_wr(1'b0),
        .tile_fifth(), .spr_fifth(rom_fifth), .test_mask(), .sd_read_pulse(), .sd_read_word(), .sd_protocol_errors(protocol_errors),
        .test_start(1'b0), .test_run(), .test_done(), .test_ok(), .test_stable(), .vram_ok(), .vram_bad(),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .eep_we(), .eep_addr(), .eep_data(),
        .prog_req(1'b0), .prog_addr(22'd0), .prog_ack(), .prog_q(),
        .tile_req(1'b0), .tile_addr(19'd0), .tile_ack(), .tile_q(),
        .map_req(1'b0), .map_addr(20'd0), .map_ack(), .map_q(),
        .blk_req(1'b0), .blk_addr(16'd0), .blk_wr(), .blk_idx(), .blk_data(), .blk_ack(),
        .spr_req(rom_req), .spr_addr(rom_addr), .spr_ack(rom_ack), .spr_q(rom_q),
        .snd_req(1'b0), .snd_addr(18'd0), .snd_ack(), .snd_q(),
        .pcm_req(1'b0), .pcm_addr(22'd0), .pcm_ack(), .pcm_q(),
        .vram_req(1'b0), .vram_we(1'b0), .vram_addr(16'd0), .vram_be(2'b11), .vram_wdata(16'd0), .vram_ack(), .vram_q()
    );
    logic [23:0] zoomtab [1024];
    logic [23:0] reciptab [2048];
    logic  [9:0] zoom_addr;
    logic [10:0] recip_addr;
    logic [23:0] zoom_q, recip_q;
    always_ff @(posedge clk) begin
        if (tab_we && !tab_sel) zoomtab[tab_waddr[9:0]] <= tab_wdata;
        if (tab_we &&  tab_sel) reciptab[tab_waddr]     <= tab_wdata;
        zoom_q  <= zoomtab[zoom_addr];
        recip_q <= reciptab[recip_addr];
    end

    logic [9:0] dr_list_idx;
    wire [9:0] list_idx = inspect_list ? inspect_idx : dr_list_idx;
    logic [31:0] list_q;
    assign inspect_q = list_q;

    logic  [9:0] ol_zoom_addr, dr_zoom_addr;
    logic  [7:0] yr_addr; logic [21:0] yr_q;
    assign zoom_addr = ol_busy ? ol_zoom_addr : dr_zoom_addr;
    k053247_objlist u_ol (
        .intro_postportrait(1'b0),
`ifndef M2_SPRITE_LEGACY
        .mystic(mystic),
        .stream_enable(1'b0),.shdprisel(6'h3f),
`endif
        .clk(clk), .reset(reset), .start(build), .done(build_done), .busy(ol_busy),
        .opset(opset), .objset1(objset1), .shadowon(shadowon), .shdpri(shdpri), .k46_offy(k46offy),
        .zoom_addr(ol_zoom_addr), .zoom_q(zoom_q), .yr_addr(yr_addr), .yr_q(yr_q),
        .ram_addr(ol_ram_addr), .ram_q(ram_q),
        .list_idx(list_idx), .list_q(list_q), .count(count), .overflow(overflow)
    );

`ifdef M2_SPRITE_LEGACY
    // Test-only adaptation of absent profile/fifth/effect ports. No old RTL edits.
    assign out_effect = 2'd0;
`endif
    k053247_draw u_dr (
`ifndef M2_SPRITE_LEGACY
        .mystic(mystic), .rom_fifth(rom_fifth), .out_effect(out_effect),
        .stream_enable(1'b0),.order_valid(),.order_priority(),.order_deferred(),.order_ready(1'b1),
        .fragment_valid(),.fragment_ready(1'b1),.fragment_x(),.fragment_pen(),.fragment_level(),
        .fragment_shadow(),.fragment_table(),.fragment_condition(),.fragment_z(),.fragment_pri(),
        .alpha1(alpha1), .alpha2(alpha2), .alpha3(alpha3),
`endif
        .clk(clk), .reset(reset),
        .line_start(line_start), .line(line), .busy(busy),
        .k46r5(k46r5), .k46_offx(k46offx), .k46_offy(k46offy),
        .opset(opset), .colorbase(colorbase),
        .list_idx(dr_list_idx), .list_q(list_q), .list_count(count),
        .ram_addr(dr_ram_addr), .ram_q(ram_q),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ack(rom_ack), .rom_q(rom_q),
        .zoom_addr(dr_zoom_addr), .zoom_q(zoom_q), .yr_addr(yr_addr), .yr_q(yr_q),
        .recip_addr(recip_addr), .recip_q(recip_q),
        .px(px), .out_opaque(out_opaque), .out_pen(out_pen), .out_pri(out_pri),
        .out_shadow(out_shadow), .out_shtab(out_shtab), .out_shpri(out_shpri),
        .shadow_overlap(shadow_overlap),
        .dbg_objs(dbg_objs), .dbg_rows(dbg_rows), .dbg_cols(dbg_cols), .dbg_pxw(dbg_pxw)
    );
endmodule
