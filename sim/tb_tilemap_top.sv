// Frozen-state bench wrapper for k056832_tilemap.
//
// Holds the chip registers, tile RAM and tile ROM so the C++ driver can load a
// dumped MAME state through simple write ports, then render a frame and read
// the four layers back a pixel at a time.
`default_nettype none

module tb_tilemap_top (
    input  logic        clk,
    input  logic        reset,

    // load ports
    input  logic        reg_we,
    input  logic  [5:0] reg_addr,
    input  logic [15:0] reg_data,
    input  logic        cb_we,
    input  logic  [1:0] cb_addr,
    input  logic  [7:0] cb_data,
    input  logic        vram_we,
    input  logic [15:0] vram_waddr,
    input  logic [15:0] vram_wdata,
    input  logic        rom_we,
    input  logic [18:0] rom_waddr,
    input  logic [31:0] rom_wdata,

    // control
    input  logic        line_start,
    input  logic  [8:0] line,
    output logic        busy,

    // scan-out
    input  logic  [8:0] px,
    output logic [11:0] pix0, pix1, pix2, pix3,
    output logic  [3:0] opaque,
    output logic        unsupported
);
    logic [15:0] regs      [32];
    logic  [7:0] colorbase [4];
    always_ff @(posedge clk) begin
        if (reg_we) regs[reg_addr[4:0]] <= reg_data;
        if (cb_we)  colorbase[cb_addr]  <= cb_data;
    end

    // tile RAM: 16 pages x 4096 words, and the tile ROM: 2 MB as 512K x 32.
    // Both answer LAT_* clocks after the request (+LAT_VRAM=n +LAT_ROM=n on
    // the command line, 0 = the cycle after: the ideal), the Pocket's memory
    // ports' behaviour, so the line budget can be measured with real latencies.
    int lat_vram, lat_rom, cnt_vram, cnt_rom;
    initial begin
        if (!$value$plusargs("LAT_VRAM=%d", lat_vram)) lat_vram = 0;
        if (!$value$plusargs("LAT_ROM=%d",  lat_rom))  lat_rom  = 0;
    end
    logic [15:0] vram [65536];
    logic        vram_req, vram_ack;
    logic [15:0] vram_addr, vram_q;
    logic [31:0] rom [524288];
    logic        rom_req, rom_ack;
    logic [18:0] rom_addr;
    logic [31:0] rom_q;
    `define ROM_PORT(req, ack, cnt, lat) \
        if (!req) begin cnt <= 0; ack <= 1'b0; end \
        else if (ack) begin ack <= 1'b0; cnt <= 0; end \
        else if (cnt >= lat) begin ack <= 1'b1; cnt <= 0; end \
        else begin cnt <= cnt + 1; ack <= 1'b0; end
    always_ff @(posedge clk) begin
        if (vram_we) vram[vram_waddr] <= vram_wdata;
        if (rom_we)  rom[rom_waddr]   <= rom_wdata;
        vram_q <= vram[vram_addr];   `ROM_PORT(vram_req, vram_ack, cnt_vram, lat_vram)
        rom_q  <= rom[rom_addr];     `ROM_PORT(rom_req,  rom_ack,  cnt_rom,  lat_rom)
    end

    logic [11:0] pix [4];
    assign pix0 = pix[0];
    assign pix1 = pix[1];
    assign pix2 = pix[2];
    assign pix3 = pix[3];

    k056832_tilemap u_tm (
        .mystic(1'b0), .rom_fifth(8'd0), .category(), .line_nonempty(),
        .clk(clk), .reset(reset),
        .line_start(line_start), .line(line), .busy(busy),
        .regs(regs), .colorbase(colorbase),
        .vram_req(vram_req), .vram_addr(vram_addr), .vram_ack(vram_ack), .vram_q(vram_q),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ack(rom_ack), .rom_q(rom_q),
        .px(px), .pix(pix), .opaque(opaque),
        .unsupported(unsupported)
    );
endmodule
