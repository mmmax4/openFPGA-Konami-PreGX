// Read-only public-port fixture for the actual queue. Producer read latency is
// exactly that of k053247_objlist: registered list and registered Y-range RAM.
`default_nettype none
module m3_vio14_queue_top (
    input logic clk, reset, line_start,
    input logic [8:0] line,
    input logic [9:0] list_count,
    input logic ready,
    input logic setup_we, setup_range,
    input logic [8:0] setup_addr,
    input logic [31:0] setup_data,
    output wire valid, scan_done, pair_ok,
    output wire [31:0] entry,
    output wire [9:0] list_idx,
    output wire [7:0] yr_addr
);
    logic [31:0] headers[512];
    logic [21:0] ranges[256];
    logic [31:0] list_q;
    logic [21:0] yr_q;
    always_ff @(posedge clk) begin
        list_q <= headers[list_idx[8:0]];
        yr_q <= ranges[yr_addr];
        if (setup_we) begin
            if (setup_range) ranges[setup_addr[7:0]] <= setup_data[21:0];
            else headers[setup_addr] <= setup_data;
        end
    end
    wire ov,od; wire [31:0]oe; wire [9:0]oi; wire [7:0]oy;
    logic [31:0]olq; logic [21:0]oyq;
    always_ff @(posedge clk) begin olq<=headers[oi[8:0]];oyq<=ranges[oy];end
    pregx_sprite_line_queue_baseline old(.clk(clk),.reset(reset),.line_start(line_start),.line(line),.list_count(list_count),.ready(ready),.list_idx(oi),.list_q(olq),.yr_addr(oy),.yr_q(oyq),.valid(ov),.entry(oe),.scan_done(od));
    assign pair_ok=(valid==ov)&&(scan_done==od)&&(list_idx==oi)&&(yr_addr==oy)&&(!valid||entry==oe);
    pregx_sprite_line_queue dut (
        .clk(clk), .reset(reset), .line_start(line_start),
        .line(line), .list_count(list_count), .ready(ready),
        .list_idx(list_idx), .list_q(list_q), .yr_addr(yr_addr), .yr_q(yr_q),
        .valid(valid), .entry(entry), .scan_done(scan_done)
    );
endmodule
`default_nettype wire
