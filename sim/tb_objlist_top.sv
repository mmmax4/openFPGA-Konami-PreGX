// Frozen-state bench wrapper for k053247_objlist.
`default_nettype none

module tb_objlist_top (
    input  logic        clk,
    input  logic        reset,
    input  logic        ram_we,
    input  logic [10:0] ram_waddr,
    input  logic [15:0] ram_wdata,
    input  logic        cfg_we,
    input  logic [15:0] opset_i,
    input  logic  [7:0] objset1_i,
    input  logic  [2:0] shadowon_i,
    input  logic  [7:0] shdpri0_i, shdpri1_i, shdpri2_i,
    input  logic        start,
    output logic        done,
    output logic        busy,
    input  logic  [9:0] list_idx,
    output logic [31:0] list_q,
    output logic  [9:0] count,
    output logic        overflow
);
    logic [15:0] opset;
    logic  [7:0] objset1;
    logic  [2:0] shadowon;
    logic  [7:0] shdpri [3];
    always_ff @(posedge clk) if (cfg_we) begin
        opset <= opset_i; objset1 <= objset1_i; shadowon <= shadowon_i;
        shdpri[0] <= shdpri0_i; shdpri[1] <= shdpri1_i; shdpri[2] <= shdpri2_i;
    end

    logic [15:0] ram [2048];
    logic [10:0] ram_addr;
    logic [15:0] ram_q;
    always_ff @(posedge clk) begin
        if (ram_we) ram[ram_waddr] <= ram_wdata;
        ram_q <= ram[ram_addr];
    end

    logic  [9:0] ol_zoom_addr; logic [21:0] ol_yr_q;
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_ol = ^{ol_zoom_addr, ol_yr_q};
    /* verilator lint_on UNUSEDSIGNAL */
    k053247_objlist u_ol (
        .intro_postportrait(1'b0),
        .mystic(1'b0),
        .stream_enable(1'b0),.shdprisel(6'h3f),
        .clk(clk), .reset(reset), .start(start), .done(done), .busy(busy),
        .opset(opset), .objset1(objset1), .shadowon(shadowon), .shdpri(shdpri), .k46_offy(16'd0),
        .zoom_addr(ol_zoom_addr), .zoom_q(24'h10000), .yr_addr(8'd0), .yr_q(ol_yr_q),
        .ram_addr(ram_addr), .ram_q(ram_q),
        .list_idx(list_idx), .list_q(list_q), .count(count), .overflow(overflow)
    );
endmodule
