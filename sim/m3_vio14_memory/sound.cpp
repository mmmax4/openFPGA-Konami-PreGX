// Actual paired TV80 + sound wrappers + dual K539. Original programs untouched.
// Actual input ports are sampled BEFORE the consuming clock, including reset.
#include "Vm3_vio14_sound_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>
static void need(bool ok,const char*s){if(!ok)throw std::runtime_error(s);}
static std::vector<uint8_t>load(const char*p){std::ifstream f(p,std::ios::binary);need(bool(f),"input open");return {std::istreambuf_iterator<char>(f),{}};}
struct Memory{bool active=false,ack=false;unsigned addr=0,left=0,reads=0;
 void tick(bool req,unsigned a,const std::vector<uint8_t>&bytes,CData&q,CData&outack,unsigned delay){
  bool was=ack;ack=false;
  if(active){need(req&&a==addr,"public ROM request/address changed before ACK");if(!--left){need(addr<bytes.size(),"original ROM address range");q=bytes[addr];ack=true;active=false;reads++;}}
  else if(req&&!was){active=true;addr=a;left=delay;}outack=ack;
 }
};
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=9)return 2;
 unsigned profile=std::atoi(argv[1]),mode=std::atoi(argv[4]),limit=std::atoi(argv[7]);int reset_phase=std::atoi(argv[5]);
 unsigned cycles=0,checks=0,writes=0,chip_writes[2]={},port_reads[2]={},samples=0,audible=0,cen_edges=0,irq_events=0,resets=0;
 unsigned reset_checks=0,preedge_checks=0,reset_write_mismatches=0,retained_witnesses=0,readback_witnesses=0;
 unsigned bad_cycle=0,bad_chip=0,bad_old_write=0,bad_new_write=0,bad_old_address=0,bad_new_address=0,bad_old_data=0,bad_new_data=0;
 unsigned retained_old[2]={},retained_new[2]={};
 try{
  auto program=load(argv[2]),pcm=load(argv[3]);need(program.size()==0x40000&&pcm.size()==0x400000,"actual program/PCM lengths");
  std::vector<std::pair<unsigned,unsigned>>expected;std::ifstream ef(argv[6]);unsigned a,v;while(ef>>std::hex>>a>>v)expected.emplace_back(a,v);
  if(mode)need(expected.size()==58&&expected[0].first==0xc2f0&&expected[1].first==0xc2f1&&expected[0].second!=0&&expected[0].second==expected[1].second,"58 ordinary/recovery witnesses and original nonzero retained seed");
  Vm3_vio14_sound_top d;Memory rom[2],sample[2];std::ofstream trace(argv[8]);need(bool(trace),"trace open");
  d.profile=profile;d.reset=1;d.pause=0;d.pix_sync=0;d.irq_pulse=0;d.main_wr=0;d.main_off=6;d.main_data=0xa5;d.rom_ack=d.pcm_ack=0;
  bool completed=false,reset_pending=false,reset_done=reset_phase<0,raw_prev=false,irq_prev=false,warm_command=false;
  int phase_count=0;unsigned reset_left=256,complete_at=0,expected_index=mode?2:0;std::array<uint64_t,8>previous{};
  for(cycles=0;cycles<limit;cycles++){
   d.main_wr=0;
   if(reset_left){d.reset=1;reset_left--;}else{d.reset=0;if(warm_command){d.main_wr=1;warm_command=false;}}
   d.pause=(!mode)&&((cycles>=4000&&cycles<4048)||(cycles>=8000&&cycles<8051));d.irq_pulse=mode&&completed&&cycles==complete_at+4096;
   d.clk=0;d.eval(); // TV80 async reset settles A/data before port sampling.
   if(d.reset){for(unsigned i=0;i<2;i++){rom[i]=Memory{};sample[i]=Memory{};}d.rom_ack=d.pcm_ack=0;}
   else for(unsigned i=0;i<2;i++){
    CData ar=0,ap=0;rom[i].tick((d.rom_req>>i)&1,d.rom_addr[i],program,d.rom_q[i],ar,12+(rom[i].reads%9));sample[i].tick((d.pcm_req>>i)&1,d.pcm_addr[i],pcm,d.pcm_q[i],ap,6+(sample[i].reads*13)%75);
    d.rom_ack=(d.rom_ack&~(1u<<i))|(unsigned(ar)<<i);d.pcm_ack=(d.pcm_ack&~(1u<<i))|(unsigned(ap)<<i);
   }
   d.eval();
   unsigned pre_wr=d.chip_wr,pre_rd=d.chip_rd;std::array<unsigned,4>pre_addr{},pre_data{};
   for(unsigned c=0;c<4;c++){pre_addr[c]=d.chip_addr[c];pre_data[c]=d.chip_wdata[c];}
   bool sample_edge=d.cen_48k,raw_reset=d.reset;
   d.clk=1;d.eval(); // Actual K539 consumes the captured pre-edge port values.
   for(unsigned c=0;c<2;c++){
    preedge_checks++;bool oldwr=(pre_wr>>c)&1,newwr=(pre_wr>>(c+2))&1;
    bool mismatch=oldwr!=newwr||((oldwr||newwr)&&(pre_addr[c]!=pre_addr[c+2]||pre_data[c]!=pre_data[c+2]));
    if(raw_reset){
     reset_checks++;
     if(mismatch){
      reset_write_mismatches++;if(reset_write_mismatches==1){bad_cycle=cycles;bad_chip=c;bad_old_write=oldwr;bad_new_write=newwr;bad_old_address=pre_addr[c];bad_new_address=pre_addr[c+2];bad_old_data=pre_data[c];bad_new_data=pre_data[c+2];}
      trace<<"RESET_COMMIT_WRITE "<<cycles<<' '<<c<<' '<<oldwr<<' '<<newwr<<' '<<std::hex<<pre_addr[c]<<' '<<pre_addr[c+2]<<' '<<pre_data[c]<<' '<<pre_data[c+2]<<std::dec<<'\n';
     }
    }else need(!mismatch,"paired actual chip write at consuming edge");
    need(((pre_rd>>c)&1)==((pre_rd>>(c+2))&1),"paired actual read input including reset");
   }
   if(!d.reset){
    bool recovery_diagnostic=reset_write_mismatches&&retained_witnesses<2;
    checks++;need(d.rom_req==0||d.rom_req==3,"paired program request");need(d.pcm_req==0||d.pcm_req==3,"paired PCM request");need(d.rom_addr[0]==d.rom_addr[1]&&d.pcm_addr[0]==d.pcm_addr[1],"paired ROM address");
    need(d.dbg_wr==0||d.dbg_wr==3,"paired CPU write strobe");need(d.dbg_rd==0||d.dbg_rd==3,"paired CPU read level");need(d.dbg_wait==0||d.dbg_wait==3,"paired CPU wait");need(d.dbg_step==0||d.dbg_step==3,"paired CPU instruction edge");need(d.cpu_addr[0]==d.cpu_addr[1],"paired CPU address");
    if(!recovery_diagnostic){need(d.cpu_wdata[0]==d.cpu_wdata[1]&&d.cpu_rdata[0]==d.cpu_rdata[1],"paired actual CPU payload/readback");need(d.snd_l[0]==d.snd_l[1]&&d.snd_r[0]==d.snd_r[1],"paired PCM every clock");}
    need((d.chip_wr&3)==((d.chip_wr>>2)&3)&&(d.chip_rd&3)==((d.chip_rd>>2)&3)&&(d.chip_stall&3)==((d.chip_stall>>2)&3),"paired post-edge chip controls");
    for(unsigned c=0;c<2;c++){
     need(d.chip_addr[c]==d.chip_addr[c+2],"paired chip address");
     if(!recovery_diagnostic)need(d.chip_wdata[c]==d.chip_wdata[c+2]&&d.chip_rdata[c]==d.chip_rdata[c+2],"paired public chip data");
     if((d.chip_wr>>c)&1)chip_writes[c]++;
     if(((d.chip_rd>>c)&1)&&d.chip_addr[c]==0x22d)port_reads[c]++;
    }
    if(d.dbg_wr&1){
     writes++;
     if(mode&&d.cpu_addr[0]>=0xc200&&d.cpu_addr[0]<0xc300){
      need(expected_index<expected.size(),"unexpected synthetic witness store");auto e=expected[expected_index++];need(e.first==d.cpu_addr[0]&&e.second==d.cpu_wdata[0],"baseline actual CPU readback must match original bytes");readback_witnesses++;
      if(e.first==0xc2f0||e.first==0xc2f1){unsigned c=e.first-0xc2f0;retained_old[c]=d.cpu_wdata[0];retained_new[c]=d.cpu_wdata[1];retained_witnesses++;trace<<"RETAINED_CHANNEL "<<cycles<<' '<<c<<' '<<retained_old[c]<<' '<<retained_new[c]<<'\n';}
      if(!recovery_diagnostic)need(e.second==d.cpu_wdata[1],"candidate actual CPU readback must match original bytes");
     }
     if(mode&&d.cpu_addr[0]==0xcffe&&d.cpu_wdata[0]==0xa5&&!completed){completed=true;complete_at=cycles;}
    }
    if(reset_write_mismatches&&retained_witnesses==2){
     need(bad_old_write==0&&bad_new_write==1&&bad_new_address==0&&bad_new_data==0,"source counterexample actual strobe identity");need(retained_old[bad_chip]!=0&&retained_new[bad_chip]==0,"actual retained channel read proves corruption before reconfiguration");trace.close();
     printf("RESULT_JSON {\"passed\":false,\"reason\":\"SOUND_RESET_COMMIT_NATIVE_NEGATIVE\",\"profile\":%u,\"reset_phase\":%d,\"resets\":%u,\"checks\":%u,\"cycles\":%u,\"reset_write_mismatches\":%u,\"reset_preedge_checks\":%u,\"actual_consumer_edge_sample\":true,\"bad_cycle\":%u,\"bad_chip\":%u,\"baseline_write\":%u,\"candidate_write\":%u,\"candidate_address\":%u,\"candidate_data\":%u,\"retained_readback_witnesses\":%u,\"retained_old\":[%u,%u],\"retained_new\":[%u,%u],\"before_postreset_reconfiguration\":true,\"physical_verified\":false}\n",profile,reset_phase,resets,checks,cycles,reset_write_mismatches,reset_checks,bad_cycle,bad_chip,bad_old_write,bad_new_write,bad_new_address,bad_new_data,retained_witnesses,retained_old[0],retained_old[1],retained_new[0],retained_new[1]);return 1;
    }
    cen_edges+=bool(d.cen_8m);if(sample_edge){samples++;audible+=d.snd_l[0]!=0||d.snd_r[0]!=0;}bool irq=d.irq_ack&1;if(irq&&!irq_prev)irq_events++;irq_prev=irq;
    std::array<uint64_t,8>now={uint64_t(d.cpu_addr[0])|(uint64_t(d.cpu_wdata[0])<<16)|(uint64_t(d.cpu_rdata[0])<<24),uint64_t(d.dbg_wr)|(uint64_t(d.dbg_rd)<<2)|(uint64_t(d.dbg_wait)<<4)|(uint64_t(d.raw_wr)<<6)|(uint64_t(d.raw_rd)<<8)|(uint64_t(d.cen_8m)<<10)|(uint64_t(d.irq_ack)<<11),uint64_t(pre_wr)|(uint64_t(pre_rd)<<4)|(uint64_t(d.chip_stall)<<8),uint64_t(d.rom_req)|(uint64_t(d.rom_addr[0])<<2)|(uint64_t(d.rom_ack)<<24),uint64_t(d.pcm_req)|(uint64_t(d.pcm_addr[0])<<2)|(uint64_t(d.pcm_ack)<<24),uint64_t(d.snd_l[0])|(uint64_t(d.snd_r[0])<<16),uint64_t(d.chip_rdata[0])|(uint64_t(d.chip_rdata[1])<<8),uint64_t(d.chip_addr[0])};
    if(cycles==256||now!=previous){trace<<cycles;for(auto x:now)trace<<' '<<std::hex<<x<<std::dec;trace<<'\n';previous=now;}
    bool raw=(d.raw_wr&1)&&((d.cpu_addr[0]&0x3ff)==0x22d)&&(d.cpu_addr[0]>=0xe000&&d.cpu_addr[0]<0xe630);
    if(mode&&!reset_done&&raw&&!raw_prev&&!reset_pending){reset_pending=true;phase_count=0;}
    if(reset_pending&&phase_count++==reset_phase){reset_left=256;reset_pending=false;reset_done=true;resets++;expected_index=0;readback_witnesses=0;retained_witnesses=0;completed=false;warm_command=true;trace<<"RESET "<<cycles<<' '<<reset_phase<<'\n';}
    raw_prev=raw;if(completed&&cycles>=complete_at+128000)break;
   }
  }
  need(checks>1000&&cen_edges>100&&rom[0].reads>100,"nonzero actual TV80 execution");need(preedge_checks>0&&reset_checks>0&&reset_write_mismatches==0,"actual chip writes compared including reset");
  if(mode){need(completed&&expected_index==expected.size(),"synthetic readbacks and completion");need(readback_witnesses==unsigned(reset_phase<0?56:58)&&retained_witnesses==unsigned(reset_phase<0?0:2),"all ordinary/retained CPU witnesses");need(chip_writes[0]>20&&chip_writes[1]>20&&port_reads[0]>0&&port_reads[1]>0,"both chips");need(sample[0].reads>16&&samples>32&&audible>0,"actual original PCM audible");need(irq_events>0,"actual TV80 IRQ");need(reset_done&&resets==unsigned(reset_phase>=0),"requested reset phase occurred");}
  trace.close();printf("RESULT_JSON {\"passed\":true,\"profile\":%u,\"mode\":%u,\"reset_phase\":%d,\"resets\":%u,\"checks\":%u,\"cycles\":%u,\"CPU_writes\":%u,\"readback_witnesses\":%u,\"retained_readback_witnesses\":%u,\"reset_write_mismatches\":%u,\"reset_preedge_checks\":%u,\"chip_preedge_checks\":%u,\"chip_writes\":[%u,%u],\"port_read_clocks\":[%u,%u],\"PCM_reads\":%u,\"program_reads\":%u,\"samples\":%u,\"audible_samples\":%u,\"CEN_edges\":%u,\"IRQ_ack_events\":%u,\"physical_verified\":false}\n",profile,mode,reset_phase,resets,checks,cycles,writes,readback_witnesses,retained_witnesses,reset_write_mismatches,reset_checks,preedge_checks,chip_writes[0],chip_writes[1],port_reads[0],port_reads[1],sample[0].reads,rom[0].reads,samples,audible,cen_edges,irq_events);return 0;
 }catch(const std::exception&e){fprintf(stderr,"FAIL cycle%u %s\n",cycles,e.what());return 1;}
}
