// Full-system bench wrapper with the Pocket memory subsystem in the loop:
// gaia_core behind target/pocket/gaia_mem.sv with behavioural SDRAM, PSRAM
// and SRAM chips. Same ports as tb_system_top so sim/tb_system.cpp drives
// it unchanged (MEM=pocket in sim/run_system.sh); the loads go straight
// into the chips in gaia_mem's layout (sim/run_mem.sh covers the loader).
`default_nettype none

module tb_pocket_top #(
    parameter int STEP_COST_BUS = 16,
    parameter int STEP_COST_INT = 8
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,

    // loads
    input  logic        prog_we, input logic [21:0] prog_waddr, input logic [15:0] prog_wdata,
    input  logic        tile_we, input logic [18:0] tile_waddr, input logic [31:0] tile_wdata,
    input  logic        map_we,  input logic [18:0] map_waddr,  input logic [15:0] map_wdata,
    input  logic        chr_we,  input logic [19:0] chr_waddr,  input logic [15:0] chr_wdata,
    input  logic        spr_we,  input logic [19:0] spr_waddr,  input logic [63:0] spr_wdata,
    input  logic        eep_we,  input logic  [6:0] eep_waddr,  input logic  [7:0] eep_wdata,
    input  logic        srom_we, input logic [17:0] srom_waddr, input logic  [7:0] srom_wdata,
    input  logic        pcm_we,  input logic [21:0] pcm_waddr,  input logic  [7:0] pcm_wdata,

    input  logic [15:0] in0_p1,
    input  logic  [7:0] in1,
    input  logic  [7:0] p2,

    output logic        cen_pix,
    output logic [23:0] rgb,
    output logic        hsync, vsync, de, vblank,
    output logic [23:0] dbg_addr,
    output logic [15:0] dbg_data,
    output logic  [1:0] dbg_busstate,
    output logic        dbg_step, dbg_irq5, dbg_overrun, dbg_unsupported, dbg_shadow_overlap,
    output logic  [2:0] dbg_overrun_src,
    output logic [31:0] dbg_draw_objs, dbg_draw_rows, dbg_draw_cols, dbg_draw_pxw,
    output logic        dbg_spr_we,
    output logic          dbg_roz_en,
    output logic [127:0]  dbg_rozctrl,
    output logic  [31:0]  dbg_rozclip,
    output logic [383:0]  dbg_k55,
    output logic  [9:0] dbg_objcount,
    output logic  [8:0] dbg_vcount,
    output logic [15:0] dbg_zpc,
    output logic        dbg_zstep, dbg_zwait, dbg_zwr, dbg_zrd,
    output logic  [7:0] dbg_zwdata,
    output logic [15:0] snd_l, snd_r,
    output logic        snd_valid
);
    // gaia_mem's layout (docs/hardware.md section 11)
    localparam [23:0] SD_TILE = 24'h000000, SD_PCM = 24'h100000, SD_SPR = 24'h300000, SD_ROZ = 24'h700000;
    localparam [21:0] PS_MAP = 22'h0C0000, PS_PROG = 22'h000000, PS_SND = 22'h180000;

    logic        prog_req, prog_ack, tile_req, tile_ack, map_req, map_ack, spr_req, spr_ack;
    logic [22:1] prog_addr; logic [18:0] tile_addr; logic [19:0] map_addr; logic [19:0] spr_addr;
    logic [15:0] prog_q, map_q; logic [31:0] tile_q; logic [63:0] spr_q;
    logic        blk_req, blk_wr, blk_ack; logic [15:0] blk_addr, blk_data; logic [5:0] blk_idx; logic [3:0] roz_lead;
    logic        srom_req, srom_ack, pcmr_req, pcmr_ack;
    logic [17:0] srom_addr; logic [21:0] pcmr_addr;
    logic  [7:0] srom_q, pcmr_q;
    logic        vram_req, vram_we, vram_ack;
    logic [15:0] vram_addr, vram_wdata, vram_q;
    logic  [1:0] vram_be;
    logic        mem_ready;
    logic [7:0]  eep_q; logic eep_dirty;

    wire  [15:0] dram_dq; wire [12:0] dram_a; wire [1:0] dram_ba, dram_dqm;
    wire         dram_clk, dram_cke, dram_ras_n, dram_cas_n, dram_we_n;
    wire  [21:16] cram0_a, cram1_a; wire [15:0] cram0_dq, cram1_dq;
    wire         cram0_clk, cram0_adv_n, cram0_cre, cram0_ce0_n, cram0_ce1_n, cram0_oe_n, cram0_we_n, cram0_ub_n, cram0_lb_n;
    wire         cram1_clk, cram1_adv_n, cram1_cre, cram1_ce0_n, cram1_ce1_n, cram1_oe_n, cram1_we_n, cram1_ub_n, cram1_lb_n;
    wire  [16:0] sram_a; wire [15:0] sram_dq; wire sram_oe_n, sram_we_n, sram_ub_n, sram_lb_n;
    logic        eep_we_unused; logic [6:0] eep_addr_unused; logic [7:0] eep_data_unused;

    gaia_mem u_mem (
        .mystic(1'b0), .test_mask(), .tile_fifth(), .spr_fifth(),
        .clk(clk), .clk_sdram(clk), .init(reset), .ready(mem_ready), .rd_late(1'b1), .burst_slow(1'b0),
        .ps_slow(1'b0), .sram_slow(1'b0), .sram_slow_wr(1'b0),
        .test_start(1'b0), .test_run(), .test_done(), .test_ok(), .test_stable(), .vram_ok(), .vram_bad(),
        .dl_we(1'b0), .dl_addr(25'd0), .dl_data(8'd0),
        .eep_we(eep_we_unused), .eep_addr(eep_addr_unused), .eep_data(eep_data_unused),
        .prog_req(prog_req), .prog_addr(prog_addr), .prog_ack(prog_ack), .prog_q(prog_q),
        .tile_req(tile_req), .tile_addr(tile_addr), .tile_ack(tile_ack), .tile_q(tile_q),
        .map_req(map_req), .map_addr(map_addr), .map_ack(map_ack), .map_q(map_q),
        .blk_req(blk_req), .blk_addr(blk_addr), .blk_wr(blk_wr), .blk_idx(blk_idx), .blk_data(blk_data), .blk_ack(blk_ack), .roz_lead(roz_lead),
        .spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_q(spr_q),
        .snd_req(srom_req), .snd_addr(srom_addr), .snd_ack(srom_ack), .snd_q(srom_q),
        .pcm_req(pcmr_req), .pcm_addr(pcmr_addr), .pcm_ack(pcmr_ack), .pcm_q(pcmr_q),
        .vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr), .vram_be(vram_be), .vram_wdata(vram_wdata),
        .vram_ack(vram_ack), .vram_q(vram_q),
        .dram_dq(dram_dq), .dram_a(dram_a), .dram_ba(dram_ba), .dram_dqm(dram_dqm),
        .dram_clk(dram_clk), .dram_cke(dram_cke), .dram_ras_n(dram_ras_n), .dram_cas_n(dram_cas_n), .dram_we_n(dram_we_n),
        .cram0_a(cram0_a), .cram0_dq(cram0_dq), .cram0_wait(1'b0), .cram0_clk(cram0_clk), .cram0_adv_n(cram0_adv_n),
        .cram0_cre(cram0_cre), .cram0_ce0_n(cram0_ce0_n), .cram0_ce1_n(cram0_ce1_n), .cram0_oe_n(cram0_oe_n),
        .cram0_we_n(cram0_we_n), .cram0_ub_n(cram0_ub_n), .cram0_lb_n(cram0_lb_n),
        .cram1_a(cram1_a), .cram1_dq(cram1_dq), .cram1_wait(1'b0), .cram1_clk(cram1_clk), .cram1_adv_n(cram1_adv_n),
        .cram1_cre(cram1_cre), .cram1_ce0_n(cram1_ce0_n), .cram1_ce1_n(cram1_ce1_n), .cram1_oe_n(cram1_oe_n),
        .cram1_we_n(cram1_we_n), .cram1_ub_n(cram1_ub_n), .cram1_lb_n(cram1_lb_n),
        .sram_a(sram_a), .sram_dq(sram_dq), .sram_oe_n(sram_oe_n), .sram_we_n(sram_we_n), .sram_ub_n(sram_ub_n), .sram_lb_n(sram_lb_n)
    );
    sdram_model #(.AW(24)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqm[0]), .dqmh(dram_dqm[1]),
        .cs_n(1'b0), .ras_n(dram_ras_n), .cas_n(dram_cas_n), .we_n(dram_we_n), .cke(dram_cke)
    );
    psram_model cram0 (.clk(clk), .a(cram0_a), .dq(cram0_dq), .adv_n(cram0_adv_n), .ce0_n(cram0_ce0_n),
                       .oe_n(cram0_oe_n), .we_n(cram0_we_n), .ub_n(cram0_ub_n), .lb_n(cram0_lb_n));
    psram_model cram1 (.clk(clk), .a(cram1_a), .dq(cram1_dq), .adv_n(cram1_adv_n), .ce0_n(cram1_ce0_n),
                       .oe_n(cram1_oe_n), .we_n(cram1_we_n), .ub_n(cram1_ub_n), .lb_n(cram1_lb_n));
    sram_model sram (.clk(clk), .a(sram_a), .dq(sram_dq), .oe_n(sram_oe_n), .we_n(sram_we_n), .ub_n(sram_ub_n), .lb_n(sram_lb_n));

    // the loads, straight into the chips in gaia_mem's packing
    always_ff @(posedge clk) begin
        if (prog_we) cram1.mem[PS_PROG + 22'(prog_waddr)] <= prog_wdata;
        if (srom_we) begin
            if (srom_waddr[0]) cram1.mem[PS_SND + 22'(srom_waddr[17:1])][7:0]  <= srom_wdata;
            else               cram1.mem[PS_SND + 22'(srom_waddr[17:1])][15:8] <= srom_wdata;
        end
        // the ROZ characters, column-major within each tile as the loader stores them
        if (chr_we) chip.mem[SD_ROZ + {4'd0, chr_waddr[19:6], chr_waddr[1:0], chr_waddr[5:2]}] <= chr_wdata;
        if (map_we) cram0.mem[PS_MAP + 22'(map_waddr)] <= map_wdata;
        if (tile_we) begin
            chip.mem[SD_TILE + {4'd0, tile_waddr, 1'b0}] <= tile_wdata[31:16];
            chip.mem[SD_TILE + {4'd0, tile_waddr, 1'b1}] <= tile_wdata[15:0];
        end
        if (pcm_we) begin
            if (pcm_waddr[0]) chip.mem[SD_PCM + 24'(pcm_waddr[21:1])][7:0]  <= pcm_wdata;
            else              chip.mem[SD_PCM + 24'(pcm_waddr[21:1])][15:8] <= pcm_wdata;
        end
        if (spr_we) begin
            chip.mem[SD_SPR + {2'd0, spr_waddr, 2'b00}] <= spr_wdata[63:48];
            chip.mem[SD_SPR + {2'd0, spr_waddr, 2'b01}] <= spr_wdata[47:32];
            chip.mem[SD_SPR + {2'd0, spr_waddr, 2'b10}] <= spr_wdata[31:16];
            chip.mem[SD_SPR + {2'd0, spr_waddr, 2'b11}] <= spr_wdata[15:0];
        end
    end

    // the core waits for the SDRAM, as core_top does
    wire core_reset = reset | ~mem_ready;
    gaia_core #(.HEXDIR("../rtl/data"), .STEP_COST_BUS(STEP_COST_BUS), .STEP_COST_INT(STEP_COST_INT)) u_core (
        .mystic(1'b0), .mystic_p12(16'hffff), .mystic_p34(16'hffff), .mystic_in0(8'hff),
        .tile_fifth(8'd0), .spr_fifth(16'd0),
        .clk(clk), .pause(pause), .reset(core_reset), .pix_sync(1'b0), .vid_reset(reset),
        .prog_req(prog_req), .prog_addr(prog_addr), .prog_ack(prog_ack), .prog_q(prog_q),
        .tile_req(tile_req), .tile_addr(tile_addr), .tile_ack(tile_ack), .tile_q(tile_q),
        .map_req(map_req), .map_addr(map_addr), .map_ack(map_ack), .map_q(map_q),
        .blk_req(blk_req), .blk_addr(blk_addr), .blk_wr(blk_wr), .blk_idx(blk_idx), .blk_data(blk_data), .blk_ack(blk_ack), .roz_lead(roz_lead),
        .spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_q(spr_q),
        .vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr), .vram_be(vram_be), .vram_wdata(vram_wdata),
        .vram_ack(vram_ack), .vram_q(vram_q),
        .snd_rom_req(srom_req), .snd_rom_addr(srom_addr), .snd_rom_ack(srom_ack), .snd_rom_q(srom_q),
        .pcm_req(pcmr_req), .pcm_addr(pcmr_addr), .pcm_ack(pcmr_ack), .pcm_q(pcmr_q),
        .eep_ld_we(eep_we), .eep_ld_addr(eep_waddr), .eep_ld_wdata(eep_wdata), .eep_ld_q(eep_q), .eep_dirty(eep_dirty),
        .in0_p1(in0_p1), .in1(in1), .p2(p2),
        .cen_pix(cen_pix), .rgb(rgb), .hsync(hsync), .vsync(vsync), .de(de), .hblank(), .vblank(vblank),
        .snd_l(snd_l), .snd_r(snd_r), .snd_valid(snd_valid),
        .dbg_addr(dbg_addr), .dbg_data(dbg_data), .dbg_busstate(dbg_busstate), .dbg_step(dbg_step), .dbg_irq5(dbg_irq5),
        .dbg_overrun(dbg_overrun), .dbg_overrun_src(dbg_overrun_src), .dbg_draw_objs(dbg_draw_objs), .dbg_draw_rows(dbg_draw_rows), .dbg_draw_cols(dbg_draw_cols), .dbg_draw_pxw(dbg_draw_pxw), .dbg_spr_we(dbg_spr_we), .dbg_roz_en(dbg_roz_en), .dbg_rozctrl(dbg_rozctrl), .dbg_rozclip(dbg_rozclip), .dbg_k55(dbg_k55), .dbg_unsupported(dbg_unsupported), .dbg_shadow_overlap(dbg_shadow_overlap),
        .dbg_objcount(dbg_objcount), .dbg_vcount(dbg_vcount), .dbg_zpc(dbg_zpc), .dbg_zstep(dbg_zstep), .dbg_zwait(dbg_zwait),
        .dbg_zwr(dbg_zwr), .dbg_zrd(dbg_zrd), .dbg_zwdata(dbg_zwdata)
    );
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{eep_q, eep_dirty, eep_we_unused, eep_addr_unused, eep_data_unused,
                    dram_clk, cram0_clk, cram0_cre, cram0_ce1_n, cram1_clk, cram1_cre, cram1_ce1_n};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
