// Actual Pocket new/old and separately pinned MiSTer M4 tile consumers.
`default_nettype none
module m4_video_tile_top(
 input logic clk,reset,line_start,input logic[8:0]line,px,
 input logic[15:0]regs[32],input logic[7:0]colorbase[4],
 output wire[2:0]busy,unsupported,vram_req,rom_req,
 output wire[15:0]vram_addr[3],input logic[2:0]vram_ack,input logic[15:0]vram_q[3],
 output wire[18:0]rom_addr[3],input logic[2:0]rom_ack,input logic[31:0]rom_q[3],
 input logic[7:0]rom_fifth[3],output wire[11:0]pix[3][4],output wire[3:0]opaque[3]
);
 k056832_tilemap candidate(.clk(clk),.reset(reset),.metam(1'b1),.mystic(1'b0),.violent(1'b0),
 .line_start(line_start),.line(line),.px(px),.regs(regs),.colorbase(colorbase),.busy(busy[0]),.unsupported(unsupported[0]),
 .vram_req(vram_req[0]),.vram_addr(vram_addr[0]),.vram_ack(vram_ack[0]),.vram_q(vram_q[0]),
 .rom_req(rom_req[0]),.rom_addr(rom_addr[0]),.rom_ack(rom_ack[0]),.rom_q(rom_q[0]),.rom_fifth(rom_fifth[0]),
 .pix(pix[0]),.opaque(opaque[0]),.category(),.last_mix(),.line_nonempty());
 k056832_tilemap_old old(.clk(clk),.reset(reset),.mystic(1'b0),.violent(1'b0),
 .line_start(line_start),.line(line),.px(px),.regs(regs),.colorbase(colorbase),.busy(busy[1]),.unsupported(unsupported[1]),
 .vram_req(vram_req[1]),.vram_addr(vram_addr[1]),.vram_ack(vram_ack[1]),.vram_q(vram_q[1]),
 .rom_req(rom_req[1]),.rom_addr(rom_addr[1]),.rom_ack(rom_ack[1]),.rom_q(rom_q[1]),.rom_fifth(rom_fifth[1]),
 .pix(pix[1]),.opaque(opaque[1]),.category(),.last_mix(),.line_nonempty());
 wire[10:0]mister_pix[4];
 for(genvar l=0;l<4;l++)assign pix[2][l]={1'b0,mister_pix[l]};
 k056832_tilemap_mister reference(.clk(clk),.reset(reset),.line_start(line_start),.line(line),.px(px),
 .regs(regs),.colorbase(colorbase),.busy(busy[2]),.unsupported(unsupported[2]),.clr_unsup(1'b0),
 .vram_req(vram_req[2]),.vram_addr(vram_addr[2]),.vram_ack(vram_ack[2]),.vram_q(vram_q[2]),
 .rom_req(rom_req[2]),.rom_addr(rom_addr[2]),.rom_ack(rom_ack[2]),.rom_q({rom_q[2],rom_fifth[2]}),
 .pix(mister_pix),.opaque(opaque[2]));
endmodule
`default_nettype wire
