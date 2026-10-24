// The actual cache owns one synchronous read port to an unchanged original
// frame snapshot. Only public setup writes while reset is asserted are used.
`default_nettype none
module tb_m2_word_cache08 (
    input logic clk, reset, line_start,
    input logic head_valid,
    input logic [7:0] head_ent,
    input logic consume,
    input logic setup_we,
    input logic [10:0] setup_addr,
    input logic [15:0] setup_data,
    output wire ready,
    output wire [10:0] ram_addr,
    output wire [15:0] word0, word1, word2, word3, word4, word5, word6
);
    logic [15:0] snapshot[2048];
    logic [15:0] ram_q;
    wire [15:0] words[7];
    always_ff @(posedge clk) begin
        ram_q <= snapshot[ram_addr];
        if (setup_we) snapshot[setup_addr] <= setup_data;
    end
    pregx_sprite_word_cache dut (
        .clk(clk), .reset(reset), .line_start(line_start),
        .head_valid(head_valid), .head_ent(head_ent), .consume(consume),
        .ram_addr(ram_addr), .ram_q(ram_q), .ready(ready), .words(words)
    );
    assign word0=words[0]; assign word1=words[1]; assign word2=words[2];
    assign word3=words[3]; assign word4=words[4]; assign word5=words[5];
    assign word6=words[6];
endmodule
`default_nettype wire
