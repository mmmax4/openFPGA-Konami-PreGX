// Mystic Warriors K056832/K055673 CPU ROM readback over the shared row ports.
// See pinned MAME mw_rom_word_r/k055673_5bpp_rom_word_r and M2_READBACK.md.
// Tile row19 addresses only populated rows; canonical erased tail returns 0.
// Out-of-region accesses are explicitly flagged, never aliased into PCM/rows.
`default_nettype none
module mystic_rom_readback (
    input logic clk, reset,
    input logic req,                 // held through ack; deassert cancels/drains
    input logic sprite,
    input logic [12:0] offset,        // CPU window WORD offset
    input logic [31:0] tile_bank,
    input logic tile_plane5,
    input logic [23:0] sprite_word,
    output logic ack,
    output logic [15:0] data,
    output logic out_of_range,
    output logic tile_req,
    output logic [18:0] tile_addr,
    input logic tile_ack,
    input logic [31:0] tile_q,
    input logic [7:0] tile_fifth,
    output logic spr_req,
    output logic [19:0] spr_addr,
    input logic spr_ack,
    input logic [63:0] spr_q,
    input logic [15:0] spr_fifth
);
    typedef enum logic [2:0] {IDLE, TILE_CALC, SPR_CALC, TILE_WAIT, SPR_WAIT, HOLD, BANK_REDUCE} state_t;
    state_t state;
    logic [12:0] off_r;
    logic plane5_r, signed_bank_unsupported;
    logic [9:0] bank_r;
    // Reduce the full raw bank using one small compare/subtract per clock.
    // A combinational32-bit %640 took61ns in fitted clock02. The cache keeps
    // successive CPU words in the same bank on the ordinary row-read path.
    logic cache_valid;
    logic [31:0] cache_tag,bank_tag,bank_shift;
    logic [9:0] cache_bank,bank_remainder;
    logic [4:0] bank_bit;
    wire [10:0] shifted_remainder={bank_remainder,bank_shift[31]};
    wire [9:0] reduced_remainder=10'((shifted_remainder>=11'd640) ?
        shifted_remainder-11'd640 : shifted_remainder);
    logic [23:0] word_r;
    logic fifth_r;
    logic [1:0] select_r;
    // Constant 640 banks are defined by canonical region length/0x2000.
    // Reduce before the 2048-row pitch; populated physical memory is 256banks.
    wire [20:0] tile_row = {bank_r,11'd0} +
                          (plane5_r ? {10'd0,off_r[12:2]} : {9'd0,off_r[12:1]});
    wire [24:0] spr_lower_word = {1'b0,word_r} +
                       (off_r[2] ? 25'd0 : 25'd2) + {24'd0,off_r[0]};
    wire [23:0] spr_fifth_byte = {1'b0,word_r[23:1]} + (off_r[2] ? 24'd0 : 24'd1);
    wire [1:0] tile_pair = tile_fifth[(3'd6 - {off_r[1:0],1'b0}) +: 2];
    always_ff @(posedge clk) begin
        ack <= 1'b0;
        if (reset) begin
            state <= IDLE; tile_req <= 1'b0; spr_req <= 1'b0;
            out_of_range <= 1'b0; cache_valid <= 1'b0;
        end else if (!req) begin
            state <= IDLE; tile_req <= 1'b0; spr_req <= 1'b0;
            out_of_range <= 1'b0;
        end else begin
            case(state)
                IDLE: begin
                    off_r <= offset; plane5_r <= tile_plane5;
                    bank_tag <= tile_bank;
                    bank_shift <= tile_bank;
                    bank_remainder <= 10'd0;
                    bank_bit <= 5'd31;
                    bank_r <= cache_bank;
                    signed_bank_unsupported <= tile_bank[31];
                    word_r <= sprite_word;
                    state <= sprite ? SPR_CALC :
                        (tile_bank[31] || (cache_valid && cache_tag==tile_bank)) ? TILE_CALC : BANK_REDUCE;
                end
                BANK_REDUCE: begin
                    bank_shift <= {bank_shift[30:0],1'b0};
                    bank_remainder <= reduced_remainder[9:0];
                    if (bank_bit==0) begin
                        bank_r <= reduced_remainder[9:0];
                        cache_tag <= bank_tag;
                        cache_bank <= reduced_remainder[9:0];
                        cache_valid <= 1'b1;
                        state <= TILE_CALC;
                    end else bank_bit <= bank_bit-5'd1;
                end
                TILE_CALC: begin
                    select_r <= off_r[1:0];
                    if (signed_bank_unsupported || tile_row >= 21'h100000) begin
                        out_of_range <= 1'b1; data <= '0; ack <= 1'b1; state <= HOLD;
                    end else if (tile_row >= 21'h080000) begin
                        // Original canonical erased00 tail is not stored in SDRAM.
                        data <= '0; ack <= 1'b1; state <= HOLD;
                    end else begin
                        tile_addr <= tile_row[18:0]; tile_req <= 1'b1; state <= TILE_WAIT;
                    end
                end
                SPR_CALC: begin
                    fifth_r <= off_r[1];
                    if (off_r[1]) begin
                        if (spr_fifth_byte >= 24'h100000) begin
                            out_of_range <= 1'b1; data <= '0; ack <= 1'b1; state <= HOLD;
                        end else begin
                            spr_addr <= {1'b0,spr_fifth_byte[19:1]};
                            select_r <= {1'b0,spr_fifth_byte[0]}; spr_req <= 1'b1; state <= SPR_WAIT;
                        end
                    end else begin
                        if (spr_lower_word >= 25'h0200000) begin
                            out_of_range <= 1'b1; data <= '0; ack <= 1'b1; state <= HOLD;
                        end else begin
                            spr_addr <= {1'b0,spr_lower_word[20:2]};
                            select_r <= spr_lower_word[1:0]; spr_req <= 1'b1; state <= SPR_WAIT;
                        end
                    end
                end
                TILE_WAIT: if (tile_ack) begin
                    tile_req <= 1'b0; ack <= 1'b1; state <= HOLD;
                    data <= plane5_r ? {3'd0,tile_pair[1],7'd0,tile_pair[0],4'd0} :
                                        (select_r[0] ? tile_q[15:0] : tile_q[31:16]);
                end
                SPR_WAIT: if (spr_ack) begin
                    spr_req <= 1'b0; ack <= 1'b1; state <= HOLD;
                    if (fifth_r) data <= {8'd0,select_r[0] ? spr_fifth[7:0] : spr_fifth[15:8]};
                    else case(select_r)
                        2'd0: data <= {spr_q[55:48],spr_q[63:56]};
                        2'd1: data <= {spr_q[39:32],spr_q[47:40]};
                        2'd2: data <= {spr_q[23:16],spr_q[31:24]};
                        2'd3: data <= {spr_q[7:0],spr_q[15:8]};
                    endcase
                end
                HOLD: begin end      // one ack until CPU request is released
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
