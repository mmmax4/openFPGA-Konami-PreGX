// Verification-owned four-state pin timing gate for AS4C32M16MSA CL2/CL3/BL1.
// Actual sdram_ctrl ports and handshake; original ROM words are read-only.
`timescale 1ps/1ps
module tb_sdram_phase;
    localparam integer T = 10410, HALF = 5205;
    localparam integer BASE = 'h8000, WORDS = 4096;
    reg clk = 0, clk_pin = 0, init = 1;
    integer phase_ps = 6120, out_ps = 0, release_late = 0, input_ps = 0, board_ps = 0;
    reg rd_late = 1, burst_slow = 0;
    wire ready;
    tri [15:0] dq;
    wire [12:0] a;
    wire [1:0] ba;
    wire dqml, dqmh, ncs, nwe, nras, ncas, cke, pin_clock;
    reg [24:1] addr_drive [6];
    reg [5:0] req_drive = 0;
    wire [24:1] c_addr [6];
    wire c_req [6], c_we [6];
    wire [15:0] c_wdata [6];
    wire [1:0] c_be [6];
    genvar g;
    generate for (g=0; g<6; g=g+1) begin : client_pins
        assign c_addr[g] = addr_drive[g];
        assign c_req[g] = req_drive[g];
        assign c_we[g] = 1'b0;
        assign c_wdata[g] = 16'd0;
        assign c_be[g] = 2'b11;
    end endgenerate
    wire c_ack [0:5];
    wire [15:0] rdata;
    reg [24:1] b_addr = BASE;
    reg [9:0] b_len = 0;
    reg b_req = 0, b_abort = 0;
    wire b_wr, b_done;
    wire [9:0] b_idx, b_widx;
    wire [15:0] b_data;
    sdram_ctrl dut (
        .clk(clk), .clk_pin(clk_pin), .init(init), .rd_late(rd_late),
        .burst_slow(burst_slow), .ready(ready), .SDRAM_DQ(dq),
        .SDRAM_A(a), .SDRAM_DQML(dqml), .SDRAM_DQMH(dqmh), .SDRAM_BA(ba),
        .SDRAM_nCS(ncs), .SDRAM_nWE(nwe), .SDRAM_nRAS(nras), .SDRAM_nCAS(ncas),
        .SDRAM_CKE(cke), .SDRAM_CLK(pin_clock), .c_addr(c_addr), .c_req(c_req),
        .c_we(c_we), .c_wdata(c_wdata), .c_be(c_be), .c_ack(c_ack), .rdata(rdata),
        .b_addr(b_addr), .b_len(b_len), .b_req(b_req), .b_abort(b_abort),
        .b_wr(b_wr), .b_idx(b_idx), .b_data(b_data), .b_done(b_done),
        .b_we(1'b0), .b_wdata(16'd0), .b_be(2'b11), .b_widx(b_widx)
    );
    initial begin
        if (!$value$plusargs("PHASE=%d", phase_ps)) phase_ps = 6120;
        if (!$value$plusargs("OUT_PS=%d", out_ps)) out_ps = 0;
        if (!$value$plusargs("RELEASE_LATE=%d", release_late)) release_late = 0;
        if (!$value$plusargs("INPUT_PS=%d", input_ps)) input_ps = 0;
        if (!$value$plusargs("BOARD_PS=%d", board_ps)) board_ps = 0;
        if (!$value$plusargs("RD_LATE=%d", rd_late)) rd_late = 1;
        if (!$value$plusargs("SLOW=%d", burst_slow)) burst_slow = 0;
    end
    // Same positive edges as the actual DDR clock carrier. Commands are
    // sampled phase_ps after the source positive edge, not one whole T later.
    initial forever begin #HALF; clk = 1; #(T-HALF); clk = 0; end
    initial begin
        #(HALF); #(phase_ps); clk_pin = 1;
        forever begin #(T-HALF); clk_pin = 0; #HALF; clk_pin = 1; end
    end
    // External pin propagation, excluding the clock pin (clock skew remains
    // an explicit limit of this gate). Variable delay captures source values.
    reg [21:0] chip_ctrl;
    wire [21:0] source_ctrl = {cke,ncs,nras,ncas,nwe,ba,a,dqmh,dqml};
    always @(source_ctrl) chip_ctrl <= #(out_ps) source_ctrl;
    wire chip_cke = chip_ctrl[21], chip_ncs = chip_ctrl[20];
    wire [2:0] chip_command = chip_ctrl[19:17];
    wire [1:0] chip_ba = chip_ctrl[16:15];
    wire [12:0] chip_a = chip_ctrl[14:2];
    // DQM is omitted from read timing: controller READ commands set it low.
    reg [15:0] seed [0:WORDS-1];
    reg [12:0] open_row [0:3];
    reg bank_open [0:3];
    reg [15:0] chip_dq = 16'hzzzz;
    reg [15:0] propagated_dq = 16'hzzzz;
    always @(chip_dq) propagated_dq <= #(input_ps) chip_dq;
    assign dq = propagated_dq;
    integer reads = 0, protocol_errors = 0, input_setup_errors = 0;
    integer input_hold_errors = 0, read_expected = 0, mismatches = 0;
    integer z_responses = 0, x_responses = 0, singles = 0, burst_words = 0;
    integer burst_done_count = 0, burst_expected = 0, next_index = 0;
    integer mode_unknown_errors=0, mode_value_errors=0, mr_seen=0, emr_seen=0;
    integer startup_delay_errors=0, missing_mode_errors=0;
    integer cas_latency = 3, clock_period_errors = 0;
    reg mode_programmed = 0;
    time previous_pin_edge = 0;
    time init_release = 0;
    always @(negedge init) init_release = $time;
    always @(posedge ready) begin
        if ($time-init_release < 200000000) startup_delay_errors++;
        if (!mr_seen) missing_mode_errors++;
        if (!emr_seen) missing_mode_errors++;
    end
    reg outstanding [0:5];
    reg [24:1] expected_addr [0:5];
    reg [24:1] active_burst_addr;
    reg collecting_burst = 0;
    time last_ctrl_change = 0, last_chip_edge = 0;
    reg timing_active = 0;
    always @(chip_ctrl) begin
        if (timing_active && $time-last_chip_edge < 1000) input_hold_errors++;
        last_ctrl_change = $time;
    end
    task automatic drive_read(input [15:0] word_data);
        // Latency follows the actual MR command: CL2 tAC=6ns, CL3=5.5ns.
        // tAC is measured from READ+(CL-1), hold from READ+CL.
        chip_dq <= #((cas_latency-1)*T+(cas_latency==3 ? 5500:6000)+board_ps) word_data;
        if (release_late) begin
            chip_dq <= #(cas_latency*T+2500) 16'hxxxx;
            chip_dq <= #(cas_latency*T+6000) 16'hzzzz;
        end else chip_dq <= #(cas_latency*T+2500) 16'hzzzz;
    endtask
    // This exact delayed pin event model permits independent overlapping
    // READ windows. BL1 commands are spaced >=2T, so output windows never
    // overlap, even with latest tHZ=6ns.
    integer model_word;
    always @(posedge pin_clock) begin
        if (mode_programmed && previous_pin_edge != 0 &&
            $time-previous_pin_edge < (cas_latency==2 ? 12000:6000)) clock_period_errors++;
        previous_pin_edge = $time;
        last_chip_edge = $time;
        if (timing_active && $time-last_ctrl_change < 2000) input_setup_errors++;
        timing_active = 1;
        if (chip_cke && !chip_ncs) begin
            case (chip_command)
                3'b011: begin open_row[chip_ba] = chip_a; bank_open[chip_ba] = 1; end
                3'b101: begin
                    if (!bank_open[chip_ba]) protocol_errors++;
                    model_word = (chip_ba << 22) + (open_row[chip_ba] << 9) + chip_a[8:0];
                    if (model_word < BASE || model_word >= BASE+WORDS) begin
                        $display("MODEL address outside original slice %0d", model_word); protocol_errors++;
                    end else begin
                        reads++;
                        drive_read(seed[model_word-BASE]);
                    end
                    if (chip_a[10]) bank_open[chip_ba] = 0;
                end
                3'b010: begin
                    if (chip_a[10]) for (int i=0; i<4; i++) bank_open[i] = 0;
                    else bank_open[chip_ba] = 0;
                end
                3'b000: begin
                    if ((^chip_ba) === 1'bx || (^chip_a) === 1'bx) mode_unknown_errors++;
                    else if (chip_ba==0) begin
                        mr_seen++;
                        if (chip_a !== 13'h220 && chip_a !== 13'h230) mode_value_errors++;
                        else begin cas_latency = chip_a[6:4]; mode_programmed = 1; end
                    end else if (chip_ba==2) begin
                        emr_seen++;
                        if (chip_a !== 13'h000) mode_value_errors++;
                    end else mode_value_errors++;
                end
                3'b100: protocol_errors++; // all test requests are reads
                default: ;
            endcase
        end
    end
    task automatic check_word(input [15:0] got, input integer address, input string who);
        if (got !== seed[address-BASE]) begin
            mismatches++;
            if (got === 16'hzzzz) z_responses++;
            else if ((^got) === 1'bx) x_responses++;
            if (mismatches <= 8) $display("MISMATCH %s word%0d got%h expected%h at%0t",who,address,got,seed[address-BASE],$time);
        end
    endtask
    // Consumers sample after NBA at the actual system clock and only on ACK.
    always @(posedge clk) begin
        #1;
        for (int i=0; i<6; i++) if (c_ack[i]) begin
            if (!outstanding[i]) protocol_errors++;
            else begin
                check_word(rdata, expected_addr[i], "single"); singles++;
                outstanding[i] = 0;
            end
        end
        if (b_wr) begin
            if (!collecting_burst || b_idx !== next_index[9:0]) protocol_errors++;
            check_word(b_data, active_burst_addr+b_idx, "burst");
            next_index++; burst_words++;
        end
        if (b_done) begin
            if (!collecting_burst || next_index != burst_expected) protocol_errors++;
            collecting_burst = 0; burst_done_count++;
        end
    end
    task automatic issue_single(input integer cli, input integer address);
        addr_drive[cli] = address; expected_addr[cli] = address;
        req_drive[cli] = 1; outstanding[cli] = 1; read_expected++;
    endtask
    task automatic wait_singles;
        integer active;
        begin : waiting
            forever begin
                @(negedge clk); active = 0;
                for (int i=0; i<6; i++) begin
                    if (!outstanding[i]) req_drive[i] = 0;
                    else active++;
                end
                if (active == 0) disable waiting;
            end
        end
    endtask
    task automatic burst(input integer address, input integer count, input integer mixed);
        @(negedge clk);
        active_burst_addr = address; burst_expected = count; next_index = 0;
        collecting_burst = 1; b_addr = address; b_len = count; b_req = 1;
        read_expected += count;
        if (mixed) for (int i=0; i<6; i++) issue_single(i, BASE+600+i);
        begin : waiting_burst
            forever begin
                @(negedge clk);
                for (int i=0; i<6; i++) if (!outstanding[i]) req_drive[i] = 0;
                if (!collecting_burst) disable waiting_burst;
            end
        end
        b_req = 0; wait_singles; repeat(3) @(negedge clk);
    endtask
    initial begin
        $readmemh("seed.hex", seed);
        for (int i=0; i<4; i++) begin bank_open[i] = 0; open_row[i] = 0; end
        for (int i=0; i<6; i++) begin
            req_drive[i]=0; addr_drive[i]=BASE;
            outstanding[i]=0; expected_addr[i]=BASE;
        end
        repeat(4) @(negedge clk); init = 0;
        wait(ready); $display("READY at %0t", $time); repeat(4) @(negedge clk);
        for (int i=0; i<6; i++) begin
            issue_single(i, BASE+200+i); wait_singles; repeat(2) @(negedge clk);
        end
        burst(BASE+32,2,0); burst(BASE+64,4,0);
        burst(BASE+96,32,1); burst(BASE+496,32,0);
        repeat(6) @(negedge clk);
        $display("RESULT_JSON {\"data_passed\":%s,\"initialization_passed\":%s,\"clock_passed\":%s,\"phase_ps\":%0d,\"out_ps\":%0d,\"input_ps\":%0d,\"board_ps\":%0d,\"rd_late\":%0d,\"slow\":%0d,\"release_late\":%0d,\"reads\":%0d,\"expected_reads\":%0d,\"singles\":%0d,\"burst_words\":%0d,\"bursts\":%0d,\"mismatches\":%0d,\"z_responses\":%0d,\"x_responses\":%0d,\"protocol_errors\":%0d,\"input_setup_errors\":%0d,\"input_hold_errors\":%0d,\"mr_seen\":%0d,\"emr_seen\":%0d,\"mode_unknown_errors\":%0d,\"mode_value_errors\":%0d,\"startup_delay_errors\":%0d,\"missing_mode_errors\":%0d,\"cas_latency\":%0d,\"clock_period_errors\":%0d}",
            (mismatches==0 && protocol_errors==0 && input_setup_errors==0 && input_hold_errors==0 && reads==read_expected) ? "true":"false",
            (mode_unknown_errors==0 && mode_value_errors==0 && startup_delay_errors==0 && missing_mode_errors==0 && mr_seen>0 && emr_seen>0) ? "true":"false",
            clock_period_errors==0 ? "true":"false",
            phase_ps,out_ps,input_ps,board_ps,rd_late,burst_slow,release_late,reads,read_expected,singles,burst_words,burst_done_count,
            mismatches,z_responses,x_responses,protocol_errors,input_setup_errors,input_hold_errors,mr_seen,emr_seen,mode_unknown_errors,mode_value_errors,startup_delay_errors,missing_mode_errors,cas_latency,clock_period_errors);
        if (mismatches || protocol_errors || input_setup_errors || input_hold_errors || reads!=read_expected || mode_unknown_errors || mode_value_errors || startup_delay_errors || missing_mode_errors || clock_period_errors)
            $fatal(1,"SDRAM phase consumer mismatch");
        $display("PASS SDRAM phase consumer"); $finish;
    end
    initial begin #500000000;
        $display("WATCHDOG ready=%b req=%b c_req0=%b ackport=%b reads=%0d singles=%0d burstwords=%0d protocol=%0d",ready,req_drive,c_req[0],{c_ack[5],c_ack[4],c_ack[3],c_ack[2],c_ack[1],c_ack[0]},reads,singles,burst_words,protocol_errors);
        $fatal(1,"watchdog 500us");
    end
endmodule
