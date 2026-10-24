// Independent RGB integration gate: frozen public RAM/register setup, actual
// controllers and line scheduling. Expected RGB is read, never recomputed here.
#include "Vtb_m2_mixer_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <fstream>
#include <iterator>
#include <sstream>
#include <map>
#include <string>
#include <vector>
#include <algorithm>
static Vtb_m2_mixer_top*d;
static uint64_t clocks=0,errors=0,compared=0,de_errors=0,de_compared=0,accepted=0,stalls=0;
static uint64_t cpu_acks[5]={},mem_acks[3]={};
static unsigned worst_tile=0,worst_rgb=0,worst_sprite=0,deadline_errors=0,scenes=0;
static uint64_t tstart=0,sstart=0;
static bool traffic=false;
static unsigned video_phase=1;
static uint64_t halfclock=0,pocket_compared=0,analog_compared=0;
static std::vector<uint32_t>* pocket_pixels=nullptr;
static std::vector<uint32_t>* analog_pixels=nullptr;
static void halfstep(){
 d->clk=(halfclock%2)==0;
 unsigned pos=(halfclock+video_phase)%32;
 if(pos==0)d->clk_vid=1;if(pos==16)d->clk_vid=0;
 d->eval();
 if(pocket_pixels&&pos==0&&d->pocket_de)pocket_pixels->push_back(d->pocket_rgb);
 if(analog_pixels&&d->clk&&d->analog_capture&&!(d->analog_pixel&3))analog_pixels->push_back(d->analog_pixel>>4);
 halfclock++;
}
static void fail(const char*w,uint64_t got,uint64_t exp){if(errors<24)printf("ERROR %s got=%llx expected=%llx cycle=%llu raster=%u:%u x=%u y=%u\n",w,(unsigned long long)got,(unsigned long long)exp,(unsigned long long)clocks,d->vcount,d->hcount,d->scan_x,d->scan_y);errors++;}
static void tick(unsigned n=1){while(n--){
 if(traffic&&!d->reset&&!d->vid_reset){
  if(!d->c_preq&&clocks%193==0){d->c_preq=1;d->c_paddr=(clocks/193)&2047;}
  if(!d->c_areq&&clocks%257==0){d->c_areq=1;d->c_aaddr=(clocks/257)&4095;}
  if(!d->c_treq&&clocks%389==0){d->c_treq=1;d->c_taddr=(clocks/389)&0x7ffff;}
  if(!d->c_sreq&&clocks%521==0){d->c_sreq=1;d->c_saddr=(clocks/521)&0x7ffff;}
  if(!d->c_vreq&&clocks%263==0){d->c_vreq=1;d->c_vaddr=(clocks/263)&65535;}
 }
 bool ts=d->tile_start,ss=d->sprite_start,tb=d->tile_busy,sb=d->sprite_busy,rb=d->compositor_busy;
 bool take=d->fragment_valid&&d->fragment_ready;
 stalls+=d->fragment_valid&&!d->fragment_ready;accepted+=take;
 halfstep();halfstep();clocks++;
 if(ts){if(tstart&&tb){deadline_errors++;fail("Tile not idle at native next start",1,0);}tstart=clocks;}
 if(ss){if(sstart&&(sb||rb)){deadline_errors++;fail("Sprite/RGB not idle at native next start",1,0);}sstart=clocks;}
 if(tb&&!d->tile_busy&&tstart){unsigned v=clocks-tstart;worst_tile=std::max(worst_tile,v);if(v>=6144){deadline_errors++;fail("Tile6144",v,6143);}}
 if(sb&&!d->sprite_busy&&sstart){unsigned v=clocks-sstart;worst_sprite=std::max(worst_sprite,v);if(v>=6144){deadline_errors++;fail("Sprite6144",v,6143);}}
 if(rb&&!d->compositor_busy&&sstart){unsigned v=clocks-sstart;worst_rgb=std::max(worst_rgb,v);if(v>=6144){deadline_errors++;fail("RGB6144",v,6143);}}
 if(d->c_tack){d->c_treq=0;cpu_acks[0]++;}if(d->c_sack){d->c_sreq=0;cpu_acks[1]++;}
 if(d->c_vack){d->c_vreq=0;cpu_acks[2]++;}if(d->c_pack){d->c_preq=0;cpu_acks[3]++;}if(d->c_aack){d->c_areq=0;cpu_acks[4]++;}
 mem_acks[0]+=d->observed_tack;mem_acks[1]+=d->observed_sack;mem_acks[2]+=d->observed_vack;
}}
static std::vector<uint8_t> bytes(const std::string&p){std::ifstream f(p,std::ios::binary);if(!f){fprintf(stderr,"Cannot read %s\n",p.c_str());exit(2);}return{std::istreambuf_iterator<char>(f),{}};}
struct State{std::map<std::string,std::vector<unsigned>> f;std::vector<unsigned> vram[17];};
static State load(const std::string&p){std::ifstream f(p);if(!f)exit(2);State s;std::string line;while(std::getline(f,line)){std::istringstream r(line);std::string k,v;if(!(r>>k)||k[0]=='#')continue;int pg=-1;if(k=="VRAM")r>>pg;std::vector<unsigned> data;while(r>>v)data.push_back(std::stoul(v,nullptr,16));if(pg>=0&&pg<17)s.vram[pg]=data;else s.f[k]=data;}return s;}
static std::vector<uint32_t> expected(const std::string&p){auto b=bytes(p);if(b.size()!=288*224*4){fprintf(stderr,"Bad RGB length\n");exit(2);}std::vector<uint32_t> out;for(unsigned i=0;i<b.size();i+=4)out.push_back(b[i]|(b[i+1]<<8)|(b[i+2]<<16)|(unsigned(b[i+3])<<24));return out;}
static void build(){d->reset=0;tick(4);d->build=1;tick();d->build=0;unsigned n=0;while(!d->build_done&&n++<245760)tick();if(!d->build_done)fail("List build vblank deadline",n,245760);if(d->overflow)fail("Object overflow",1,0);printf("BUILD objects=%u clocks=%u\n",d->object_count,n);}
static void setup(const State&s){
 traffic=false;d->vid_reset=1;d->reset=1;d->build=0;d->vsetup_mode=1;d->c_treq=d->c_sreq=d->c_vreq=d->c_preq=d->c_areq=0;tick(100);tstart=sstart=0;
 const char*keys[]={"K56REGS","K55REGS","K38REGS","K46REGS","K47REGS","SPRITERAM","PALETTE"};unsigned sizes[]={32,48,16,8,8,2048,4096};
 for(unsigned b=0;b<7;b++){auto &v=s.f.at(keys[b]);if(v.size()<sizes[b]){fprintf(stderr,"State %s length%zu !=%u\n",keys[b],v.size(),sizes[b]);exit(2);}for(unsigned a=0;a<sizes[b];a++){d->setup_we=1;d->setup_bank=b;d->setup_addr=a;d->setup_data=v[a];tick();}}d->setup_we=0;
 for(unsigned pg=0;pg<16;pg++){if(s.vram[pg].size()!=4096)exit(2);for(unsigned a=0;a<4096;a++){d->vsetup_req=1;d->vsetup_addr=pg*4096+a;d->vsetup_data=s.vram[pg][a];unsigned n=0;while(!d->vsetup_ack&&n++<200)tick();if(!d->vsetup_ack)fail("VRAM setup ACK",0,1);d->vsetup_req=0;tick(2);}}
 d->vsetup_mode=0;tick(100);build();
}
static void frame(const std::vector<uint32_t>&oracle,const std::string&tag,bool contend,const std::string&outdir){
 std::vector<uint32_t> out(288*224,0xffffffff),deout,pocketout,analogout;std::vector<unsigned> seen(288*224,0);uint64_t prior=errors;unsigned deindex=0;
 pocket_pixels=&pocketout;analog_pixels=&analogout;
 traffic=contend;d->vid_reset=0;unsigned n=0;
 while(n++<1700000){tick();
  if(d->sample_valid){unsigned x=d->scan_x,y=d->scan_y;if(x>=288||y>=224){fail("Visible coordinate bounds",(y<<16)|x,287);continue;}unsigned i=y*288+x;out[i]=d->rgb;seen[i]++;compared++;if(d->rgb!=oracle[i])fail("Registered consumer RGB",d->rgb,oracle[i]);}
  if(d->cen_pix&&d->de){deout.push_back(d->rgb);if(deindex<oracle.size()){de_compared++;de_errors+=d->rgb!=oracle[deindex];}deindex++;}
  if(d->vcount>=242)break;
 }
 pocket_pixels=nullptr;analog_pixels=nullptr;
 traffic=false;for(auto count:seen)if(count!=1)fail("Pixel sampled exactly once",count,1);
 if(deindex!=288*224)fail("Native DE pixel count",deindex,288*224);
 for(unsigned channel=0;channel<2;channel++){
  auto &samples=channel?analogout:pocketout;
  if(samples.size()!=oracle.size())fail(channel?"Analogizer source pixel count":"Pocket pixel count",samples.size(),oracle.size());
  for(unsigned i=0;i<std::min(samples.size(),oracle.size());i++){
   if(channel)analog_compared++;else pocket_compared++;
   if(samples[i]!=oracle[i])fail(channel?"Analogizer source RGB":"Pocket sampled RGB",samples[i],oracle[i]);
  }
  std::ofstream capture(outdir+"/"+tag+(channel?".analog-rgb.bin":".pocket-rgb.bin"),std::ios::binary);
  for(auto c:samples)for(unsigned j=0;j<4;j++)capture.put(char(c>>(8*j)));
 }
 if(d->protocol_errors)fail("SDRAM logical chip protocol",d->protocol_errors,0);if(d->unsupported)fail("Unsupported renderer config",1,0);
 std::ofstream f(outdir+"/"+tag+".rgb.bin",std::ios::binary),g(outdir+"/"+tag+".de-rgb.bin",std::ios::binary);for(auto c:out)for(unsigned j=0;j<4;j++)f.put(char(c>>(8*j)));for(auto c:deout)for(unsigned j=0;j<4;j++)g.put(char(c>>(8*j)));
 printf("SCENE %s contention=%u pixels=%u errors=%llu tile=%u sprite=%u rgb=%u de_mismatches_total=%llu\n",tag.c_str(),contend,288*224,(unsigned long long)(errors-prior),worst_tile,worst_sprite,worst_rgb,(unsigned long long)de_errors);fflush(stdout);scenes++;
 d->vid_reset=1;d->reset=1;tick(100);tstart=sstart=0;
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=4){fprintf(stderr,"usage: mixer originalROM cases.tsv outdir\n");return 2;}auto rom=bytes(argv[1]);if(rom.size()!=0xdc0080)exit(2);
 d=new Vtb_m2_mixer_top;d->reset=d->vid_reset=d->init=1;tick(8);d->init=0;unsigned n=0;while(!d->ready&&n++<100000)tick();if(!d->ready){fail("Memory ready",0,1);return 1;}
 // Immutable original tiles/sprites plus small original program/PCM prefixes
 // used by deterministic read-only contention clients through actual arbiters.
 const unsigned base[]={0,0x240000,0x8c0000,0x4c0000},len[]={4096,0x280000,0x500000,4096};
 for(unsigned r=0;r<4;r++)for(unsigned i=0;i<len[r];i++){d->dl_we=1;d->dl_addr=base[r]+i;d->dl_data=rom[base[r]+i];tick();d->dl_we=0;tick(7);}tick(500);
 std::ifstream cases(argv[2]);std::string row;while(std::getline(cases,row)){if(row.empty())continue;std::istringstream r(row);std::string sp,op,tag;getline(r,sp,'\t');getline(r,op,'\t');getline(r,tag,'\t');auto s=load(sp);auto oracle=expected(op);for(unsigned phase:{1u,31u}){video_phase=phase;auto suffix="-phase"+std::to_string(phase);setup(s);frame(oracle,tag+suffix+"-quiet",false,argv[3]);setup(s);frame(oracle,tag+suffix+"-contention",true,argv[3]);}}
 if(!scenes)fail("Zero executed scenes",0,1);
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"scenes\":%u,\"oracle_pixels_compared\":%llu,\"pocket_pixels_compared\":%llu,\"analogizer_source_pixels_compared\":%llu,\"native_de_pixels_compared\":%llu,\"native_de_rgb_mismatches\":%llu,\"deadline_failures\":%u,\"worst_tile_clocks\":%u,\"worst_sprite_clocks\":%u,\"worst_compositor_clocks\":%u,\"accepted_fragments\":%llu,\"backpressure_cycles\":%llu,\"contention_acks\":[%llu,%llu,%llu,%llu,%llu],\"memory_acks\":[%llu,%llu,%llu],\"cycles\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,scenes,(unsigned long long)compared,(unsigned long long)pocket_compared,(unsigned long long)analog_compared,(unsigned long long)de_compared,(unsigned long long)de_errors,deadline_errors,worst_tile,worst_sprite,worst_rgb,(unsigned long long)accepted,(unsigned long long)stalls,(unsigned long long)cpu_acks[0],(unsigned long long)cpu_acks[1],(unsigned long long)cpu_acks[2],(unsigned long long)cpu_acks[3],(unsigned long long)cpu_acks[4],(unsigned long long)mem_acks[0],(unsigned long long)mem_acks[1],(unsigned long long)mem_acks[2],(unsigned long long)clocks);
 printf("%s M2 combined consumer RGB + Pocket + Analogizer source capture (raw CEN diagnostic separate)\n",errors?"FAIL":"PASS");delete d;return errors?1:0;
}
