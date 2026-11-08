// Actual public cabinet, serial EEPROM, and autosave request interfaces.
`default_nettype none
module tb_m4_controls (
 input logic clk,reset,
 input logic[1:0]profile,
 input logic[7:0]p1_keys,p2_keys,p3_keys,p4_keys,
 input logic[3:0]p1_dirs,p2_dirs,p3_dirs,p4_dirs,
 input logic test_manual,input logic[3:0]test_select,service_select,input logic[12:0]dips,
 output wire[15:0]in0_p1,mystic_p12,mystic_p34,output wire[7:0]in1,p2,mystic_in0,
 input logic cs,sclk,di,ld_we,input logic[6:0]ld_addr,input logic[7:0]ld_wdata,
 output wire dout,ready,dirty,output wire[7:0]ld_q,
 input logic loaded,run,inmenu,host_ack,host_done,input logic[2:0]host_error,output wire save_request
);
 pregx_inputs cabinet(.mystic(profile==1),.violent(profile==2),.metam(profile==3),
  .p1_keys(p1_keys),.p2_keys(p2_keys),.p3_keys(p3_keys),.p4_keys(p4_keys),
  .p1_dirs(p1_dirs),.p2_dirs(p2_dirs),.p3_dirs(p3_dirs),.p4_dirs(p4_dirs),
  .test_manual(test_manual),.test_select(test_select),.service_select(service_select),.dips(dips),
  .in0_p1(in0_p1),.in1(in1),.p2(p2),.mystic_p12(mystic_p12),.mystic_p34(mystic_p34),.mystic_in0(mystic_in0));
 er5911 eeprom(.clk(clk),.reset(reset),.cs(cs),.sclk(sclk),.di(di),.dout(dout),.ready(ready),
  .ld_we(ld_we),.ld_addr(ld_addr),.ld_wdata(ld_wdata),.ld_q(ld_q),.dirty(dirty));
 pregx_nv_save #(.SETTLE_CYCLES(8),.BOOT_CYCLES(64)) save(
  .clk(clk),.loaded(loaded),.run(run),.dirty_toggle(dirty),.inmenu(inmenu),
  .ack(host_ack),.done(host_done),.error(host_error),.request(save_request));
endmodule
`default_nettype wire
