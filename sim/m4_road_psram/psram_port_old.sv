// Frozen old port, extracted without behavior changes; original gaia_mem hash in private archive.
`default_nettype none
module psram_port_old (
    input  logic        clk,
    input  logic        reset,
    input  logic        slow,
    input  logic        r0_req, input  logic [22:0] r0_addr, output logic r0_ack, output logic [15:0] r0_q,
    input  logic        r1_req, input  logic [22:0] r1_addr, output logic r1_ack, output logic [15:0] r1_q,
    input  logic        w_req,  input  logic [22:0] w_addr,  input  logic [15:0] w_data, input logic [1:0] w_be,
    output logic        w_ack,

    output logic [21:16] cram_a,
    inout  wire  [15:0] cram_dq,
    input  logic        cram_wait,
    output logic        cram_clk, cram_adv_n, cram_cre, cram_ce0_n, cram_ce1_n, cram_oe_n, cram_we_n, cram_ub_n, cram_lb_n
);
    typedef enum logic [1:0] { P_IDLE, P_READ, P_WRITE } pst_t;
    pst_t        pst;
    logic  [1:0] who;                   // the read in flight: 0 reader 0, 1 reader 1, 2 prefetch
    logic        last;                  // the reader served last, for the alternation
    logic [22:0] addr_l;
    logic [15:0] wdata_l;
    logic  [1:0] be_l;
    logic        rd_en, wr_en, busy, avail;
    logic [15:0] dout;
    // reader 1's cache: c1 the word last fetched, c2 the word after it
    logic        c1_valid, c2_valid, pf_want;
    logic [22:0] c1_addr, c2_addr, pf_addr;
    logic [15:0] c1_q, c2_q;

    // Reader 1's request and address are taken through a register first: the
    // cache compares below then start from registers instead of the platform's
    // request mux (0.28 ns of slack at 96 MHz otherwise). The client sees its
    // ack a clock later, and drops its request a clock later still, so a
    // request being acked stays masked for two clocks.
    logic        r1_req_r, r1_ack_d;
    logic [22:0] r1_addr_r;
    always_ff @(posedge clk) begin r1_req_r <= r1_req; r1_addr_r <= r1_addr; r1_ack_d <= r1_ack; end
    // A request is still standing in the clock its ack is visible (the client
    // drops it on seeing the ack), so a request being acked is not a new one.
    wire r1_pend = r1_req_r && !r1_ack && !r1_ack_d;
    wire hit1a = r1_pend && c1_valid && (r1_addr_r == c1_addr);
    wire hit1b = r1_pend && c2_valid && (r1_addr_r == c2_addr);
    wire hit1  = hit1a || hit1b;
    wire pend0 = r0_req && !r0_ack;
    wire pend1 = r1_pend && !hit1;
    wire pick0 = pend0 && (!pend1 || last);
    wire pick1 = pend1 && !pick0;

    always_ff @(posedge clk) begin
        r0_ack <= 1'b0; r1_ack <= 1'b0; w_ack <= 1'b0;
        rd_en <= 1'b0; wr_en <= 1'b0;
        if (reset) begin pst <= P_IDLE; c1_valid <= 1'b0; c2_valid <= 1'b0; pf_want <= 1'b0; last <= 1'b0; end
        else begin
            // a cache hit costs no access and is served in any state except
            // while reader 1's own fetch is in flight; moving on to the
            // prefetched word asks for the one after it
            if (hit1 && !(pst == P_READ && who == 2'd1)) begin
                r1_ack <= 1'b1; r1_q <= hit1a ? c1_q : c2_q;
                if (!hit1a) begin
                    c1_valid <= 1'b1; c1_addr <= c2_addr; c1_q <= c2_q;
                    pf_want <= 1'b1; pf_addr <= c2_addr + 23'd1;
                end
            end
            case (pst)
                P_IDLE: if (!busy && !rd_en && !wr_en) begin
                    if (w_req && !w_ack) begin
                        addr_l <= w_addr; wdata_l <= w_data; be_l <= w_be;
                        wr_en <= 1'b1; w_ack <= 1'b1; c1_valid <= 1'b0; c2_valid <= 1'b0; pf_want <= 1'b0;
                        pst <= P_WRITE;
                    end else if (pick0) begin
                        who <= 2'd0; addr_l <= r0_addr; rd_en <= 1'b1; last <= 1'b0; pst <= P_READ;
                    end else if (pick1) begin
                        who <= 2'd1; addr_l <= r1_addr_r; rd_en <= 1'b1; last <= 1'b1; pst <= P_READ;
                    end else if (pf_want) begin
                        who <= 2'd2; addr_l <= pf_addr; rd_en <= 1'b1; pf_want <= 1'b0; pst <= P_READ;
                    end
                end
                P_READ: if (avail) begin
                    case (who)
                        2'd0: if (r0_req && r0_addr == addr_l) begin r0_ack <= 1'b1; r0_q <= dout; end
                        2'd1: begin
                            if (r1_req_r && r1_addr_r == addr_l) begin r1_ack <= 1'b1; r1_q <= dout; end
                            c1_valid <= 1'b1; c1_addr <= addr_l; c1_q <= dout;
                            pf_want <= 1'b1; pf_addr <= addr_l + 23'd1;
                        end
                        default: begin c2_valid <= 1'b1; c2_addr <= addr_l; c2_q <= dout; end
                    endcase
                    pst <= P_IDLE;
                end
                P_WRITE: if (!busy && !wr_en) pst <= P_IDLE;     // busy rises the cycle after the issue
                default: pst <= P_IDLE;
            endcase
        end
    end

    // 96 MHz timings: the SNES core's controller with the access times padded
    // to 85 ns for the pin delays on top of the part's 70 ns: reads capture 9
    // clocks (94 ns) after the address strobe. The SNES core captures at
    // 81.5 ns (7 clocks of 85.9 MHz); 80 here would give 8 clocks (83 ns) and
    // an 11-clock access, to be tried with the memory test as the judge.
    psram #(
        .CLOCK_SPEED(96.0),
        .MAX_ACCESS_TIME_FROM_ADV(85),
        .MIN_WRITE_TIME_FROM_ADV(85)
    ) u_psram (
        .clk(clk),
        .bank_sel(addr_l[22]), .addr(addr_l[21:0]),
        .write_en(wr_en), .data_in(wdata_l), .write_high_byte(be_l[1]), .write_low_byte(be_l[0]),
        .read_en(rd_en), .slow(slow), .read_avail(avail), .data_out(dout), .busy(busy),
        .cram_a(cram_a), .cram_dq(cram_dq), .cram_wait(cram_wait), .cram_clk(cram_clk), .cram_adv_n(cram_adv_n),
        .cram_cre(cram_cre), .cram_ce0_n(cram_ce0_n), .cram_ce1_n(cram_ce1_n), .cram_oe_n(cram_oe_n),
        .cram_we_n(cram_we_n), .cram_ub_n(cram_ub_n), .cram_lb_n(cram_lb_n)
    );
endmodule
`default_nettype wire
