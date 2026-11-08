`default_nettype none
module tb_m4_road_psram(
 input logic clk,reset,slow,frame_tick,reg4_dma,
 output wire initialized,dma_busy,
 input logic cpu_req,cpu_we,input logic[12:0]cpu_addr,input logic[1:0]cpu_be,input logic[15:0]cpu_wdata,
 output wire cpu_ack,output wire[15:0]cpu_q,
 input logic snapshot_begin,snapshot_active,snapshot_req,input logic[10:0]snapshot_addr,
 output wire snapshot_allowed,snapshot_ack,output wire[15:0]snapshot_q,output wire page,
 output logic legacy_mismatch,early_ack_error,
 output logic[31:0]accepted_writes,committed_writes,pin_write_ends
);
 wire mem_req,mem_we,mem_ack;wire[13:0]mem_addr;wire[1:0]mem_be;wire[15:0]mem_wdata,mem_q;
 pregx_road_state state(.clk(clk),.reset(reset),.frame_tick(frame_tick),.reg4_dma(reg4_dma),.initialized(initialized),.dma_busy(dma_busy),
 .cpu_req(cpu_req),.cpu_we(cpu_we),.cpu_addr(cpu_addr),.cpu_be(cpu_be),.cpu_wdata(cpu_wdata),.cpu_ack(cpu_ack),.cpu_q(cpu_q),
 .snapshot_begin(snapshot_begin),.snapshot_active(snapshot_active),.snapshot_req(snapshot_req),.snapshot_addr(snapshot_addr),
 .snapshot_allowed(snapshot_allowed),.snapshot_ack(snapshot_ack),.snapshot_q(snapshot_q),.page(page),
 .mem_req(mem_req),.mem_we(mem_we),.mem_addr(mem_addr),.mem_be(mem_be),.mem_wdata(mem_wdata),.mem_ack(mem_ack),.mem_q(mem_q));
 wire r_req,r_ack,w_req,w_accept,w_commit;wire[22:0]r_addr,w_addr;wire[15:0]r_q,w_data;wire[1:0]w_be;
 pregx_road_psram_bridge bridge(.clk(clk),.reset(reset),.req(mem_req),.we(mem_we),.addr(mem_addr),.be(mem_be),.wdata(mem_wdata),.ack(mem_ack),.q(mem_q),
 .r_req(r_req),.r_addr(r_addr),.r_ack(r_ack),.r_q(r_q),.w_req(w_req),.w_addr(w_addr),.w_be(w_be),.w_data(w_data),.w_accept(w_accept),.w_commit(w_commit));
 wire[21:16]a,oa;wire[15:0]dq,odq;wire cc,adv,cre,ce0,ce1,oe,we,ub,lb;
 wire occ,oadv,ocre,oce0,oce1,ooe,owe,oub,olb;wire old_rack,old_wack;wire[15:0]old_q;
 psram_port port(.clk(clk),.reset(reset),.slow(slow),.r0_req(r_req),.r0_addr(r_addr),.r0_ack(r_ack),.r0_q(r_q),
 .r1_req(1'b0),.r1_addr(23'd0),.r1_ack(),.r1_q(),.w_req(w_req),.w_addr(w_addr),.w_data(w_data),.w_be(w_be),.w_ack(w_accept),.w_commit(w_commit),
 .cram_a(a),.cram_dq(dq),.cram_wait(1'b0),.cram_clk(cc),.cram_adv_n(adv),.cram_cre(cre),.cram_ce0_n(ce0),.cram_ce1_n(ce1),.cram_oe_n(oe),.cram_we_n(we),.cram_ub_n(ub),.cram_lb_n(lb));
 psram_port_old old_port(.clk(clk),.reset(reset),.slow(slow),.r0_req(r_req),.r0_addr(r_addr),.r0_ack(old_rack),.r0_q(old_q),
 .r1_req(1'b0),.r1_addr(23'd0),.r1_ack(),.r1_q(),.w_req(w_req),.w_addr(w_addr),.w_data(w_data),.w_be(w_be),.w_ack(old_wack),
 .cram_a(oa),.cram_dq(odq),.cram_wait(1'b0),.cram_clk(occ),.cram_adv_n(oadv),.cram_cre(ocre),.cram_ce0_n(oce0),.cram_ce1_n(oce1),.cram_oe_n(ooe),.cram_we_n(owe),.cram_ub_n(oub),.cram_lb_n(olb));
 psram_model #(.TAA(7)) chip(.clk(clk),.a(a),.dq(dq),.adv_n(adv),.ce0_n(ce0),.oe_n(oe),.we_n(we),.ub_n(ub),.lb_n(lb));
 psram_model #(.TAA(7)) old_chip(.clk(clk),.a(oa),.dq(odq),.adv_n(oadv),.ce0_n(oce0),.oe_n(ooe),.we_n(owe),.ub_n(oub),.lb_n(olb));
 logic we_previous;
 always_ff @(posedge clk) begin
  we_previous<=we;
  if(reset)begin legacy_mismatch<=0;early_ack_error<=0;accepted_writes<=0;committed_writes<=0;pin_write_ends<=0;end
  else begin
   if({a,cc,adv,cre,ce0,ce1,oe,we,ub,lb,r_ack,r_q,w_accept}!={oa,occ,oadv,ocre,oce0,oce1,ooe,owe,oub,olb,old_rack,old_q,old_wack})legacy_mismatch<=1;
   if(w_accept)accepted_writes<=accepted_writes+1;
   if(w_commit)committed_writes<=committed_writes+1;
   if(!we_previous&&we)pin_write_ends<=pin_write_ends+1;
   if(mem_req&&mem_we&&mem_ack&&(!we||accepted_writes!=committed_writes||committed_writes>pin_write_ends))early_ack_error<=1;
  end
 end
endmodule
`default_nettype wire
