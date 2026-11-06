//------------------------------------------------------------------------------
// K055550: the protection / helper chip at 0x25c000-0x25c03f of Violent Storm.
//
// Thirty-two 16-bit registers (readable: MAME's K055550_word_r returns what was
// written) and a command, a write to the high byte of register 0. MAME performs a
// command at once, in zero time (konamigx_m.cpp, K055550_word_w); this chip
// masters the main bus while it works and holds the 68000 (`busy`), so the
// program sees the result when its next instruction runs, as MAME's does.
//
//   0x97 / 0x9f  memset: fill (reg7:reg8) .. + (reg10:reg11) * ((reg0 & 0xff) + 1)
//                bytes with the word in reg 13
//   0x98         copy: (reg10:reg11) / 4 dwords, the dword at (reg2:reg3) + 8 x to
//                (reg7:reg8) + 4 x ("color check" palette, the service menu)
//   0xa0         collision list: (reg0 & 0xff) objects of (reg5:reg6) bytes at
//                (reg2:reg3), nine signed words each (centre, offset, size for x, y,
//                z); each object's hit list, at byte (reg1 >> 7), is cleared and
//                then gets 0x80 for every later object that overlaps it on all
//                three axes, one byte a later object in order
//   0xc0         homing vector: the direction (0..255) from the point (reg12, reg13)
//                (signed words) goes to reg 16
//   0x87         "unknown memory write" in MAME's source, which does nothing there;
//                nothing here (the game issues it every frame in play)
//
// The commands' arithmetic is MAME's, exactly (checked against it: sim/k550_ref.cpp
// for the homing vector over all 2^32 inputs; the rest by the whole-machine bench).
// The angle is floor(atan(|dy| / |dx|) * 128 / pi) taken the way MAME's `int angle =
// atan(dy / dx) * 128 / pi` truncates it, found by six steps of a bit search against
// the 63 tangents tan(k pi / 128) as 40-bit fractions (rtl/data/tan128.hex): a candidate
// angle k holds when |dy| * 2^40 >= |dx| * T[k].
//
// Bus master protocol (to the main board, rtl/vs_main.sv): m_we / m_a / m_be / m_wd
// are stable from two clocks before m_go (a one-clock strobe) until m_done
// (a one-clock pulse; for a read, m_rd is valid with it).
//------------------------------------------------------------------------------
// Pocket adaptation: pipeline collision arithmetic and homing compare/table
// selection for the 96MHz Pocket clock. Command results and master handshake
// are unchanged; busy includes the extra arithmetic cycles. Original upstream
// file/hash and source-bound negative fit are retained in M3 provenance.
`default_nettype none

module k055550 #(
    parameter string HEXDIR = "rtl/data"
) (
    input  logic        clk,
    input  logic        reset,

    // the 68000's register port
    input  logic        wr,              // a CPU write to the chip, one clock
    input  logic  [4:0] idx,             // register (word) index
    input  logic  [1:0] be,              // {uds, lds}
    input  logic [15:0] wdata,
    input  logic  [4:0] rd_idx,
    output logic [15:0] rd_q,
    output logic        busy,            // a command is running: hold the 68000

    // bus master
    output logic        m_go,
    output logic        m_we,
    output logic [23:1] m_a,
    output logic  [1:0] m_be,
    output logic [15:0] m_wd,
    input  logic        m_done,
    input  logic [15:0] m_rd
);
    logic [15:0] r [32];
    assign rd_q = r[rd_idx];

    // the tangents, T[k] = tan(k pi / 128) * 2^40 for k = 1..63 (0 at 0)
    logic [45:0] tan_tab [64];
    initial $readmemh({HEXDIR, "/tan128.hex"}, tan_tab);

    typedef enum logic [5:0] {
        S_IDLE, S_DEC,
        S_MS_ACC, S_MS_RUN,
        S_CP_INIT, S_CP_R0, S_CP_R1, S_CP_W0, S_CP_W1, S_CP_NEXT,
        S_CL_INIT, S_CL_SRC, S_CL_SRCW, S_CL_ZERO, S_CL_TGT, S_CL_TGTW, S_CL_DELTA, S_CL_TEST, S_CL_HIT, S_CL_NEXT,
        S_HM_INIT, S_HM_MUL, S_HM_CMP, S_HM_NEXT, S_HM_FIN,
        S_A1, S_A2, S_A3
    } st_t;
    st_t st, ret;

    logic        start;
    logic  [7:0] cmd;
    logic [15:0] acc_rd;                 // the last word read

    assign busy = start || (st != S_IDLE);

    // ------------------------------------------------ shared datapath state
    logic [31:0] adr, dst, bsz;
    logic [31:0] tot;                    // memset: byte count
    logic  [8:0] cnt;
    logic [31:0] cptr;                   // memset: running byte address
    logic [31:0] n_words;
    logic [23:0] src, tgt, hit, zcur, zend;
    logic  [8:0] skp;
    logic  [7:0] n_out, n_in;
    logic  [3:0] k;
    logic signed [15:0] so [9];
    logic signed [15:0] t3 [2];
    logic  [1:0] axis;
    logic [15:0] w_hi, w_lo;             // copy: the dword's two words

    // homing vector
    logic [15:0] lfsr = 16'hace1;
    logic        h_neg, h_dxneg;
    logic [15:0] h_a, h_b;
    logic  [5:0] h_q, h_cand;
    logic  [4:0] h_bit;
    logic [61:0] h_prod;
    logic [45:0] h_t;
    logic  [2:0] h_j;

    // Same signed axis rejection, split at sum/difference boundaries.
    logic signed [20:0] cl_source, cl_target, cl_width, cl_delta;
    wire signed [20:0] cl_absolute = cl_delta[20] ? -cl_delta : cl_delta;

    wire [15:0] hdx = r[12], hdy = r[13];

    always_ff @(posedge clk) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        m_go <= 1'b0;
        start <= 1'b0;

        if (reset) begin
            st <= S_IDLE; start <= 1'b0; m_go <= 1'b0; m_we <= 1'b0;
            for (int i = 0; i < 32; i++) r[i] <= '0;
        end else begin
            // the register file: byte lanes as written
            if (wr) begin
                if (be[1]) r[idx][15:8] <= wdata[15:8];
                if (be[0]) r[idx][7:0]  <= wdata[7:0];
                if (idx == 5'd0 && be[1]) begin start <= 1'b1; cmd <= wdata[15:8]; end
            end

            case (st)
                S_IDLE: if (start) st <= S_DEC;

                S_DEC: begin
                    case (cmd)
                        8'h97, 8'h9f: begin
                            adr <= {r[7], r[8]}; cnt <= {1'b0, r[0][7:0]} + 9'd1; tot <= '0; st <= S_MS_ACC;
                        end
                        8'h98: st <= S_CP_INIT;
                        8'ha0: st <= S_CL_INIT;
                        8'hc0: st <= S_HM_INIT;
                        default: st <= S_IDLE;           // 0x87 and anything unknown: no effect
                    endcase
                end

                // ---------------------------------------------------- memset
                // bytes = unit size x count by repeated addition (a few additions: 4 x 256 in play)
                S_MS_ACC: begin
                    if (cnt != 9'd0) begin tot <= tot + {r[10], r[11]}; cnt <= cnt - 9'd1; end
                    else begin
                        n_words <= (tot + 32'd1) >> 1; cptr <= adr;
                        st <= (tot == 32'd0) ? S_IDLE : S_MS_RUN;
                    end
                end
                S_MS_RUN: begin
                    m_we <= 1'b1; m_a <= cptr[23:1]; m_be <= 2'b11; m_wd <= r[13];
                    cptr <= cptr + 32'd2; n_words <= n_words - 32'd1;
                    ret <= (n_words == 32'd1) ? S_IDLE : S_MS_RUN; st <= S_A1;
                end

                // ------------------------------------------------------ copy
                S_CP_INIT: begin
                    adr <= {r[2], r[3]}; dst <= {r[7], r[8]}; n_words <= {r[10], r[11]} >> 2;    // dwords
                    st <= (({r[10], r[11]} >> 2) == 32'd0) ? S_IDLE : S_CP_R0;
                end
                S_CP_R0: begin m_we <= 1'b0; m_a <= adr[23:1]; m_be <= 2'b11; ret <= S_CP_R1; st <= S_A1; end
                S_CP_R1: begin
                    w_hi <= acc_rd; m_we <= 1'b0; m_a <= adr[23:1] + 23'd1; m_be <= 2'b11; ret <= S_CP_W0; st <= S_A1;
                end
                S_CP_W0: begin
                    w_lo <= acc_rd;
                    m_we <= 1'b1; m_a <= dst[23:1]; m_be <= 2'b11; m_wd <= w_hi; ret <= S_CP_W1; st <= S_A1;
                end
                S_CP_W1: begin
                    m_we <= 1'b1; m_a <= dst[23:1] + 23'd1; m_be <= 2'b11; m_wd <= w_lo; ret <= S_CP_NEXT; st <= S_A1;
                end
                S_CP_NEXT: begin
                    adr <= adr + 32'd8; dst <= dst + 32'd4; n_words <= n_words - 32'd1;
                    st <= (n_words == 32'd1) ? S_IDLE : S_CP_R0;
                end

                // ----------------------------------------------- collision list
                // n_out objects are left to take as sources (the count in reg 0 low); the k-th (0-based) has
                // count - k later objects as targets, which is n_out again
                S_CL_INIT: begin
                    n_out <= r[0][7:0]; skp <= r[1][15:7];
                    src <= {r[2][7:0], r[3]};
                    bsz <= {r[5], r[6]};
                    k <= 4'd0;
                    st <= (r[0][7:0] == 8'd0 || {r[5], r[6]} == 32'd0) ? S_IDLE : S_CL_SRC;
                end
                // the source object's nine words
                S_CL_SRC: begin
                    m_we <= 1'b0; m_a <= src[23:1] + 23'(k); m_be <= 2'b11; ret <= S_CL_SRCW; st <= S_A1;
                end
                S_CL_SRCW: begin
                    so[k] <= acc_rd;
                    if (k == 4'd8) begin
                        k <= 4'd0;
                        hit <= src + 24'(skp);
                        zcur <= src + 24'(skp); zend <= src + bsz[23:0];
                        st <= S_CL_ZERO;
                    end else begin k <= k + 4'd1; st <= S_CL_SRC; end
                end
                // clear the hit list: bytes [src + skip, src + bsize)
                S_CL_ZERO: begin
                    if (zcur >= zend) begin
                        tgt <= src + bsz[23:0]; n_in <= n_out; axis <= 2'd0; k <= 4'd0;
                        st <= S_CL_TGT;
                    end else begin
                        m_we <= 1'b1; m_a <= zcur[23:1]; m_wd <= 16'h0000;
                        if (zcur[0] || (zend - zcur) == 24'd1) begin
                            m_be <= zcur[0] ? 2'b01 : 2'b10; zcur <= zcur + 24'd1;
                        end else begin
                            m_be <= 2'b11; zcur <= zcur + 24'd2;
                        end
                        ret <= S_CL_ZERO; st <= S_A1;
                    end
                end
                // the target's triple for the current axis
                S_CL_TGT: begin
                    m_we <= 1'b0; m_a <= tgt[23:1] + 23'(axis * 3) + 23'(k); m_be <= 2'b11; ret <= S_CL_TGTW; st <= S_A1;
                end
                S_CL_TGTW: begin
                    if (k[1:0] == 2'd2) begin
                        // The triple is (t3[0],t3[1],acc_rd). Register sums
                        // before the subtract/absolute/compare chain.
                        k <= 4'd0;
                        cl_source <= 21'(so[axis * 3]) + 21'(so[axis * 3 + 1]);
                        cl_target <= 21'(t3[0]) + 21'(t3[1]);
                        cl_width <= 21'(so[axis * 3 + 2]) + 21'($signed(acc_rd));
                        st <= S_CL_DELTA;
                    end else begin
                        t3[k[0]] <= $signed(acc_rd);
                        k <= k + 4'd1; st <= S_CL_TGT;
                    end
                end
                S_CL_DELTA: begin cl_delta <= cl_source-cl_target; st <= S_CL_TEST; end
                S_CL_TEST: begin
                    if (cl_absolute >= cl_width) st <= S_CL_NEXT;
                    else if (axis == 2'd2) st <= S_CL_HIT;
                    else begin axis <= axis + 2'd1; st <= S_CL_TGT; end
                end
                // collision confirmed: the byte at the hit list's current place becomes 0x80
                S_CL_HIT: begin
                    m_we <= 1'b1; m_a <= hit[23:1]; m_wd <= 16'h8080; m_be <= hit[0] ? 2'b01 : 2'b10;
                    ret <= S_CL_NEXT; st <= S_A1;
                end
                // the next target, or the next source object
                S_CL_NEXT: begin
                    tgt <= tgt + bsz[23:0]; hit <= hit + 24'd1; n_in <= n_in - 8'd1; axis <= 2'd0; k <= 4'd0;
                    if (n_in == 8'd1) begin
                        src <= src + bsz[23:0]; n_out <= n_out - 8'd1;
                        st <= (n_out == 8'd1) ? S_IDLE : S_CL_SRC;
                    end else st <= S_CL_TGT;
                end

                // ------------------------------------------------ homing vector
                S_HM_INIT: begin
                    if (hdx == 16'd0) begin
                        r[16] <= (hdy[15] ? 16'h0080 : (hdy == 16'd0) ? {8'h00, lfsr[7:0]} : 16'h0000);
                        st <= S_IDLE;
                    end else if (hdy == 16'd0) begin
                        r[16] <= hdx[15] ? 16'h0040 : 16'h00c0;
                        st <= S_IDLE;
                    end else begin
                        h_a <= hdy[15] ? -hdy : hdy;                // |dy|, up to 32768: 16 bits unsigned
                        h_b <= hdx[15] ? -hdx : hdx;
                        h_dxneg <= hdx[15]; h_neg <= hdx[15] ^ hdy[15];
                        h_q <= 6'd0; h_j <= 3'd5; st <= S_HM_MUL;
                        h_cand <= 6'd32;                            // the first candidate: bit 5
                        h_prod <= '0; h_bit <= 5'd0;
                        h_t <= tan_tab[6'd32];
                    end
                end
                // |dx| x T[cand] by shift-add, 16 clocks, against |dy| << 40
                S_HM_MUL: begin
                    if (h_b[h_bit[3:0]]) h_prod <= h_prod + (62'(h_t) << h_bit[3:0]);
                    if (h_bit == 5'd15) st <= S_HM_CMP; else h_bit <= h_bit + 5'd1;
                end
                S_HM_CMP: begin
                    if ((62'(h_a) << 40) >= h_prod) h_q <= h_cand;
                    st <= S_HM_NEXT;
                end
                S_HM_NEXT: begin
                    logic [5:0] c_n;
                    c_n = h_q | (6'd1 << (h_j - 3'd1));
                    if (h_j == 3'd0) st <= S_HM_FIN;
                    else begin
                        h_j <= h_j - 3'd1;
                        h_cand <= c_n;
                        h_t <= tan_tab[c_n];
                        h_prod <= '0; h_bit <= 5'd0; st <= S_HM_MUL;
                    end
                end
                S_HM_FIN: begin
                    logic signed [9:0] ang;
                    ang = h_neg ? -$signed({4'd0, h_q}) : $signed({4'd0, h_q});
                    if (h_dxneg) ang = ang + 10'sd128;
                    r[16] <= {8'h00, 8'(ang - 10'sd64)};
                    st <= S_IDLE;
                end

                // --------------------------- one bus access: m_* set, then the strobe, then done
                S_A1: st <= S_A2;
                S_A2: begin m_go <= 1'b1; st <= S_A3; end
                S_A3: if (m_done) begin
                    if (!m_we) acc_rd <= m_rd;
                    st <= ret;
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
