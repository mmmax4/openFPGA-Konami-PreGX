// Read the next ordered object's seven raw words while the current object
// draws. The source is the frame snapshot SRAM, immutable during rendering.
// One synchronous read port, one clock latency; no new block RAM.
`default_nettype none
module pregx_sprite_word_cache (
    input wire clk, reset, line_start,
    input wire head_valid,
    input wire [7:0] head_ent,
    input wire consume,
    output wire [10:0] ram_addr,
    input wire [15:0] ram_q,
    output wire ready,
    output wire [15:0] words [7]
);
    (* ramstyle = "logic" *) logic [15:0] data [7];
    logic [7:0] ent;
    logic [3:0] issued;
    logic fetching, complete, response_valid;
    logic [2:0] response_word;
    wire issue = fetching && issued < 4'd7;
    assign ram_addr = {ent,issued[2:0]};
    assign ready = complete && head_valid && ent == head_ent;
    genvar w;
    generate
    for (w=0;w<7;w=w+1) begin : expose_word
        assign words[w] = data[w];
    end
    endgenerate

    always_ff @(posedge clk) begin
        if (reset || line_start) begin
            fetching <= 1'b0; complete <= 1'b0; response_valid <= 1'b0;
            ent <= 8'd0; issued <= 4'd0; response_word <= 3'd0;
        end else if (consume) begin
            fetching <= 1'b0; complete <= 1'b0; response_valid <= 1'b0;
        end else begin
            response_valid <= issue;
            if (!fetching && !complete && head_valid) begin
                ent <= head_ent; issued <= 4'd0; fetching <= 1'b1;
            end
            if (issue) begin
                issued <= issued + 4'd1;
                response_word <= issued[2:0];
            end
            if (response_valid) begin
                data[response_word] <= ram_q;
                if (response_word == 3'd6) begin fetching <= 1'b0; complete <= 1'b1; end
            end
        end
    end
endmodule
`default_nettype wire
