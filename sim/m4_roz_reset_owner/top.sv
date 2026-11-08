// Public-port fixture adapted from sim/tb_roz_top.sv; existing fixture retained.
// Original ROM bytes/registers only. Model delays extend the historical Pocket
// map12/block14 configuration, and do not model physical SDRAM capture timing.
`default_nettype none
module m4_roz_reset_owner_top (
 input logic clk,reset,variable_latency,
 input logic alternate_owner,overwrite,input logic[10:0]overwrite_addr,
 input logic ctrl_we,input logic[3:0]ctrl_addr,input logic[15:0]ctrl_data,
 input logic clip_we,clip_addr,input logic[15:0]clip_data,
 input logic cfg_we,roz_enable_i,input logic[7:0]palbase_i,
 input logic map_we,input logic[18:0]map_waddr,input logic[15:0]map_wdata,
 input logic chr_we,input logic[19:0]chr_waddr,input logic[15:0]chr_wdata,
 input logic prestart,line_start,input logic[8:0]line,
 input logic[8:0]px,output wire[11:0]pix,output wire opaque,busy,unsupported,
 output wire[3:0]lead,
 output logic[31:0]map_transactions,block_transactions,
 output logic[7:0]map_latency_min,map_latency_max,block_latency_min,block_latency_max,
 output logic protocol_error
);
 logic[15:0]ctrl[16],clip[2];logic roz_enable;logic[7:0]palbase;
 always_ff @(posedge clk) begin
  if(ctrl_we)ctrl[ctrl_addr]<=ctrl_data;
  if(clip_we)clip[clip_addr]<=clip_data;
  if(cfg_we)begin roz_enable<=roz_enable_i;palbase<=palbase_i;end
 end
 logic[15:0]maprom[327680],chrrom[786432];
 logic map_req,map_ack,map_run;logic[19:0]map_addr,map_latched;logic[15:0]map_q;
 logic blk_req,blk_wr,blk_ack,blk_run;logic[15:0]blk_addr,blk_data,blk_latched;
 logic[5:0]blk_idx;logic[6:0]blk_n;
 integer map_wait,blk_wait,map_serial,blk_serial;
 always_ff @(posedge clk) begin
  if(map_we)maprom[map_waddr]<=map_wdata;
  if(chr_we)chrrom[chr_waddr]<=chr_wdata;
  map_ack<=0;blk_wr<=0;blk_ack<=0;
  if(reset)begin
   map_run<=0;blk_run<=0;map_wait<=0;blk_wait<=0;blk_n<=0;
   map_serial<=0;blk_serial<=0;map_transactions<=0;block_transactions<=0;
   map_latency_min<=255;map_latency_max<=0;block_latency_min<=255;block_latency_max<=0;
   protocol_error<=0;
  end else begin
   if(!map_run)begin
    if(map_req&&!map_ack)begin
     map_run<=1;map_latched<=map_addr;
     map_wait<=12+(variable_latency?(map_serial%9):0);
     map_serial<=map_serial+1;
     if((12+(variable_latency?(map_serial%9):0))<map_latency_min)map_latency_min<=8'(12+(variable_latency?(map_serial%9):0));
     if((12+(variable_latency?(map_serial%9):0))>map_latency_max)map_latency_max<=8'(12+(variable_latency?(map_serial%9):0));
     if(map_addr[19:1]>=19'd327680)protocol_error<=1;
    end
   end else if(!map_req)map_run<=0;
   else begin
    if(map_addr!=map_latched)protocol_error<=1;
    if(map_wait>0)map_wait<=map_wait-1;
    else begin
     map_q<=maprom[map_latched[19:1]];map_ack<=1;map_run<=0;map_transactions<=map_transactions+1;
    end
   end
   // Once started, the original64word block finishes even if the request is
   // cancelled. ACK belongs only to the still-standing matching request.
   if(!blk_run)begin
    if(blk_req&&!blk_ack)begin
     blk_run<=1;blk_latched<=blk_addr;blk_n<=0;
     blk_wait<=14+(variable_latency?(blk_serial%17):0);blk_serial<=blk_serial+1;
     if((14+(variable_latency?(blk_serial%17):0))<block_latency_min)block_latency_min<=8'(14+(variable_latency?(blk_serial%17):0));
     if((14+(variable_latency?(blk_serial%17):0))>block_latency_max)block_latency_max<=8'(14+(variable_latency?(blk_serial%17):0));
     if(blk_addr[13:0]>=14'd12288)protocol_error<=1;
    end
   end else if(blk_wait>0)blk_wait<=blk_wait-1;
   else if(blk_n!=64)begin
    blk_wr<=1;blk_idx<=blk_n[5:0];
    blk_data<=chrrom[{blk_latched[13:0],blk_n[3:0],blk_n[5:4]}];blk_n<=blk_n+1;
   end else begin
    blk_run<=0;block_transactions<=block_transactions+1;
    if(blk_req&&blk_addr==blk_latched)blk_ack<=1;
   end
  end
 end
 wire cache_we,line_we; wire[12:0]cache_wa,cache_ra;
 wire[15:0]cache_wdata,cache_q; wire[11:0]line_wa,line_ra,line_wdata,line_q;
 k053936_roz #(.EXTERNAL_RAM(1'b1)) dut(.clk(clk),.reset(reset),.prestart(prestart),.line_start(line_start),.line(line),.busy(busy),.lead(lead),
  .ctrl(ctrl),.clip(clip),.roz_enable(roz_enable),.palbase(palbase),
  .map_req(map_req),.map_addr(map_addr),.map_ack(map_ack),.map_q(map_q),
  .blk_req(blk_req),.blk_addr(blk_addr),.blk_wr(blk_wr),.blk_idx(blk_idx),.blk_data(blk_data),.blk_ack(blk_ack),
  .px(px),.pix(pix),.opaque(opaque),.unsupported(unsupported),
  .cache_we(cache_we),.cache_wa(cache_wa),.cache_ra(cache_ra),.cache_wdata(cache_wdata),.cache_q(cache_q),
  .line_we(line_we),.line_wa(line_wa),.line_ra(line_ra),.line_wdata(line_wdata),.line_q(line_q));
 pregx_video_ram actual_ram(.clk(clk),.metam(alternate_owner),
 .g_we(cache_we),.g_wa(cache_wa),.g_ra(cache_ra),.g_wdata(cache_wdata),.g_q(cache_q),
 .f_we(overwrite),.f_wa(overwrite_addr),.f_ra(11'd0),.f_wdata(16'd0),.f_q(),
 .c_we(overwrite),.c_wa(overwrite_addr[8:0]),.c_ra(9'd0),.c_wdata(53'd0),.c_q(),
 .cache_we(overwrite),.cache_wa(overwrite_addr[8:0]),.cache_ra(9'd0),.cache_wdata(80'd0),.cache_q(),
 .g_lb_we(line_we),.g_lb_wa(line_wa),.g_lb_ra(line_ra),.g_lb_wdata(line_wdata),.g_lb_q(line_q),
 .r_lb_we(overwrite),.r_lb_wa({1'b0,overwrite_addr}),.r_lb_ra(10'd0),.r_lb_wdata(9'd0),.r_lb_q());
endmodule
`default_nettype wire
