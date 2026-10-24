// M2 independent fixture: actual gaia_mem and memory controllers, original
// ROM bytes downloaded through public ports, no DUT hierarchy forcing.
// Derived from the preserved upstream tb_mem_top wrapper.
// Bench wrapper for target/pocket/gaia_mem.sv: the Pocket memory subsystem
// with behavioural SDRAM, PSRAM and SRAM chips behind it. The C++ side loads
// bytes through the download port and reads them back through every core
// port (sim/tb_mem.cpp).
`default_nettype none
module tb_m2_mem_top #(parameter int TEST_SHRINK = 9) (
    input  logic        clk,
    input  logic        init,
    input logic mystic, rd_late, burst_slow,
    output logic [7:0] tile_fifth,
    output logic [15:0] spr_fifth,
    output logic [6:0] test_mask,
    output logic sd_read_pulse,
    output logic [23:0] sd_read_word,
    output logic [31:0] sd_protocol_errors,
    output logic        ready,
    input  logic        ps_slow, sram_slow, sram_slow_wr,
    input  logic        test_start, output logic test_run, test_done,
    output logic  [6:0] test_ok, test_stable, output logic vram_ok, output logic [3:0] vram_bad,
    input  logic        dl_we, input logic [24:0] dl_addr, input logic [7:0] dl_data,
    output logic        eep_we, output logic [6:0] eep_addr, output logic [7:0] eep_data,
    input  logic        prog_req, input  logic [22:1] prog_addr, output logic prog_ack, output logic [15:0] prog_q,
    input  logic        tile_req, input  logic [18:0] tile_addr, output logic tile_ack, output logic [31:0] tile_q,
    input  logic        map_req,  input  logic [19:0] map_addr,  output logic map_ack,  output logic [15:0] map_q,
    input  logic        blk_req,  input  logic [15:0] blk_addr,  output logic blk_wr,   output logic  [5:0] blk_idx,
    output logic [15:0] blk_data, output logic        blk_ack,
    input  logic        spr_req,  input  logic [19:0] spr_addr,  output logic spr_ack,  output logic [63:0] spr_q,
    input  logic        snd_req,  input  logic [17:0] snd_addr,  output logic snd_ack,  output logic  [7:0] snd_q,
    input  logic        pcm_req,  input  logic [21:0] pcm_addr,  output logic pcm_ack,  output logic  [7:0] pcm_q,
    input  logic        vram_req, input  logic        vram_we,   input  logic [15:0] vram_addr,
    input  logic  [1:0] vram_be,  input  logic [15:0] vram_wdata, output logic vram_ack, output logic [15:0] vram_q
);
    wire  [15:0] dram_dq; wire [12:0] dram_a; wire [1:0] dram_ba, dram_dqm;
    wire         dram_clk, dram_cke, dram_ras_n, dram_cas_n, dram_we_n;
    wire  [21:16] cram0_a, cram1_a; wire [15:0] cram0_dq, cram1_dq;
    wire         cram0_clk, cram0_adv_n, cram0_cre, cram0_ce0_n, cram0_ce1_n, cram0_oe_n, cram0_we_n, cram0_ub_n, cram0_lb_n;
    wire         cram1_clk, cram1_adv_n, cram1_cre, cram1_ce0_n, cram1_ce1_n, cram1_oe_n, cram1_we_n, cram1_ub_n, cram1_lb_n;
    wire  [16:0] sram_a; wire [15:0] sram_dq; wire sram_oe_n, sram_we_n, sram_ub_n, sram_lb_n;

    gaia_mem #(.TEST_SHRINK(TEST_SHRINK)) dut (
        .clk(clk), .clk_sdram(clk), .init(init), .ready(ready), .rd_late(rd_late), .burst_slow(burst_slow),
`ifndef M2_LEGACY
        .mystic(mystic), .tile_fifth(tile_fifth), .spr_fifth(spr_fifth), .test_mask(test_mask),
`endif
        .ps_slow(ps_slow), .sram_slow(sram_slow), .sram_slow_wr(sram_slow_wr),
        .test_start(test_start), .test_run(test_run), .test_done(test_done), .test_ok(test_ok), .test_stable(test_stable),
        .vram_ok(vram_ok), .vram_bad(vram_bad),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data),
        .eep_we(eep_we), .eep_addr(eep_addr), .eep_data(eep_data),
        .prog_req(prog_req), .prog_addr(prog_addr), .prog_ack(prog_ack), .prog_q(prog_q),
        .tile_req(tile_req), .tile_addr(tile_addr), .tile_ack(tile_ack), .tile_q(tile_q),
        .map_req(map_req), .map_addr(map_addr), .map_ack(map_ack), .map_q(map_q),
        .blk_req(blk_req), .blk_addr(blk_addr), .blk_wr(blk_wr), .blk_idx(blk_idx), .blk_data(blk_data), .blk_ack(blk_ack), .roz_lead(4'd0),
        .spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_q(spr_q),
        .snd_req(snd_req), .snd_addr(snd_addr), .snd_ack(snd_ack), .snd_q(snd_q),
        .pcm_req(pcm_req), .pcm_addr(pcm_addr), .pcm_ack(pcm_ack), .pcm_q(pcm_q),
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
`ifdef M2_LEGACY
    // Test-only ABI adapter: the archived M1b DUT bytes are untouched.
    // It has no Mystic profile or fifth-plane outputs.
    assign tile_fifth = 8'd0;
    assign spr_fifth = 16'd0;
    assign test_mask = 7'h7f;
`endif
    // Passive pin monitor, independent of the DUT's internal burst FSM.
    // This chip model checks logical command/CL3 delivery only. Physical
    // phase/tAC/tOH/Z qualification remains a separate timed-controller gate.
    logic [12:0] observed_row [4];
    always_ff @(posedge clk) begin
        sd_read_pulse <= 1'b0;
        if ({dram_ras_n, dram_cas_n, dram_we_n} == 3'b011)
            observed_row[dram_ba] <= dram_a;
        if ({dram_ras_n, dram_cas_n, dram_we_n} == 3'b101) begin
            sd_read_pulse <= 1'b1;
            sd_read_word <= {dram_ba, observed_row[dram_ba], dram_a[8:0]};
        end
    end
    assign sd_protocol_errors = 32'(chip.errors);
    sdram_model #(.AW(24)) chip (
        .clk(clk), .dq(dram_dq), .a(dram_a), .ba(dram_ba), .dqml(dram_dqm[0]), .dqmh(dram_dqm[1]),
        .cs_n(1'b0), .ras_n(dram_ras_n), .cas_n(dram_cas_n), .we_n(dram_we_n), .cke(dram_cke)
    );
    psram_model cram0 (.clk(clk), .a(cram0_a), .dq(cram0_dq), .adv_n(cram0_adv_n), .ce0_n(cram0_ce0_n),
                       .oe_n(cram0_oe_n), .we_n(cram0_we_n), .ub_n(cram0_ub_n), .lb_n(cram0_lb_n));
    psram_model cram1 (.clk(clk), .a(cram1_a), .dq(cram1_dq), .adv_n(cram1_adv_n), .ce0_n(cram1_ce0_n),
                       .oe_n(cram1_oe_n), .we_n(cram1_we_n), .ub_n(cram1_ub_n), .lb_n(cram1_lb_n));
    sram_model sram (.clk(clk), .a(sram_a), .dq(sram_dq), .oe_n(sram_oe_n), .we_n(sram_we_n), .ub_n(sram_ub_n), .lb_n(sram_lb_n));
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused = ^{mystic, dram_clk, cram0_clk, cram0_cre, cram0_ce1_n, cram1_clk, cram1_cre, cram1_ce1_n};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
