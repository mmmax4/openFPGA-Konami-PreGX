// Independent bounded pause test: original TG68K and original ROM from reset.
// OLD_BASELINE only omits the nonexistent pause port; no CPU/ROM substitutions.
`timescale 1ns/1ps
module tb_pause_main;
  reg clk=0;
  always #5.205 clk=~clk;
  reg reset=1, pause=0, vblank_rise=0;
  integer cycles=0;
  wire cen_16m = cycles % 6 == 0;
  always @(posedge clk) cycles <= cycles+1;
  wire rom_req,vc_req,vc_we;
  wire [22:1] rom_addr;
  wire [15:0] vc_addr,vc_wdata;
  wire [1:0] vc_be;
  reg rom_ack=0,vc_ack=0;
  reg [15:0] rom_q=0,vc_q=0;
  wire [23:0] dbg_addr;
  wire [15:0] dbg_data;
  wire [1:0] dbg_busstate;
  wire dbg_step,dbg_irq5;
  wire eep_cs,eep_clk,eep_di,eep_do,eep_ready;
  reg ld_we=0;
  reg [6:0] ld_addr=0;
  reg [7:0] ld_wdata=0;
  wire [7:0] ld_q;
  wire dirty;
  gaia_main dut(
    .clk(clk),.reset(reset),.cen_16m(cen_16m),
`ifndef OLD_BASELINE
        .mystic(1'b0), .raster_start(1'b0), .raster_line(9'd0),
        .mystic_p12(16'hffff), .mystic_p34(16'hffff), .mystic_in0(8'hff),
        .trom_fifth(8'd0), .srom_fifth(16'd0), .dbg_irq2(), .dbg_irq4(), .dbg_rb_oob(),
    .pause(pause),
`endif
    .rom_req(rom_req),.rom_addr(rom_addr),.rom_ack(rom_ack),.rom_q(rom_q),
    .map_ack(1'b0),.map_q(16'd0),.chr_ack(1'b0),.chr_q(16'd0),
    .trom_ack(1'b0),.trom_q(32'd0),.srom_ack(1'b0),.srom_q(64'd0),
    .vblank_rise(vblank_rise),.in0_p1(16'hffff),.in1(8'hff),.p2(8'hff),
    .eep_di(eep_di),.eep_cs(eep_cs),.eep_clk(eep_clk),.eep_do(eep_do),.eep_ready(eep_ready),
    .snd_rdata(8'd0),.col_rdata(8'd0),
    .vc_req(vc_req),.vc_we(vc_we),.vc_addr(vc_addr),.vc_be(vc_be),.vc_wdata(vc_wdata),
    .vc_ack(vc_ack),.vc_q(vc_q),.sram_raddr(11'd0),.pal_raddr(11'd0),
    .dbg_addr(dbg_addr),.dbg_data(dbg_data),.dbg_busstate(dbg_busstate),
    .dbg_step(dbg_step),.dbg_irq5(dbg_irq5)
  );
  er5911 eeprom(.clk(clk),.reset(reset),.cs(eep_cs),.sclk(eep_clk),.di(eep_di),
    .dout(eep_do),.ready(eep_ready),.ld_we(ld_we),.ld_addr(ld_addr),
    .ld_wdata(ld_wdata),.ld_q(ld_q),.dirty(dirty));

  reg [15:0] prog[0:1572863];
  reg [7:0] defaults[0:127];
  reg [15:0] vram[0:65535];
  integer rom_wait=0, vc_wait=0;
  reg rom_busy=0,vc_busy=0;
  reg [22:1] ra;
  reg [15:0] va,vd;
  reg [1:0] vb;
  reg vw;
  integer rom_reads=0,vram_reads=0,vram_writes=0,steps=0;
  // Requests complete after 12/7 clocks, with one-cycle ack carrying data.
  always @(posedge clk) begin
    rom_ack<=0; vc_ack<=0;
    if (!reset) begin
      if (dbg_step) steps<=steps+1;
      if (!rom_busy && rom_req && !rom_ack) begin
        ra<=rom_addr; rom_wait<=12; rom_busy<=1;
      end else if (rom_busy) begin
        if (rom_wait==1) begin
          if (!rom_req || rom_addr!==ra) $fatal(1,"ROM request changed before ack");
          if (ra>=1572864) $fatal(1,"program ROM out of original region");
          rom_q<=prog[ra];rom_ack<=1;rom_busy<=0;rom_reads<=rom_reads+1;
        end else rom_wait<=rom_wait-1;
      end
      if (!vc_busy && vc_req && !vc_ack) begin
        va<=vc_addr;vd<=vc_wdata;vb<=vc_be;vw<=vc_we;vc_wait<=7;vc_busy<=1;
      end else if (vc_busy) begin
        if (vc_wait==1) begin
          if (!vc_req || vc_addr!==va || vc_we!==vw) $fatal(1,"VRAM request changed before ack");
          if(vw) begin
            if (vb[1]) vram[va][15:8]<=vd[15:8];
            if (vb[0]) vram[va][7:0]<=vd[7:0];
            vram_writes<=vram_writes+1;
          end else vram_reads<=vram_reads+1;
          vc_q<=vram[va];vc_ack<=1;vc_busy<=0;
        end else vc_wait<=vc_wait-1;
      end
    end
  end

  task automatic freeze_check(input integer kind,input bit pending_irq);
    integer before_steps;
    reg [23:0] frozen_addr;
    reg [1:0] frozen_bus;
    reg [15:0] frozen_data;
    reg irq_before;
    begin
      // Invocation is on negedge while a real CPU request is outstanding.
      pause=1;
      repeat(32) @(negedge clk); // > ROM/VRAM latency + registered enable/gap
      if(rom_req || vc_req || rom_busy || vc_busy) $fatal(1,"request failed to drain in pause");
      before_steps=steps;frozen_addr=dbg_addr;frozen_bus=dbg_busstate;frozen_data=dbg_data;
      irq_before=dbg_irq5;
      if(pending_irq && !irq_before) $fatal(1,"preexisting IRQ not preserved");
      vblank_rise=1;
      @(negedge clk);vblank_rise=0;
      repeat(180) begin
        @(negedge clk);
        if(steps!=before_steps || dbg_step || dbg_addr!==frozen_addr ||
           dbg_busstate!==frozen_bus || dbg_data!==frozen_data)
          $fatal(1,"NEGATIVE: main keeps advancing during pause kind=%0d",kind);
        if(dbg_irq5!==irq_before) $fatal(1,"IRQ changed due to raster during pause");
      end
      pause=0;
      repeat(300) @(negedge clk);
      if(steps<=before_steps) $fatal(1,"CPU did not resume");
      $display("CASE PASS kind=%0d pending_irq=%0d steps=%0d rom=%0d vram_r=%0d vram_w=%0d",
        kind,pending_irq,steps,rom_reads,vram_reads,vram_writes);
      $fflush();
    end
  endtask

  string rom_path;
  integer fd,n,max_cycles=400000,i;
  bit got_vram=0;
  initial begin
    if(!$value$plusargs("ROM=%s",rom_path)) $fatal(1,"ROM path required");
    if($value$plusargs("MAX_CYCLES=%d",max_cycles)) begin end
    fd=$fopen(rom_path,"rb");if(!fd) $fatal(1,"ROM open");
    n=$fread(prog,fd); if(n!=3145728) $fatal(1,"program ROM length %0d",n);
    n=$fseek(fd,'h1360000,0);if(n!=0) $fatal(1,"EEPROM seek");
    n=$fread(defaults,fd);if(n!=128) $fatal(1,"EEPROM length");$fclose(fd);
    for(i=0;i<65536;i=i+1) vram[i]=0;
    for(i=0;i<128;i=i+1) begin
      @(negedge clk);ld_we=1;ld_addr=7'(i);ld_wdata=defaults[i];
    end
    @(negedge clk);ld_we=0;reset=0;
    // Original reset vector and first actual instruction fetches, not a synthetic program.
    wait(rom_busy && rom_wait==8);@(negedge clk);
    freeze_check(0,0);
    wait(rom_busy && rom_wait==8);@(negedge clk);
    vblank_rise=1;@(negedge clk);vblank_rise=0;
    freeze_check(1,1);
    while(cycles<max_cycles && !vc_req) @(negedge clk);
    if(vc_req) begin
      got_vram=1;freeze_check(2,0);
    end
    if(!got_vram) $display("UNCOVERED VRAM: original boot did not reach VC within %0d clocks",max_cycles);
    $display("PASS main pause ROM/IRQ/resume; vram_covered=%0d cycles=%0d steps=%0d original_program=1",got_vram,cycles,steps);
    $finish;
  end
  initial begin
    #20000000;
    $fatal(1,"watchdog cycles=%0d steps=%0d addr=%h rom=%0d vc=%b",cycles,steps,dbg_addr,rom_reads,vc_req);
  end
endmodule
