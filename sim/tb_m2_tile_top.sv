// Actual tile linebuffer/scanout behind the independently tested memory wrapper.
// Test setup uses public download + byte-enabled VRAM ports, never DUT hierarchy.
`default_nettype none
module tb_m2_tile_top (
    input logic clk, init, reset, mystic,
    output logic ready,
    input logic dl_we,
    input logic [24:0] dl_addr,
    input logic [7:0] dl_data,
    input logic reg_we, cb_we,
    input logic [4:0] reg_addr,
    input logic [15:0] reg_data,
    input logic [1:0] cb_addr,
    input logic [7:0] cb_data,
    input logic setup_mode, setup_req,
    input logic [15:0] setup_addr, setup_wdata,
    output logic setup_ack,
    input logic line_start,
    input logic [8:0] line, px,
    output logic busy, unsupported,
    output logic [14:0] packed0, packed1, packed2, packed3,
    output logic pending_vram, pending_rom, observed_vram_ack, observed_rom_ack,
    output logic [15:0] observed_vram_addr,
    output logic [18:0] observed_rom_addr,
    output logic [31:0] protocol_errors
);
    logic [15:0] regs [32];
    logic [7:0] colorbase [4];
    always_ff @(posedge clk) begin
        if (reg_we) regs[reg_addr] <= reg_data;
        if (cb_we) colorbase[cb_addr] <= cb_data;
    end
    logic vreq, vack, rreq, rack;
    logic [15:0] va, vq;
    logic [18:0] ra;
    logic [31:0] rq;
    logic [7:0] fifth;
    logic [11:0] pix [4];
    logic [1:0] category [4];
    logic [3:0] opaque;
    assign packed0 = {category[0],opaque[0],pix[0]};
    assign packed1 = {category[1],opaque[1],pix[1]};
    assign packed2 = {category[2],opaque[2],pix[2]};
    assign packed3 = {category[3],opaque[3],pix[3]};
    assign pending_vram = vreq;
    assign pending_rom = rreq;
    assign observed_vram_ack = !setup_mode && vack;
    assign observed_rom_ack = rack;
    assign observed_vram_addr = va;
    assign observed_rom_addr = ra;
    assign setup_ack = setup_mode && vack;
`ifdef M2_TILE_LEGACY
    assign category[0] = 2'd0;
    assign category[1] = 2'd0;
    assign category[2] = 2'd0;
    assign category[3] = 2'd0;
`endif
    k056832_tilemap tile (
`ifndef M2_TILE_LEGACY
        .mystic(mystic), .rom_fifth(fifth), .category(category), .line_nonempty(),
`endif
        .clk(clk), .reset(reset), .line_start(line_start), .line(line),
        .busy(busy), .regs(regs), .colorbase(colorbase),
        .vram_req(vreq), .vram_addr(va), .vram_ack(!setup_mode && vack), .vram_q(vq),
        .rom_req(rreq), .rom_addr(ra), .rom_ack(rack), .rom_q(rq),
        .px(px), .pix(pix), .opaque(opaque), .unsupported(unsupported)
    );
    tb_m2_mem_top memory (
        .clk(clk), .init(init), .mystic(mystic), .ready(ready), .rd_late(1'b1), .burst_slow(1'b0),
        .ps_slow(1'b0), .sram_slow(1'b0), .sram_slow_wr(1'b0),
        .tile_fifth(fifth), .spr_fifth(), .test_mask(), .sd_read_pulse(), .sd_read_word(), .sd_protocol_errors(protocol_errors),
        .test_start(1'b0), .test_run(), .test_done(), .test_ok(), .test_stable(), .vram_ok(), .vram_bad(),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data), .eep_we(), .eep_addr(), .eep_data(),
        .prog_req(1'b0), .prog_addr(22'd0), .prog_ack(), .prog_q(),
        .tile_req(rreq), .tile_addr(ra), .tile_ack(rack), .tile_q(rq),
        .map_req(1'b0), .map_addr(20'd0), .map_ack(), .map_q(),
        .blk_req(1'b0), .blk_addr(16'd0), .blk_wr(), .blk_idx(), .blk_data(), .blk_ack(),
        .spr_req(1'b0), .spr_addr(20'd0), .spr_ack(), .spr_q(),
        .snd_req(1'b0), .snd_addr(18'd0), .snd_ack(), .snd_q(),
        .pcm_req(1'b0), .pcm_addr(22'd0), .pcm_ack(), .pcm_q(),
        .vram_req(setup_mode ? setup_req : vreq), .vram_we(setup_mode),
        .vram_addr(setup_mode ? setup_addr : va), .vram_be(2'b11), .vram_wdata(setup_wdata), .vram_ack(vack), .vram_q(vq)
    );
endmodule
