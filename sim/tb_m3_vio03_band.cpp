// Independent RGB integration gate: frozen public RAM/register setup, actual
// controllers and line scheduling. Expected RGB is read, never recomputed here.
#include "Vtb_m3_vio03_band.h"
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
static Vtb_m3_vio03_band*d;
static uint64_t clocks=0,errors=0,compared=0,de_errors=0,de_compared=0,accepted=0,stalls=0;
static uint64_t cpu_acks[4]={},mem_acks[3]={};
static unsigned worst_tile=0,worst_rgb=0,worst_sprite=0,deadline_errors=0,scenes=0;
static uint64_t tstart=0,sstart=0;
static bool traffic=false;
static bool audio_running=false;
static bool audio_manual_write=false;
static uint64_t audio_clock=0,audio_requests=0,audio_acks=0,audio_bytes_correct=0;
static uint64_t audio_high_acks=0,audio_active_cycles=0,audio_events=0,audio_samples=0,audio_late=0;
static uint64_t audio_chip_requests[2]={},audio_chip_active[2]={};
static unsigned previous_chip_req=0;
static bool pcm_pending=false,pcm_held=false;
static unsigned pcm_address=0,pcm_wait=0,max_pcm_wait=0;
static std::vector<uint8_t> pcm_original;
struct AudioWrite {unsigned chip,address,value;};
static std::vector<std::vector<AudioWrite>> audio_schedule;
static std::string audio_dir;
struct LineStats {unsigned line=0,depth=0,reserved=0,rgb=0,pcm_wait=0,overrun=0,busy=0,tile_cycles=0,sprite_cycles=0,rgb_cycles=0,deadlines=0;uint64_t requests=0,acks=0,stalls=0;
 unsigned spr_reqs=0,spr_acks=0,spr_wait_cycles=0,spr_max_wait=0;
 unsigned tile_reqs=0,tile_acks=0,tile_wait_cycles=0,tile_max_wait=0;
 unsigned row_wait=0,order_wait=0,compositor_mask=0;
};
static LineStats line_stats;
static std::ofstream* line_log=nullptr;
static uint64_t observed_overruns=0;
static std::ofstream* abort_log=nullptr;
static unsigned spr_wait=0,tile_wait=0;
static bool previous_spr_req=false,previous_tile_req=false;
static uint64_t aborts=0;
static unsigned previous_render_line=0;

static void flush_line(){if(line_log)(*line_log)<<line_stats.line<<'\t'<<(int(line_stats.line)-16)<<'\t'<<line_stats.depth<<'\t'<<line_stats.reserved<<'\t'<<line_stats.rgb<<'\t'<<line_stats.pcm_wait<<'\t'<<line_stats.overrun<<'\t'<<line_stats.busy<<'\t'<<line_stats.tile_cycles<<'\t'<<line_stats.sprite_cycles<<'\t'<<line_stats.rgb_cycles<<'\t'<<line_stats.deadlines<<'\t'<<line_stats.requests<<'\t'<<line_stats.acks<<'\t'<<line_stats.stalls<<'\t'<<line_stats.spr_reqs<<'\t'<<line_stats.spr_acks<<'\t'<<line_stats.spr_wait_cycles<<'\t'<<line_stats.spr_max_wait<<'\t'<<line_stats.tile_reqs<<'\t'<<line_stats.tile_acks<<'\t'<<line_stats.tile_wait_cycles<<'\t'<<line_stats.tile_max_wait<<'\t'<<line_stats.row_wait<<'\t'<<line_stats.order_wait<<'\t'<<line_stats.compositor_mask<<'\n';}

static unsigned video_phase=1;
static uint64_t halfclock=0,pocket_compared=0,analog_compared=0;
static std::vector<uint32_t>* pocket_pixels=nullptr;
static std::vector<uint32_t>* analog_pixels=nullptr;
static void halfstep(){
 d->clk=(halfclock%2)==0;
 unsigned pos=(halfclock+video_phase)%24;
 if(pos==0)d->clk_vid=1;if(pos==12)d->clk_vid=0;
 d->eval();
 if(pocket_pixels&&pos==0&&d->pocket_de)pocket_pixels->push_back(d->pocket_rgb);
 if(analog_pixels&&d->clk&&d->analog_capture&&!(d->analog_pixel&3))analog_pixels->push_back(d->analog_pixel>>4);
 halfclock++;
}
static void fail(const char*w,uint64_t got,uint64_t exp){if(errors<24)printf("ERROR %s got=%llx expected=%llx cycle=%llu raster=%u:%u x=%u y=%u\n",w,(unsigned long long)got,(unsigned long long)exp,(unsigned long long)clocks,d->vcount,d->hcount,d->scan_x,d->scan_y);errors++;}
static void tick(unsigned n=1){while(n--){
 d->audio_cen=0;if(!audio_manual_write)d->audio_wr=0;
 if(audio_running){
  uint64_t sample=audio_clock/2000;unsigned slot=audio_clock%2000;
  if(sample>=audio_schedule.size()){fail("Audio original event window exhausted",sample,audio_schedule.size()-1);audio_running=false;}
  else{
   const auto &events=audio_schedule[sample];
   if(slot<events.size()*2 && !(slot&1)){
    const auto &e=events[slot/2];d->audio_chip=e.chip;d->audio_addr=e.address;d->audio_data=e.value;d->audio_wr=1;audio_events++;
   }
   if(slot==events.size()*2){d->audio_cen=1;audio_samples++;audio_late+=bool(d->audio_busy);}
  }
 }

 if(traffic&&!d->reset&&!d->vid_reset){
  if(!d->c_preq&&clocks%193==0){d->c_preq=1;d->c_paddr=(clocks/193)&2047;}

  if(!d->c_treq&&clocks%389==0){d->c_treq=1;d->c_taddr=(clocks/389)&0x7ffff;}
  if(!d->c_sreq&&clocks%521==0){d->c_sreq=1;d->c_saddr=(clocks/521)&0x7ffff;}
  if(!d->c_vreq&&clocks%263==0){d->c_vreq=1;d->c_vaddr=(clocks/263)&65535;}
 }
 bool ts=d->tile_start,ss=d->sprite_start,tb=d->tile_busy,sb=d->sprite_busy,rb=d->compositor_busy;
 bool take=d->fragment_valid&&d->fragment_ready;
 stalls+=d->fragment_valid&&!d->fragment_ready;accepted+=take;
 if(audio_running){
  if(line_log&&line_stats.line!=d->vcount){flush_line();line_stats={};line_stats.line=d->vcount;}
  bool spr_req=d->diag_spr_req,tile_req=d->diag_tile_req;
  line_stats.spr_reqs+=spr_req&&!previous_spr_req;
  line_stats.tile_reqs+=tile_req&&!previous_tile_req;
  previous_spr_req=spr_req;previous_tile_req=tile_req;
  line_stats.spr_acks+=bool(d->diag_spr_ack);line_stats.tile_acks+=bool(d->diag_tile_ack);
  spr_wait=spr_req&&!d->diag_spr_ack?spr_wait+1:0;
  tile_wait=tile_req&&!d->diag_tile_ack?tile_wait+1:0;
  line_stats.spr_wait_cycles+=spr_req&&!d->diag_spr_ack;
  line_stats.tile_wait_cycles+=tile_req&&!d->diag_tile_ack;
  line_stats.spr_max_wait=std::max(line_stats.spr_max_wait,spr_wait);
  line_stats.tile_max_wait=std::max(line_stats.tile_max_wait,tile_wait);
  line_stats.row_wait+=bool(d->diag_row_wait);line_stats.order_wait+=bool(d->diag_order_wait);
  line_stats.compositor_mask|=1u<<d->diag_compositor_state;
  if(ss&&(sb||rb)){
   if(abort_log)(*abort_log)<<clocks<<'\t'<<unsigned(d->vcount)<<'\t'<<unsigned(d->hcount)<<'\t'<<previous_render_line<<'\t'<<unsigned(d->diag_render_line)<<'\t'<<unsigned(d->diag_draw_state)<<'\t'<<unsigned(d->diag_object_index)<<'\t'<<unsigned(d->diag_entry)<<'\t'<<unsigned(d->diag_compositor_state)<<'\t'<<sb<<'\t'<<rb<<'\t'<<unsigned(d->overrun_src)<<'\t'<<unsigned(d->queue_depth)<<'\t'<<unsigned(d->queue_reserved)<<'\t'<<unsigned(d->rgb_pending)<<'\t'<<spr_wait<<'\t'<<tile_wait<<'\n';
   if(!aborts)printf("FIRST_ABORT cycle=%llu native_line=%u h=%u drawstate=%u obj_i=%u entry=%u compositorstate=%u spritebusy=%u rgbbusy=%u overrunsrc=%u\n",(unsigned long long)clocks,d->vcount,d->hcount,d->diag_draw_state,d->diag_object_index,d->diag_entry,d->diag_compositor_state,sb,rb,d->overrun_src);
   aborts++;
  }
  if(ss)previous_render_line=d->diag_render_line;
  line_stats.depth=std::max(line_stats.depth,unsigned(d->queue_depth));
  line_stats.reserved=std::max(line_stats.reserved,unsigned(d->queue_reserved));
  line_stats.rgb=std::max(line_stats.rgb,unsigned(d->rgb_pending));
  line_stats.stalls+=d->fragment_valid&&!d->fragment_ready;
  line_stats.tile_cycles+=d->tile_busy;line_stats.sprite_cycles+=d->sprite_busy;line_stats.rgb_cycles+=d->compositor_busy;
  line_stats.busy|=unsigned(d->tile_busy)|(unsigned(d->sprite_busy)<<1)|(unsigned(d->compositor_busy)<<2);
  if(ss&&d->overrun){observed_overruns++;line_stats.overrun|=d->overrun_src;line_stats.deadlines++;deadline_errors++;fail("Native overrun source",d->overrun_src,0);}
  unsigned chipreq=d->audio_chip_req;
  for(unsigned chip=0;chip<2;chip++){
   audio_chip_requests[chip]+=bool((chipreq&~previous_chip_req)&(1u<<chip));
   audio_chip_active[chip]+=bool(d->audio_chip_nonzero&(1u<<chip));
  }
  previous_chip_req=chipreq;
  audio_active_cycles+=bool(d->audio_chip_nonzero);
  if(!d->audio_req){
   if(pcm_pending){fail("PCM request cancelled before real ACK",pcm_address,0);pcm_pending=false;}
   pcm_held=false;
  }else if(!pcm_pending&&!pcm_held){pcm_pending=true;pcm_address=d->audio_rom_addr;pcm_wait=0;audio_requests++;line_stats.requests++;}
  if(pcm_pending){
   pcm_wait++;max_pcm_wait=std::max(max_pcm_wait,pcm_wait);line_stats.pcm_wait=std::max(line_stats.pcm_wait,pcm_wait);
   if(d->audio_rom_addr!=pcm_address)fail("PCM held address",d->audio_rom_addr,pcm_address);
  }
  if(d->audio_ack){
   if(!pcm_pending)fail("PCM ACK without outstanding request",d->audio_rom_addr,0);
   else{
    audio_acks++;line_stats.acks++;
    if(pcm_address>=pcm_original.size())fail("PCM address bound",pcm_address,pcm_original.size()-1);
    else if(d->audio_q!=pcm_original[pcm_address])fail("PCM real memory byte",d->audio_q,pcm_original[pcm_address]);
    else audio_bytes_correct++;
    audio_high_acks+=pcm_address>=4096;pcm_pending=false;pcm_held=true;
   }
  }
 }
 halfstep();halfstep();clocks++;if(audio_running)audio_clock++;

 if(ts){if(tstart&&tb){line_stats.deadlines++;deadline_errors++;fail("Tile not idle at native next start",1,0);}tstart=clocks;}
 if(ss){if(sstart&&(sb||rb)){line_stats.deadlines++;deadline_errors++;fail("Sprite/RGB not idle at native next start",1,0);}sstart=clocks;}
 if(tb&&!d->tile_busy&&tstart){unsigned v=clocks-tstart;worst_tile=std::max(worst_tile,v);if(v>=6144){line_stats.deadlines++;deadline_errors++;fail("Tile6144",v,6143);}}
 if(sb&&!d->sprite_busy&&sstart){unsigned v=clocks-sstart;worst_sprite=std::max(worst_sprite,v);if(v>=6144){line_stats.deadlines++;deadline_errors++;fail("Sprite6144",v,6143);}}
 if(rb&&!d->compositor_busy&&sstart){unsigned v=clocks-sstart;worst_rgb=std::max(worst_rgb,v);if(v>=6144){line_stats.deadlines++;deadline_errors++;fail("RGB6144",v,6143);}}
 if(d->c_tack){d->c_treq=0;cpu_acks[0]++;}if(d->c_sack){d->c_sreq=0;cpu_acks[1]++;}
 if(d->c_vack){d->c_vreq=0;cpu_acks[2]++;}if(d->c_pack){d->c_preq=0;cpu_acks[3]++;}
 mem_acks[0]+=d->observed_tack;mem_acks[1]+=d->observed_sack;mem_acks[2]+=d->observed_vack;
}}
static std::vector<uint8_t> bytes(const std::string&p){std::ifstream f(p,std::ios::binary);if(!f){fprintf(stderr,"Cannot read %s\n",p.c_str());exit(2);}return{std::istreambuf_iterator<char>(f),{}};}
struct State{std::map<std::string,std::vector<unsigned>> f;std::vector<unsigned> vram[17];};
static State load(const std::string&p){std::ifstream f(p);if(!f)exit(2);State s;std::string line;while(std::getline(f,line)){std::istringstream r(line);std::string k,v;if(!(r>>k)||k[0]=='#')continue;int pg=-1;if(k=="VRAM")r>>pg;std::vector<unsigned> data;while(r>>v)data.push_back(std::stoul(v,nullptr,16));if(pg>=0&&pg<17)s.vram[pg]=data;else s.f[k]=data;}return s;}
static std::vector<uint32_t> expected(const std::string&p){auto b=bytes(p);if(b.size()!=384*224*4){fprintf(stderr,"Bad RGB length\n");exit(2);}std::vector<uint32_t> out;for(unsigned i=0;i<b.size();i+=4)out.push_back(b[i]|(b[i+1]<<8)|(b[i+2]<<16)|(unsigned(b[i+3])<<24));return out;}
// Original MAME write order and seed; intra-frame positions match play11's
// declared public-port cold replay, not original hidden phase or Z80 timing.
static void prepare_audio(){
 struct E{unsigned frame,chip,address,value,line;};std::vector<E> all;
 std::ifstream f(audio_dir+"/events.tsv");std::string row;while(getline(f,row)){
  if(row.empty()||row[0]=='#')continue;std::istringstream q(row);E e;
  q>>e.frame>>e.chip>>std::hex>>e.address>>e.value>>std::dec>>e.line;
  if(!q||e.frame<2701||e.frame>2720||e.chip<1||e.chip>2)exit(2);all.push_back(e);
 }
 if(all.empty())exit(2);audio_schedule.assign(20*811,{});
 for(unsigned frame=2701;frame<=2720;frame++){
  std::vector<E> current;for(auto e:all)if(e.frame==frame)current.push_back(e);
  unsigned index=0;for(unsigned sample=0;sample<811;sample++){
   auto &dst=audio_schedule[(frame-2701)*811+sample];
   while(index<current.size()&&index*811/current.size()<=sample){auto e=current[index++];dst.push_back({e.chip-1,e.address,e.value});}
   if(dst.size()*2>=2000)exit(2);
  }
 }
}
static void audio_write(unsigned chip,unsigned a,unsigned v){
 d->audio_chip=chip;d->audio_addr=a;d->audio_data=v;d->audio_wr=1;audio_manual_write=true;tick();
 d->audio_wr=0;tick();audio_manual_write=false;
}
static void seed_audio(){
 audio_running=false;d->audio_wr=0;d->audio_cen=0;d->audio_reset=1;tick(10);d->audio_reset=0;tick(10);
 for(unsigned chip=0;chip<2;chip++){
  char name[512];snprintf(name,sizeof(name),"%s/f02700-k539_%u_regs.bin",audio_dir.c_str(),chip+1);auto regs=bytes(name);if(regs.size()!=560)exit(2);
  audio_write(chip,0x22e,0x80);for(unsigned a=0;a<0x14000;a++)audio_write(chip,0x22d,0);
  for(unsigned a=0;a<560;a++)if(a!=0x214&&a!=0x215&&a!=0x22c&&a!=0x22d&&a!=0x22e&&a!=0x22f)audio_write(chip,a,regs[a]);
  audio_write(chip,0x22e,regs[0x22e]);audio_write(chip,0x214,regs[0x22c]);audio_write(chip,0x22f,regs[0x22f]);
 }
 audio_clock=0;pcm_pending=pcm_held=false;previous_chip_req=0;
}
static void build(){d->reset=0;tick(4);d->build=1;tick();d->build=0;unsigned n=0;while(!d->build_done&&n++<245760)tick();if(!d->build_done)fail("List build vblank deadline",n,245760);if(d->overflow)fail("Object overflow",1,0);printf("BUILD objects=%u clocks=%u\n",d->object_count,n);}
static void setup(const State&s){
 traffic=false;d->vid_reset=1;d->reset=1;d->build=0;d->vsetup_mode=1;d->c_treq=d->c_sreq=d->c_vreq=d->c_preq=0;tick(100);tstart=sstart=0;
 const char*keys[]={"K56REGS","K55REGS","K38REGS","K46REGS","K47REGS","SPRITERAM","PALETTE"};unsigned sizes[]={32,48,16,8,8,2048,4096};
 for(unsigned b=0;b<7;b++){auto &v=s.f.at(keys[b]);if(v.size()<sizes[b]){fprintf(stderr,"State %s length%zu !=%u\n",keys[b],v.size(),sizes[b]);exit(2);}for(unsigned a=0;a<sizes[b];a++){d->setup_we=1;d->setup_bank=b;d->setup_addr=a;d->setup_data=v[a];tick();}}d->setup_we=0;
 for(unsigned pg=0;pg<16;pg++){if(s.vram[pg].size()!=4096)exit(2);for(unsigned a=0;a<4096;a++){d->vsetup_req=1;d->vsetup_addr=pg*4096+a;d->vsetup_data=s.vram[pg][a];unsigned n=0;while(!d->vsetup_ack&&n++<200)tick();if(!d->vsetup_ack)fail("VRAM setup ACK",0,1);d->vsetup_req=0;tick(2);}}
 d->vsetup_mode=0;tick(100);build();
}
static void frame(const std::vector<uint32_t>&oracle,const std::string&tag,bool contend,const std::string&outdir){
 std::vector<uint32_t> out(384*224,0xffffffff),deout,pocketout,analogout;std::vector<unsigned> seen(384*224,0);uint64_t prior=errors;unsigned deindex=0;
 std::ofstream per_line(outdir+"/"+tag+".lines.tsv"),per_abort(outdir+"/"+tag+".aborts.tsv");
 per_abort<<"cycle\tnative_line\thcount\taborted_target_line\tnext_target_line\tdraw_state_preedge\tobject_index_preedge\tentry_preedge\tcompositor_state_preedge\tsprite_busy\trgb_busy\toverrun_src\tqueue_depth\tqueue_reserved\trgb_pending\tspr_wait\ttile_wait\n";
 abort_log=&per_abort;spr_wait=tile_wait=0;previous_spr_req=previous_tile_req=false;previous_render_line=0;
 std::vector<unsigned> pixel_errors(224,0),first_bad_x(224,384),first_got(224,0),first_expected(224,0);

 per_line<<"native_line\tvisible_y\tqueue_depth_max\tqueue_reserved_max\trgb_pending_max\tpcm_wait_max\toverrun_src\trenderer_busy_seen\ttile_busy_cycles\tsprite_busy_cycles\trgb_busy_cycles\tdeadline_failures\tpcm_requests\tpcm_acks\tfragment_stalls\tspr_req_edges\tspr_acks\tspr_wait_cycles\tspr_max_wait\ttile_req_edges\ttile_acks\ttile_wait_cycles\ttile_max_wait\tD_ROWW_cycles\torder_wait_cycles\tcompositor_state_mask\n";
 line_log=&per_line;line_stats={};line_stats.line=d->vcount;
 uint64_t req0=audio_requests,ack0=audio_acks,byte0=audio_bytes_correct,high0=audio_high_acks,active0=audio_active_cycles;
 uint64_t chipreq0[2]={audio_chip_requests[0],audio_chip_requests[1]},chipactive0[2]={audio_chip_active[0],audio_chip_active[1]};
 audio_running=true;
 pocket_pixels=&pocketout;analog_pixels=&analogout;
 traffic=contend;d->vid_reset=0;unsigned n=0;
 while(n++<1700000){tick();
  if(d->sample_valid){unsigned x=d->scan_x,y=d->scan_y;if(x>=384||y>=224){fail("Visible coordinate bounds",(y<<16)|x,383);continue;}unsigned i=y*384+x;out[i]=d->rgb;seen[i]++;compared++;if(d->rgb!=oracle[i]){pixel_errors[y]++;if(first_bad_x[y]==384){first_bad_x[y]=x;first_got[y]=d->rgb;first_expected[y]=oracle[i];}fail("Registered consumer RGB",d->rgb,oracle[i]);}}
  if(d->cen_pix&&d->de){deout.push_back(d->rgb);if(deindex<oracle.size()){de_compared++;de_errors+=d->rgb!=oracle[deindex];}deindex++;}
  if(d->vcount>=242)break;
 }
 pocket_pixels=nullptr;analog_pixels=nullptr;
 flush_line();line_log=nullptr;abort_log=nullptr;
 std::ofstream per_pixel(outdir+"/"+tag+".pixels.tsv");per_pixel<<"visible_y\tmismatch_count\tfirst_bad_x\tfirst_got_rgb\tfirst_expected_rgb\n";
 for(unsigned y=0;y<224;y++)per_pixel<<y<<'\t'<<pixel_errors[y]<<'\t'<<first_bad_x[y]<<'\t'<<first_got[y]<<'\t'<<first_expected[y]<<'\n';
 audio_running=false;d->audio_wr=0;d->audio_cen=0;
 if(audio_requests==req0||audio_acks==ack0||audio_bytes_correct==byte0||audio_high_acks==high0||audio_active_cycles==active0)fail("Exercised real PCM beyond4KiB/nonzero",audio_acks-ack0,1);
 for(unsigned chip=0;chip<2;chip++)if(audio_chip_requests[chip]==chipreq0[chip]||audio_chip_active[chip]==chipactive0[chip])fail("Both original PCM chips exercised",chip,1);
 printf("PCM_SCENE %s requests=%llu acks=%llu correct=%llu above4KiB=%llu active=%llu maxwait=%u sample_late=%llu\n",tag.c_str(),(unsigned long long)(audio_requests-req0),(unsigned long long)(audio_acks-ack0),(unsigned long long)(audio_bytes_correct-byte0),(unsigned long long)(audio_high_acks-high0),(unsigned long long)(audio_active_cycles-active0),max_pcm_wait,(unsigned long long)audio_late);

 traffic=false;for(auto count:seen)if(count!=1)fail("Pixel sampled exactly once",count,1);
 if(deindex!=384*224)fail("Native DE pixel count",deindex,384*224);
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
 printf("SCENE %s contention=%u pixels=%u errors=%llu tile=%u sprite=%u rgb=%u de_mismatches_total=%llu\n",tag.c_str(),contend,384*224,(unsigned long long)(errors-prior),worst_tile,worst_sprite,worst_rgb,(unsigned long long)de_errors);fflush(stdout);scenes++;
 d->vid_reset=1;d->reset=1;tick(100);tstart=sstart=0;
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=7){fprintf(stderr,"usage: vio03_band originalROM cases.tsv outdir audio-seed-dir phasesCSV quiet|reads|both\n");return 2;}auto rom=bytes(argv[1]);if(rom.size()!=0x1240080)exit(2);
 std::vector<unsigned> phases;std::istringstream phase_input(argv[5]);std::string part;
 while(std::getline(phase_input,part,',')){if(part.empty()||part.find_first_not_of("0123456789")!=std::string::npos)return 2;unsigned v=std::stoul(part);if(v>=24||std::find(phases.begin(),phases.end(),v)!=phases.end())return 2;phases.push_back(v);}
 if(phases.empty())return 2;
 std::string mode=argv[6];if(mode!="quiet"&&mode!="reads"&&mode!="both")return 2;
 std::vector<bool> modes;if(mode!="reads")modes.push_back(false);if(mode!="quiet")modes.push_back(true);
 audio_dir=argv[4];prepare_audio();pcm_original.assign(rom.begin()+0x640000,rom.begin()+0xa40000);
 d=new Vtb_m3_vio03_band;d->audio_reset=1;d->audio_cen=d->audio_wr=0;d->reset=d->vid_reset=d->init=1;tick(8);d->init=0;unsigned n=0;while(!d->ready&&n++<100000)tick();if(!d->ready){fail("Memory ready",0,1);return 1;}
 // Full original graphics and4MiB PCM; the4096byte program prefix is used
 // only by the optional synthetic nonPCM read contender.
 const unsigned base[]={0,0x240000,0xa40000,0x640000},len[]={4096,0x400000,0x800000,0x400000};
 for(unsigned r=0;r<4;r++)for(unsigned i=0;i<len[r];i++){d->dl_we=1;d->dl_addr=base[r]+i;d->dl_data=rom[base[r]+i];tick();d->dl_we=0;tick(7);}tick(500);
 std::ifstream cases(argv[2]);std::string row;while(std::getline(cases,row)){if(row.empty())continue;std::istringstream r(row);std::string sp,op,tag;getline(r,sp,'\t');getline(r,op,'\t');getline(r,tag,'\t');auto s=load(sp);auto oracle=expected(op);for(unsigned phase:phases){video_phase=phase;auto suffix="-phase"+std::to_string(phase);for(bool contend:modes){setup(s);seed_audio();frame(oracle,tag+suffix+(contend?"-pcm-and-reads":"-pcm"),contend,argv[3]);}}}
 if(!scenes)fail("Zero executed scenes",0,1);
 printf("DIAG_JSON {\"sprite_rgb_aborts\":%llu,\"passive_only\":true}\n",(unsigned long long)aborts);
 printf("PCM_JSON {\"requests\":%llu,\"acks\":%llu,\"bytes_correct\":%llu,\"acks_above_4KiB\":%llu,\"active_audio_cycles\":%llu,\"chip_requests\":[%llu,%llu],\"chip_active_cycles\":[%llu,%llu],\"max_wait_clocks\":%u,\"sample_busy_at_cen\":%llu,\"original_events_executed\":%llu,\"sample_ce\":%llu,\"native_overruns\":%llu}\n",(unsigned long long)audio_requests,(unsigned long long)audio_acks,(unsigned long long)audio_bytes_correct,(unsigned long long)audio_high_acks,(unsigned long long)audio_active_cycles,(unsigned long long)audio_chip_requests[0],(unsigned long long)audio_chip_requests[1],(unsigned long long)audio_chip_active[0],(unsigned long long)audio_chip_active[1],max_pcm_wait,(unsigned long long)audio_late,(unsigned long long)audio_events,(unsigned long long)audio_samples,(unsigned long long)observed_overruns);

 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"scenes\":%u,\"oracle_pixels_compared\":%llu,\"pocket_pixels_compared\":%llu,\"analogizer_source_pixels_compared\":%llu,\"native_de_pixels_compared\":%llu,\"native_de_rgb_mismatches\":%llu,\"deadline_failures\":%u,\"worst_tile_clocks\":%u,\"worst_sprite_clocks\":%u,\"worst_compositor_clocks\":%u,\"accepted_fragments\":%llu,\"backpressure_cycles\":%llu,\"synthetic_read_acks\":[%llu,%llu,%llu,%llu],\"memory_acks\":[%llu,%llu,%llu],\"cycles\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,scenes,(unsigned long long)compared,(unsigned long long)pocket_compared,(unsigned long long)analog_compared,(unsigned long long)de_compared,(unsigned long long)de_errors,deadline_errors,worst_tile,worst_sprite,worst_rgb,(unsigned long long)accepted,(unsigned long long)stalls,(unsigned long long)cpu_acks[0],(unsigned long long)cpu_acks[1],(unsigned long long)cpu_acks[2],(unsigned long long)cpu_acks[3],(unsigned long long)mem_acks[0],(unsigned long long)mem_acks[1],(unsigned long long)mem_acks[2],(unsigned long long)clocks);
 printf("%s M3 real dualPCM + registered RGB + Pocket + Analogizer source capture (raw CEN diagnostic separate)\n",errors?"FAIL":"PASS");delete d;return errors?1:0;
}
