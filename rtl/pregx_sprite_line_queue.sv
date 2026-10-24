// Prefetch ordered sprite headers and discard entries outside this line.
// Both producer ports are synchronous with one clock of read latency, as in
// k053247_objlist. Two response tags reserve FIFO space before issuing a read.
// No pixels, object ordering, or ROM data are changed here.
`default_nettype none
module pregx_sprite_line_queue (
    input  wire clk, reset, line_start,
    input  wire [8:0] line,
    input  wire [9:0] list_count,
    output wire [9:0] list_idx,
    input  wire [31:0] list_q,
    output wire [7:0] yr_addr,
    input  wire [21:0] yr_q,
    output wire valid,
    output wire [31:0] entry,
    input  wire ready,
    output wire scan_done
);
    // Four entries are deliberately registers: the Pocket design has only
    // one unused M10K and this queue does not require another memory block.
    (* ramstyle = "logic" *) logic [31:0] fifo [4];
    logic [1:0] rd_ptr, wr_ptr;
    logic [2:0] queued;
    logic [9:0] issued, count;
    logic [8:0] render_line;
    logic active, list_response, range_response;
    logic [31:0] delayed_entry;
    wire [2:0] reserved = queued + {2'd0, list_response} + {2'd0, range_response};
    wire issue = active && issued < count && reserved < 3'd4;
    wire covers = $signed({2'b00, render_line}) >= $signed(yr_q[21:11]) &&
                  $signed({2'b00, render_line}) <= $signed(yr_q[10:0]);
    wire push = active && range_response && covers;
    wire pop = valid && ready;

    assign list_idx = issued;
    assign yr_addr = list_q[15:8];
    assign valid = active && queued != 3'd0;
    assign entry = fifo[rd_ptr];
    assign scan_done = active && issued == count && !list_response && !range_response;

    always_ff @(posedge clk) begin
        if (reset) begin
            active <= 1'b0;
            issued <= 10'd0; count <= 10'd0; render_line <= 9'd0;
            rd_ptr <= 2'd0; wr_ptr <= 2'd0; queued <= 3'd0;
            list_response <= 1'b0; range_response <= 1'b0;
        end else if (line_start) begin
            active <= 1'b1;
            issued <= 10'd0; count <= list_count; render_line <= line;
            rd_ptr <= 2'd0; wr_ptr <= 2'd0; queued <= 3'd0;
            list_response <= 1'b0; range_response <= 1'b0;
        end else begin
            list_response <= issue;
            range_response <= list_response;
            if (issue) issued <= issued + 10'd1;
            if (list_response) delayed_entry <= list_q;
            if (push) begin
                fifo[wr_ptr] <= delayed_entry;
                wr_ptr <= wr_ptr + 2'd1;
            end
            if (pop) rd_ptr <= rd_ptr + 2'd1;
            case ({push,pop})
                2'b10: queued <= queued + 3'd1;
                2'b01: queued <= queued - 3'd1;
                default: ;
            endcase
        end
    end
endmodule
`default_nettype wire
