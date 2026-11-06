`default_nettype none
// Actual modules and public ports only. Old source is namespace-only renamed.
module m3_vio15_tag_top(
 input wire clk,dl_we,input wire[24:0]dl_addr,input wire[7:0]dl_data,
 output wire[4:0]observed[2]
);
 pregx_rom_profile candidate(.clk(clk),.dl_we(dl_we),.dl_addr(dl_addr),.dl_data(dl_data),
  .violent(observed[0][0]),.mystic(observed[0][1]),.identified(observed[0][2]),
  .valid(observed[0][3]),.begin_image(observed[0][4]));
 pregx_rom_profile_baseline baseline(.clk(clk),.dl_we(dl_we),.dl_addr(dl_addr),.dl_data(dl_data),
  .violent(observed[1][0]),.mystic(observed[1][1]),.identified(observed[1][2]),
  .valid(observed[1][3]),.begin_image(observed[1][4]));
endmodule
`default_nettype wire
