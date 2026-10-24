// Verification: actual public clock-enable and CPU ports, no game behavior claim.
`timescale 1ns/1ps
module tb_tv80_enable;
    reg clk=0, reset=1, pix_sync=0;
    wire cen16, cen8, cen48;
    clk_enables enables(clk,reset,pix_sync,cen16,cen8,cen48);
    reg wait_n=1, int_n=1, nmi_n=1;
    wire m1_n,mreq_n,iorq_n,rd_n,wr_n,rfsh_n,halt_n,busak_n;
    wire [15:0] address;
    wire [7:0] dout;
    tv80s_cen cpu(.clk(clk),.reset_n(~reset),.cen(cen8),.wait_n(wait_n),
        .int_n(int_n),.nmi_n(nmi_n),.busrq_n(1'b1),.di(8'h00),
        .m1_n(m1_n),.mreq_n(mreq_n),.iorq_n(iorq_n),.rd_n(rd_n),
        .wr_n(wr_n),.rfsh_n(rfsh_n),.halt_n(halt_n),.busak_n(busak_n),
        .A(address),.dout(dout));
    wire [31:0] public_state={address,dout,m1_n,mreq_n,iorq_n,rd_n,wr_n,rfsh_n,halt_n,busak_n};
    always #5 clk=~clk;
    integer cycle=0,last_output=-1,last_consumed=-1,min_output=999,min_consumed=999;
    integer pulses=0,hold_checks=0,errors=0,min_gap=8;
    reg old_cen;
    reg [31:0] previous_state;
    reg have_previous=0;
    always @(posedge clk) begin
        old_cen=cen8;
        cycle++;
        if (!reset && old_cen) begin
            if(last_consumed>=0 && cycle-last_consumed<min_consumed)
                min_consumed=cycle-last_consumed;
            last_consumed=cycle;
        end
        #1;
        if (!reset) begin
            if (cen8) begin
                if(last_output>=0 && cycle-last_output<min_output)
                    min_output=cycle-last_output;
                last_output=cycle;pulses++;
            end
            if (have_previous && !old_cen) begin
                hold_checks++;
                if(public_state !== previous_state) begin
                    errors++;
                    if(errors<5)$display("public CPU outputs changed without CEN at cycle%0d",cycle);
                end
            end
            previous_state=public_state;have_previous=1;
        end else begin
            have_previous=0;last_output=-1;last_consumed=-1;
        end
    end
    integer model_div=0;
    reg [31:0] random_state=32'h16a50731;
    initial begin
        if(!$value$plusargs("MIN_GAP=%d",min_gap))min_gap=8;
        repeat(3)@(negedge clk);reset=0;
        // Free run, then force pix_sync on the predicted div11 edge. This
        // uses only applied inputs to schedule stimuli, never DUT hierarchy.
        for(integer n=0;n<8000;n++)begin
            if(n<48)pix_sync=0;
            else if(n<400)pix_sync=(model_div==11);
            else begin
                random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                pix_sync=(random_state[3:0]==0);
            end
            wait_n=(n%17!=0);int_n=(n%19!=0);nmi_n=(n%23!=0);
            @(posedge clk);#2;
            model_div=pix_sync?3:(model_div==11?0:model_div+1);
            @(negedge clk);
        end
        $display("RESULT pulses=%0d min_output=%0d min_consumed=%0d public_hold_checks=%0d errors=%0d required_gap=%0d",
            pulses,min_output,min_consumed,hold_checks,errors,min_gap);
        if(errors || pulses<50 || min_output<min_gap || min_consumed<min_gap)
            $fatal(1,"enable gap/hold gate failed");
        if(min_output!=9 || min_consumed!=9)$fatal(1,"adversarial shortened pulse not reached");
        $display("PASS actual TV80/CEN public enable hold");$finish;
    end
    initial begin #100000;$fatal(1,"watchdog");end
endmodule
