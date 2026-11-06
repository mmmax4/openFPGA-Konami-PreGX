#include "Vm3_vio15_tag_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
static Vm3_vio15_tag_top d;
static uint64_t checks=0,errors=0,clocks=0,begins=0,bytes=0,paired_edges=0;
static uint64_t idle_checks=0,held_checks=0,hold_patterns[8]={};
static unsigned full_original=0,full_crc_fault=0,prefix_cases=0,malformed=0,truncated=0,hold_windows=0;
static unsigned active_profile=0;
static void need(bool v,const char* what){checks++;if(!v){if(errors<24)printf("ERROR %s clock=%llu addr=%x WE=%u got=%x old=%x\n",what,(unsigned long long)clocks,unsigned(d.dl_addr),unsigned(d.dl_we),unsigned(d.observed[0]),unsigned(d.observed[1]));errors++;}}
static void pair(){need(d.observed[0]==d.observed[1],"all actual public outputs identical, no cycle masks");paired_edges++;}
static void tick(){d.clk=0;d.eval();pair();begins+=(d.observed[0]&16)!=0;d.clk=1;d.eval();pair();clocks++;}
static unsigned flags(){return d.observed[0]&15;}
static unsigned expected(unsigned p,bool identified,bool valid){return(p==2?1U:0U)|(p==1?2U:0U)|(identified?4U:0U)|(valid?8U:0U);}
static void idle(unsigned count){
 unsigned before=flags();d.dl_we=0;
 for(unsigned i=0;i<count;i++){
  // Address/data may vary with no strobe: identity and valid must hold.
  d.dl_addr=(i*137U)&0x1ffffff;d.dl_data=(i*29U)&255;tick();
  need(flags()==before&&!(d.observed[0]&16),"idle/host-reset hold keeps tag state and suppresses begin");idle_checks++;
 }
 if(count==256)hold_windows++;
}
static void byte(unsigned address,unsigned value,unsigned held=1){
 d.dl_we=0;tick();d.dl_addr=address;d.dl_data=value;d.dl_we=1;
 for(unsigned i=0;i<held;i++)tick();bytes++;hold_patterns[held-1]++;
}
static unsigned held(unsigned address,unsigned size){return address<256||address+8>=size?address%8+1:1;}
static std::vector<uint8_t> load(const char* path){std::ifstream f(path,std::ios::binary);need(bool(f),"original image opens read-only");return{std::istreambuf_iterator<char>(f),{}};}
static void prefix(const std::vector<uint8_t>& image,unsigned p,int kind=0){
 auto starts=begins;unsigned prior=active_profile;
 for(unsigned a=0;a<256;a++){
  unsigned at=kind==2&&a==20?21:a;
  unsigned value=image[a]^((kind==1&&a==23)?1U:0U);
  byte(at,value,a%8+1);
  if(a<255||kind)need(flags()==expected(prior,false,false),"unrecognized/incomplete prefix cannot change last profile or release valid");
 }
 need(begins==starts+1,"one start despite held prefix WE");
 if(kind){need(flags()==expected(prior,false,false),"bad CRC or ordered prefix rejected");malformed++;}
 else{active_profile=p;need(flags()==expected(p,true,false),"original byte255 identifies on exact accepted edge");idle(256);}
 prefix_cases++;
}
static void full(const std::vector<uint8_t>& image,unsigned p,bool fault=false){
 auto starts=begins;unsigned prior=active_profile;
 for(unsigned a=0;a<image.size();a++){
  unsigned value=image[a]^((fault&&a==0x1000)?1U:0U);
  byte(a,value,held(a,image.size()));
  if(a<255)need(flags()==expected(prior,false,false),"new byte0 immediately invalidates previous image and retains last profile");
  else if(a==255){active_profile=p;need(flags()==expected(p,true,false),"correct profile known on original prefix edge");}
  else if(a+1<image.size())need(flags()==expected(p,true,false),"ordered body never raises valid early");
  else need(flags()==expected(p,true,!fault),"last original byte complete CRC acceptance or transmission fault rejection");
 }
 need(begins==starts+1,"full stream has exactly one begin pulse");
 if(fault)full_crc_fault++;else full_original++;
 idle(256);
 // Held WE is not another byte even if unconsumed address/data change.
 byte(0,image[0],8);need(flags()==expected(p,false,false),"restart clears validity on original first edge");
 unsigned before=flags();
 for(unsigned n=0;n<8;n++){d.dl_we=1;d.dl_addr=n?255:0;d.dl_data=image[255-n];tick();need(flags()==before&&!(d.observed[0]&16),"held-high strobe cannot create another byte or image-start");held_checks++;}
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=4)return 2;
 d.clk=0;d.dl_we=0;d.dl_addr=0;d.dl_data=0;d.eval();pair();
 need(flags()==0&&!(d.observed[0]&16),"configuration powerup keeps all profile/identity/valid outputs clear");
 auto gaia=load(argv[1]),mystic=load(argv[2]),violent=load(argv[3]);
 need(gaia.size()==0x1360080&&mystic.size()==0xdc0080&&violent.size()==0x1240080,"three immutable original image lengths");if(errors)return 2;
 idle(256);
 byte(255,gaia[255],8);need(flags()==0,"unstarted address255 cannot identify");malformed++;
 prefix(mystic,1,1);prefix(gaia,0,2);
 prefix(gaia,0);byte(unsigned(gaia.size()-1),gaia.back(),8);need(flags()==expected(0,true,false),"valid prefix then skipped body/last byte remains invalid");truncated++;
 full(gaia,0);full(mystic,1);full(violent,2);full(violent,2,true);
 // Recovery and reverse swaps use only256 original bytes: no repeated full
 // positive image replay. All these profiles stay under the valid/reset hold.
 prefix(mystic,1);prefix(violent,2);prefix(gaia,0);
 // A new byte0 interrupts an existing prefix and preserves previous profile
 // until a new complete prefix, even when the image upload then stops.
 byte(0,mystic[0],8);need(flags()==expected(0,false,false),"new image clears identified/valid while preserving last decoded profile");idle(256);truncated++;
 for(unsigned i=0;i<8;i++)need(hold_patterns[i]>0,"all held-WE phases1..8 exercised");
 need(full_original==3&&full_crc_fault==1&&prefix_cases==6&&malformed==3&&truncated==2,"bounded full-image/protocol matrix complete");
 need(hold_windows==10&&held_checks==32,"configuration/reset hold and held-strobe matrix complete");
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"cycles\":%llu,\"paired_observations\":%llu,\"bytes_presented\":%llu,\"begin_pulses\":%llu,\"original_full_images\":%u,\"bad_crc_full_images\":%u,\"prefix_cases\":%u,\"malformed_cases\":%u,\"truncated_cases\":%u,\"hold256_windows\":%u,\"held_high_ignored\":%llu,\"idle_checks\":%llu,\"held_we_patterns\":[%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu],\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,(unsigned long long)clocks,(unsigned long long)paired_edges,(unsigned long long)bytes,(unsigned long long)begins,full_original,full_crc_fault,prefix_cases,malformed,truncated,hold_windows,(unsigned long long)held_checks,(unsigned long long)idle_checks,(unsigned long long)hold_patterns[0],(unsigned long long)hold_patterns[1],(unsigned long long)hold_patterns[2],(unsigned long long)hold_patterns[3],(unsigned long long)hold_patterns[4],(unsigned long long)hold_patterns[5],(unsigned long long)hold_patterns[6],(unsigned long long)hold_patterns[7]);
 return errors?1:0;
}
