`timescale 1ns/1ps
module tb_cabinet_menu;
    reg clk=0, bridge_clk=0;
    always #5 clk=~clk;
    always #7 bridge_clk=~bridge_clk;
    reg [31:0] addr=0, data=0;
    reg wr=0;
    wire [7:0] dip0,mod0,mod1,mod2;
    wire rst,svc;
    interact menu(.clk_74a(bridge_clk),.clk_sync(clk),.reset_n(1'b1),
        .bridge_addr(addr),.bridge_wr(wr),.bridge_wr_data(data),.bridge_rd(1'b0),
        .dip_sw0(dip0),.mod_sw0(mod0),.mod_sw1(mod1),.mod_sw2(mod2),.reset_sw(rst),.svc_sw(svc));
    reg [7:0] keys=0,p2keys=0;
    reg [3:0] dirs=0,p2dirs=0;
    wire [15:0] in0;
    wire [7:0] in1,p2;
    gaia_inputs dut(.p1_keys(keys),.p2_keys(p2keys),.p1_dirs(dirs),.p2_dirs(p2dirs),
        .test_manual(mod1[0]|svc),.test_select(mod2[3:0]),.service_select(mod2[7:4]),
        .dips(dip0[1:0]),.in0_p1(in0),.in1(in1),.p2(p2));
    reg osmenu=0;
    wire pause;
    pause_crtl pc(.clk_sys(clk),.os_inmenu(osmenu),.pause_req(1'b0),.pause_core(pause));
    integer n=0;
    task check(input bit ok,input string msg);
        if(!ok) $fatal(1,"%s in0=%h in1=%h p2=%h",msg,in0,in1,p2);
        n++;
    endtask
    task write_bus(input [31:0] a,input [31:0] d);
        @(negedge bridge_clk);addr=a;data=d;wr=1;
        @(negedge bridge_clk);wr=0;
        repeat(8) @(negedge clk);
    endtask
    task menu_try(input [31:0] a,input [31:0] mask,input [31:0] value,input integer which,input integer opt);
        reg [31:0] prev;
        begin
            prev = a==32'hf2000000 ? {8'd0,mod2,mod1,mod0} : {24'd0,dip0};
            write_bus(a,(prev & mask)|value);
            case(which)
                64: check(mod2[3:0]==opt,"Test menu field");
                65: check(mod2[7:4]==opt,"Service menu field");
                66: check(dip0[0]==opt,"Sound menu field");
                67: check(dip0[1]==opt,"Flip menu field");
            endcase
            if(a==32'hf1000000) begin
                check(rst,"DIP requires machine reset");
                repeat(11400) @(negedge clk);
            end else check(!rst,"optional mapping must not reset");
        end
    endtask
    `include "cabinet_menu.svh"
    integer t,s,k,d;
    reg test_on,service_on;
    reg [7:0] expected;
    initial begin
        repeat(15) @(negedge clk);
        check(in0==16'hffff && in1==8'heb && p2==8'hff,"board idle defaults");
        check(mod2==0 && dip0==0,"selectors and DIP default zero");
        write_bus(32'hf0000000,1);repeat(11400) @(negedge clk);
        menu_entries();
        write_bus(32'hf1000000,0);repeat(11400) @(negedge clk);
        for(t=0;t<16;t++) for(s=0;s<16;s++) begin
            write_bus(32'hf2000000,(t<<16)|(s<<20));
            for(k=0;k<8;k++) begin
                keys=8'b1<<k;#1;
                test_on=t==k+1;service_on=s==k+1;
                check(in0[11]==!test_on && in1[3]==!test_on && in0[12]==!service_on && in0[13],"one-hot optional selectors");
            end
        end
        // Exhaust gameplay keys and directions, including simultaneous keys,
        // against board bit order, with optional functions unassigned.
        write_bus(32'hf2000000,0);
        for(k=0;k<256;k++) for(d=0;d<16;d++) begin
            keys=k;p2keys=k;dirs=d;p2dirs=d;#1;
            expected=~{keys[7],keys[5],keys[1]|keys[2],keys[0]|keys[3],dirs};
            check(in0[7:0]==expected && p2==expected,"ordinary gameplay unchanged");
            check(in0[9:8]=={!keys[6],!keys[6]} && in0[13:11]==3'b111,"coins and unassigned functions");
        end
        keys=0;p2keys=0;dirs=0;p2dirs=0;
        write_bus(32'hf2000000,32'h100);
        check(in0==16'hf7ff && in1==8'he3,"manual Test retained");
        write_bus(32'hf2000000,32'h00110000);keys=1;#1;
        check(in0[13:11]==3'b100 && in1[3]==0,"same button Test plus Service");
        write_bus(32'hf2000000,0);keys=0;
        for(d=0;d<4;d++) begin
            write_bus(32'hf1000000,d);
            check(in1==((8'heb ^ ((d&1)<<4)) ^ ((d&2)<<4)),"literal board DIP readback");
        end
        osmenu=1;repeat(5) @(negedge clk);check(pause,"menu entry synchronized pause");
        osmenu=0;repeat(5) @(negedge clk);check(!pause,"menu exit releases pause");
        $display("PASS cabinet/menu %0d checks",n);$finish;
    end
    initial begin #4000000;$fatal(1,"timeout");end
endmodule
