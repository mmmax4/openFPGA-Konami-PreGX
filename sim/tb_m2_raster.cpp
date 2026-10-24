// Actual CE->raster public waveforms/counts, no display/DDR/PLL model.
#include "Vtb_m2_raster_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
static Vtb_m2_raster_top d;
static unsigned clocks=0,checks=0;
static void ck(bool b,const char*m){++checks;if(!b){fprintf(stderr,"FAIL clock%u h%u v%u %s\n",clocks,unsigned(d.hcount),unsigned(d.vcount),m);exit(1);}}
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();++clocks;}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=3)return 2;bool m=atoi(argv[1]);FILE*f=fopen(argv[2],"wb");ck(f,"trace open");
 const unsigned ht=m?384:512,w=m?288:376,period=m?16:12;
 d.reset=1;d.mystic=m;for(int i=0;i<8;i++)tick();d.reset=0;
 unsigned h=0,v=0,frames=0,pixels=0,active=0,hs=0,vs=0,hb=0,vb=0,ls=0,pre=0,scan=0,irqs=0,ovl=0,lastline=0,lastpixel=0;
 uint64_t prev=~0ull;
 while(frames<3){
  d.renderers_busy=d.hcount==0&&d.vcount==99?5:0;tick();
  ck(d.hcount<ht&&d.vcount<264,"native raster bounds");
  if(d.px_valid)ck(d.px<w,"visible scanout clipped correctly");
  if(d.line_start){++ls;ck(d.render_line>=16&&d.render_line<=240,"next-line renderer window");if(d.overrun){++ovl;ck(d.overrun_src==5&&d.render_line==100,"deadline diagnostic retains source");}if(lastline)ck(clocks-lastline==6144||d.render_line==16,"6144 line budget");lastline=clocks;}
  pre+=d.prestart;if(frames>=1)irqs+=d.vblank_rise;
#ifndef OLD_RASTER
  if(d.scanline_start){++scan;ck(d.hcount==1,"native all-line IRQ event");}
#endif
  uint64_t flags=d.line_start|(d.prestart<<1)|(d.overrun<<2)|(d.overrun_src<<3)|(d.px_valid<<6)|(d.hsync<<7)|(d.vsync<<8)|(d.de<<9)|(d.hblank<<10)|(d.vblank<<11)|(d.vblank_rise<<12);
  uint64_t val=d.hcount|(uint64_t(d.vcount)<<9)|(uint64_t(d.px)<<18)|(uint64_t(d.render_line)<<27)|(flags<<36);
  if(val!=prev){uint64_t now=clocks;fwrite(&now,8,1,f);fwrite(&val,8,1,f);prev=val;}
  if(d.hcount!=h||d.vcount!=v){
   if(lastpixel)ck(clocks-lastpixel==period,"pixel period independent of CPU enable");lastpixel=clocks;
   if(frames>=1){++pixels;active+=d.de;hs+=d.hsync;vs+=d.vsync;hb+=d.hblank;vb+=d.vblank;}
   if(d.hcount==0&&d.vcount==0)++frames;h=d.hcount;v=d.vcount;
  }
  ck(clocks<6000000,"one warm-up and two complete measured frames");
 }
 fclose(f);printf("COUNTS pixels%u visible%u hs%u vs%u hb%u vb%u ls%u pre%u irq%u ovl%u scan%u\n",pixels,active,hs,vs,hb,vb,ls,pre,irqs,ovl,scan);fflush(stdout);ck(pixels==2*ht*264,"complete pixel count");ck(active==2*w*224,"complete visible frame");
 ck(hs==2*32*264,"hsync width");ck(vs==2*(m?8:3)*ht,"vsync width");ck(hb==2*(ht-w)*264&&vb==2*ht*40,"blanking intervals");
 ck(ls==675&&pre==(m?0:3)&&irqs==2&&ovl==3,"renderer/prestart/vblank/deadline counts");
#ifndef OLD_RASTER
 ck(scan==792,"native every-line IRQ events");
#endif
 printf("PASS mode%u clocks%u checks%u pixels%u visible%u lines%u scanline%u prestart%u irq%u deadlines_injected%u\n",m,clocks,checks,pixels,active,ls,scan,pre,irqs,ovl);
}
