// Actual M4 candidate engine and actual pinned Metamorphic engine, fixed chip1 gain.
`default_nettype none
module tb_m4_audio_state(input logic clk,reset,cen,cs,wr,rd,input logic[9:0]addr,input logic[7:0]data,
 output wire[7:0]rdata[2],output wire stall[2],req[2],output wire[21:0]rom_addr[2],input logic ack[2],input logic[7:0]q[2],
 output wire[15:0]l[2],r[2]);
 k054539 #(.HEXDIR("rtl/data"),.GAIN_Q14_METAM({8{16'h3333}})) candidate(
 .clk(clk),.reset(reset),.cen_48k(cen),.gain_alt(1'b0),.gain_vio(1'b0),.gain_metam(1'b1),
 .cs(cs),.wr(wr),.rd(rd),.addr(addr),.wdata(data),.rdata(rdata[0]),.rd_stall(stall[0]),
 .rom_req(req[0]),.rom_addr(rom_addr[0]),.rom_ack(ack[0]),.rom_q(q[0]),.timer_out(),.snd_l(l[0]),.snd_r(r[0]));
 k054539_m4_pinned #(.HEXDIR("rtl/data"),.GAIN_Q14({8{16'h3333}})) pinned(
 .clk(clk),.reset(reset),.cen_48k(cen),.cs(cs),.wr(wr),.rd(rd),.addr(addr),.wdata(data),.rdata(rdata[1]),.rd_stall(stall[1]),
 .rom_req(req[1]),.rom_addr(rom_addr[1]),.rom_ack(ack[1]),.rom_q(q[1]),.timer_out(),.snd_l(l[1]),.snd_r(r[1]));
endmodule
`default_nettype wire
