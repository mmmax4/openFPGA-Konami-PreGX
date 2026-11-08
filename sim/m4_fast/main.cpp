// Original EAA full core through public tagged memory ports. This controlled
// latency model does not claim to execute Pocket pin controllers or fitted DQ.
#include "Vtb_m4_fast_top.h"
#include "verilated.h"
#include <array>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>
static Vtb_m4_fast_top d;
static uint64_t cycles=0,protocol=0;
static std::vector<uint8_t> image;
static std::array<uint16_t,65536> vram{};
static std::array<uint16_t,16384> road{};
static uint64_t packed(unsigned a,unsigned n){if(a+n>image.size())throw std::runtime_error("Original image port bounds");uint64_t v=0;while(n--)v=(v<<8)|image[a++];return v;}
struct Port {bool req=false,we=false;unsigned addr=0,be=0,data=0;};
struct Bus {
 bool active=false,continuous=false;unsigned who=0,address=0,remaining=0,round=0,gap=0,be=0,data=0;bool write=false;
 std::array<bool,4>held{};std::array<unsigned,4>last{};
 std::array<uint64_t,4>requests{},acks{},cancelled{};
 template<class Complete> void step(const std::array<Port,4>&p,unsigned count,const std::array<unsigned,4>&lat,Complete complete){
  for(unsigned i=0;i<count;i++)if(!p[i].req||p[i].addr!=last[i])held[i]=false;
  if(active){
   if(!p[who].req||p[who].addr!=address||p[who].we!=write)continuous=false;
   if(remaining)remaining--;
   else {
    bool valid=continuous&&p[who].req&&p[who].addr==address;
    complete(who,address,write,be,data,valid);if(valid){acks[who]++;held[who]=true;last[who]=address;}else cancelled[who]++;
    active=false;gap=1;
   }
  } else if(gap)gap--;
  else for(unsigned n=0;n<count;n++){
   unsigned i=(round+n)%count;
   if(p[i].req&&!held[i]){active=true;continuous=true;who=i;address=p[i].addr;write=p[i].we;be=p[i].be;data=p[i].data;
    remaining=lat[i];round=(i+1)%count;requests[i]++;break;}
  }
 }
};
static Bus programs,graphics,tile_ram,state_ram;
static bool snd_cached=false;static unsigned snd_word=0;
static uint64_t ram_commits=0;
static void memory(){
 d.prog_ack=d.srom_ack=d.tile_ack=d.spr_ack=d.lvc_ack=d.pcmr_ack=d.vram_ack=d.road_ack=0;
 std::array<Port,4>p{};
 p[0]={bool(d.prog_req),false,unsigned(d.prog_addr),0,0};p[1]={bool(d.srom_req),false,unsigned(d.srom_addr),0,0};
 // Program and sound share one port. Sound repeats the cached 16-bit word;
 // no speculative prefetch is modeled. All uncached reads wait15clocks.
 unsigned snd_lat=snd_cached&&snd_word==(d.srom_addr>>1)?2:15;
 programs.step(p,2,{{15,snd_lat,0,0}},[](unsigned i,unsigned a,bool,unsigned,unsigned,bool valid){if(!valid)return;
  if(i==0){d.prog_q=packed(a*2,2);d.prog_ack=1;}else{d.srom_q=image.at(0x200000+a);d.srom_ack=1;snd_cached=true;snd_word=a>>1;}});
 p={};p[0]={bool(d.tile_req),false,unsigned(d.tile_addr),0,0};p[1]={bool(d.spr_req),false,unsigned(d.spr_addr),0,0};
 p[2]={bool(d.lvc_req),false,unsigned(d.lvc_addr),0,0};p[3]={bool(d.pcmr_req),false,unsigned(d.pcmr_addr),0,0};
 // One four-client SDRAM envelope, round robin at each complete transaction.
 // All queues run concurrently with both PSRAM ports and the real core VRAM arbiter.
 graphics.step(p,4,{{14,18,18,14}},[](unsigned i,unsigned a,bool,unsigned,unsigned,bool valid){if(!valid)return;
  if(i==0){if(a>=0x100000)throw std::runtime_error("Tile port address");d.tile_q=packed(0x240000+a*4,4);d.tile_ack=1;}
  if(i==1){if(a>=0x100000)throw std::runtime_error("Sprite port address");d.spr_q=packed(0xa40000+a*8,8);d.spr_ack=1;}
  if(i==2){if(a>=32768)throw std::runtime_error("Road ROM port address");d.lvc_q=packed(0x1240000+a*8,8);d.lvc_ack=1;}
  if(i==3){if(a>=0x400000)throw std::runtime_error("PCM port address");d.pcmr_q=image.at(0x640000+a);d.pcmr_ack=1;}});
 p={};p[0]={bool(d.vram_req),bool(d.vram_we),unsigned(d.vram_addr),unsigned(d.vram_be),unsigned(d.vram_wdata)};
 tile_ram.step(p,1,{{6,0,0,0}},[](unsigned,unsigned a,bool we,unsigned be,unsigned data,bool valid){
  auto&word=vram.at(a);if(we){if(be&2)word=(word&255)|(data&0xff00);if(be&1)word=(word&0xff00)|(data&255);}
  if(valid){d.vram_q=word;d.vram_ack=1;}});
 p={};p[0]={bool(d.road_req),bool(d.road_we),unsigned(d.road_addr),unsigned(d.road_be),unsigned(d.road_wdata)};
 state_ram.step(p,1,{{16,0,0,0}},[](unsigned,unsigned a,bool we,unsigned be,unsigned data,bool valid){
  auto&word=road.at(a);if(we){if(be&2)word=(word&255)|(data&0xff00);if(be&1)word=(word&0xff00)|(data&255);ram_commits++;}
  // Writes become visible on the SAME committed edge as ACK, never at request acceptance.
  if(valid){d.road_q=word;d.road_ack=1;}});
}
static void tick(){d.clk=0;d.eval();if(!d.reset)memory();d.eval();
 if(!d.reset&&((d.prog_ack&&!d.prog_req)||(d.srom_ack&&!d.srom_req)||(d.tile_ack&&!d.tile_req)||
  (d.spr_ack&&!d.spr_req)||(d.lvc_ack&&!d.lvc_req)||(d.pcmr_ack&&!d.pcmr_req)||(d.vram_ack&&!d.vram_req)||(d.road_ack&&!d.road_req)))protocol++;
 d.clk=1;d.eval();cycles++;}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);if(argc!=6)return 2;try{
 std::ifstream input(argv[1],std::ios::binary);image.assign(std::istreambuf_iterator<char>(input),{});if(image.size()!=0x1280080)return 2;
 uint64_t bound=std::stoull(argv[2]);bool qualified=std::string(argv[5])=="qualified";
 FILE*trace=fopen(argv[3],"w");if(!trace)return 2;std::string output=argv[4];
 d.reset=1;d.pause=0;d.in0_p1=0xffff;d.p2=0xff;d.in1=0xeb;for(unsigned i=0;i<16;i++)tick();
 for(unsigned i=0;i<128;i++){d.eep_we=1;d.eep_waddr=i;d.eep_wdata=image.at(0x1280000+i);tick();}d.eep_we=0;for(unsigned i=0;i<16;i++)tick();d.reset=0;
 uint64_t start=cycles,steps=0,zsteps=0,raw_events=0,effective_events=0,cold_events=0,nonzero_samples=0,samples=0,work_writes=0,rb=0,irq5=0,irq6=0,copy=0,frame_ticks=0;
 unsigned frames=0,pixels=0,nonzero=0,drawn_frames=0;bool vb=true,i5=false,i6=false;std::vector<uint32_t>frame(288*224);
 for(;cycles-start<bound;){tick();
  if(d.readback_oob)throw std::runtime_error("CPU readback OOB");if(d.k550_write||d.k550_busy)throw std::runtime_error("M4 K055550 activity");
  steps+=d.dbg_step;zsteps+=d.dbg_zstep;work_writes+=d.cpu_work_write;rb+=d.cpu_graphics_ack;
  if(d.global_enable&&d.display_enables&&d.dbg_unsupported)throw std::runtime_error("Enabled unsupported video mode");
  if(d.cpu_irq5&&!i5)irq5++;if(d.cpu_irq6&&!i6)irq6++;i5=d.cpu_irq5;i6=d.cpu_irq6;copy+=d.sprite_copy;frame_ticks+=d.road_frame_tick;
  if(d.line_event&&d.dbg_overrun){raw_events++;
   unsigned relevant=((d.previous_planes&15)?4:0)|((d.previous_planes&16)?2:0)|((d.previous_planes||d.previous_sprite_enable)?1:0);
   if(d.sampled_busy&relevant){effective_events++;if(effective_events<17)fprintf(trace,"deadline cycle%llu v%u src%x relevant%x planes%x sprite%u global%u enable%x\n",(unsigned long long)(cycles-start),d.dbg_vcount,d.sampled_busy,relevant,d.previous_planes,d.previous_sprite_enable,d.global_enable,d.display_enables);}
   else cold_events++;
  }
  if(d.snd_valid){samples++;nonzero_samples+=(d.snd_l||d.snd_r);}
  if(d.cen_pix&&d.de){if(pixels<frame.size())frame[pixels]=d.rgb;pixels++;nonzero+=(d.rgb!=0);}
  if(d.vblank&&!vb){frames++;drawn_frames+=nonzero!=0;
   fprintf(trace,"frame%u cycles%llu cpu%llu zcpu%llu enable%02x global%u pixels%u nonzero%u workwrites%llu rb%llu irq5%llu irq6%llu raw%llu effective%llu samples%llu nonzeroaudio%llu addr%06x\n",frames,(unsigned long long)(cycles-start),(unsigned long long)steps,(unsigned long long)zsteps,d.display_enables,d.global_enable,pixels,nonzero,(unsigned long long)work_writes,(unsigned long long)rb,(unsigned long long)irq5,(unsigned long long)irq6,(unsigned long long)raw_events,(unsigned long long)effective_events,(unsigned long long)samples,(unsigned long long)nonzero_samples,d.dbg_addr);fflush(trace);
   if(frames%120==0||(nonzero&&drawn_frames==1)){char path[1024];snprintf(path,sizeof(path),"%s.f%05u.rgb",output.c_str(),frames);FILE*f=fopen(path,"wb");if(!f)return 2;fwrite(frame.data(),4,frame.size(),f);fclose(f);}
   pixels=nonzero=0;
  }vb=d.vblank;
 }
 fclose(trace);FILE*f=fopen((output+".last.rgb").c_str(),"wb");if(!f)return 2;fwrite(frame.data(),4,frame.size(),f);fclose(f);
 bool base=steps>10000&&zsteps>1000&&frames>2&&copy>2&&frame_ticks>2&&!protocol;
 bool meaningful=drawn_frames>10&&nonzero_samples>100&&work_writes>100&&rb>100&&irq5>5&&irq6>5;
 bool pass=base&&effective_events==0&&(!qualified||meaningful);
 printf("RESULT_JSON {\"passed\":%s,\"qualified_run\":%s,\"cycles\":%llu,\"frames\":%u,\"CPUsteps\":%llu,\"Z80steps\":%llu,\"work_writes\":%llu,\"readback_ack_context\":%llu,\"IRQ5edges\":%llu,\"IRQ6edges\":%llu,\"drawn_frames\":%u,\"audio_samples\":%llu,\"nonzero_audio_samples\":%llu,\"raw_deadline_events\":%llu,\"effective_deadline_events\":%llu,\"unused_deadline_events\":%llu,\"road_state_commits\":%llu,\"gfx_acks\":[%llu,%llu,%llu,%llu],\"hardware_verified\":false}\n",pass?"true":"false",qualified?"true":"false",(unsigned long long)(cycles-start),frames,(unsigned long long)steps,(unsigned long long)zsteps,(unsigned long long)work_writes,(unsigned long long)rb,(unsigned long long)irq5,(unsigned long long)irq6,drawn_frames,(unsigned long long)samples,(unsigned long long)nonzero_samples,(unsigned long long)raw_events,(unsigned long long)effective_events,(unsigned long long)cold_events,(unsigned long long)ram_commits,(unsigned long long)graphics.acks[0],(unsigned long long)graphics.acks[1],(unsigned long long)graphics.acks[2],(unsigned long long)graphics.acks[3]);return pass?0:1;
 }catch(const std::exception&e){fprintf(stderr,"FAIL clock%llu: %s\n",(unsigned long long)cycles,e.what());return 2;}}
