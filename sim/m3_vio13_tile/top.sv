`default_nettype none
module m3_vio13_tile_top(
 input wire clk,reset,mystic,violent,line_start,input wire[8:0]line,px,
 input wire[15:0]regs[32],input wire[7:0]colorbase[4],
 output wire[1:0]busy,unsupported,vram_req,rom_req,
 output wire[15:0]vram_addr[2],input wire vram_ack,input wire[15:0]vram_q,
 output wire[18:0]rom_addr[2],input wire rom_ack,input wire[31:0]rom_q,input wire[7:0]rom_fifth,
 output wire[11:0]pix[2][4],output wire[3:0]opaque[2],line_nonempty[2],
 output wire[1:0]category[2][4],last_mix[2]);
 k056832_tilemap current(.clk(clk),.reset(reset),.mystic(mystic),.violent(violent),.line_start(line_start),.line(line),.busy(busy[0]),.regs(regs),.colorbase(colorbase),
 .vram_req(vram_req[0]),.vram_addr(vram_addr[0]),.vram_ack(vram_ack),.vram_q(vram_q),.rom_req(rom_req[0]),.rom_addr(rom_addr[0]),.rom_ack(rom_ack),.rom_q(rom_q),.rom_fifth(rom_fifth),
 .px(px),.pix(pix[0]),.opaque(opaque[0]),.category(category[0]),.last_mix(last_mix[0]),.line_nonempty(line_nonempty[0]),.unsupported(unsupported[0]));
 k056832_tilemap_baseline old(.clk(clk),.reset(reset),.mystic(mystic),.violent(violent),.line_start(line_start),.line(line),.busy(busy[1]),.regs(regs),.colorbase(colorbase),
 .vram_req(vram_req[1]),.vram_addr(vram_addr[1]),.vram_ack(vram_ack),.vram_q(vram_q),.rom_req(rom_req[1]),.rom_addr(rom_addr[1]),.rom_ack(rom_ack),.rom_q(rom_q),.rom_fifth(rom_fifth),
 .px(px),.pix(pix[1]),.opaque(opaque[1]),.category(category[1]),.last_mix(last_mix[1]),.line_nonempty(line_nonempty[1]),.unsupported(unsupported[1]));
endmodule
