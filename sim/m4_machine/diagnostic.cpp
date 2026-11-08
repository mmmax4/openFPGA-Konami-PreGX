// Verification diagnostic over exact failed boot01 RTL: observation only.
#include "Vtb_m4_machine_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
static Vtb_m4_machine_top d;
static uint64_t cycle=0;
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();cycle++;}
static void need(bool b,const char*s){if(!b){fprintf(stderr,"FAIL cycle%llu %s\n",(unsigned long long)cycle,s);exit(1);}}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);
 if(argc!=5){fprintf(stderr,"usage: machine original.rom maxclocks trace frame.rgb\n");return 2;}
 FILE*f=fopen(argv[1],"rb");need(f,"original image open");std::vector<unsigned char> image(0x1280080);
 need(fread(image.data(),1,image.size(),f)==image.size()&&fgetc(f)==EOF,"exact original compact image length");fclose(f);
 const uint64_t bound=strtoull(argv[2],nullptr,10);FILE*tr=fopen(argv[3],"w");need(tr,"trace open");
 d.reset=1;d.pause=0;d.in0_p1=65535;d.in1=0xeb;d.p2=255;
 for(unsigned i=0;i<8;i++)tick();
 auto load=[&](unsigned from,unsigned to,unsigned dest,bool sd){d.preload_sdram=sd;d.preload_we=1;for(unsigned a=from;a<to;a+=2){d.preload_addr=dest++;d.preload_data=(image[a]<<8)|image[a+1];tick();}d.preload_we=0;};
 load(0,0x200000,0,false);load(0x200000,0x240000,0x180000,false);load(0x240000,0x1280000,0,true);
 for(unsigned i=0;i<128;i++){d.eep_we=1;d.eep_waddr=i;d.eep_wdata=image[0x1280000+i];tick();}d.eep_we=0;
 for(unsigned i=0;i<16;i++)tick();d.reset=0;const auto start=cycle;
 uint64_t steps=0,zsteps=0,irq2edges=0,irq4edges=0,unsupported=0,overruns=0,active_overruns=0,road_ready_clocks=0,road_ram_acks=0,road_rom_acks=0,road_dmas=0,sprite_copies=0,frame_ticks=0,audio=0,nonzeroaudio=0,rb=0,wram=0;
 unsigned frames=0,pixels=0,nonzero=0,sound_events=0;uint16_t last_z_opcode=0;
 bool vb=true,i2=false,i4=false;std::vector<uint32_t> frame(288*224);
 uint64_t line_events=0,raw_line_events=0,old_classifier_events=0,current_global_events=0,latched_effective_events=0,cold_raw_events=0,global_hold=0,first_latch=0;
 unsigned event_logs=0,control_logs=0;unsigned last_control=~0u,last_enable=~0u;
 for(;cycle-start<bound;){
  if(d.dbg_k550_wr) {fprintf(tr,"k550 cycle%llu idx%02x be%x value%04x\n",(unsigned long long)(cycle-start),d.dbg_k550_idx,d.dbg_k550_be,d.dbg_k550_data);fflush(tr);}
  // Capture the completed row's latched enables before the edge that records
  // the deadline. Current MMIO controls may have changed during that row.
  const unsigned oldplanes=d.diag_latched_planes,oldsprite=d.diag_latched_sprite;
  const unsigned oldctl=d.diag_global_control,oldenable=d.dbg_k55_enable;
  const unsigned oldbusy=d.diag_busy;
  tick();need(d.sd_errors==0,"SDRAM logical protocol");need(!d.dbg_rb_oob,"CPU readback stays within known original region");
  if(d.sprite_copy && !first_latch)first_latch=cycle-start;
  if(d.diag_global_control!=last_control || d.dbg_k55_enable!=last_enable){
   if(control_logs++<128)fprintf(tr,"CONTROL cycle%llu v%u h%u ctl%04x enable%02x latched%02x sprite%u ahead%u needvalid%u needrow%u ready%02x\n",(unsigned long long)(cycle-start),d.dbg_vcount,d.diag_hcount,d.diag_global_control,d.dbg_k55_enable,d.diag_latched_planes,d.diag_latched_sprite,d.diag_road_ahead_ready,d.diag_road_need_valid,d.diag_road_need_row,d.diag_road_ready_rows);
   last_control=d.diag_global_control;last_enable=d.dbg_k55_enable;
  }
  if(d.diag_line_start){
   line_events++;
   const unsigned src=d.dbg_overrun_src;
   // This is a diagnostic visibility classifier, not an RTL deadline repair.
   const unsigned effective=((oldplanes&15)?4:0)|((oldplanes&16)?2:0)|((oldplanes||oldsprite)?1:0);
   if(d.dbg_overrun){
    raw_line_events++;old_classifier_events+=(oldenable&63)!=0;
    current_global_events+=(oldenable&63)!=0 && (oldctl&1);
    latched_effective_events+=(src&effective)!=0;cold_raw_events+=first_latch==0;
   }
   if((d.dbg_overrun || line_events<=4) && event_logs++<512)
    fprintf(tr,"DEADLINE cycle%llu v%u render%u raw%u src%x presrc%x ctl%04x enable%02x prevplanes%02x prevsprite%u effective%x tile%u draw%u comp%u road%u ahead%u needvalid%u needrow%u nextrow%u ready%02x firstlatch%llu snapshot%u begin%u\n",(unsigned long long)(cycle-start),d.dbg_vcount,d.diag_render_line,d.dbg_overrun,src,oldbusy,oldctl,oldenable,oldplanes,oldsprite,effective,d.diag_tile_busy,d.diag_draw_busy,d.diag_compositor_busy,d.diag_road_busy,d.diag_road_ahead_ready,d.diag_road_need_valid,d.diag_road_need_row,d.diag_road_next_row,d.diag_road_ready_rows,(unsigned long long)first_latch,d.diag_snapshot_active,d.diag_snapshot_begin);
  }
  if(d.dbg_step){steps++;if(d.dbg_addr>=0x200000&&d.dbg_addr<0x210000)wram++;if((d.dbg_addr>=0x310000&&d.dbg_addr<0x312000)||(d.dbg_addr>=0x244000&&d.dbg_addr<0x244010))rb++;}
  zsteps+=d.dbg_zstep;unsupported+=d.dbg_unsupported;overruns+=d.dbg_overrun;
  active_overruns+=d.dbg_overrun && (d.dbg_k55_enable&0x3f);road_ready_clocks+=d.road_initialized;
  global_hold+=d.dbg_overrun && (d.dbg_k55_enable&63) && (d.diag_global_control&1);
  road_ram_acks+=d.cpu_road_ack;road_rom_acks+=d.road_rom_ack;
  road_dmas+=d.road_dma_busy;sprite_copies+=d.sprite_copy;frame_ticks+=d.road_frame_tick;
  need(!d.dbg_k550_wr && !d.dbg_k550_busy,"Metamorphic has no K055550 engine");
  if(d.dbg_zstep)last_z_opcode=d.dbg_zpc;
  if(d.dbg_zwr&&(d.dbg_zpc==0xf000||d.dbg_zpc==0xf800||d.dbg_zpc==0xe227||
     d.dbg_zpc==0xe22f||d.dbg_zpc==0xd094||d.dbg_zpc==0xd095)&&sound_events<512){
   fprintf(tr,"soundwrite cycle%llu bus%04x value%02x opcode%04x\n",(unsigned long long)(cycle-start),d.dbg_zpc,d.dbg_zwdata,last_z_opcode);sound_events++;
  }
  if(d.dbg_irq2&&!i2)irq2edges++;if(d.dbg_irq4&&!i4)irq4edges++;i2=d.dbg_irq2;i4=d.dbg_irq4;
  if(d.snd_valid){audio++;nonzeroaudio+=(d.snd_l!=0||d.snd_r!=0);}
  if(d.cen_pix&&d.de){if(pixels<frame.size())frame[pixels]=d.rgb;pixels++;nonzero+=(d.rgb!=0);}
  if(d.vblank&&!vb){frames++;fprintf(tr,"frame%u cycle%llu steps%llu zsteps%llu irq2%llu irq4%llu gate%02x enable%02x pixels%u nonzero%u addr%06x readback%llu workram%llu overrun%llu unsupported%llu samples%llu activeaudio%llu zaddr%04x zopcode%04x zwait%u\n",frames,(unsigned long long)(cycle-start),(unsigned long long)steps,(unsigned long long)zsteps,(unsigned long long)irq2edges,(unsigned long long)irq4edges,d.dbg_irq_gate,d.dbg_k55_enable,pixels,nonzero,d.dbg_addr,(unsigned long long)rb,(unsigned long long)wram,(unsigned long long)overruns,(unsigned long long)unsupported,(unsigned long long)audio,(unsigned long long)nonzeroaudio,d.dbg_zpc,last_z_opcode,d.dbg_zwait);fflush(tr);pixels=nonzero=0;}
  vb=d.vblank;
 }
 fclose(tr);f=fopen(argv[4],"wb");need(f,"frame open");need(fwrite(frame.data(),sizeof(uint32_t),frame.size(),f)==frame.size(),"frame write");fclose(f);
 printf("RESULT cycles%llu frames%u steps%llu zsteps%llu IRQ5%llu IRQ6%llu workram%llu readback%llu enable%02x audio%llu active%llu unsupported%llu overrun%llu\n",(unsigned long long)(cycle-start),frames,(unsigned long long)steps,(unsigned long long)zsteps,(unsigned long long)irq2edges,(unsigned long long)irq4edges,(unsigned long long)wram,(unsigned long long)rb,d.dbg_k55_enable,(unsigned long long)audio,(unsigned long long)nonzeroaudio,(unsigned long long)unsupported,(unsigned long long)overruns);
 need(steps>10000&&zsteps>1000&&frames>2,"bounded complete machine CPU/raster progress");
 printf("M4_ROAD initialized_clocks%llu RAMacks%llu ROMacks%llu DMAbusyclocks%llu sprite_copies%llu frameticks%llu cold_and_active_overrun_holdclocks%llu active_overrun_holdclocks%llu\n",(unsigned long long)road_ready_clocks,(unsigned long long)road_ram_acks,(unsigned long long)road_rom_acks,(unsigned long long)road_dmas,(unsigned long long)sprite_copies,(unsigned long long)frame_ticks,(unsigned long long)overruns,(unsigned long long)active_overruns);
 need(road_ready_clocks>100000 && sprite_copies>2 && frame_ticks>2,"M4 initialization and native snapshots progress");
 printf("DIAGNOSTIC_JSON {\"cycles\":%llu,\"line_events\":%llu,\"raw_deadline_events\":%llu,\"K55_only_events\":%llu,\"K55_and_current_global_events\":%llu,\"previous_latched_effective_events\":%llu,\"before_first_latch_events\":%llu,\"old_classifier_holdclocks\":%llu,\"K55_and_current_global_holdclocks\":%llu,\"first_latch_cycle\":%llu,\"unsupported\":%llu,\"classification_only\":true,\"hardware_verified\":false}\n",(unsigned long long)(cycle-start),(unsigned long long)line_events,(unsigned long long)raw_line_events,(unsigned long long)old_classifier_events,(unsigned long long)current_global_events,(unsigned long long)latched_effective_events,(unsigned long long)cold_raw_events,(unsigned long long)active_overruns,(unsigned long long)global_hold,(unsigned long long)first_latch,(unsigned long long)unsupported);
 need(unsupported==0,"supported modes during bounded diagnostic");
 // Reached scopes are reported independently; no requirement/claim of reaching
 // graphics readback, IRQ gate or game title in this first bounded probe.
 puts("COMPLETE bounded diagnostic; deadline classifications are observations, not repaired-hardware qualification");
}
