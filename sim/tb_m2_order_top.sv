`default_nettype none
module tb_m2_order_top(
    input logic clk,reset,start,mystic,stream_enable,
    input logic [5:0] shdprisel,
    input logic ram_we,
    input logic [10:0] ram_waddr,
    input logic [15:0] ram_wdata,
    input logic [9:0] list_idx,
    output wire [31:0] list_q,
    output wire [9:0] count,
    output wire done,busy,overflow
);
    logic [15:0] ram[2048];
    logic [10:0] ram_addr;
    logic [15:0] ram_q;
    always_ff @(posedge clk) begin
        if(ram_we) ram[ram_waddr]<=ram_wdata;
        ram_q<=ram[ram_addr];
    end
    wire [7:0] shdpri[3];
    assign shdpri='{8'd16,8'd64,8'd96};
    k053247_objlist objects(
        .intro_postportrait(1'b0),
`ifdef M2_ORDER_STREAM_API
        .stream_enable(stream_enable),.shdprisel(shdprisel),
`else
        // Planned optional interface; original baseline has neither input.
`endif
        .mystic(mystic),.clk(clk),.reset(reset),.start(start),.done(done),.busy(busy),
        .opset(16'd0),.objset1(8'h20),.shadowon(3'b111),.shdpri(shdpri),.k46_offy(16'd0),
        .zoom_addr(),.zoom_q(24'h10000),.yr_addr(8'd0),.yr_q(),
        .ram_addr(ram_addr),.ram_q(ram_q),.list_idx(list_idx),.list_q(list_q),.count(count),.overflow(overflow)
    );
    wire unused_controls=^{stream_enable,shdprisel};
endmodule
`default_nettype wire
