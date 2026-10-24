`timescale 1ns/1ps
// Adapted from Asterix tb_pocket_nv_unloader.sv; DUT and Intel FIFO unmodified.
module tb_pregx_nv_unloader;
 reg clk_74a=0,clk_memory=0;
 always #6.734007 clk_74a=~clk_74a;
 integer phase_ps=1700;
 initial begin
  if(!$value$plusargs("PHASE_PS=%d",phase_ps))phase_ps=1700;
  #(phase_ps/1000.0);forever #5.208333 clk_memory=~clk_memory;
 end
 reg bridge_rd=0,bridge_endian_little=0;reg[31:0]bridge_addr=0;
 wire[31:0]bridge_rd_data;wire read_en;wire[6:0]read_addr;wire[7:0]read_data;
 reg reset=1,ld_we=0;reg[6:0]ld_addr=0;reg[7:0]ld_wdata=0;
 wire[6:0]memory_addr=ld_we?ld_addr:read_addr;
 wire dout,ready,dirty;
 reg[7:0]original_nv[0:127];
 // Actual EEPROM byte port is wired exactly as in target/pocket/core_top.sv.
 er5911 memory(.clk(clk_memory),.reset(reset),.cs(1'b0),.sclk(1'b0),.di(1'b0),
  .dout(dout),.ready(ready),.ld_we(ld_we),.ld_addr(memory_addr),.ld_wdata(ld_wdata),.ld_q(read_data),.dirty(dirty));
 data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(7),.READ_MEM_CLOCK_DELAY(4),.INPUT_WORD_SIZE(1)) dut(.*);
 integer session,spacing,transaction,address,i,mis=0,underflow=0,overflow=0,reads=0,eof_mis=0,ordinary_mis=0,first_mis=0;
 integer first_underflow=0,reads_before;
 reg[31:0]little,expected;
 function[7:0]byte_at(input integer addr,input integer saved);
  byte_at=saved?(original_nv[addr]^((addr*37+19)&255)):original_nv[addr];
 endfunction
 always@(posedge clk_74a)begin
  if(dut.data_read_req && dut.data_empty)begin
   underflow=underflow+1;
   if(session==0)first_underflow=first_underflow+1;
   $display("MONITOR response FIFO empty pop session=%0d time=%0t",session,$time);
  end
 end
 always@(posedge clk_memory)begin
  if(read_en)reads=reads+1;
  if(dut.data_write_req && dut.fifo_data_response.wrfull)overflow=overflow+1;
 end
 initial begin
  $readmemh("gaiapols-original-nv.hex",original_nv);
  if(!$value$plusargs("ENDIAN=%d",bridge_endian_little))bridge_endian_little=0;
  repeat(20)@(negedge clk_74a);
  // Two upload sessions; second uses a distinct existing-save fixture loaded
  // through the public port. No DUT registers, FIFO or memory force/init.
  for(session=0;session<2;session=session+1)begin
   reset=1;
   for(i=0;i<128;i=i+1)begin
    @(negedge clk_memory);ld_we=1;ld_addr=i;ld_wdata=byte_at(i,session);
   end
   @(negedge clk_memory);ld_we=0;reset=0;
   repeat(20)@(negedge clk_74a);
   // Nonmatching bridge upper nibble must leave the unloader idle.
   reads_before=reads;
   bridge_addr=32'h30000000;bridge_rd=1;
   repeat(3)@(negedge clk_74a);bridge_rd=0;
   repeat(80)@(negedge clk_74a);
   if(reads!==reads_before)begin mis=mis+1;$display("wrong-mask read reached EEPROM");end
   for(spacing=80;spacing<=240;spacing=spacing+80)begin
    for(transaction=0;transaction<32;transaction=transaction+1)begin
     address=4*transaction;
     little={byte_at(address+3,session),byte_at(address+2,session),byte_at(address+1,session),byte_at(address,session)};
     expected=bridge_endian_little?little:{little[7:0],little[15:8],little[23:16],little[31:24]};
     @(negedge clk_74a);bridge_addr=32'h20000000+address;bridge_rd=1;
     repeat(3)@(negedge clk_74a);bridge_rd=0;
     repeat(spacing-3)@(negedge clk_74a);
     if(bridge_rd_data!==expected)begin
      mis=mis+1;if(address==124)eof_mis=eof_mis+1;else ordinary_mis=ordinary_mis+1;
      if(session==0 && spacing==80 && transaction==0)first_mis=first_mis+1;
      $display("unloader mismatch phase=%0d endian=%0d session=%0d spacing=%0d addr=%02x got=%08x want=%08x",phase_ps,bridge_endian_little,session,spacing,address,bridge_rd_data,expected);
     end
    end
   end
  end
  $display("RESULT_JSON {\"passed\":%s,\"phase_ps\":%0d,\"endian_little\":%0d,\"transactions\":192,\"mismatches\":%0d,\"first_transaction_mismatches\":%0d,\"eof_mismatches\":%0d,\"ordinary_mismatches\":%0d,\"empty_response_pops\":%0d,\"first_upload_empty_pops\":%0d,\"response_overflow\":%0d}",mis==0 && underflow==0 && overflow==0?"true":"false",phase_ps,bridge_endian_little,mis,first_mis,eof_mis,ordinary_mis,underflow,first_underflow,overflow);
  $finish;
 end
 initial begin #10000000;$fatal(1,"unloader timeout");end
endmodule
