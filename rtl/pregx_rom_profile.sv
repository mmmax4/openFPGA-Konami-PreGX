// Private original-image identity, without adding headers or patching ROMs.
// CRC constants bind the two exact host SHA-verified M1b/M2 memory images.
// Early profile after byte255 precedes every profile-dependent image region;
// valid remains low until an ordered complete image and its CRC are accepted.
`default_nettype none
module pregx_rom_profile (
    input  logic        clk,
    input  logic        dl_we,       // actual gaia_mem port: sample rising edge
    input  logic [24:0] dl_addr,
    input  logic  [7:0] dl_data,
    output logic        mystic,
    output logic        identified,
    output logic        valid,
    output logic        begin_image
);
    localparam logic [31:0] GAIA_PREFIX = 32'hb3464cae;
    localparam logic [31:0] MYSTIC_PREFIX = 32'hc821c2b6;
    localparam logic [31:0] GAIA_CRC = 32'h13ba3e74;
    localparam logic [31:0] MYSTIC_CRC = 32'h4c82bad4;
    localparam logic [24:0] GAIA_LAST = 25'h136007f;
    localparam logic [24:0] MYSTIC_LAST = 25'h0dc007f;
    logic we_d;
    logic ordered;
    logic [31:0] crc;
    logic [24:0] next_addr;
    initial begin
        mystic=1'b0; identified=1'b0; valid=1'b0;
        we_d=1'b0; ordered=1'b0; crc=32'hffffffff; next_addr=25'd0;
    end
    wire byte_we = dl_we && !we_d;
    assign begin_image = byte_we && dl_addr == 25'd0;
    function automatic logic [31:0] advance(input logic [31:0] c, input logic [7:0] d);
        logic [31:0] v;
        v = c ^ {24'd0,d};
        for (int i=0;i<8;i++) v = (v >> 1) ^ (v[0] ? 32'hedb88320 : 32'd0);
        return v;
    endfunction
    wire [31:0] crc_next = advance(crc,dl_data);
    always_ff @(posedge clk) begin
        we_d <= dl_we;
        if (byte_we) begin
            valid <= 1'b0;
            if (dl_addr == 25'd0) begin
                crc <= advance(32'hffffffff,dl_data);
                next_addr <= 25'd1;
                ordered <= 1'b1;
                identified <= 1'b0;
                // Keep the last profile until a new prefix is known. All
                // machine consumers must already be reset by valid=0.
            end else begin
                crc <= crc_next;
                next_addr <= dl_addr + 25'd1;
                if (dl_addr != next_addr) ordered <= 1'b0;
                if (ordered && dl_addr == next_addr) begin
                    if (dl_addr == 25'd255) begin
                        identified <= (~crc_next == GAIA_PREFIX) || (~crc_next == MYSTIC_PREFIX);
                        if (~crc_next == MYSTIC_PREFIX) mystic <= 1'b1;
                        else if (~crc_next == GAIA_PREFIX) mystic <= 1'b0;
                    end
                    valid <= identified &&
                        ((!mystic && dl_addr == GAIA_LAST && ~crc_next == GAIA_CRC) ||
                         (mystic && dl_addr == MYSTIC_LAST && ~crc_next == MYSTIC_CRC));
                end
            end
        end
    end
endmodule
`default_nettype wire
