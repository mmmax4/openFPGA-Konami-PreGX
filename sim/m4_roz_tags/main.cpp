// Public k053936_roz pixels at a fixed6144clock raster, original frozen states.
// Based on existing sim/tb_roz.cpp; no internal force/state access or ROM patch.
#include "Vm4_roz_tags_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <map>
#include <string>
#include <stdexcept>
#include <algorithm>
static constexpr unsigned W=376,H=224,Y0=16,X0=40,LINE_CLOCKS=6144;
static Vm4_roz_tags_top d;
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();}
static void require(bool v,const char *why){if(!v)throw std::runtime_error(why);}
static std::vector<unsigned char> bytes(const char *path){FILE*f=fopen(path,"rb");require(f,"Inputopen");fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);require(n>=0,"Inputlength");std::vector<unsigned char>b(n);require(fread(b.data(),1,b.size(),f)==b.size(),"Inputread");fclose(f);return b;}
static std::vector<unsigned short> pixels(const char *p){auto b=bytes(p);require(b.size()==W*H*2,"Modelsize");std::vector<unsigned short>v(W*H);for(unsigned i=0;i<v.size();i++)v[i]=b[2*i]|(unsigned(b[2*i+1])<<8);return v;}
static std::map<std::string,std::vector<unsigned>> state(const char *path){std::map<std::string,std::vector<unsigned>>s;FILE*f=fopen(path,"r");require(f,"Stateopen");char*line=nullptr;size_t cap=0;while(getline(&line,&cap,f)>0){if(line[0]=='#')continue;char*save=nullptr;char*key=strtok_r(line," \t\r\n",&save);if(!key||!strcmp(key,"VRAM"))continue;std::vector<unsigned>v;char*t;while((t=strtok_r(nullptr," \t\r\n",&save)))v.push_back(strtoul(t,nullptr,16));s[key]=v;}free(line);fclose(f);return s;}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);if(argc!=7){fprintf(stderr,"usage state ROM output pcb-exact.roz mame-exact.roz variable0or1\n");return 2;}try{
 auto s=state(argv[1]);auto rom=bytes(argv[2]);auto pcb=pixels(argv[4]),mame=pixels(argv[5]);require(rom.size()>=0x760000,"OriginalROMsize");require(s["ROZCT16"].size()==16&&s["ROZCLIP"].size()==2&&s["ROZCTRL"].size()==1&&s["K55REGS"].size()>=48,"Originalregistershape");
 d.variable_latency=atoi(argv[6])!=0;d.reset=1;for(unsigned i=0;i<8;i++)tick();d.reset=0;
 for(unsigned i=0;i<16;i++){d.ctrl_we=1;d.ctrl_addr=i;d.ctrl_data=s["ROZCT16"][i];tick();}d.ctrl_we=0;
 for(unsigned i=0;i<2;i++){d.clip_we=1;d.clip_addr=i;d.clip_data=s["ROZCLIP"][i];tick();}d.clip_we=0;
 d.cfg_we=1;d.roz_enable_i=(s["ROZCTRL"][0]>>8)&1;d.palbase_i=s["K55REGS"][28]&255;tick();d.cfg_we=0;
 for(unsigned w=0;w<0xa0000/2;w++){d.map_we=1;d.map_waddr=w;d.map_wdata=(unsigned(rom[0x6c0000+2*w])<<8)|rom[0x6c0000+2*w+1];tick();}d.map_we=0;
 for(unsigned w=0;w<0x180000/2;w++){d.chr_we=1;d.chr_waddr=w;d.chr_wdata=(unsigned(rom[0x540000+2*w])<<8)|rom[0x540000+2*w+1];tick();}d.chr_we=0;
 // gaia_video emits prestart atvcount10 and firstline_start(next16) at15.
 // Run the exact five-line interval; never stretch the raster to awaitbusy.
 d.prestart=1;tick();d.prestart=0;for(unsigned c=1;c<5*LINE_CLOCKS;c++)tick();
 std::vector<unsigned short>out(W*H,0xffff);unsigned deadlines=0,minimum_lead=15,unsupported=0,protocol=0,checks=0;
 for(unsigned due=0;due<=H;due++){
  // Atpulse due1..224 the previouslyneeded line is about to be displayed.
  if(due){deadlines+=bool(d.busy);minimum_lead=std::min(minimum_lead,unsigned(d.lead));checks++;}
  d.line=Y0+due;d.line_start=1;tick();d.line_start=0;
  for(unsigned c=1;c<LINE_CLOCKS;c++){
   unsigned h=c/12;if(c%12==0)d.px=(h>=X0&&h<X0+W)?h-X0:0;
   tick();unsupported|=d.unsupported;protocol|=d.protocol_error;
   if(due&&c%12==11&&h>=X0&&h<X0+W)out[(due-1)*W+h-X0]=d.opaque?d.pix:0xffff;
  }
 }
 require(checks==H,"All224deadlineschecked");unsigned pcb_bad=0,mame_bad=0,changed_targets=0,visible=0,unchanged_opaque=0,pens_changed=0,first=W*H;
 for(unsigned i=0;i<W*H;i++){
  if(out[i]!=pcb[i]){pcb_bad++;first=std::min(first,i);}mame_bad+=out[i]!=mame[i];changed_targets+=pcb[i]!=mame[i];visible+=pcb[i]!=0xffff;unchanged_opaque+=pcb[i]==mame[i]&&pcb[i]!=0xffff;
  if(pcb[i]!=0xffff&&mame[i]!=0xffff)pens_changed+=(pcb[i]&15)!=(mame[i]&15);
 }
 FILE*f=fopen(argv[3],"wb");require(f,"Outputopen");for(auto p:out){unsigned char b[2]={static_cast<unsigned char>(p&255),static_cast<unsigned char>(p>>8)};require(fwrite(b,1,2,f)==2,"Outputwrite");}fclose(f);
 bool passed=pcb_bad==0&&deadlines==0&&!unsupported&&!protocol;
 if(first<W*H)fprintf(stderr,"PCB firstdifference x%u y%u actual%04x pcb%04x historicalMAME%04x\n",first%W,first/W,out[first],pcb[first],mame[first]);
 unsigned warm_pixels=0,warm_deadlines=0,warm_rasters=0;
 if(std::string(argv[1]).find("s_selrot45.txt")!=std::string::npos && !d.variable_latency){
  // Populated metadata survives physically in RAM. Reset must invalidate it
  // before reuse; issue prestart immediately, earlier than the real consumer.
  d.reset=1;for(unsigned i=0;i<4;i++)tick();d.reset=0;
  d.prestart=1;tick();d.prestart=0;for(unsigned c=1;c<5*LINE_CLOCKS;c++)tick();
  for(unsigned due=0;due<=H;due++){
   if(due)warm_deadlines+=bool(d.busy);
   d.line=Y0+due;d.line_start=1;tick();d.line_start=0;
   for(unsigned c=1;c<LINE_CLOCKS;c++){
    unsigned h=c/12;if(c%12==0)d.px=(h>=X0&&h<X0+W)?h-X0:0;
    tick();require(!d.unsupported&&!d.protocol_error,"Warm reset protocol");
    if(due&&c%12==11&&h>=X0&&h<X0+W)
     warm_pixels+=(d.opaque?d.pix:0xffff)!=pcb[(due-1)*W+h-X0];
   }
  }
  warm_rasters=1;passed=passed&&!warm_pixels&&!warm_deadlines;
 }
 printf("RESET_JSON {\"rasters\":%u,\"pixels_compared\":%u,\"pixel_errors\":%u,\"deadline_checks\":%u,\"deadline_failures\":%u}\n",warm_rasters,warm_rasters*W*H,warm_pixels,warm_rasters*H,warm_deadlines);
 printf("RESULT_JSON {\"passed\":%s,\"pcb_pixel_errors\":%u,\"historical_mame_pixel_errors\":%u,\"pixels_compared\":%u,\"pcb_visible_pixels\":%u,\"pcb_vs_mame_changed_pixels\":%u,\"unchanged_opaque_pixels\":%u,\"target_pen_changes\":%u,\"line_deadline_checks\":%u,\"line_deadline_failures\":%u,\"minimum_lead\":%u,\"unsupported\":%u,\"protocol_errors\":%u,\"map_transactions\":%u,\"block_transactions\":%u,\"map_latency_min\":%u,\"map_latency_max\":%u,\"block_latency_min\":%u,\"block_latency_max\":%u,\"variable_latency\":%s,\"hardware_verified\":false}\n",passed?"true":"false",pcb_bad,mame_bad,W*H,visible,changed_targets,unchanged_opaque,pens_changed,checks,deadlines,minimum_lead,unsupported,protocol,unsigned(d.map_transactions),unsigned(d.block_transactions),unsigned(d.map_latency_min),unsigned(d.map_latency_max),unsigned(d.block_latency_min),unsigned(d.block_latency_max),d.variable_latency?"true":"false");return passed?0:1;
 }catch(const std::exception&e){fprintf(stderr,"FAIL %s\n",e.what());return 2;}}
