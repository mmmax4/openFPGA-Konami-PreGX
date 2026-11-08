// Actual tile + actual road/shared banks + actual five-plane RGB consumer.
// Source-only reference uses pinned upstream tile pixels and MAME's LVC transcription.
// Compatible original scenes additionally compare captured MAME RGB directly.
#include "Vm4_rgb_top.h"
#include "verilated.h"
#include "lvc_ref.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>
static Vm4_rgb_top d;
static LvcRef roadref;
static std::vector<uint8_t>tile_rom,road_rom;
static std::array<uint16_t,65536>vram{};
static unsigned road_latency=35,active_y=999,row_clocks=0;
static uint64_t clocks=0,raw_road_checks=0,raw_road_errors=0,protocol_errors=0;
struct Memory{bool active=false,held=false;unsigned address=0,wait=0,serial=0,acks=0;};static Memory vr,tr,rr;
static bool fired_order=false,fired_fragment=false;static uint64_t orders_sent=0,fragments_sent=0,shadows_sent=0;
static void need(bool b,const char*s){if(!b)throw std::runtime_error(s);}
static std::vector<uint8_t>bytes(const std::string&p){std::ifstream f(p,std::ios::binary);need(bool(f),p.c_str());return{std::istreambuf_iterator<char>(f),{}};}
static unsigned le16(const std::vector<uint8_t>&b,unsigned at){return b.at(at)|(unsigned(b.at(at+1))<<8);}
static uint32_t le32(const std::vector<uint8_t>&b,unsigned at){return le16(b,at)|(uint32_t(le16(b,at+2))<<16);}
static void tick(){
 d.clk=0;d.vram_ack=d.tile_ack=d.road_ack=0;d.eval();
 auto memory=[&](Memory&r,bool req,unsigned address,unsigned delay,unsigned kind){
  if(!req){r.active=false;r.held=false;return;}
  if(r.held&&address!=r.address)r.held=false;
  if(r.active&&address!=r.address){protocol_errors++;r.active=false;}
  if(!r.active&&!r.held){r.active=true;r.address=address;r.wait=delay;r.serial++;}
  if(r.active){if(r.wait)r.wait--;else{
   if(kind==0){d.vram_q=vram.at(address);d.vram_ack=1;}
   else if(kind==1){unsigned a=address*5;need(a+5<=tile_rom.size(),"Original tile bounds");d.tile_q=(unsigned(tile_rom[a])<<24)|(unsigned(tile_rom[a+1])<<16)|(unsigned(tile_rom[a+2])<<8)|tile_rom[a+3];need(!tile_rom[a+4],"Original M4 fifth plane");d.tile_ack=1;}
   else{unsigned a=address*8;need(a+8<=road_rom.size(),"Original road bounds");uint64_t q=0;for(unsigned i=0;i<8;i++)q=(q<<8)|road_rom[a+i];d.road_q=q;d.road_ack=1;}
   r.active=false;r.held=true;r.acks++;
  }}
 };
 if(!d.reset){memory(vr,d.vram_req,d.vram_addr,5+vr.serial%5,0);memory(tr,d.tile_req,d.tile_addr,14+tr.serial%22,1);memory(rr,d.road_req,d.road_addr,road_latency,2);}
 d.eval();fired_order=d.order_valid&&d.order_ready;fired_fragment=d.fragment_valid&&d.fragment_ready;orders_sent+=fired_order;fragments_sent+=fired_fragment;shadows_sent+=fired_fragment&&d.fragment_shadow;unsigned sampled_x=d.tile_x;bool check=active_y<224&&row_clocks>3&&!d.row_busy;
 d.clk=1;d.eval();clocks++;
 if(check&&!d.row_busy){unsigned want=roadref.bitmap[(15+active_y)*roadref.W()+24+sampled_x];bool op=want!=0;unsigned pen=((unsigned(d.k55[28])<<8)+(want&511))&2047;
  raw_road_checks++;if(bool(d.road_opaque)!=op||(op&&d.road_pen!=pen)){if(raw_road_errors<6)fprintf(stderr,"ROAD_TO_RGB mismatch row%u x%u got%03x op%u want%03x op%u\n",active_y,sampled_x,unsigned(d.road_pen),unsigned(d.road_opaque),pen,unsigned(op));raw_road_errors++;}}
 row_clocks++;
}
static unsigned factor(unsigned selector){return selector==1?d.k38[11]&255:selector==2?d.k38[12]>>8:d.k38[12]&255;}
static uint32_t bright(uint32_t color,unsigned f){if(f==255)return color;uint32_t out=0;for(unsigned s=0;s<24;s+=8)out|=((((color>>s)&255)*f)>>8)<<s;return out;}
static unsigned alpha(unsigned effect){if(!effect)return 255;unsigned v=effect==1?d.k38[13]&255:effect==2?d.k38[14]>>8:d.k38[14]&255;unsigned l=(v&32)?v&31:31-(v&31);return(l<<3)|(l>>2);}
static uint32_t blend(uint32_t src,uint32_t dst,unsigned a){if(a==255)return src;uint32_t out=0;for(unsigned s=0;s<24;s+=8)out|=((((src>>s)&255)*a+((dst>>s)&255)*(256-a))>>8)<<s;return out;}
static void output(const std::string&p,const std::vector<uint32_t>&pixels){std::ofstream f(p,std::ios::binary);need(bool(f),"RGB artifact");for(auto v:pixels)for(unsigned b=0;b<4;b++)f.put(char(v>>(8*b)));}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);if(argc!=7)return 2;try{
 std::string folder=argv[1];auto k56=bytes(folder+"/k56_regs.bin"),k55=bytes(folder+"/k55_regs.bin"),k38=bytes(folder+"/k38_regs.bin"),pal=bytes(folder+"/palette.bin"),ram=bytes(folder+"/lvc_ram.bin"),reg=bytes(folder+"/lvc_regs.bin"),page=bytes(folder+"/lvc_page.bin"),tvram=bytes(folder+"/k56_vram.bin"),tiles=bytes(folder+"/tiles-reference.bin"),mame=bytes(folder+"/pixels-current.bin");
 tile_rom=bytes(argv[2]);road_rom=bytes(argv[3]);road_latency=std::stoul(argv[4]);unsigned mode=std::stoul(argv[5]);
 need(k56.size()==64&&k55.size()==128&&k38.size()>=32&&pal.size()==8192&&ram.size()==0x6000&&reg.size()==8&&page.size()==1&&page[0]<2&&tiles.size()==4*288*224*2&&mame.size()==288*224*4,"Original RGB input shape");
 for(unsigned i=0;i<32;i++)d.k56[i]=le16(k56,2*i);for(unsigned i=0;i<48;i++)d.k55[i]=k55[i];for(unsigned i=0;i<16;i++)d.k38[i]=le16(k38,2*i);for(unsigned i=0;i<8;i++)d.k50[i]=reg[i];for(unsigned i=0;i<65536;i++)vram[i]=le16(tvram,2*i);
 // Explicit isolated controls; original captured bytes remain untouched.
 if(mode==2){d.k55[16]=0;d.k55[7]=48;} // road in front, text farther back
 if(mode==3)d.k55[16]=d.k55[13];       // SUB1/tileC equal-priority ordering
 if(mode==4){d.k55[35]=4;d.k38[13]=(d.k38[13]&0xff00)|31;} // zero alpha hides road
 if(mode==6){d.k55[35]=4;d.k38[13]=(d.k38[13]&0xff00)|16;} // partial road alpha still paints solid
 if(mode==5)d.k55[42]=0x55;            // original BRIGHT1 register, all tile events
 roadref.set_rom(road_rom.data(),road_rom.size());for(unsigned i=0;i<8;i++)roadref.regs[i]=reg[i];for(unsigned i=0;i<2048;i++)roadref.line_ram[i]=le16(ram,0x4000+page[0]*0x1000+2*i);roadref.draw();
 std::array<uint32_t,2048>palette{};for(unsigned i=0;i<2048;i++)palette[i]=((le16(pal,4*i)&255)<<16)|le16(pal,4*i+2);
 std::vector<unsigned>layers;const unsigned spr_priority=mode==7?unsigned(d.k55[16]):0;
 const unsigned pr[7]={d.k55[7],d.k55[10],d.k55[13],d.k55[14],d.k55[16],spr_priority,spr_priority};
 for(unsigned l=0;l<4;l++)if((d.k55[45]&(1u<<l))&&(d.k38[15]&1))layers.push_back(l);
 unsigned road_mix=(d.k55[35]>>2)&3,road_control=road_mix==1?d.k38[13]&255:road_mix==2?d.k38[14]>>8:d.k38[14]&255;
 bool hide=d.k55[35]!=255&&road_mix&&((road_control&31)==31);
 if((d.k55[45]&32)&&(d.k38[15]&1)&&!hide)layers.push_back(4);
 if(mode>=7){layers.push_back(5);layers.push_back(6);}
 const unsigned tie[7]={6,5,4,3,2,0,1}; // pinned MF tie order OBJ,SHD,SUB1,D,C,B,A
 std::sort(layers.begin(),layers.end(),[&](unsigned a,unsigned b){return pr[a]!=pr[b]?pr[a]>pr[b]:tie[a]<tie[b];});
 unsigned initial=255;bool any=false;unsigned lastprio=0;
 for(int l=3;l>=0;l--)if((d.k55[45]&(1u<<l))&&(!any||pr[l]<=lastprio)){any=true;lastprio=pr[l];unsigned s=(d.k55[42]>>(2*l))&3;initial=s?factor(s):255;}
 unsigned fallback_pen=0;for(unsigned i=0;i<4*288*224;i++)if(le16(tiles,2*i)!=65535){fallback_pen=le16(tiles,2*i)&2047;break;}
 auto injected_pen=[&](unsigned y,unsigned x){unsigned p=le16(tiles,2*(y*288+x));return p==65535?fallback_pen:p&2047;};
 auto shade=[&](uint32_t rgb){uint32_t out=0;for(unsigned c=0;c<3;c++){unsigned shift=16-8*c,v=(rgb>>shift)&255;unsigned five=v>>3;int delta=d.k38[2+c]&511;if(delta&256)delta-=512;delta=std::max(-255,delta);int value=int((five<<3)|(five>>2))+delta;unsigned result=(d.k38[15]&32)?unsigned(value)&255:unsigned(std::max(0,std::min(255,value)));out|=result<<shift;}return out;};
 std::vector<uint32_t>oracle(288*224),actual(288*224,0xffffffff);uint64_t road_visible=0;
 for(unsigned y=0;y<224;y++)for(unsigned x=0;x<288;x++){
  unsigned at=y*288+x;uint32_t rgb=((d.k38[0]&255)<<16)|d.k38[1];unsigned brightness=initial;
  for(unsigned l:layers){unsigned pen=65535,a=255;
   if(l==5){rgb=blend(bright(palette[injected_pen(y,x)],brightness),rgb,128);continue;}
   if(l==6){rgb=shade(rgb);continue;}
   if(l<4){unsigned s=(d.k55[42]>>(2*l))&3;brightness=s?factor(s):255;pen=le16(tiles,2*(l*288*224+at));unsigned e=((d.k55[33]>>(2*l))&3)&((d.k55[34]>>(2*l))&3);a=alpha(e);}
   else{unsigned v=roadref.bitmap[(15+y)*roadref.W()+24+x];if(v){pen=((unsigned(d.k55[28])<<8)+(v&511))&2047;road_visible++;}}
   if(pen!=65535&&a)rgb=blend(bright(palette[pen&2047],brightness),rgb,a);
  }oracle[at]=rgb;
 }
 d.reset=1;d.spr_busy=d.order_valid=d.fragment_valid=0;d.cpu_we=0;d.tile_start=d.road_start=d.rgb_start=d.latch=d.frame_tick=0;for(unsigned i=0;i<256;i++)tick();
 for(unsigned i=0;i<4096;i++){d.pal_we=1;d.pal_addr=i;d.pal_data=le16(pal,2*i);tick();}d.pal_we=0;d.reset=0;for(unsigned i=0;i<700;i++)tick();
 auto dma=[&](unsigned source){d.frame_tick=1;tick();d.frame_tick=0;d.k50[4]=reg[4]|2;
  for(unsigned i=0;i<2048;i++){d.cpu_we=1;d.cpu_addr=i;d.cpu_be=3;d.cpu_wdata=le16(ram,0x4000+source*0x1000+2*i);tick();}d.cpu_we=0;for(unsigned i=0;i<4;i++)tick();d.k50[4]=reg[4]&~2;for(unsigned i=0;i<4;i++)tick();
  unsigned n=0;while(d.dma_busy&&n++<10000)tick();need(!d.dma_busy,"Internal road DMA completion");};
 dma(page[0]);dma(page[0]^1);for(unsigned i=0;i<8;i++)d.k50[i]=reg[i];for(unsigned i=0;i<4;i++)tick();d.latch=1;tick();d.latch=0;for(unsigned i=0;i<6000;i++)tick();
 // Forecast row0 in vblank. Eight-line warmup matches the retained continuous fixture.
 d.native_line=17;d.tile_line=17;d.tile_start=d.road_start=1;tick();d.tile_start=d.road_start=0;for(unsigned i=1;i<8*6144;i++)tick();
 unsigned tile_late=0,rgb_late=0,road_late=0,unsupported=0,worst_rgb=0;uint64_t compared=0,bad=0,mame_bad=0;
 for(unsigned row=0;row<=224;row++){
  unsigned packet=mode>=7&&row<224?0:4,packet_x=0;d.spr_busy=packet<4;d.order_valid=d.fragment_valid=0;
  active_y=row;row_clocks=0;d.native_line=17+row;d.tile_line=18+row;d.tile_start=d.road_start=d.rgb_start=1;tick();d.tile_start=d.road_start=d.rgb_start=0;unsigned done=0;
  for(unsigned c=1;c<6144;c++){
   bool scan=row>0&&c>=24*16&&c<(24+288)*16;unsigned x=scan?(c-24*16)/16:0;
   if(mode>=7&&row<224){
    d.spr_busy=packet<4;d.order_valid=packet==0||packet==2;d.order_priority=spr_priority;d.order_deferred=0;
    d.fragment_valid=packet==1||packet==3;d.fragment_x=packet_x;d.fragment_pen=injected_pen(row,packet_x);d.fragment_level=packet==3?255:128;
    d.fragment_shadow=packet==3;d.fragment_table=0;d.fragment_condition=3;d.fragment_z=20;d.fragment_pri=spr_priority;
   }
   if(scan&&c%16==0)d.scan_x=x;tick();
   if(fired_order){packet++;packet_x=0;}if(fired_fragment){if(++packet_x==288){packet++;packet_x=0;}}
   unsupported|=d.unsupported;if(!done&&!d.rgb_busy)done=c;
   if(scan&&c%16==2){unsigned at=(row-1)*288+x;actual[at]=d.rgb;compared++;if(d.rgb!=oracle[at]){if(bad<8)fprintf(stderr,"RGB mismatch y%u x%u actual%06x source%06x\n",row-1,x,unsigned(d.rgb),oracle[at]);bad++;}mame_bad+=d.rgb!=(le32(mame,4*at)&0xffffff);}
  }
  if(row<224){tile_late+=bool(d.tile_busy);rgb_late+=bool(d.rgb_busy)||!done;road_late+=bool(d.row_busy);if(done>worst_rgb)worst_rgb=done;}
 }
 if(mode>=7)need(orders_sent==448&&fragments_sent==129024&&shadows_sent==64512,"All constructed solid/shadow public packets accepted");
 printf("SPRITE_CONSUMER_JSON {\"orders\":%llu,\"fragments\":%llu,\"shadow_fragments\":%llu,\"shadow_condition\":3}\n",(unsigned long long)orders_sent,(unsigned long long)fragments_sent,(unsigned long long)shadows_sent);
 output(std::string(argv[6])+".actual.rgb",actual);output(std::string(argv[6])+".source.rgb",oracle);
 bool pass=bad==0&&raw_road_errors==0&&tile_late==0&&rgb_late==0&&road_late==0&&!unsupported&&!protocol_errors&&(mode!=0||mame_bad==0);
 printf("RESULT_JSON {\"passed\":%s,\"mode\":%u,\"road_latency\":%u,\"pixels_compared\":%llu,\"source_RGB_errors\":%llu,\"captured_MAME_RGB_errors\":%llu,\"MAME_RGB_required\":%s,\"raw_road_pixel_checks\":%llu,\"raw_road_pixel_errors\":%llu,\"reference_road_visible_pixels\":%llu,\"tile_deadline_failures\":%u,\"RGB_deadline_failures\":%u,\"road_deadline_failures\":%u,\"deadline_checks_each\":224,\"worst_RGB_line_clocks\":%u,\"protocol_errors\":%llu,\"unsupported\":%u,\"VRAM_responses\":%u,\"tile_ROM_responses\":%u,\"road_ROM_responses\":%u,\"hardware_verified\":false}\n",pass?"true":"false",mode,road_latency,(unsigned long long)compared,(unsigned long long)bad,(unsigned long long)mame_bad,mode==0?"true":"false",(unsigned long long)raw_road_checks,(unsigned long long)raw_road_errors,(unsigned long long)road_visible,tile_late,rgb_late,road_late,worst_rgb,(unsigned long long)protocol_errors,unsupported,vr.acks,tr.acks,rr.acks);return pass?0:1;
 }catch(const std::exception&e){fprintf(stderr,"FAIL %s\n",e.what());return 2;}}
