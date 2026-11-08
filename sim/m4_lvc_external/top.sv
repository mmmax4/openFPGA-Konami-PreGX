// K053250 bench: the line-scroll plane alone, its ROM behind a request/ack port of
// configurable latency, driven from C++ (tb_lvc.cpp) and compared with the transcription
// of MAME's draw routine (lvc_ref.h).
`default_nettype none

module tb_lvc_top (
    input  logic        clk,
    input  logic        reset,
    input  logic [63:0] regs_flat,          // the eight registers, byte i at [8 i +: 8]
    input  logic        cpu_we, cpu_req, slow,
    output wire cpu_ack, state_ready,
    input  logic [12:0] cpu_addr,
    input  logic  [1:0] cpu_be,
    input  logic [15:0] cpu_wdata,
    output logic [15:0] cpu_rq,
    output logic        dma_busy,
    input  logic        frame_tick,
    input  logic        latch,
    input  logic        line_start,
    input  logic  [8:0] line,
    output logic        busy,
    output wire         row_busy,
    input  logic  [7:0] palbase,
    input  logic  [8:0] px,
    output logic [10:0] pix,
    output logic        opaque,
    // ROM load
    input  logic        rom_we,
    input  logic [14:0] rom_wa,
    input  logic [63:0] rom_wd,
    input  logic [7:0]  lat,                // clocks before the ack
    output logic [31:0] n_fetch
);
    logic [7:0] regs [8];
    always_comb for (int i = 0; i < 8; i++) regs[i] = regs_flat[8*i +: 8];

    logic [63:0] rom [32768];
    logic        rom_req, rom_ack;
    logic [14:0] rom_addr;
    logic [63:0] rom_q;
    logic  [7:0] cn;
    always_ff @(posedge clk) begin
        if (rom_we) rom[rom_wa] <= rom_wd;
        rom_ack <= 1'b0;
        if (!rom_req) cn <= 8'd0;
        else if (rom_ack) cn <= 8'd0;
        else if (cn >= lat) begin rom_ack <= 1'b1; rom_q <= rom[rom_addr]; cn <= 8'd0; n_fetch <= n_fetch + 32'd1; end
        else cn <= cn + 8'd1;
        if (reset) n_fetch <= 32'd0;
    end

    // +dbg=1: the normal orientation's first rows' parameters and the first pixels' evaluation
    int dbg;
    int nrow;
    initial begin
        if (!$value$plusargs("dbg=%d", dbg)) dbg = 0;
        nrow = 0;
    end
    always_ff @(posedge clk) if (dbg != 0) begin
        if (dut.m == 3'd5 && dut.r == 5'd5 && nrow < 2) begin
            $display("PRM row ry=%0d entry=%0d w0=%04x w1=%04x w2=%04x scrollword=%04x msx=%0d msy=%0d ctrl=%02x",
                     dut.ry, dut.n_entry, dut.w0, dut.w1, dut.w2, dut.fr_q, dut.msx, dut.msy, dut.ctrl);
        end
        if (dut.m == 3'd5 && dut.r == 5'd17 && dut.ux < 6 && nrow < 2)
            $display("  px %0d: scroll=%0d pos=%0d a=%0d prod=%0d nib=%05x grp=%04x sel=%0d ok=%0d pen=%0d",
                     dut.ux, dut.e_scroll, dut.e_pos, dut.e_a, dut.e_prod, dut.e_nib, dut.e_grp, dut.e_sel, dut.e_ok, dut.u_pen);
        if (dut.m == 3'd5 && dut.r == 5'd17 && dut.ux == 287) nrow <= nrow + 1;
    end

`ifdef M4_SHARED
    wire state_dma_busy,snapshot_allowed,snapshot_begin,snapshot_active,snapshot_req,snapshot_ack;
    wire[10:0]snapshot_addr;wire[15:0]snapshot_q;
    wire mem_req,mem_we,mem_ack;wire[13:0]mem_addr;wire[1:0]mem_be;wire[15:0]mem_wdata,mem_q;
    pregx_road_state external_state(.clk(clk),.reset(reset),.frame_tick(frame_tick),.reg4_dma(regs[4][1]),.initialized(state_ready),.dma_busy(state_dma_busy),
        .cpu_req(cpu_req),.cpu_we(cpu_we),.cpu_addr(cpu_addr),.cpu_be(cpu_be),.cpu_wdata(cpu_wdata),.cpu_ack(cpu_ack),.cpu_q(cpu_rq),
        .snapshot_begin(snapshot_begin),.snapshot_active(snapshot_active),.snapshot_req(snapshot_req),.snapshot_addr(snapshot_addr),
        .snapshot_allowed(snapshot_allowed),.snapshot_ack(snapshot_ack),.snapshot_q(snapshot_q),.page(),
        .mem_req(mem_req),.mem_we(mem_we),.mem_addr(mem_addr),.mem_be(mem_be),.mem_wdata(mem_wdata),.mem_ack(mem_ack),.mem_q(mem_q));
    wire r_req,r_ack,w_req,w_accept,w_commit;wire[22:0]r_addr,w_addr;wire[15:0]r_q,w_data;wire[1:0]w_be;
    pregx_road_psram_bridge bridge(.clk(clk),.reset(reset),.req(mem_req),.we(mem_we),.addr(mem_addr),.be(mem_be),.wdata(mem_wdata),.ack(mem_ack),.q(mem_q),
        .r_req(r_req),.r_addr(r_addr),.r_ack(r_ack),.r_q(r_q),.w_req(w_req),.w_addr(w_addr),.w_be(w_be),.w_data(w_data),.w_accept(w_accept),.w_commit(w_commit));
    wire[21:16]pa;wire[15:0]pdq;wire pclk,padv,pcre,pce0,pce1,poe,pwe,pub,plb;
    psram_port port(.clk(clk),.reset(reset),.slow(slow),.r0_req(r_req),.r0_addr(r_addr),.r0_ack(r_ack),.r0_q(r_q),
        .r1_req(1'b0),.r1_addr(23'd0),.r1_ack(),.r1_q(),.w_req(w_req),.w_addr(w_addr),.w_data(w_data),.w_be(w_be),.w_ack(w_accept),.w_commit(w_commit),
        .cram_a(pa),.cram_dq(pdq),.cram_wait(1'b0),.cram_clk(pclk),.cram_adv_n(padv),.cram_cre(pcre),.cram_ce0_n(pce0),.cram_ce1_n(pce1),.cram_oe_n(poe),.cram_we_n(pwe),.cram_ub_n(pub),.cram_lb_n(plb));
    psram_model #(.TAA(7)) state_chip(.clk(clk),.a(pa),.dq(pdq),.adv_n(padv),.ce0_n(pce0),.oe_n(poe),.we_n(pwe),.ub_n(pub),.lb_n(plb));
    always_ff @(posedge clk)if(!reset && mem_req && mem_we && mem_ack && !pwe)$fatal(1,"road state write ACK before WE release");
    wire f_we,c_we,group_we,line_we;
    wire[10:0]f_wa,f_ra;wire[15:0]f_wdata,f_q;
    wire[8:0]c_wa,c_ra,group_wa,group_ra;
    wire[52:0]c_wdata,c_q;wire[79:0]group_wdata,group_q;
    wire[11:0]line_wa,line_ra;wire[8:0]line_wdata,line_q;
    pregx_video_ram actual_video_ram(.clk(clk),.metam(1'b1),
        .g_we(1'b0),.g_wa(13'd0),.g_ra(13'd0),.g_wdata(16'd0),.g_q(),
        .f_we(f_we),.f_wa(f_wa),.f_ra(f_ra),.f_wdata(f_wdata),.f_q(f_q),
        .c_we(c_we),.c_wa(c_wa),.c_ra(c_ra),.c_wdata(c_wdata),.c_q(c_q),
        .cache_we(group_we),.cache_wa(group_wa),.cache_ra(group_ra),.cache_wdata(group_wdata),.cache_q(group_q),
        .g_lb_we(1'b0),.g_lb_wa(12'd0),.g_lb_ra(12'd0),.g_lb_wdata(12'd0),.g_lb_q(),
        .r_lb_we(line_we),.r_lb_wa(line_wa),.r_lb_ra(line_ra),.r_lb_wdata(line_wdata),.r_lb_q(line_q));
    k053250_lvc #(.RUN_AHEAD(1'b1),.EXTERNAL_VIDEO(1'b1),.EXTERNAL_STATE(1'b1)) dut (
`elsif M4_AHEAD
    k053250_lvc #(.RUN_AHEAD(1'b1)) dut (
`else
    k053250_lvc dut (
`endif
        .clk(clk), .reset(reset), .regs(regs),
        .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_be(cpu_be), .cpu_wdata(cpu_wdata), .cpu_rq(),
        .dma_busy(dma_busy), .frame_tick(frame_tick), .latch(latch),
        .line_start(line_start), .line(line), .busy(busy), .row_busy(row_busy),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ack(rom_ack), .rom_q(rom_q),
        .palbase(palbase), .px(px), .pix(pix), .opaque(opaque)
`ifdef M4_SHARED
        ,.external_dma_busy(state_dma_busy),.snapshot_allowed(snapshot_allowed),.snapshot_begin(snapshot_begin)
        ,.snapshot_active(snapshot_active),.snapshot_req(snapshot_req),.snapshot_addr(snapshot_addr),.snapshot_ack(snapshot_ack),.snapshot_q(snapshot_q)
        ,.f_we(f_we),.f_wa(f_wa),.f_ra(f_ra),.f_wdata(f_wdata),.f_q(f_q)
        ,.c_we(c_we),.c_wa(c_wa),.c_ra(c_ra),.c_wdata(c_wdata),.c_q(c_q)
        ,.group_we(group_we),.group_wa(group_wa),.group_ra(group_ra),.group_wdata(group_wdata),.group_q(group_q)
        ,.line_we(line_we),.line_wa(line_wa),.line_ra(line_ra),.line_wdata(line_wdata),.line_q(line_q)
`endif
    );
endmodule
