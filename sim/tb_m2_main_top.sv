// Board-only original-program boot probe, not a whole-game simulation.
`default_nettype none
module tb_m2_main_top (
    input logic clk, reset, pause, cen_16m, raster_start,
    input logic [8:0] raster_line,
    output logic rom_req, output logic [22:1] rom_addr,
    input logic rom_ack, input logic [15:0] rom_q,
    output logic tile_req, output logic [18:0] tile_addr,
    input logic tile_ack, input logic [31:0] tile_q, input logic [7:0] tile_fifth,
    output logic spr_req, output logic [19:0] spr_addr,
    input logic spr_ack, input logic [63:0] spr_q, input logic [15:0] spr_fifth,
    output logic vc_req,vc_we,output logic [15:0] vc_addr,vc_wdata,output logic [1:0] vc_be,
    input logic vc_ack,input logic [15:0] vc_q,
    input logic eep_we, input logic [6:0] eep_addr,input logic [7:0] eep_data,
    output logic eep_cs,eep_clk,eep_di,eep_ready,eep_do,
    output logic [23:0] dbg_addr,output logic [15:0] dbg_data,output logic [1:0] dbg_busstate,
    output logic dbg_step,irq2,irq4,rb_oob,spr_we,
    output logic [15:0] k56regs[32], k56regsb[4],
    output logic [7:0] k55regs[48], k46regs[8],
    output logic snd_wr,snd_rd,snd_irq,output logic [3:0] snd_off,output logic [7:0] snd_wdata,
    output logic unexpected_roz
);
    logic [7:0] snd_rdata;
    logic map_req,chr_req;
    assign unexpected_roz=map_req||chr_req;
    gaia_main u_main (
        .clk(clk),.reset(reset),.pause(pause),.mystic(1'b1),.cen_16m(cen_16m),
        .raster_start(raster_start),.raster_line(raster_line),
        .mystic_p12(16'hffff),.mystic_p34(16'hffff),.mystic_in0(8'hff),
        .rom_req(rom_req),.rom_addr(rom_addr),.rom_ack(rom_ack),.rom_q(rom_q),
        .map_req(map_req),.map_addr(),.map_ack(1'b0),.map_q(16'd0),
        .chr_req(chr_req),.chr_addr(),.chr_ack(1'b0),.chr_q(16'd0),
        .trom_req(tile_req),.trom_addr(tile_addr),.trom_ack(tile_ack),.trom_q(tile_q),.trom_fifth(tile_fifth),
        .srom_req(spr_req),.srom_addr(spr_addr),.srom_ack(spr_ack),.srom_q(spr_q),.srom_fifth(spr_fifth),
        .vblank_rise(1'b0),.in0_p1(16'hffff),.in1(8'he4),.p2(8'hff),
        .eep_di(eep_di),.eep_cs(eep_cs),.eep_clk(eep_clk),.eep_do(eep_do),.eep_ready(eep_ready),
        .snd_wr(snd_wr),.snd_rd(snd_rd),.snd_off(snd_off),.snd_wdata(snd_wdata),.snd_rdata(snd_rdata),.snd_irq(snd_irq),
        .col_wr(),.col_rd(),.col_off(),.col_wdata(),.col_rdata(8'd0),
        .k56regs(k56regs),.k56regsb(k56regsb),.k55regs(k55regs),.k38regs(),
        .rozctrl(),.rozclip(),.roz_enable(),.roz_rombank(),.k46regs(k46regs),.k47regs(),
        .vc_req(vc_req),.vc_we(vc_we),.vc_addr(vc_addr),.vc_be(vc_be),.vc_wdata(vc_wdata),.vc_ack(vc_ack),.vc_q(vc_q),
        .sram_raddr(11'd0),.sram_q(),.pal_raddr(11'd0),.pal_q(),
        .dbg_addr(dbg_addr),.dbg_data(dbg_data),.dbg_busstate(dbg_busstate),.dbg_step(dbg_step),.dbg_irq5(),
        .dbg_irq2(irq2),.dbg_irq4(irq4),.dbg_rb_oob(rb_oob),.dbg_spr_we(spr_we)
    );
    er5911 u_eep(.clk(clk),.reset(reset),.cs(eep_cs),.sclk(eep_clk),.di(eep_di),.dout(eep_do),.ready(eep_ready),
        .ld_we(eep_we),.ld_addr(eep_addr),.ld_wdata(eep_data),.ld_q(),.dirty());
    k054321 u_sif(.clk(clk),.reset(reset),.m_wr(snd_wr),.m_rd(snd_rd),.m_off(snd_off),.m_wdata(snd_wdata),.m_rdata(snd_rdata),
        .s_wr(1'b0),.s_off(2'd0),.s_wdata(8'd0),.s_rdata(),.volume(),.active());
endmodule
`default_nettype wire
