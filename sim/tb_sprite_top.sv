// Frozen-state bench wrapper: object list + rasterizer, with the sprite ROM,
// sprite RAM and the two reciprocal ROMs.
`default_nettype none

module tb_sprite_top (
    input  logic        clk,
    input  logic        reset,

    input  logic        ram_we,
    input  logic [10:0] ram_waddr,
    input  logic [15:0] ram_wdata,
    input  logic        rom_we,
    input  logic [19:0] rom_waddr,
    input  logic [63:0] rom_wdata,
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
    always_ff @(posedge clk) if (cfg_we) begin
        opset <= opset_i; objset1 <= objset1_i; shadowon <= shadowon_i;
        shdpri[0] <= shdpri0_i; shdpri[1] <= shdpri1_i; shdpri[2] <= shdpri2_i;
        k46r5 <= k46r5_i; k46offx <= k46offx_i; k46offy <= k46offy_i;
        colorbase <= colorbase_i;
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

    logic [63:0] srom [1048576];
    logic        rom_req, rom_ack;
    logic [19:0] rom_addr;
    logic [63:0] rom_q;
    always_ff @(posedge clk) begin
        if (rom_we) srom[rom_waddr] <= rom_wdata;
        rom_q   <= srom[rom_addr];
        rom_ack <= rom_req & ~rom_ack;
    end

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

    logic  [9:0] list_idx;
    logic [31:0] list_q;

    logic  [9:0] ol_zoom_addr, dr_zoom_addr;
    logic  [7:0] yr_addr; logic [21:0] yr_q;
    assign zoom_addr = ol_busy ? ol_zoom_addr : dr_zoom_addr;
    k053247_objlist u_ol (
        .mystic(1'b0),
        .stream_enable(1'b0),.shdprisel(6'h3f),
        .clk(clk), .reset(reset), .start(build), .done(build_done), .busy(ol_busy),
        .opset(opset), .objset1(objset1), .shadowon(shadowon), .shdpri(shdpri), .k46_offy(k46offy),
        .zoom_addr(ol_zoom_addr), .zoom_q(zoom_q), .yr_addr(yr_addr), .yr_q(yr_q),
        .ram_addr(ol_ram_addr), .ram_q(ram_q),
        .list_idx(list_idx), .list_q(list_q), .count(count), .overflow(overflow)
    );

    k053247_draw u_dr (
        .mystic(1'b0), .rom_fifth(16'b0), .out_effect(),
        .stream_enable(1'b0),.order_valid(),.order_priority(),.order_deferred(),.order_ready(1'b1),
        .fragment_valid(),.fragment_ready(1'b1),.fragment_x(),.fragment_pen(),.fragment_level(),
        .fragment_shadow(),.fragment_table(),.fragment_condition(),.fragment_z(),.fragment_pri(),
        .alpha1(10'd255), .alpha2(10'd255), .alpha3(10'd255),
        .clk(clk), .reset(reset),
        .line_start(line_start), .line(line), .busy(busy),
        .k46r5(k46r5), .k46_offx(k46offx), .k46_offy(k46offy),
        .opset(opset), .colorbase(colorbase),
        .list_idx(list_idx), .list_q(list_q), .list_count(count),
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
