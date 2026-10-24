// Source-bound production snapshot pipeline, original consecutive RAM states.
#include "Vtb_m2_sprite_capture_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <array>
static Vtb_m2_sprite_capture_top d;
static unsigned starts=0,cycles=0,timing_errors=0;
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();cycles++;if(d.list_start)starts++;}
using RAM=std::array<uint16_t,2048>;
static RAM readram(const char*path){RAM a{};FILE*f=fopen(path,"rb");if(!f)exit(3);for(auto&v:a){int l=fgetc(f),h=fgetc(f);if(l<0||h<0)exit(3);v=uint16_t(l|(h<<8));}if(fgetc(f)!=EOF)exit(3);fclose(f);return a;}
static void load(const RAM&a){d.source_we=1;for(unsigned i=0;i<a.size();i++){d.source_addr=i;d.source_data=a[i];tick();}d.source_we=0;}
static unsigned frame(const RAM&expected,bool mystic,bool enable,unsigned expected_starts){
 unsigned before=starts,errors=0,first_line=999,first_clock=999;
 d.mystic=mystic;d.objset1=enable?0x30:0x20;
 // Actual Mystic raster:384 pixels,16 clocks/pixel,HS328..359, blank from240.
 // Prime two active HS samples, then visit three complete blanking lines.
 for(unsigned line=238;line<=242;line++){
  d.vcount=line;d.vblank=line>=240;
  for(unsigned clock=0;clock<6144;clock++){
   d.hcount=clock/16;d.cen_pix=(clock%16)==0;
   d.hsync=d.hcount>=328&&d.hcount<360;tick();
   if(d.copy_busy&&first_line==999){first_line=line;first_clock=clock;}
  }
 }
 d.vcount=243;d.hcount=0;d.cen_pix=0;d.hsync=0;
 errors+=(starts-before!=expected_starts);
 if(mystic){
  if(enable)timing_errors+=(first_line!=241||first_clock!=5249);
  else timing_errors+=(first_line!=999);
 }else errors+=(first_line!=240||first_clock!=1);
 for(unsigned i=0;i<expected.size();i++){d.read_addr=i;tick();if(d.snapshot_data!=expected[i])errors++;}
 return errors;
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=4)return 3;
 RAM a=readram(argv[1]),partial=readram(argv[2]),complete=readram(argv[3]);
 d.reset=1;d.mystic=1;d.objset1=0x30;d.cen_pix=0;d.vcount=241;d.hcount=1;
 for(unsigned i=0;i<8;i++)tick();d.reset=0;
 load(a);unsigned initial=frame(a,true,true,1);
 load(partial);unsigned held=frame(a,true,false,0);
 load(complete);unsigned published=frame(complete,true,true,1);
 load(a);unsigned gaia=frame(a,false,false,1);
 printf("CAPTURE_RESULT initial%u held%u published%u gaia%u timing%u starts%u cycles%u words%u\n",initial,held,published,gaia,timing_errors,starts,cycles,4*2048);
 return (initial||held||published||gaia||timing_errors)?1:0;
}
