`default_nettype none
module m3_vio03_mmio_decode(input wire clk,mystic,violent,input wire[23:1] a,
 output wire[47:0] k55,old55,output wire[31:0] k56,old56,
 output wire[3:0] k56b,old56b,output wire other_match,raw55);
 pregx_mmio_targets dut(.clk(clk),.mystic(mystic),.violent(violent),.a(a),.k55(k55),.k56(k56),.k56b(k56b));
 old_mmio_targets reference(.mystic(mystic),.violent(violent),.a(a),.k55(old55),.k56(old56),.k56b(old56b),.other_match(other_match),.raw55(raw55));
endmodule
`default_nettype wire
