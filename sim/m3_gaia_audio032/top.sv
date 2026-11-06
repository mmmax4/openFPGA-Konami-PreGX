`default_nettype none
// All three pair modules and mix modules are generated from literal source spans.
module m3_gaia_audio032_top(
 input wire clk,reset,cen,mystic,violent,cs,wr,rd,chip,
 input wire[9:0] addr,input wire[7:0] wdata,
 output wire[7:0] rdata[3],output wire[2:0] stall,req,timer,
 output wire[21:0] rom_addr[3],input wire[2:0] ack,input wire[7:0] q[3],
 output wire[15:0] l[3],r[3],chip_l0[3],chip_r0[3],chip_l1[3],chip_r1[3],
 input wire[15:0] probe_l0,probe_r0,probe_l1,probe_r1,
 output wire[15:0] probe_l[3],probe_r[3]);
 audio_pair_candidate a0(.clk(clk),.reset(reset),.cen_48k(cen),.mystic(mystic),.violent(violent),.cs(cs),.wr(wr),.rd(rd),.chip(chip),.addr(addr),.wdata(wdata),.rdata(rdata[0]),.stall(stall[0]),.pcm_req(req[0]),.pcm_addr(rom_addr[0]),.pcm_ack(ack[0]),.pcm_q(q[0]),.snd_l(l[0]),.snd_r(r[0]),.timer(timer[0]),.chip_l0(chip_l0[0]),.chip_r0(chip_r0[0]),.chip_l1(chip_l1[0]),.chip_r1(chip_r1[0]));
 audio_pair_baseline a1(.clk(clk),.reset(reset),.cen_48k(cen),.mystic(mystic),.violent(violent),.cs(cs),.wr(wr),.rd(rd),.chip(chip),.addr(addr),.wdata(wdata),.rdata(rdata[1]),.stall(stall[1]),.pcm_req(req[1]),.pcm_addr(rom_addr[1]),.pcm_ack(ack[1]),.pcm_q(q[1]),.snd_l(l[1]),.snd_r(r[1]),.timer(timer[1]),.chip_l0(chip_l0[1]),.chip_r0(chip_r0[1]),.chip_l1(chip_l1[1]),.chip_r1(chip_r1[1]));
 audio_pair_upstream a2(.clk(clk),.reset(reset),.cen_48k(cen),.mystic(mystic),.violent(violent),.cs(cs),.wr(wr),.rd(rd),.chip(chip),.addr(addr),.wdata(wdata),.rdata(rdata[2]),.stall(stall[2]),.pcm_req(req[2]),.pcm_addr(rom_addr[2]),.pcm_ack(ack[2]),.pcm_q(q[2]),.snd_l(l[2]),.snd_r(r[2]),.timer(timer[2]),.chip_l0(chip_l0[2]),.chip_r0(chip_r0[2]),.chip_l1(chip_l1[2]),.chip_r1(chip_r1[2]));
 mix_candidate m0(.mystic(mystic),.violent(violent),.l1(probe_l0),.r1(probe_r0),.l2(probe_l1),.r2(probe_r1),.snd_l(probe_l[0]),.snd_r(probe_r[0]));
 mix_baseline m1(.mystic(mystic),.violent(violent),.l1(probe_l0),.r1(probe_r0),.l2(probe_l1),.r2(probe_r1),.snd_l(probe_l[1]),.snd_r(probe_r[1]));
 mix_upstream m2(.mystic(mystic),.violent(violent),.l1(probe_l0),.r1(probe_r0),.l2(probe_l1),.r2(probe_r1),.snd_l(probe_l[2]),.snd_r(probe_r[2]));
endmodule
