`default_nettype none
module tb_m2_zslot_top(
    input logic clk,reset,start,mystic,stream_enable,
    input logic [15:0] opset,k46_offy,
    input logic [7:0] objset1,
    input logic [2:0] shadowon,
    input logic [5:0] shdprisel,
    input logic [23:0] shadow_priorities,
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
    assign shdpri='{shadow_priorities[7:0],shadow_priorities[15:8],shadow_priorities[23:16]};
    wire [9:0] zoom_addr;
    wire [23:0] zoom_q;
    sprite_tables tables(.clk(clk),.zoom_addr(zoom_addr),.zoom_q(zoom_q),
                         .recip_addr(11'd0),.recip_q());
    k053247_objlist objects(
        .mystic(mystic),.stream_enable(stream_enable),.shdprisel(shdprisel),
        .clk(clk),.reset(reset),.start(start),.done(done),.busy(busy),
        .opset(opset),.objset1(objset1),.shadowon(shadowon),.shdpri(shdpri),.k46_offy(k46_offy),
        .zoom_addr(zoom_addr),.zoom_q(zoom_q),.yr_addr(8'd0),.yr_q(),
        .ram_addr(ram_addr),.ram_q(ram_q),.list_idx(list_idx),.list_q(list_q),.count(count),.overflow(overflow)
    );
endmodule
`default_nettype wire
