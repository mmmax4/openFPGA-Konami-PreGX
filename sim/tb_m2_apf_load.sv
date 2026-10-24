`timescale 1ns/1ps
// Public APF commands and original bytes only. No forcing FIFO/DUT state.
module tb_m2_apf_load;
 reg clk_74a=0,clk_memory=0;
 always #6.734007 clk_74a=~clk_74a;
 integer phase_ps=1700;
 initial begin
  if(!$value$plusargs("PHASE_PS=%d",phase_ps))phase_ps=1700;
  #(phase_ps/1000.0);forever #5.208333 clk_memory=~clk_memory;
 end
 reg bridge_wr=0,bridge_rd=0,bridge_endian_little=0;
 reg[31:0]bridge_addr=0,bridge_wr_data=0;
 wire[31:0]bridge_rd_data;
 wire reset_n,requestwrite,allcomplete;wire[15:0]request_id;wire[31:0]request_size;
 core_bridge_cmd bridge(
  .clk(clk_74a),.reset_n(reset_n),.bridge_endian_little(bridge_endian_little),
  .bridge_addr(bridge_addr),.bridge_rd(bridge_rd),.bridge_rd_data(bridge_rd_data),.bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
  .status_boot_done(1'b1),.status_setup_done(1'b0),.status_running(reset_n),
  .dataslot_requestread(),.dataslot_requestread_id(),.dataslot_requestread_ack(1'b1),.dataslot_requestread_ok(1'b1),
  .dataslot_requestwrite(requestwrite),.dataslot_requestwrite_id(request_id),.dataslot_requestwrite_size(request_size),
  .dataslot_requestwrite_ack(1'b1),.dataslot_requestwrite_ok(1'b1),.dataslot_update(),.dataslot_update_id(),.dataslot_update_size(),.dataslot_allcomplete(allcomplete),
  .rtc_epoch_seconds(),.rtc_date_bcd(),.rtc_time_bcd(),.rtc_valid(),.osnotify_inmenu(),.osnotify_docked(),
  .savestate_supported(1'b0),.savestate_addr(32'd0),.savestate_size(32'd0),.savestate_maxloadsize(32'd0),
  .savestate_start(),.savestate_start_ack(1'b0),.savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),
  .savestate_load(),.savestate_load_ack(1'b0),.savestate_load_busy(1'b0),.savestate_load_ok(1'b0),.savestate_load_err(1'b0),
  .target_dataslot_read(1'b0),.target_dataslot_write(1'b0),.target_dataslot_getfile(1'b0),.target_dataslot_openfile(1'b0),
  .target_dataslot_ack(),.target_dataslot_done(),.target_dataslot_err(),.target_dataslot_id(16'd0),
  .target_dataslot_slotoffset(32'd0),.target_dataslot_bridgeaddr(32'd0),.target_dataslot_length(32'd0),
  .target_buffer_param_struct(32'd0),.target_buffer_resp_struct(32'd0),
  .datatable_addr(10'd0),.datatable_wren(1'b0),.datatable_data(32'd0),.datatable_q()
 );
 wire rom_dl,rom_wr,nv_dl,nv_wr;wire[15:0]rom_index,nv_index;
 wire[24:0]rom_addr;wire[6:0]nv_addr;wire[7:0]rom_data,nv_data;
 wire rom_drained,nv_drained;
 data_io #(.MASK(0),.AW(25),.DW(8),.DELAY(7),.HOLD(4)) rom_loader(
  .clk_74a(clk_74a),.clk_memory(clk_memory),.dataslot_requestwrite(requestwrite),.dataslot_requestwrite_id(request_id),.dataslot_allcomplete(allcomplete),
  .bridge_endian_little(bridge_endian_little),.bridge_addr(bridge_addr),.bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
`ifdef APF_DRAINED
  .ioctl_drained(rom_drained),
`endif
  .ioctl_download(rom_dl),.ioctl_index(rom_index),.ioctl_wr(rom_wr),.ioctl_addr(rom_addr),.ioctl_data(rom_data));
 data_io #(.MASK(2),.AW(7),.DW(8),.DELAY(7),.HOLD(4)) nv_loader(
  .clk_74a(clk_74a),.clk_memory(clk_memory),.dataslot_requestwrite(requestwrite),.dataslot_requestwrite_id(request_id),.dataslot_allcomplete(allcomplete),
  .bridge_endian_little(bridge_endian_little),.bridge_addr(bridge_addr),.bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
`ifdef APF_DRAINED
  .ioctl_drained(nv_drained),
`endif
  .ioctl_download(nv_dl),.ioctl_index(nv_index),.ioctl_wr(nv_wr),.ioctl_addr(nv_addr),.ioctl_data(nv_data));
`ifndef APF_DRAINED
 assign rom_drained=1'b1,nv_drained=1'b1;
`endif
 // Consumer gating matches current top slot0 ROM / slot1 NV. Added drained
 // gate is used only when the new public ABI exists, not as an old-DUT fix.
 wire dl_we=rom_dl && rom_index==0 && rom_wr;
 wire nv_we=nv_dl && nv_index==1 && nv_wr;
 reg init=1,mystic=0;wire mem_ready,img_we;wire[6:0]img_addr;wire[7:0]img_data;
 reg prog_req=0;reg[21:0]prog_addr=0;wire prog_ack;wire[15:0]prog_q;wire[31:0]sd_errors;
 tb_m2_mem_top memory(
  .clk(clk_memory),.init(init),.mystic(mystic),.ready(mem_ready),.rd_late(1'b1),.burst_slow(1'b0),.ps_slow(1'b0),.sram_slow(1'b0),.sram_slow_wr(1'b0),
  .tile_fifth(),.spr_fifth(),.test_mask(),.sd_read_pulse(),.sd_read_word(),.sd_protocol_errors(sd_errors),
  .test_start(1'b0),.test_run(),.test_done(),.test_ok(),.test_stable(),.vram_ok(),.vram_bad(),
  .dl_we(dl_we),.dl_addr(rom_addr),.dl_data(rom_data),.eep_we(img_we),.eep_addr(img_addr),.eep_data(img_data),
  .prog_req(prog_req),.prog_addr(prog_addr),.prog_ack(prog_ack),.prog_q(prog_q),
  .tile_req(1'b0),.tile_addr(19'd0),.tile_ack(),.tile_q(),.map_req(1'b0),.map_addr(20'd0),.map_ack(),.map_q(),
  .blk_req(1'b0),.blk_addr(16'd0),.blk_wr(),.blk_idx(),.blk_data(),.blk_ack(),
  .spr_req(1'b0),.spr_addr(20'd0),.spr_ack(),.spr_q(),.snd_req(1'b0),.snd_addr(18'd0),.snd_ack(),.snd_q(),
  .pcm_req(1'b0),.pcm_addr(22'd0),.pcm_ack(),.pcm_q(),
  .vram_req(1'b0),.vram_we(1'b0),.vram_addr(16'd0),.vram_be(2'b11),.vram_wdata(16'd0),.vram_ack(),.vram_q());
 reg[6:0]read_addr=0;wire[7:0]eep_q;wire dirty;
 wire eep_we=img_we|nv_we;wire[6:0]eep_addr=img_we?img_addr:nv_we?nv_addr:read_addr;
 er5911 eeprom(.clk(clk_memory),.reset(1'b1),.cs(1'b0),.sclk(1'b0),.di(1'b0),.dout(),.ready(),.dirty(dirty),
  .ld_we(eep_we),.ld_addr(eep_addr),.ld_wdata(img_we?img_data:nv_data),.ld_q(eep_q));
 reg loaded=0;always@(posedge clk_74a)if(allcomplete)loaded<=1;
 wire loaded_s,reset_s;synch_3 ls(loaded,loaded_s,clk_memory);synch_3 rs(reset_n,reset_s,clk_memory);
 wire release_ok=loaded_s && reset_s && mem_ready && rom_drained && nv_drained;
 reg old_rom_wr=0,old_nv_wr=0,old_nv_we=0;integer rom_raw=0,nv_raw=0,nv_consumed=0,wrong_slot=0,dropped=0,early_release=0,errors=0;
 reg[7:0]prefix[0:63],nv[0:127];integer scenario=0,i,k,waits=0;reg[24:0]eep_base;reg[31:0]little,v;string prefix_path,nv_path;
 always@(posedge clk_memory)begin
  old_rom_wr<=rom_wr;old_nv_wr<=nv_wr;old_nv_we<=nv_we;
  if(rom_wr&&!old_rom_wr)begin
   rom_raw=rom_raw+1;if(rom_index!==16'd0)begin wrong_slot=wrong_slot+1;$display("WRONG_SLOT ROM index=%h addr=%h",rom_index,rom_addr);end
   if(!dl_we)dropped=dropped+1;
  end
  if(nv_wr&&!old_nv_wr)begin
   nv_raw=nv_raw+1;if(nv_index!==16'd1)begin wrong_slot=wrong_slot+1;$display("WRONG_SLOT NV index=%h addr=%h",nv_index,nv_addr);end
   if(nv_data!==nv[nv_addr])begin errors=errors+1;$display("NV raw data mismatch addr=%h got=%h want=%h",nv_addr,nv_data,nv[nv_addr]);end
   if(!nv_we)dropped=dropped+1;
  end
  if(nv_we&&!old_nv_we)nv_consumed=nv_consumed+1;
  if(release_ok && nv_consumed<128)early_release=early_release+1;
 end
 function[31:0]swap(input[31:0]x);swap={x[7:0],x[15:8],x[23:16],x[31:24]};endfunction
 task put(input[31:0]addr,input[31:0]data);begin
  @(negedge clk_74a);bridge_addr=addr;bridge_wr_data=data;bridge_wr=1;
  @(negedge clk_74a);bridge_wr=0;
 end endtask
 task parameter_slot(input[15:0]slot,input[31:0]size);begin
  put(32'hf8000020,bridge_endian_little?swap({16'd0,slot}):{16'd0,slot});
  put(32'hf8000024,bridge_endian_little?swap(size):size);
 end endtask
 task command(input[15:0]cmd);integer n;reg[31:0]status;begin
  put(32'hf8000000,bridge_endian_little?swap({16'h434d,cmd}):{16'h434d,cmd});
  n=0;status=0;
  while(status[31:16]!=16'h4f4b && n<80)begin
   @(negedge clk_74a);bridge_addr=32'hf8000000;bridge_rd=1;
   @(negedge clk_74a);status=bridge_endian_little?swap(bridge_rd_data):bridge_rd_data;bridge_rd=0;n=n+1;
  end
  if(n>=80||status[15:0]!=0)begin $display("COMMAND ERROR cmd=%h status=%h",cmd,status);$fatal(2,"real command parser failed");end
 end endtask
 task slot(input[15:0]id,input[31:0]size);begin parameter_slot(id,size);command(16'h0082);end endtask
 task data_word(input[31:0]addr,input[31:0]le,input integer spaced);begin
  put(addr,bridge_endian_little?le:swap(le));if(spaced)repeat(73)@(negedge clk_74a);
 end endtask
 initial begin
  if(!$value$plusargs("GAME=%d",mystic))mystic=0;
  if(!$value$plusargs("CASE=%d",scenario))scenario=0;
  if(!$value$plusargs("ENDIAN=%d",bridge_endian_little))bridge_endian_little=0;
  if(!$value$plusargs("PREFIX=%s",prefix_path)||!$value$plusargs("NV=%s",nv_path))$fatal(2,"missing original inputs");
  $readmemh(prefix_path,prefix);$readmemh(nv_path,nv);eep_base=mystic?25'h0dc0000:25'h1360000;
  repeat(16)@(negedge clk_memory);init=0;
  while(!mem_ready&&waits<100000)begin @(negedge clk_memory);waits=waits+1;end
  if(!mem_ready)$fatal(2,"memory startup timeout");repeat(20)@(negedge clk_74a);
  command(16'h0010);slot(0,192);
  for(i=0;i<64;i=i+4)begin little={prefix[i+3],prefix[i+2],prefix[i+1],prefix[i]};data_word(i,little,1);end
  // A new index is staged in command parameters before the last original
  // default word; the command itself still arrives strictly after that word.
  for(i=0;i<128;i=i+4)begin
   if(scenario==3&&i==124)parameter_slot(1,128);
   little={nv[i+3],nv[i+2],nv[i+1],nv[i]};data_word(eep_base+i,little,!(scenario==3&&i==124));
  end
  if(scenario==3)command(16'h0082);else slot(1,128);
  for(i=0;i<128;i=i+4)begin
   if(scenario==2&&i==124)parameter_slot(0,4);
   little={nv[i+3],nv[i+2],nv[i+1],nv[i]};data_word(32'h20000000+i,little,!(i==124&&(scenario==1||scenario==2)));
  end
  if(scenario==2)begin command(16'h0082);data_word(0,{prefix[3],prefix[2],prefix[1],prefix[0]},1);end
  command(16'h008f);command(16'h0011);repeat(300)@(negedge clk_memory);
  if(nv_raw!=128||nv_consumed!=128)begin errors=errors+1;$display("NV COUNT raw=%0d consumed=%0d expected128",nv_raw,nv_consumed);end
  for(i=0;i<128;i=i+1)begin read_addr=i;repeat(3)@(negedge clk_memory);if(eep_q!==nv[i])begin errors=errors+1;$display("EEPROM readback mismatch at%0d got=%h want=%h",i,eep_q,nv[i]);end end
  for(i=0;i<32;i=i+1)begin
   prog_addr=i;prog_req=1;k=0;while(!prog_ack&&k<1000)begin @(negedge clk_memory);k=k+1;end
   if(!prog_ack||prog_q!=={prefix[2*i],prefix[2*i+1]})begin errors=errors+1;$display("ROM public read mismatch at%0d got=%h",i,prog_q);end
   prog_req=0;repeat(3)@(negedge clk_memory);
  end
  if(sd_errors!==0)begin errors=errors+1;$display("SDRAM model protocol errors=%d",sd_errors);end
  $display("RESULT_JSON {\"passed\":%s,\"scenario\":%0d,\"game_mystic\":%0d,\"endian\":%0d,\"phase_ps\":%0d,\"raw_rom_bytes\":%0d,\"raw_nv_bytes\":%0d,\"consumed_nv_bytes\":%0d,\"wrong_slot_bytes\":%0d,\"dropped_bytes\":%0d,\"early_release_cycles\":%0d,\"other_errors\":%0d}",wrong_slot==0&&dropped==0&&early_release==0&&errors==0?"true":"false",scenario,mystic,bridge_endian_little,phase_ps,rom_raw,nv_raw,nv_consumed,wrong_slot,dropped,early_release,errors);
  if(wrong_slot||dropped||early_release||errors)$fatal(1,"APF transfer invariant failed");$finish;
 end
 initial begin #10000000;$fatal(2,"global watchdog");end
endmodule
