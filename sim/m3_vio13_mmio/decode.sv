`default_nettype none
module m3_vio13_mmio_decode(input wire clk,mystic,violent,input wire[23:1]a,
 output wire[47:0]k55,old55,output wire[31:0]k56,old56,
 output wire[3:0]k56b,old56b,
 output wire [26:0]board,old_board,
 output wire k000,local_other,vram,old_k000,old_other,old_vram);
 pregx_mmio_targets dut(.clk(clk),.mystic(mystic),.violent(violent),.a(a),.k55(k55),.k56(k56),.k56b(k56b),.k000(k000),.local_other(local_other),.vram(vram),.board(board));
 baseline_pregx_mmio_targets baseline(.clk(clk),.mystic(mystic),.violent(violent),.a(a),.k55(old55),.k56(old56),.k56b(old56b));
 old_leaf_targets old_controls(.clk(clk),.mystic(mystic),.violent(violent),.a(a),.k000(old_k000),.local_other(old_other),.vram(old_vram),.board(old_board));
endmodule
