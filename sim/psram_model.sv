// Behavioural Pocket PSRAM (CellularRAM, 16-bit, async mode, one die): the
// address is taken from the address pins and the data bus while ADV# is low;
// a read drives the data TAA clocks after that (inverted data before, so an
// early sample shows up as a mismatch); a write takes the data bus while WE#
// is low, byte lanes per UB#/LB#. Only die 0 (CE0#) is modelled.
`default_nettype none
module psram_model #(parameter int TAA = 7) (
    input  logic        clk,
    input  logic [21:16] a,
    inout  wire  [15:0] dq,
    input  logic        adv_n, ce0_n, oe_n, we_n, ub_n, lb_n
);
    logic [15:0] mem [4194304] /*verilator public_flat_rw*/;
    logic [21:0] addr_l;
    logic  [4:0] tcnt;
    always_ff @(posedge clk) begin
        if (!ce0_n && !adv_n) begin addr_l <= {a, dq}; tcnt <= '0; end
        else if (tcnt != 5'd31) tcnt <= tcnt + 5'd1;
        if (!ce0_n && !we_n && adv_n) begin
            if (!ub_n) mem[addr_l][15:8] <= dq[15:8];
            if (!lb_n) mem[addr_l][7:0]  <= dq[7:0];
        end
    end
    wire drive = !ce0_n && !oe_n && we_n && adv_n;
    // +PSDBG: trace the first accesses on the pins
    int dbg_n;
    initial dbg_n = 0;
    logic we_d;
    always_ff @(posedge clk) begin
        we_d <= we_n;
        if ($test$plusargs("PSDBG") && dbg_n < 60 && (!ce0_n || !we_d)) begin
            dbg_n <= dbg_n + 1;
            $display("%m ce0=%b adv=%b oe=%b we=%b ub=%b lb=%b a=%h dq=%h addr_l=%h tcnt=%0d drive=%b mem=%h",
                     ce0_n, adv_n, oe_n, we_n, ub_n, lb_n, a, dq, addr_l, tcnt, drive, mem[addr_l]);
        end
    end
    assign dq = drive ? ((tcnt >= 5'(TAA)) ? mem[addr_l] : ~mem[addr_l]) : 16'bz;
endmodule
