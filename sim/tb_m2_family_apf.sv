`timescale 1ns/1ps
// Public APF transaction bench. Extracted top spans are included by the runner.
// RAM ACK/readiness/test-completion API is explicit, not a memory or CPU model.
module tb_m2_family_apf;
 reg clk_sys=0,clk_74a=0;
 always #5.208333 clk_sys=~clk_sys;
 initial begin #1.7; forever #6.734007 clk_74a=~clk_74a;end
 reg bridge_endian_little=0,bridge_rd=0,bridge_wr=0;
 reg[31:0]bridge_addr=0,bridge_wr_data=0;logic[31:0]bridge_rd_data;
 wire[31:0]cmd_bridge_rd_data,nvm_bridge_rd_data_s;
 wire reset_n,dataslot_requestwrite,dataslot_allcomplete,osnotify_inmenu;
 wire[15:0]dataslot_requestwrite_id;wire[31:0]dataslot_requestwrite_size;
 logic target_dataslot_read,target_dataslot_write,target_dataslot_getfile,target_dataslot_openfile;
 wire target_dataslot_ack,target_dataslot_done;wire[2:0]target_dataslot_err;
 logic[15:0]target_dataslot_id;
 logic[31:0]target_dataslot_slotoffset,target_dataslot_bridgeaddr,target_dataslot_length;
 localparam DIO_DELAY=7,DIO_HOLD=4;
 wire[31:0]int_bridge_rd_data=0;assign ana_bridge_rd_data=0;
 wire reset_sw=~reset_n;
 reg pll_core_locked=0;reg memory_ready_api=0;
 wire ioctl_download,ioctl_wr,ioctl_drained;wire[15:0]ioctl_index;
 wire[26:0]ioctl_addr;wire[7:0]ioctl_data;
 data_io #(.MASK(0),.AW(27),.DW(8),.DELAY(DIO_DELAY),.HOLD(DIO_HOLD)) rom_io(
 .clk_74a(clk_74a),.clk_memory(clk_sys),.dataslot_requestwrite(dataslot_requestwrite),.dataslot_requestwrite_id(dataslot_requestwrite_id),.dataslot_allcomplete(dataslot_allcomplete),
 .bridge_endian_little(bridge_endian_little),.bridge_addr(bridge_addr),.bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
 .ioctl_download(ioctl_download),.ioctl_wr(ioctl_wr),.ioctl_drained(ioctl_drained),.ioctl_index(ioctl_index),.ioctl_addr(ioctl_addr),.ioctl_data(ioctl_data));
 `include "family_top_extract.svh"
 core_bridge_cmd bridge(
 .clk(clk_74a),.reset_n(reset_n),.bridge_endian_little(bridge_endian_little),.bridge_addr(bridge_addr),.bridge_rd(bridge_rd),.bridge_rd_data(cmd_bridge_rd_data),.bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
 .status_boot_done(1'b1),.status_setup_done(1'b0),.status_running(reset_n),
 .dataslot_requestread(),.dataslot_requestread_id(),.dataslot_requestread_ack(1'b1),.dataslot_requestread_ok(1'b1),
 .dataslot_requestwrite(dataslot_requestwrite),.dataslot_requestwrite_id(dataslot_requestwrite_id),.dataslot_requestwrite_size(dataslot_requestwrite_size),.dataslot_requestwrite_ack(1'b1),.dataslot_requestwrite_ok(1'b1),
 .dataslot_update(),.dataslot_update_id(),.dataslot_update_size(),.dataslot_allcomplete(dataslot_allcomplete),.rtc_epoch_seconds(),.rtc_date_bcd(),.rtc_time_bcd(),.rtc_valid(),.osnotify_inmenu(osnotify_inmenu),.osnotify_docked(),
 .savestate_supported(1'b0),.savestate_addr(32'd0),.savestate_size(32'd0),.savestate_maxloadsize(32'd0),.savestate_start(),.savestate_start_ack(1'b0),.savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),.savestate_load(),.savestate_load_ack(1'b0),.savestate_load_busy(1'b0),.savestate_load_ok(1'b0),.savestate_load_err(1'b0),
 .target_dataslot_read(target_dataslot_read),.target_dataslot_write(target_dataslot_write),.target_dataslot_getfile(target_dataslot_getfile),.target_dataslot_openfile(target_dataslot_openfile),.target_dataslot_ack(target_dataslot_ack),.target_dataslot_done(target_dataslot_done),.target_dataslot_err(target_dataslot_err),.target_dataslot_id(target_dataslot_id),.target_dataslot_slotoffset(target_dataslot_slotoffset),.target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),.target_dataslot_length(target_dataslot_length),.target_buffer_param_struct(32'd0),.target_buffer_resp_struct(32'd0),
 .datatable_addr(datatable_addr),.datatable_wren(datatable_wren),.datatable_data(datatable_data),.datatable_q(datatable_q));
 wire pending;wire[6:0]queue_used;
 source_default_download download(.clk(clk_sys),.init(mem_init),.mystic(mystic_profile),.dl_we(dl_we),.dl_addr(dl_addr),.dl_data(dl_data),.eep_we(img_eep_we),.eep_addr(img_eep_addr),.eep_data(img_eep_data),.pending(pending),.queue_used(queue_used));
 er5911 eeprom(.clk(clk_sys),.reset(ga_reset),.cs(1'b0),.sclk(1'b0),.di(1'b0),.dout(),.ready(),.dirty(po_nv_dirty),.ld_we(eep_we),.ld_addr(eep_addr),.ld_wdata(eep_wdata),.ld_q(nv_rd_data));
 assign mem_ready=memory_ready_api;
 reg test_run_api=0,test_done_api=0;integer test_wait=0,test_starts=0;
 assign test_run=test_run_api;assign test_done=test_done_api;
 assign test_ok=0;assign test_stable=0;assign vram_ok=0;assign vram_bad=0;
 integer sys_count=0,rom_count=0,nv_count=0,default_count=0,release_count=0,save_count=0;
 reg old_dl=0,old_nv=0,old_save=0;
 integer scenario=0,game=0,save_present=0,expected_size=0,errors=0;
 byte unsigned rom[0:20316287];byte unsigned stored[0:127],expected[0:127];
 reg[127:0]default_seen=0,nv_seen=0;
 always @(posedge clk_sys) begin
  sys_count<=sys_count+1;
  if(sys_count==16)pll_core_locked<=1;
  if(sys_count==32)memory_ready_api<=1;
  test_done_api<=0;
  if(test_start)begin test_starts<=test_starts+1;test_wait<=64;test_run_api<=1;end
  else if(test_wait>0)begin test_wait<=test_wait-1;if(test_wait==1)begin test_run_api<=0;test_done_api<=1;end end
  old_dl<=dl_we;old_nv<=nv_load_we;
  if(dl_we&&!old_dl)begin
   if(scenario!=1 && (32'(dl_addr)!==rom_count || dl_data!==rom[rom_count]))$fatal(2,"ROM consumer ordering/data mismatch at%h count%0d",dl_addr,rom_count);
   rom_count<=rom_count+1;
  end
  if(img_eep_we)begin
   default_count<=default_count+1;default_seen[img_eep_addr]<=1;
   if(img_eep_data!==rom[expected_size-128+32'(img_eep_addr)])$fatal(2,"original EEPROM default mismatch");
  end
  if(nv_load_we&&!old_nv)begin nv_count<=nv_count+1;nv_seen[nv_dl_addr]<=1;if(nv_dl_data!==stored[nv_dl_addr])$fatal(2,"stored fixture mismatch");end
  if(queue_used>=64)$fatal(2,"word FIFO overflow");
  if(!ga_reset)begin
   release_count<=release_count+1;
   if(scenario!=0||!rom_valid||!rom_identified||!ioctl_drained||!nv_dl_drained||!initial_test_done||rom_count!=expected_size||default_count!=128||default_seen!={128{1'b1}}||((save_present!=0)&&(nv_count!=128||nv_seen!={128{1'b1}})))$fatal(2,"release before complete original image/default/save/drain/test");
  end
 end
 always @(posedge clk_74a)begin
  if($test$plusargs("TABLE_TRACE") && (sys_count<24 || bridge_rd))begin
   $display("TABLE_TRACE time=%0t addr=%0d we=%b data=%h qa=%h bridge_rd=%b bridge_addr=%h cmd=%h mux=%h",$time,datatable_addr,datatable_wren,datatable_data,datatable_q,bridge_rd,bridge_addr,cmd_bridge_rd_data,bridge_rd_data);$fflush();
  end
  old_save<=target_dataslot_write;
  if(target_dataslot_write&&!old_save)begin
   save_count<=save_count+1;
   if(ga_reset||!image_ready_bridge||target_dataslot_id!=2||target_dataslot_bridgeaddr!=32'h20000000||target_dataslot_length!=128||target_dataslot_slotoffset!=0)$fatal(2,"bad/early save target transaction");
  end
 end
 function automatic[31:0]swap(input[31:0]v);return{v[7:0],v[15:8],v[23:16],v[31:24]};endfunction
 task automatic put(input[31:0]a,input[31:0]v);begin @(negedge clk_74a);bridge_addr=a;bridge_wr_data=v;bridge_wr=1;@(negedge clk_74a);bridge_wr=0;end endtask
 task automatic putlogical(input[31:0]a,input[31:0]v);put(a,bridge_endian_little?swap(v):v);endtask
 task automatic getlogical(input[31:0]a,output[31:0]v);begin
 @(negedge clk_74a);bridge_addr=a;bridge_rd=1;repeat(4)@(negedge clk_74a);v=bridge_endian_little?swap(bridge_rd_data):bridge_rd_data;bridge_rd=0;end endtask
 task automatic command(input[15:0]cmd);integer n;reg[31:0]v;begin
 putlogical(32'hf8000000,{16'h434d,cmd});n=0;v=0;
 while(v[31:16]!=16'h4f4b&&n<100)begin getlogical(32'hf8000000,v);n++;end
 if(n>=100||v[15:0]!=0)$fatal(2,"command%h failed status%h",cmd,v);
 end endtask
 task automatic slot(input[15:0]id,input integer size);begin putlogical(32'hf8000020,{16'd0,id});putlogical(32'hf8000024,size);command(16'h0082);end endtask
 task automatic bytes_word(input[31:0]a,input[31:0]le);begin put(a,bridge_endian_little?le:swap(le));repeat(73)@(negedge clk_74a);end endtask
 task automatic unload(input integer pass);integer i,j,fd;reg[31:0]v,le;string outpath;begin
 putlogical(32'hf8000020,2);putlogical(32'hf8000024,128);command(16'h0080);
 if(!$value$plusargs("OUT=%s",outpath))$fatal(2,"OUT path missing");
 fd=$fopen($sformatf("%s-%0d.bin",outpath,pass),"wb");if(fd==0)$fatal(2,"unload output open");
 for(i=0;i<128;i+=4)begin
 @(negedge clk_74a);bridge_addr=32'h20000000+i;bridge_rd=1;
 @(negedge clk_74a);bridge_rd=0;repeat(100)@(negedge clk_74a);
 le=bridge_endian_little?bridge_rd_data:swap(bridge_rd_data);
 for(j=0;j<4;j++)begin
 if(le[8*j+:8]!==expected[i+j])$fatal(2,"unload pass%0d addr%0d got%h want%h",pass,i+j,le[8*j+:8],expected[i+j]);
 $fwrite(fd,"%c",le[8*j+:8]);end
 end
 $fclose(fd);end endtask
 integer fd,i,n,got;reg[31:0]v,word_le;string rom_path,nv_path;
 initial begin
 if(!$value$plusargs("SCENARIO=%d",scenario))scenario=0;
 if(!$value$plusargs("GAME=%d",game))game=0;
 if(!$value$plusargs("ENDIAN=%d",bridge_endian_little))bridge_endian_little=0;
 if(!$value$plusargs("SAVE=%d",save_present))save_present=0;
 if(!$value$plusargs("ROM=%s",rom_path)||!$value$plusargs("NV=%s",nv_path))$fatal(2,"original file paths missing");
 expected_size=(game!=0)?14418048:20316288;
 fd=$fopen(rom_path,"rb");got=$fread(rom,fd);$fclose(fd);if(got!=expected_size)$fatal(2,"original image size mismatch %0d",got);
 fd=$fopen(nv_path,"rb");got=$fread(stored,fd);$fclose(fd);if(got!=128)$fatal(2,"stored fixture size");
 for(i=0;i<128;i++)expected[i]=(save_present!=0)?stored[i]:rom[expected_size-128+i];
 repeat(80)@(negedge clk_74a);command(16'h0010);
 getlogical(32'hf8002014,v);if(v!=128)$fatal(2,"public table5 !=128: %h",v);
 slot(scenario==1?0:1,scenario==0?expected_size:256);
 for(i=0;i<(scenario==0?expected_size:256);i+=4)begin
 word_le={rom[i+3],rom[i+2],rom[i+1],rom[i]};bytes_word(i,word_le);
 if((i&'hfffff)==0)begin $display("PROGRESS game%0d scenario%0d bytes%0d/%0d",game,scenario,i,expected_size);$fflush();end
 end
 // Do not insert a special drain wait between the original default tail and the next public slot.
 if((save_present!=0)&&scenario==0)begin slot(2,128);for(i=0;i<128;i+=4)bytes_word(32'h20000000+i,{stored[i+3],stored[i+2],stored[i+1],stored[i]});end
 command(16'h008f);command(16'h0011);
 if(scenario!=0)begin
 repeat(6000)@(negedge clk_74a);
 if(!ga_reset||rom_valid||(save_count!=0)||(release_count!=0)||(scenario==1&&(rom_count!=0)))$fatal(2,"negative input released or saved");
 if(scenario==2&&!rom_identified)$fatal(2,"truncated prefix did not identify");
 end else begin
 n=0;while(ga_reset&&n<10000)begin @(negedge clk_74a);n++;end
 if(ga_reset||32'(mystic_profile)!=game||rom_count!=expected_size||default_count!=128||test_starts<1)$fatal(2,"full image release/profile/default/test failed");
 n=0;v=0;while(v!=32'h636d0184&&n<6000)begin getlogical(32'hf8001000,v);n++;end
 if(v!=32'h636d0184)$fatal(2,"boot save0184 missing status%h",v);
 getlogical(32'hf8001020,v);if(v!=2)$fatal(2,"save ID !=2");getlogical(32'hf8001024,v);if(v!=0)$fatal(2,"offset !=0");
 getlogical(32'hf8001028,v);if(v!=32'h20000000)$fatal(2,"save bridgeaddr");getlogical(32'hf800102c,v);if(v!=128)$fatal(2,"save length");
 putlogical(32'hf8001000,32'h62750000);repeat(10)@(negedge clk_74a);
 unload(0);putlogical(32'hf8001000,32'h6f6b0000);repeat(20)@(negedge clk_74a);
 command(16'h0010);repeat(50)@(negedge clk_74a);if(!ga_reset)$fatal(2,"host reset not effective");unload(1);
 if(default_count!=128||nv_count!=((save_present!=0)?128:0)||save_count!=1)$fatal(2,"final consumer/target counts");
 end
 $display("RESULT_JSON {\"passed\":true,\"scenario\":%0d,\"game\":%0d,\"endian\":%0d,\"save_present\":%0d,\"rom_bytes\":%0d,\"default_bytes\":%0d,\"stored_bytes\":%0d,\"test_starts\":%0d,\"save_requests\":%0d,\"release_cycles\":%0d,\"unload_bytes\":%0d}",scenario,game,bridge_endian_little,save_present,rom_count,default_count,nv_count,test_starts,save_count,release_count,scenario==0?256:0);$fflush();$finish;
 end
 initial begin #15000000000;$fatal(2,"virtual watchdog15s");end
endmodule

// BEGIN FAMILY_APF_TABLE_MODEL
`ifdef FAMILY_APF_TABLE_MODEL
// Simulation backend for the unchanged mf_datatable public ABI. Parameters
// mirror the generated Intel wrapper: 256x32, registered input addresses and
// registered outputs, same-port NEW_DATA_NO_NBE_READ. Physical M10K timing and
// different-data simultaneous dual-port write collisions are outside scope.
module mf_datatable #(
 parameter WIDTH=32, ADDRESS_BITS=8,
 parameter INIT_FILE="../target/pocket/build_id-table.hex"
)(input wire[ADDRESS_BITS-1:0] address_a,address_b,
 input wire clock_a,clock_b,
 input wire[WIDTH-1:0]data_a,data_b,input wire wren_a,wren_b,
 output logic[WIDTH-1:0]q_a,q_b);
 logic[WIDTH-1:0]mem[0:(1<<ADDRESS_BITS)-1];
 logic[ADDRESS_BITS-1:0]a_reg=0,b_reg=0;
 logic[WIDTH-1:0]a_data_reg=0,b_data_reg=0;
 logic a_we=0,b_we=0;
 // Runner converts the pinned MIF verbatim data into 256 hex words; no game
 // data or table value is invented by this model.
 initial begin
  q_a=0;q_b=0;
  $readmemh(INIT_FILE,mem);
 end
 always @(posedge clock_a)begin
  a_reg<=address_a;a_we<=wren_a;a_data_reg<=data_a;
  q_a<=a_we?a_data_reg:mem[a_reg];
  if(wren_a)mem[address_a]<=data_a;
 end
 always @(posedge clock_b)begin
  b_reg<=address_b;b_we<=wren_b;b_data_reg<=data_b;
  q_b<=b_we?b_data_reg:mem[b_reg];
  if(wren_b)mem[address_b]<=data_b;
 end
endmodule
`endif
// END FAMILY_APF_TABLE_MODEL
