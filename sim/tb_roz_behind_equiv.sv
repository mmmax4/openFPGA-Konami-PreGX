// Source-extracted combinational cone ONLY: not a renderer or timing proof.
`timescale 1ns/1ps
module tb_roz_behind_equiv;
  reg [8:0] line,rline;
  reg line_start,prestart;
  wire old_behind,new_behind,old_abandon,new_abandon;
  wire signed [9:0] old_disp,new_disp;
  extracted_roz_old old_cone(.line(line),.rline(rline),.line_start(line_start),.prestart(prestart),
    .behind_o(old_behind),.abandon_o(old_abandon),.disp_o(old_disp));
  extracted_roz_new new_cone(.line(line),.rline(rline),.line_start(line_start),.prestart(prestart),
    .behind_o(new_behind),.abandon_o(new_abandon),.disp_o(new_disp));
  // Deliberately narrow threshold is a guard against accidentally testing
  // a nine-bit sum. This mutation is not an old DUT or a pixel defect.
  wire [8:0] unsafe_threshold=rline+9'd17;
  wire unsafe_behind=line_start && (line>=unsafe_threshold);
  integer l,r,s,p,cases=0,width_counterexamples=0;
  initial begin
    for(l=0;l<512;l=l+1)
      for(r=0;r<512;r=r+1)
        for(s=0;s<2;s=s+1)
          for(p=0;p<2;p=p+1) begin
            line=9'(l);rline=9'(r);line_start=1'(s);prestart=1'(p);
            #1;
            if(old_behind!==new_behind || old_abandon!==new_abandon || old_disp!==new_disp)
              $fatal(1,"MISMATCH line=%0d rline=%0d line_start=%0d prestart=%0d old=%b/%b new=%b/%b disp=%0d/%0d",
                l,r,s,p,old_behind,old_abandon,new_behind,new_abandon,old_disp,new_disp);
            if((old_behind!==1'b0 && old_behind!==1'b1) ||
               (old_abandon!==1'b0 && old_abandon!==1'b1)) $fatal(1,"unknown result");
            if(unsafe_behind!==old_behind) width_counterexamples=width_counterexamples+1;
            cases=cases+1;
          end
    if(cases!=1048576 || width_counterexamples==0) $fatal(1,"coverage/width guard");
    $display("PASS source-extracted ROZ cone cases=%0d width9_counterexamples=%0d VIS_Y0=16",cases,width_counterexamples);
    $finish;
  end
endmodule
