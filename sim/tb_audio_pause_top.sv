// Actual K054539 and public byte/ROM ports. Internal signals are monitors only.
`default_nettype none
module tb_audio_pause_top(
 input wire clk,reset,pause,cen,cs,wr,rd,
 input wire [9:0] addr,input wire [7:0] wdata,
 output wire [7:0] rdata,output wire stall,
 output wire req,output wire [21:0] rom_addr,input wire ack,input wire [7:0] q,
 output wire [15:0] l,r,output wire timer,done,busy,
 output wire [16:0] stream_pos,output wire [15:0] timer_count
);
 k054539 #(.HEXDIR("rtl/data")) chip(.clk(clk),.reset(reset),.cen_48k(cen && !pause),.gain_alt(1'b0),
  .cs(cs),.wr(wr),.rd(rd),.addr(addr),.wdata(wdata),.rdata(rdata),.rd_stall(stall),
  .rom_req(req),.rom_addr(rom_addr),.rom_ack(ack),.rom_q(q),.timer_out(timer),.snd_l(l),.snd_r(r));
 reg was_busy;
 assign busy=(chip.ast!=0)||chip.wb_run;
 always @(posedge clk) was_busy<=busy;
 assign done=was_busy&&!busy;
 assign stream_pos=chip.cur_ptr;
 assign timer_count=chip.tcount;
endmodule
