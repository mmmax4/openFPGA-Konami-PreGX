`timescale 1ns/1ps
// Real parser + verbatim extracted controller; all stimulus uses public ports.
module tb_m2_apf_save;
 reg clk_74a=0;
 always #6.734007 clk_74a=~clk_74a;
 reg bridge_wr=0,bridge_rd=0,bridge_endian_little=0;
 reg[31:0]bridge_addr=0,bridge_wr_data=0;wire[31:0]bridge_rd_data;
 wire reset_n,requestwrite,allcomplete,osnotify_inmenu;wire[15:0]request_id;wire[31:0]request_size;
 wire target_read,target_write,target_getfile,target_openfile,target_ack,target_done;
 wire[2:0]target_err;wire[15:0]target_id;wire[31:0]target_offset,target_address,target_length;
 reg dirty_toggle=0;
 extracted_save_controller controller(
  .clk_74a(clk_74a),.reset_n(reset_n),.dirty_toggle(dirty_toggle),.osnotify_inmenu(osnotify_inmenu),.dataslot_allcomplete(allcomplete),
  .target_dataslot_ack(target_ack),.target_dataslot_done(target_done),.target_dataslot_err(target_err),
  .target_dataslot_read(target_read),.target_dataslot_write(target_write),.target_dataslot_getfile(target_getfile),.target_dataslot_openfile(target_openfile),
  .target_dataslot_id(target_id),.target_dataslot_slotoffset(target_offset),.target_dataslot_bridgeaddr(target_address),.target_dataslot_length(target_length));
 core_bridge_cmd bridge(
  .clk(clk_74a),.reset_n(reset_n),.bridge_endian_little(bridge_endian_little),
  .bridge_addr(bridge_addr),.bridge_rd(bridge_rd),.bridge_rd_data(bridge_rd_data),.bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
  .status_boot_done(1'b1),.status_setup_done(1'b0),.status_running(reset_n),
  .dataslot_requestread(),.dataslot_requestread_id(),.dataslot_requestread_ack(1'b1),.dataslot_requestread_ok(1'b1),
  .dataslot_requestwrite(requestwrite),.dataslot_requestwrite_id(request_id),.dataslot_requestwrite_size(request_size),
  .dataslot_requestwrite_ack(1'b1),.dataslot_requestwrite_ok(1'b1),.dataslot_update(),.dataslot_update_id(),.dataslot_update_size(),.dataslot_allcomplete(allcomplete),
  .rtc_epoch_seconds(),.rtc_date_bcd(),.rtc_time_bcd(),.rtc_valid(),.osnotify_inmenu(osnotify_inmenu),.osnotify_docked(),
  .savestate_supported(1'b0),.savestate_addr(32'd0),.savestate_size(32'd0),.savestate_maxloadsize(32'd0),
  .savestate_start(),.savestate_start_ack(1'b0),.savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),
  .savestate_load(),.savestate_load_ack(1'b0),.savestate_load_busy(1'b0),.savestate_load_ok(1'b0),.savestate_load_err(1'b0),
  .target_dataslot_read(target_read),.target_dataslot_write(target_write),.target_dataslot_getfile(target_getfile),.target_dataslot_openfile(target_openfile),
  .target_dataslot_ack(target_ack),.target_dataslot_done(target_done),.target_dataslot_err(target_err),.target_dataslot_id(target_id),
  .target_dataslot_slotoffset(target_offset),.target_dataslot_bridgeaddr(target_address),.target_dataslot_length(target_length),
  .target_buffer_param_struct(32'd0),.target_buffer_resp_struct(32'd0),
  .datatable_addr(10'd0),.datatable_wren(1'b0),.datatable_data(32'd0),.datatable_q()
 );
 integer scenario=0,rises=0,errors=0,timeouts=0,reset_requests=0,reads=0;
 integer cycles=0,dirty_at=0,run_at=0,first_request_at=0,kick_latency=0;
 reg previous_write=0,previous_run=0;reg[31:0]value;reg found;
 always@(posedge clk_74a)begin
  cycles=cycles+1;previous_write<=target_write;previous_run<=reset_n;
  if(reset_n&&!previous_run)run_at=cycles;
  if(target_write&&!previous_write)begin
   if(rises==0)first_request_at=cycles;
   rises=rises+1;if(!reset_n)reset_requests=reset_requests+1;
  end
 end
 task put(input[31:0]addr,input[31:0]data);begin
  @(negedge clk_74a);bridge_addr=addr;bridge_wr_data=data;bridge_wr=1;
  @(negedge clk_74a);bridge_wr=0;
 end endtask
 task read_bridge(input[31:0]addr,output[31:0]data);begin
  @(negedge clk_74a);bridge_addr=addr;bridge_rd=1;
  @(negedge clk_74a);data=bridge_rd_data;bridge_rd=0;reads=reads+1;
 end endtask
 task host(input[15:0]cmd);integer n;reg[31:0]status;begin
  put(32'hf8000000,{16'h434d,cmd});n=0;status=0;
  while(status[31:16]!=16'h4f4b&&n<80)begin read_bridge(32'hf8000000,status);n=n+1;end
  if(n>=80||status[15:0]!=0)$fatal(2,"host command failed %h %h",cmd,status);
 end endtask
 task dirty;begin @(negedge clk_74a);dirty_toggle=~dirty_toggle;dirty_at=cycles;end endtask
 task await_command(input integer count,output reg ok);integer n;reg[31:0]status,id,offset,address,length;begin
  n=0;ok=0;
  while(!ok&&n<100)begin
   read_bridge(32'hf8001000,status);n=n+1;
   if(status==32'h636d0184&&rises>=count)ok=1;
  end
  if(!ok)begin timeouts=timeouts+1;errors=errors+1;$display("MISSING_COMMAND wanted%0d rises%0d status%h",count,rises,status);end
  else begin
   read_bridge(32'hf8001020,id);read_bridge(32'hf8001024,offset);read_bridge(32'hf8001028,address);read_bridge(32'hf800102c,length);
   if(id!=1||offset!=0||address!=32'h20000000||length!=128)begin errors=errors+1;$display("PARAMETER_MISMATCH %h %h %h %h",id,offset,address,length);end
  end
 end endtask
 task busy;begin put(32'hf8001000,32'h62750000);repeat(5)@(negedge clk_74a);end endtask
 task done(input[2:0]err);begin put(32'hf8001000,32'h6f6b0000|{29'd0,err});repeat(5)@(negedge clk_74a);end endtask
 initial begin
  if(!$value$plusargs("CASE=%d",scenario))scenario=0;
  repeat(20)@(negedge clk_74a);host(16'h0010);host(16'h008f);
  if(scenario!=4)host(16'h0011);
  if(scenario!=5)dirty;
  if(scenario==5)begin
   // No dirty event at all: first-save creation must come from boot timing.
   repeat(4000)@(negedge clk_74a);
   if(rises!=0)begin errors=errors+1;$display("EARLY_BOOT_REQUEST %0d",rises);end
   await_command(1,found);
   kick_latency=first_request_at-run_at;
   if(kick_latency<4095||kick_latency>4098)begin errors=errors+1;$display("BOOT_KICK_LATENCY %0d",kick_latency);end
   if(found)begin busy;done(0);end
   repeat(150)@(negedge clk_74a);
   if(rises!=1||dirty_toggle!=0)begin errors=errors+1;$display("BOOT_REPEAT_OR_DIRTY %0d",rises);end
  end else if(scenario==6)begin
   // Enter menu through the real host parser before the24-cycle settle.
   put(32'hf8000020,32'd1);host(16'h00b0);await_command(1,found);
   kick_latency=first_request_at-dirty_at;
   if(kick_latency<=0||kick_latency>=24)begin errors=errors+1;$display("MENU_NOT_EARLY_KICK %0d",kick_latency);end
   if(found)begin busy;done(0);end
   repeat(100)@(negedge clk_74a);
   if(rises!=1)begin errors=errors+1;$display("MENU_DUPLICATE_REQUEST %0d",rises);end
  end else if(scenario==4)begin
   repeat(100)@(negedge clk_74a);
   if(rises!=0)begin errors=errors+1;$display("RESET_EMIT rises%0d",rises);end
   host(16'h0011);await_command(1,found);if(found)begin busy;done(0);end
  end else begin
   await_command(1,found);
   if(found)begin
    case(scenario)
     0: begin busy;done(0);repeat(100)@(negedge clk_74a);if(rises!=1)begin errors=errors+1;$display("UNEXPECTED_EXTRA_SUCCESS_COMMAND %0d",rises);end end
     1: begin busy;done(1);await_command(2,found);if(found)begin busy;done(0);end end
     2: begin
      busy;dirty;repeat(40)@(negedge clk_74a);
      if(rises!=1)begin errors=errors+1;$display("PARALLEL_COMMAND_FIRST %0d",rises);end
      done(0);
      // Observe the public request edge, before the parser retires old done.
      begin integer n;n=0;while(rises<2&&n<100)begin @(negedge clk_74a);n=n+1;end end
      dirty;await_command(2,found);repeat(40)@(negedge clk_74a);
      if(rises!=2)begin errors=errors+1;$display("OLD_DONE_OR_PARALLEL_COMMAND %0d",rises);end
      if(found)begin busy;done(0);await_command(3,found);if(found)begin busy;done(0);end end
     end
     3: begin
      // Real parser accepts a direct final result without a preceding busy.
      done(0);dirty;await_command(2,found);if(found)begin busy;done(0);end
     end
     default:$fatal(2,"unknown scenario");
    endcase
   end
  end
  $display("RESULT_JSON {\"passed\":%s,\"scenario\":%0d,\"target_requests\":%0d,\"missing_commands\":%0d,\"requests_while_reset\":%0d,\"errors\":%0d,\"public_bridge_reads\":%0d,\"kick_latency_cycles\":%0d}",errors==0?"true":"false",scenario,rises,timeouts,reset_requests,errors,reads,kick_latency);
  if(errors)$fatal(1,"save-controller invariant failed");$finish;
 end
 initial begin #1000000;$fatal(2,"global watchdog");end
endmodule
