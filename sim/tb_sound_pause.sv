// Real sound board; hierarchical signals below are passive observation only.
module tb_sound_pause(
 input logic clk,reset,cen_8m,cen_48k,irq_pulse,
 input logic main_wr,input logic [3:0] main_off,input logic [7:0] main_data,
 output logic rom_req,output logic [17:0] rom_addr,input logic rom_ack,input logic [7:0] rom_q,
 output logic pcm_req,output logic [21:0] pcm_addr,input logic pcm_ack,input logic [7:0] pcm_q,
 output wire ack_active,irq_pending,output logic [15:0] dbg_pc,
 output wire [15:0] snd_l,snd_r
);
 wire lat_wr;wire [1:0] lat_off;wire [7:0] lat_wdata,lat_rdata;
 gaia_sound dut(.mystic(1'b0),.clk(clk),.reset(reset),.cen_8m(cen_8m),.cen_48k(cen_48k),
  .rom_req(rom_req),.rom_addr(rom_addr),.rom_ack(rom_ack),.rom_q(rom_q),
  .pcm_req(pcm_req),.pcm_addr(pcm_addr),.pcm_ack(pcm_ack),.pcm_q(pcm_q),
  .lat_wr(lat_wr),.lat_off(lat_off),.lat_wdata(lat_wdata),.lat_rdata(lat_rdata),
  .irq_pulse(irq_pulse),.snd_l(snd_l),.snd_r(snd_r),.dbg_pc(dbg_pc),
  .dbg_step(),.dbg_wait(),.dbg_wr(),.dbg_rd(),.dbg_wdata());
 k054321 latch(.clk(clk),.reset(reset),.m_wr(main_wr),.m_rd(1'b0),.m_off(main_off),.m_wdata(main_data),.m_rdata(),
  .s_wr(lat_wr),.s_off(lat_off),.s_wdata(lat_wdata),.s_rdata(lat_rdata),.volume(),.active());
 assign ack_active=!dut.m1_n && !dut.iorq_n;
 assign irq_pending=dut.irq_pend;
endmodule
