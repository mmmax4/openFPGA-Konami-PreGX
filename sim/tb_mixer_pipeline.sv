// Verification-owned public-interface gate. No hierarchical DUT state reads.
// Palette read and read-before-write NBA ordering match gaia_main.sv's
// pal0/pal1 synchronous port. Latency=2 is an intentional consumer-negative.
`timescale 1ns/1ps
module tb_mixer_pipeline;
    logic clk = 0, reset = 1, cen_pix = 0;
    logic [11:0] tm_pen [4], roz_pen, spr_pen;
    logic [3:0] tm_opq;
    logic roz_opq, spr_opq, spr_shadow, roz_enable;
    logic [7:0] spr_pri, spr_shpri, k55regs [48];
    logic [1:0] spr_shtab;
    logic [15:0] k38regs [16];
    wire [10:0] addr_new, addr_old;
    wire [23:0] rgb_new, rgb_old;
    logic [23:0] palette [2048], pipe_new [2], pipe_old [2];
    logic cpu_we = 0;
    logic [10:0] cpu_addr = 0;
    logic [23:0] cpu_data = 0;
    integer latency = 1, errors = 0, stable_cases = 0, dynamic_cases = 0;
    integer old_dynamic_differences = 0, pixel_checks = 0, hold_checks = 0;
    wire [23:0] pal_new = pipe_new[latency-1], pal_old = pipe_old[latency-1];
    always_ff @(posedge clk) begin
        pipe_new[0] <= palette[addr_new];
        pipe_old[0] <= palette[addr_old];
        pipe_new[1] <= pipe_new[0];
        pipe_old[1] <= pipe_old[0];
        if (cpu_we) palette[cpu_addr] <= cpu_data;
    end

    k055555_mixer dut (
        .clk(clk), .reset(reset), .cen_pix(cen_pix),
        .tm_pen(tm_pen), .tm_opq(tm_opq), .roz_pen(roz_pen), .roz_opq(roz_opq),
        .spr_opq(spr_opq), .spr_pen(spr_pen), .spr_pri(spr_pri),
        .spr_shadow(spr_shadow), .spr_shtab(spr_shtab), .spr_shpri(spr_shpri),
        .k55regs(k55regs), .k38regs(k38regs), .roz_enable(roz_enable),
        .pal_addr(addr_new), .pal_q(pal_new), .rgb(rgb_new)
    );
    k055555_mixer_original ordinary_reference (
        .clk(clk), .reset(reset), .cen_pix(cen_pix),
        .tm_pen(tm_pen), .tm_opq(tm_opq), .roz_pen(roz_pen), .roz_opq(roz_opq),
        .spr_opq(spr_opq), .spr_pen(spr_pen), .spr_pri(spr_pri),
        .spr_shadow(spr_shadow), .spr_shtab(spr_shtab), .spr_shpri(spr_shpri),
        .k55regs(k55regs), .k38regs(k38regs), .roz_enable(roz_enable),
        .pal_addr(addr_old), .pal_q(pal_old), .rgb(rgb_old)
    );
    task automatic tick;
        #5; clk = 1; #5; clk = 0;
    endtask
    task automatic fault(input string label);
        $display("FAIL %s", label); errors++;
    endtask
    task automatic defaults;
        for (int i = 0; i < 48; i++) k55regs[i] = 0;
        for (int i = 0; i < 16; i++) k38regs[i] = 0;
        tm_pen[0] = 16; tm_pen[1] = 32; tm_pen[2] = 80; tm_pen[3] = 96;
        tm_opq = 15; roz_pen = 64; roz_opq = 1; roz_enable = 1;
        spr_pen = 48; spr_opq = 1; spr_pri = 60;
        spr_shadow = 0; spr_shtab = 0; spr_shpri = 0;
        k55regs[45] = 8'h3f;
        k55regs[7] = 10; k55regs[10] = 20; k55regs[13] = 30;
        k55regs[14] = 40; k55regs[16] = 50;
        k38regs[0] = 16'h11; k38regs[1] = 16'h2233;
        cpu_we = 0;
    endtask
    // mode 1 changes pens and MMIO AFTER the fixed phase-2 snapshot;
    // mode 2 changes them BEFORE it; mode 3 writes the selected palette
    // at tick 7, preserving the palette's read-before-write value at phase 7.
    task automatic pixel(input string label, input logic [23:0] expected,
                         input logic [10:0] expected_addr, input int mode);
        logic [23:0] before_rgb;
        before_rgb = rgb_new;
        for (int cycle = 0; cycle < 12; cycle++) begin
            cen_pix = (cycle == 0);
            if (mode == 1 && cycle == 4) begin
                k55regs[45] = 0;
                k38regs[0] = 16'hfe; k38regs[1] = 16'hdcba;
                k38regs[2] = 100; k38regs[3] = 100; k38regs[4] = 100;
                k38regs[15] = 16'h20;
                tm_pen[0] = 32; roz_pen = 32; spr_pen = 32;
                spr_pri = 0; spr_shpri = 255; spr_shtab = 3;
            end
            if (mode == 2 && cycle == 2) begin
                k55regs[45] = 8'h02; k55regs[10] = 1;
                tm_pen[1] = 32;
            end
            if (mode == 3 && cycle == 7) begin
                cpu_we = 1; cpu_addr = 16; cpu_data = 24'habcdef;
            end else cpu_we = 0;
            tick();
            if (cycle < 10) begin
                if (rgb_new !== before_rgb) fault({label, ": RGB changed before phase-9 capture"});
                hold_checks++;
            end
            if (cycle == 6 && addr_new !== expected_addr)
                fault({label, ": phase-5 palette address wrong"});
            if (cycle == 10) begin
                pixel_checks++;
                if (rgb_new !== expected) begin
                    $display("FAIL %s got %06x expected %06x (palette latency %0d)",
                             label, rgb_new, expected, latency); errors++;
                end
                if (mode == 0 || mode == 2) begin
                    if (rgb_old !== expected) fault({label, ": unchanged ordinary original output differs"});
                    if (rgb_new !== rgb_old) fault({label, ": new/old ordinary mismatch"});
                end else if (rgb_old !== expected) old_dynamic_differences++;
            end
            if (cycle == 11 && rgb_new !== expected) fault({label, ": RGB not held after output"});
        end
        if (mode == 0) stable_cases++; else dynamic_cases++;
        $display("case %s new %06x old %06x", label, rgb_new, rgb_old);
    endtask

    initial begin
        if (!$value$plusargs("LATENCY=%d", latency)) latency = 1;
        if (latency < 1 || latency > 2) $fatal(1, "bad latency");
        for (int i = 0; i < 2048; i++) palette[i] = 24'h556677;
        palette[16] = 24'h924e23; palette[32] = 24'h1f2f3f;
        palette[48] = 24'ha1b2c3; palette[64] = 24'h123456;
        palette[80] = 24'hf6e5d4; palette[96] = 24'h102030;
        defaults();
        repeat (3) begin tick(); if (rgb_new !== 24'h000000) fault("reset RGB"); end
        reset = 0;
        defaults(); pixel("tile-A", 24'h924e23, 16, 0);
        defaults(); k55regs[10] = 10; spr_pri = 10;
        pixel("equal-priority-A-before-B-and-sprite", 24'h924e23, 16, 0);
        defaults(); k55regs[13] = 1;
        pixel("tile-C-lowest", 24'hf6e5d4, 80, 0);
        defaults(); spr_pri = 1;
        pixel("sprite-lowest", 24'ha1b2c3, 48, 0);
        defaults(); k55regs[16] = 1;
        pixel("ROZ-lowest", 24'h123456, 64, 0);
        defaults(); k55regs[16] = 1; roz_enable = 0;
        pixel("ROZ-disabled", 24'h924e23, 16, 0);
        defaults(); k55regs[45] = 0;
        pixel("backdrop", 24'h112233, 0, 0);
        defaults(); tm_opq = 0; roz_opq = 0; spr_opq = 0;
        pixel("transparent-backdrop", 24'h112233, 0, 0);
        defaults(); spr_shadow = 1; spr_shpri = 10;
        pixel("shadow-blocked-by-layer-priority", 24'h924e23, 16, 0);
        defaults(); spr_shadow = 1; spr_shpri = 9;
        k38regs[2] = 120; k38regs[3] = 16'h188; k38regs[4] = 16'h1b0;
        pixel("signed-shadow-clamp", 24'hff0000, 16, 0);
        defaults(); spr_shadow = 1; spr_shpri = 9;
        k38regs[2] = 120; k38regs[3] = 16'h188; k38regs[4] = 16'h1b0;
        k38regs[15] = 16'h20;
        pixel("signed-shadow-wrap", 24'h0cd2d1, 16, 0);
        defaults(); spr_shadow = 1; spr_shpri = 9; spr_shtab = 3;
        pixel("fixed-shadow-table-3", 24'h440000, 16, 0);
        defaults(); pixel("MMIO-before-snapshot", 24'h1f2f3f, 32, 2);
        defaults(); pixel("MMIO-and-pen-after-snapshot", 24'h924e23, 16, 1);
        defaults(); spr_shadow = 1; spr_shpri = 9;
        k38regs[2] = 120; k38regs[3] = 16'h188; k38regs[4] = 16'h1b0;
        pixel("shadow-config-after-snapshot", 24'hff0000, 16, 1);
        defaults(); k55regs[45] = 0;
        pixel("backdrop-config-after-snapshot", 24'h112233, 0, 1);
        defaults(); pixel("palette-write-at-operand-capture", 24'h924e23, 16, 3);
        defaults(); pixel("next-pixel-observes-palette-write", 24'habcdef, 16, 0);
        reset = 1; repeat (2) begin tick(); if (rgb_new !== 0) fault("late reset RGB"); end
        reset = 0; defaults(); pixel("post-reset-new-pixel", 24'habcdef, 16, 0);
        $display("SUMMARY latency=%0d stable=%0d dynamic=%0d pixels=%0d holdchecks=%0d original_dynamic_differences=%0d errors=%0d",
                 latency, stable_cases, dynamic_cases, pixel_checks, hold_checks, old_dynamic_differences, errors);
        if (errors) $fatal(1, "mixer pipeline mismatch");
        if (old_dynamic_differences == 0) $fatal(1, "dynamic snapshot cases did not distinguish original policy");
        $display("PASS mixer pipeline public palette consumer"); $finish;
    end
    initial begin #100000; $fatal(1, "watchdog"); end
endmodule
