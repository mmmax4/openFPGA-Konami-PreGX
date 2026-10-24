// Lead original-machine integration probe, not a golden RGB/gameplay test.
#include "Vtb_m2_machine_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
static Vtb_m2_machine_top d;
static uint64_t cycle=0;
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();cycle++;}
static void need(bool b,const char*s){if(!b){fprintf(stderr,"FAIL cycle%llu %s\n",(unsigned long long)cycle,s);exit(1);}}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);
 if(argc!=5){fprintf(stderr,"usage: machine original.rom maxclocks trace frame.rgb\n");return 2;}
 FILE*f=fopen(argv[1],"rb");need(f,"original image open");std::vector<unsigned char> image(0xdc0080);
 need(fread(image.data(),1,image.size(),f)==image.size()&&fgetc(f)==EOF,"exact original compact image length");fclose(f);
 const uint64_t bound=strtoull(argv[2],nullptr,10);FILE*tr=fopen(argv[3],"w");need(tr,"trace open");
 d.reset=1;d.pause=0;d.in0_p1=65535;d.in1=0xe7;d.p2=255;
 for(unsigned i=0;i<8;i++)tick();
 auto load=[&](unsigned from,unsigned to,unsigned dest,bool sd){d.preload_sdram=sd;d.preload_we=1;for(unsigned a=from;a<to;a+=2){d.preload_addr=dest++;d.preload_data=(image[a]<<8)|image[a+1];tick();}d.preload_we=0;};
 load(0,0x200000,0,false);load(0x200000,0x240000,0x180000,false);load(0x240000,0xdc0000,0,true);
 for(unsigned i=0;i<128;i++){d.eep_we=1;d.eep_waddr=i;d.eep_wdata=image[0xdc0000+i];tick();}d.eep_we=0;
 for(unsigned i=0;i<16;i++)tick();d.reset=0;const auto start=cycle;
 uint64_t steps=0,zsteps=0,irq2edges=0,irq4edges=0,unsupported=0,overruns=0,audio=0,nonzeroaudio=0,rb=0,wram=0;
 unsigned frames=0,pixels=0,nonzero=0,sound_events=0;uint16_t last_z_opcode=0;
 bool vb=true,i2=false,i4=false;std::vector<uint32_t> frame(288*224);
 for(;cycle-start<bound;){
  tick();need(d.sd_errors==0,"SDRAM logical protocol");need(!d.dbg_rb_oob,"CPU readback stays within known original region");
  if(d.dbg_step){steps++;if(d.dbg_addr>=0x200000&&d.dbg_addr<0x210000)wram++;if((d.dbg_addr>=0x680000&&d.dbg_addr<0x684000)||(d.dbg_addr>=0x482000&&d.dbg_addr<0x482010))rb++;}
  zsteps+=d.dbg_zstep;unsupported+=d.dbg_unsupported;overruns+=d.dbg_overrun;
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
 printf("RESULT cycles%llu frames%u steps%llu zsteps%llu IRQ2%llu IRQ4%llu workram%llu readback%llu enable%02x audio%llu active%llu unsupported%llu overrun%llu\n",(unsigned long long)(cycle-start),frames,(unsigned long long)steps,(unsigned long long)zsteps,(unsigned long long)irq2edges,(unsigned long long)irq4edges,(unsigned long long)wram,(unsigned long long)rb,d.dbg_k55_enable,(unsigned long long)audio,(unsigned long long)nonzeroaudio,(unsigned long long)unsupported,(unsigned long long)overruns);
 need(steps>10000&&zsteps>1000&&frames>2,"bounded complete machine CPU/raster progress");
 need(overruns==0&&unsupported==0,"renderer line deadlines and supported modes");
 // Reached scopes are reported independently; no requirement/claim of reaching
 // graphics readback, IRQ gate or game title in this first bounded probe.
 puts("PASS bounded machine CPU/raster/protocol probe; RGB equivalence and unreached scopes unqualified");
}
