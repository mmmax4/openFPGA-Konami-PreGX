`default_nettype none
module tb_m2_names_compat_top(
    input logic clk,reset,start,mystic,opt_in,stream_enable,
    input logic [7:0] priority_c,priority_d,
    input logic [15:0] opset,k46_offy,
    input logic [7:0] objset1,
    input logic [2:0] shadowon,
    input logic [5:0] shdprisel,
    input logic [23:0] shadow_priorities,
    input logic ram_we,
    input logic [10:0] ram_waddr,
    input logic [15:0] ram_wdata,
    input logic [9:0] list_idx,
    input logic [7:0] yr_addr,
    output wire [31:0] list_q[4],
    output wire [21:0] yr_q[4],
    output wire [9:0] count[4],
    output wire [3:0] done,busy,overflow
);
    logic [15:0] ram[2048];
    wire [7:0] shdpri[3];
    assign shdpri='{shadow_priorities[7:0],shadow_priorities[15:8],shadow_priorities[23:16]};
    wire intro_gate=opt_in && priority_c==8'h50 && priority_d==8'h90;
    always_ff @(posedge clk) if(ram_we) ram[ram_waddr]<=ram_wdata;
    for(genvar g=0;g<4;g++) begin: instances
        wire [10:0] ram_addr;
        logic [15:0] ram_q;
        always_ff @(posedge clk) ram_q<=ram[ram_addr];
        wire [9:0] zoom_addr;
        wire [23:0] zoom_q;
        sprite_tables tables(.clk(clk),.zoom_addr(zoom_addr),.zoom_q(zoom_q),
                             .recip_addr(11'd0),.recip_q());
        if(g==0) begin: original
            names_compat_original objects(
                .clk(clk),.reset(reset),.start(start),.mystic(mystic),
                .stream_enable(stream_enable),.shdprisel(shdprisel),
                .opset(opset),.objset1(objset1),.shadowon(shadowon),.shdpri(shdpri),.k46_offy(k46_offy),
                .zoom_addr(zoom_addr),.zoom_q(zoom_q),.yr_addr(yr_addr),.yr_q(yr_q[g]),
                .ram_addr(ram_addr),.ram_q(ram_q),.list_idx(list_idx),.list_q(list_q[g]),
                .count(count[g]),.done(done[g]),.busy(busy[g]),.overflow(overflow[g]));
        end else begin: current_rtl
            // 1: parameter-default bypass, even with flag asserted.
            // 2: feature compiled, hardwired flag off. 3: runtime gate.
            k053247_objlist #(.INTRO_COMPAT(g!=1)) objects(
                .clk(clk),.reset(reset),.start(start),.mystic(mystic),
                .intro_postportrait(g==2 ? 1'b0 : intro_gate),
                .stream_enable(stream_enable),.shdprisel(shdprisel),
                .opset(opset),.objset1(objset1),.shadowon(shadowon),.shdpri(shdpri),.k46_offy(k46_offy),
                .zoom_addr(zoom_addr),.zoom_q(zoom_q),.yr_addr(yr_addr),.yr_q(yr_q[g]),
                .ram_addr(ram_addr),.ram_q(ram_q),.list_idx(list_idx),.list_q(list_q[g]),
                .count(count[g]),.done(done[g]),.busy(busy[g]),.overflow(overflow[g]));
        end
    end
endmodule
`default_nettype wire
