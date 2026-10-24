`timescale 1ns/1ps
module tb_overlay_path;
    logic clk=0, clk_vid=0, reset=1;
    always #5.208 clk=~clk;
    initial begin #10.416; forever #62.496 clk_vid=~clk_vid; end
    logic vt=0, vt_s=0, vt_d=0, cp, c16, c48;
    always @(posedge clk_vid) vt<=~vt;
    always @(posedge clk) begin vt_s<=vt; vt_d<=vt_s; end
    clk_enables ce(clk,reset,vt_s^vt_d,c16,cp,c48);
    logic [11:0] pen[4]; logic [7:0] k55[48]; logic [15:0] k38[16];
    wire [23:0] rgb; wire [10:0] addr;
    k055555_mixer mix(.clk(clk),.reset(reset),.cen_pix(cp),.tm_pen(pen),
        .tm_opq(4'b0),.roz_pen(12'b0),.roz_opq(1'b0),.spr_opq(1'b0),
        .spr_pen(12'b0),.spr_pri(8'b0),.spr_shadow(1'b0),.spr_shtab(2'b0),
        .spr_shpri(8'b0),.k55regs(k55),.k38regs(k38),.roz_enable(1'b0),
        .pal_addr(addr),.pal_q(24'b0),.rgb(rgb));
    wire [23:0] out_rgb;
    dbg_overlay off_path(clk,cp,1'b0,1'b1,1'b0,rgb[23:16],rgb[15:8],rgb[7:0],96'b0,
        out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
    integer ticks=0, pix=0, line=0, checks=0, errors=0, diagchecks=0;
    integer green=0, dark=0, gap=0, bypass=0;
    logic de=0, vs=1; logic [95:0] status=0, status_d=0;
    wire [23:0] diag, old_diag;
    dbg_overlay on_path(clk,cp,1'b1,de,vs,8'h41,8'h82,8'hc3,status,
        diag[23:16],diag[15:8],diag[7:0]);
    dbg_overlay_original reference(clk,cp,1'b1,de,vs,8'h41,8'h82,8'hc3,status_d,
        old_diag[23:16],old_diag[15:8],old_diag[7:0]);
    logic [23:0] expected;
    always @(posedge clk) begin
        expected=old_diag;
        status_d<=status;
        status<={status[94:0],~status[95]};
        ticks<=ticks+1;
        if (cp) begin
            k38[0]<=k38[0]+16'd1;
            k38[1]<=k38[1]+16'h0103;
            pix<=pix+1;
            if (pix==43) begin pix<=0; line<=line+1; end
            de <= pix<40 && line%30<24;
            vs <= line%30==29;
        end
        #0.001;
        if(ticks>6000 && !$isunknown(expected)) begin
            diagchecks++;
            case(diag)
                24'h20e020:green++;
                24'h303030:dark++;
                24'h000000:gap++;
                24'h4182c3:bypass++;
                default:begin errors++; $display("unexpected diagnostic colour %h",diag); end
            endcase
            if(diag!==expected) begin errors++; if(errors<5) $display("overlay mismatch %h %h",diag,expected); end
        end
    end
    always @(posedge clk_vid) if(ticks>300) begin
        checks++;
        if(out_rgb!==rgb) begin errors++; if(errors<5) $display("Pocket RGB mismatch %h %h",out_rgb,rgb); end
    end
    initial begin
        for(integer i=0;i<4;i++)pen[i]=0;
        for(integer i=0;i<48;i++)k55[i]=0;
        for(integer i=0;i<16;i++)k38[i]=0;
        k38[0]=16'h0041; k38[1]=16'h82c3;
        #150 reset=0;
        #600000;
        $display("%s Pocket_pixels=%0d overlay_stage_checks=%0d errors=%0d",errors?"FAIL":"PASS",checks,diagchecks,errors);
        $display("diagnostic colours green=%0d dark=%0d gap=%0d bypass=%0d",green,dark,gap,bypass);
        if(errors || checks<100 || diagchecks<100 || green==0 || dark==0 || gap==0 || bypass==0) $fatal(1,"overlay gate failed");
        $finish;
    end
endmodule
