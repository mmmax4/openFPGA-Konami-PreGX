// Actual production core, original ROM bytes supplied through public ports by C++.
// Controlled bounded-latency memory model; actual Pocket controllers/pins are
// separately exercised by m4-machine/boot01 and component memory gates.
`default_nettype none
module tb_m4_fast_top(
 input logic clk,reset,pause,
 input logic eep_we,input logic[6:0]eep_waddr,input logic[7:0]eep_wdata,
 input logic[15:0]in0_p1,input logic[7:0]in1,p2,
 output wire prog_req,output wire[22:1]prog_addr,input logic prog_ack,input logic[15:0]prog_q,
 output wire tile_req,output wire[19:0]tile_addr,input logic tile_ack,input logic[31:0]tile_q,
 output wire spr_req,output wire[19:0]spr_addr,input logic spr_ack,input logic[63:0]spr_q,
 output wire lvc_req,output wire[14:0]lvc_addr,input logic lvc_ack,input logic[63:0]lvc_q,
 output wire road_req,road_we,output wire[13:0]road_addr,output wire[1:0]road_be,
 output wire[15:0]road_wdata,input logic road_ack,input logic[15:0]road_q,
 output wire vram_req,vram_we,output wire[15:0]vram_addr,vram_wdata,output wire[1:0]vram_be,
 input logic vram_ack,input logic[15:0]vram_q,
 output wire srom_req,output wire[17:0]srom_addr,input logic srom_ack,input logic[7:0]srom_q,
 output wire pcmr_req,output wire[21:0]pcmr_addr,input logic pcmr_ack,input logic[7:0]pcmr_q,
 output wire cen_pix,output wire[23:0]rgb,output wire hsync,vsync,de,vblank,
 output wire[23:0]dbg_addr,output wire[15:0]dbg_data,output wire[1:0]dbg_busstate,
 output wire dbg_step,dbg_irq5,dbg_overrun,dbg_unsupported,dbg_shadow_overlap,
 output wire[2:0]dbg_overrun_src,output wire[31:0]dbg_draw_objs,dbg_draw_rows,dbg_draw_cols,dbg_draw_pxw,
 output wire dbg_spr_we,dbg_roz_en,output wire[127:0]dbg_rozctrl,output wire[31:0]dbg_rozclip,
 output wire[383:0]dbg_k55,output wire[9:0]dbg_objcount,output wire[8:0]dbg_vcount,
 output wire[15:0]dbg_zpc,output wire dbg_zstep,dbg_zwait,dbg_zwr,dbg_zrd,output wire[7:0]dbg_zwdata,
 output wire[15:0]snd_l,snd_r,output wire snd_valid,
 output wire road_initialized,road_dma_busy,cpu_road_req,cpu_road_ack,road_rom_req,road_rom_ack,sprite_copy,road_frame_tick,
 output wire line_event,scan_event,global_enable,previous_sprite_enable,output wire[4:0]previous_planes,
 output wire[7:0]display_enables,output wire[2:0]sampled_busy,
 output wire cpu_write,cpu_work_write,output wire[23:0]cpu_address,output wire[15:0]cpu_wdata,
 output wire cpu_irq5,cpu_irq6,readback_oob,k550_write,k550_busy,cpu_graphics_ack
);
 wire[7:0]tile_fifth=0;wire[15:0]spr_fifth=0;
 wire map_req,blk_req;wire[19:0]map_addr;wire[15:0]map_q=0,blk_addr,blk_data=0;
 wire map_ack=0,blk_wr=0,blk_ack=0;wire[5:0]blk_idx=0;wire[3:0]roz_lead;
 wire[7:0]eep_q;wire eep_dirty;
    gaia_core #(.HEXDIR("../rtl/data"), .STEP_COST_BUS(16), .STEP_COST_INT(8)) u_core (.lvc_req(lvc_req),.lvc_addr(lvc_addr),.lvc_ack(lvc_ack),.lvc_q(lvc_q),
        .road_req(road_req),.road_we(road_we),.road_addr(road_addr),.road_be(road_be),.road_wdata(road_wdata),.road_ack(road_ack),.road_q(road_q),
        .violent(1'b0),.metam(1'b1), 
        .mystic(1'b0), .mystic_p12({8'hff,in0_p1[7:0]}), .mystic_p34({8'hff,p2}), .mystic_in0({6'h3f,in0_p1[9:8]}),
        .tile_fifth(tile_fifth), .spr_fifth(spr_fifth),
        .clk(clk), .pause(pause), .reset(reset), .pix_sync(1'b0), .vid_reset(reset),
        .prog_req(prog_req), .prog_addr(prog_addr), .prog_ack(prog_ack), .prog_q(prog_q),
        .tile_req(tile_req), .tile_addr(tile_addr), .tile_ack(tile_ack), .tile_q(tile_q),
        .map_req(map_req), .map_addr(map_addr), .map_ack(map_ack), .map_q(map_q),
        .blk_req(blk_req), .blk_addr(blk_addr), .blk_wr(blk_wr), .blk_idx(blk_idx), .blk_data(blk_data), .blk_ack(blk_ack), .roz_lead(roz_lead),
        .spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_q(spr_q),
        .vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr), .vram_be(vram_be), .vram_wdata(vram_wdata),
        .vram_ack(vram_ack), .vram_q(vram_q),
        .snd_rom_req(srom_req), .snd_rom_addr(srom_addr), .snd_rom_ack(srom_ack), .snd_rom_q(srom_q),
        .pcm_req(pcmr_req), .pcm_addr(pcmr_addr), .pcm_ack(pcmr_ack), .pcm_q(pcmr_q),
        .eep_ld_we(eep_we), .eep_ld_addr(eep_waddr), .eep_ld_wdata(eep_wdata), .eep_ld_q(eep_q), .eep_dirty(eep_dirty),
        .in0_p1(in0_p1), .in1(in1), .p2(p2),
        .cen_pix(cen_pix), .rgb(rgb), .hsync(hsync), .vsync(vsync), .de(de), .hblank(), .vblank(vblank),
        .snd_l(snd_l), .snd_r(snd_r), .snd_valid(snd_valid),
        .dbg_addr(dbg_addr), .dbg_data(dbg_data), .dbg_busstate(dbg_busstate), .dbg_step(dbg_step), .dbg_irq5(dbg_irq5),
        .dbg_overrun(dbg_overrun), .dbg_overrun_src(dbg_overrun_src), .dbg_draw_objs(dbg_draw_objs), .dbg_draw_rows(dbg_draw_rows), .dbg_draw_cols(dbg_draw_cols), .dbg_draw_pxw(dbg_draw_pxw), .dbg_spr_we(dbg_spr_we), .dbg_roz_en(dbg_roz_en), .dbg_rozctrl(dbg_rozctrl), .dbg_rozclip(dbg_rozclip), .dbg_k55(dbg_k55), .dbg_unsupported(dbg_unsupported), .dbg_shadow_overlap(dbg_shadow_overlap),
        .dbg_objcount(dbg_objcount), .dbg_vcount(dbg_vcount), .dbg_zpc(dbg_zpc), .dbg_zstep(dbg_zstep), .dbg_zwait(dbg_zwait),
        .dbg_zwr(dbg_zwr), .dbg_zrd(dbg_zrd), .dbg_zwdata(dbg_zwdata)
    );
    assign road_initialized=u_core.road_ready;
    assign road_dma_busy=u_core.road_dma_busy;
    assign cpu_road_req=u_core.lc_req;assign cpu_road_ack=u_core.lc_ack;
    assign road_rom_req=lvc_req;assign road_rom_ack=lvc_ack;
    assign sprite_copy=u_core.copy_start;assign road_frame_tick=u_core.road_frame_tick;

 assign line_event=u_core.line_start;assign scan_event=u_core.scanline_start;
 assign global_enable=u_core.k38regs[15][0];assign display_enables=u_core.k55regs[45];
 assign previous_planes=u_core.u_mystic_rgb.enables;assign previous_sprite_enable=u_core.u_mystic_rgb.sprite_enable;
 assign sampled_busy=u_core.u_vid.overrun_src;
 assign cpu_write=u_core.u_main.cpu_wr;assign cpu_work_write=u_core.u_main.cpu_wr && u_core.u_main.sel_wram;
 assign cpu_address=u_core.u_main.A;assign cpu_wdata=u_core.u_main.wdat;
 assign cpu_irq5=u_core.u_main.irq5_pend;assign cpu_irq6=u_core.u_main.irq6_pend;
 assign readback_oob=u_core.u_main.dbg_rb_oob;
 assign cpu_graphics_ack=u_core.ctrom_ack || u_core.csrom_ack || u_core.clrom_ack;
 assign k550_write=u_core.u_main.cpu_wr && u_core.u_main.sel_k550;assign k550_busy=u_core.u_main.k550_busy;
 // M4 must never enter Gaia's external ROZ interfaces.
 always @(posedge clk)if(!reset && (map_req || blk_req))$fatal(1,"M4 requested Gaia ROZ memory");
endmodule
`default_nettype wire
