`default_nettype none
module m3_vio13_mmio_bus (
 input logic clk,reset,pause,cen_16m,
 input logic [1:0] profile,
 input logic vblank_rise,raster_start,
 input logic [8:0] raster_line,
 output logic rom_req,
 output logic [22:1] rom_addr,
 input logic rom_ack,
 input logic [15:0] rom_q,
 output logic vc_req,vc_we,
 output logic [15:0] vc_addr,vc_wdata,
 output logic [1:0] vc_be,
 input logic vc_ack,
 input logic [15:0] vc_q,
 output logic trom_req,srom_req,
 output logic [19:0] trom_addr,srom_addr,
 input logic trom_ack,srom_ack,
 input logic [31:0] trom_q,
 input logic [7:0] trom_fifth,
 input logic [63:0] srom_q,
 input logic [15:0] srom_fifth,
 input logic ld_we,
 input logic [6:0] ld_addr,
 input logic [7:0] ld_wdata,
 input logic [10:0] sram_raddr,pal_raddr,
 output logic [15:0] sram_q,
 output logic [23:0] pal_q,
 output logic [23:0] dbg_addr,
 output logic [15:0] dbg_data,
 output logic [1:0] dbg_busstate,
 output logic dbg_step,dbg_irq5,dbg_irq2,dbg_irq4,dbg_rb_oob,
 output logic eep_di,eep_cs,eep_clk,
 output logic snd_wr,snd_rd,snd_irq,
 output logic [3:0] snd_off,
 output logic [7:0] snd_wdata,
 output wire [7:0] k55regs[48],k46regs[8],
 output wire [15:0] k56regs[32],k56regsb[4],k38regs[16],k47regs[8],rozctrl[16],rozclip[2],
 output wire roz_enable,output wire[1:0] roz_rombank,
 output wire col_wr,col_rd,output wire[4:0] col_off,output wire[7:0] col_wdata,
 output wire[15:0] observed_wdat,output wire[2:0] observed_ipl,
 output wire observed_engine_write
);
 wire eep_do,eep_ready;wire[7:0]col_rdata;
 k054000 collision(.clk(clk),.reset(reset),.wr(col_wr),.off(col_off),.wdata(col_wdata),.rdata(col_rdata));
 gaia_main dut (
`ifdef M3_CANDIDATE
 .violent(profile==2),
`endif
 .clk(clk),.reset(reset),.pause(pause),.mystic(profile==1),
 .cen_16m(cen_16m),.raster_start(raster_start),.raster_line(raster_line),
 .mystic_p12(16'h3c69),.mystic_p34(16'ha596),.mystic_in0(8'hdb),
 .rom_req(rom_req),.rom_addr(rom_addr),.rom_ack(rom_ack),.rom_q(rom_q),
 .map_ack(1'b0),.map_q(16'd0),.chr_ack(1'b0),.chr_q(16'd0),
 .trom_req(trom_req),.trom_addr(trom_addr),.trom_ack(trom_ack),.trom_q(trom_q),.trom_fifth(trom_fifth),
 .srom_req(srom_req),.srom_addr(srom_addr),.srom_ack(srom_ack),.srom_q(srom_q),.srom_fifth(srom_fifth),
 .vblank_rise(vblank_rise),.in0_p1(16'h9a5c),.in1(8'hf7),.p2(8'h3a),
 .eep_di(eep_di),.eep_cs(eep_cs),.eep_clk(eep_clk),.eep_do(eep_do),.eep_ready(eep_ready),
 .snd_wr(snd_wr),.snd_rd(snd_rd),.snd_irq(snd_irq),.snd_off(snd_off),.snd_wdata(snd_wdata),.snd_rdata(8'ha7),.col_rdata(col_rdata),
 .k55regs(k55regs),.k56regs(k56regs),.k56regsb(k56regsb),.k38regs(k38regs),
 .k46regs(k46regs),.k47regs(k47regs),.rozctrl(rozctrl),.rozclip(rozclip),
 .roz_enable(roz_enable),.roz_rombank(roz_rombank),
 .col_wr(col_wr),.col_rd(col_rd),.col_off(col_off),.col_wdata(col_wdata),
 .vc_req(vc_req),.vc_we(vc_we),.vc_addr(vc_addr),.vc_be(vc_be),.vc_wdata(vc_wdata),.vc_ack(vc_ack),.vc_q(vc_q),
 .sram_raddr(sram_raddr),.sram_q(sram_q),.pal_raddr(pal_raddr),.pal_q(pal_q),
 .dbg_addr(dbg_addr),.dbg_data(dbg_data),.dbg_busstate(dbg_busstate),.dbg_step(dbg_step),.dbg_irq5(dbg_irq5),
 .dbg_irq2(dbg_irq2),.dbg_irq4(dbg_irq4),.dbg_rb_oob(dbg_rb_oob)
 );
 // Read-only protocol witnesses; test never forces internal state.
 assign observed_wdat=dut.wdat;
 assign observed_ipl=dut.ipl_n;
 assign observed_engine_write=dut.engine_wr;
 er5911 eeprom(.clk(clk),.reset(reset),.cs(eep_cs),.sclk(eep_clk),.di(eep_di),.dout(eep_do),.ready(eep_ready),
 .ld_we(ld_we),.ld_addr(ld_addr),.ld_wdata(ld_wdata),.ld_q(),.dirty());
endmodule
`default_nettype wire
