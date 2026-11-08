// Original per-game EEPROM bytes; game setting writes use the real serial pins.
// Fresh DUT per game models a new RBF configuration, not an unsupported hot switch.
#include "Vtb_m4_controls.h"
#include "verilated.h"
#include <array>
#include <vector>
#include <fstream>
#include <iterator>
#include <cstdio>
#include <cstdlib>
#include <algorithm>
static Vtb_m4_controls*d;static unsigned errors=0,checks=0,serial_reads=0,serial_writes=0,save_rises=0;static bool oldreq=false;
static void eq(const char*s,unsigned a,unsigned b){checks++;if(a!=b){if(errors<15)printf("ERROR %s got=%x expected=%x\n",s,a,b);errors++;}}
static void tick(unsigned n=1){while(n--){d->clk=0;d->eval();d->clk=1;d->eval();if(d->save_request&&!oldreq)save_rises++;oldreq=d->save_request;}}
static unsigned pbyte(unsigned keys,unsigned dirs){unsigned v=255;for(unsigned bit=0;bit<4;bit++)if(dirs&(1u<<bit))v&=~(1u<<bit);if(keys&9)v&=~16u;if(keys&6)v&=~32u;if(keys&32)v&=~64u;if(keys&128)v&=~128u;return v;}
static bool selected(unsigned selector,unsigned keys){return selector>=1&&selector<=8&&(keys&(1u<<(selector-1)));}
static void input_test(){
 for(unsigned profile=0;profile<4;profile++)for(unsigned k=0;k<256;k++)for(unsigned dirs=0;dirs<16;dirs++)for(unsigned dips=0;dips<16;dips++){
  d->profile=profile;d->p1_keys=k;d->p2_keys=k^0xa5;d->p3_keys=k^0x39;d->p4_keys=k^0xc6;
  d->p1_dirs=dirs;d->p2_dirs=dirs^15;d->p3_dirs=dirs^5;d->p4_dirs=dirs^10;
  d->test_select=(k>>4)&15;d->service_select=k&15;d->test_manual=k&1;d->dips=dips<<9;d->eval();
  unsigned p1=pbyte(k,dirs),p2=pbyte(k^0xa5,dirs^15),p3=pbyte(k^0x39,dirs^5),p4=pbyte(k^0xc6,dirs^10);
  unsigned test=!(d->test_manual||selected(d->test_select,k)),service=!selected(d->service_select,k);
  unsigned base=profile==1?0xe3:0xe7; // low fixed bits + high DIP default; Test added below
  if(profile==3)base=((dips&1)?16:0)|((dips&2)?0:32)|((dips&4)?0:64)|((dips&8)?0:128)|3|test*8;
  else if(profile==1)base=0xe3|test*4;
  else base=0xe3|test*8; // Violent/Gaia default SoundStereo/Common/2p/energyNo
  eq("EEPROM/Test/DIP board bits",d->in1,base);
  eq("P1 direction/action/start",d->in0_p1&255,p1);eq("P2 direction/action/start",d->p2,p2);
  if(profile==3){eq("Metam P1/P3 lane",d->mystic_p12,p1|(p3<<8));eq("Metam P2/P4 lane",d->mystic_p34,p2|(p4<<8));
   unsigned coins=0xe0|(service<<4)|((!(k&64))<<0)|((!((k^0xa5)&64))<<1)|((!((k^0x39)&64))<<2)|((!((k^0xc6)&64))<<3);eq("Metam four coin/service independent",d->mystic_in0,coins);eq("Metam pollbit2 zero",d->in1&4,0);
  }
 }
 d->p1_keys=d->p2_keys=d->p3_keys=d->p4_keys=0;d->p1_dirs=d->p2_dirs=d->p3_dirs=d->p4_dirs=0;d->dips=0;d->test_manual=0;d->test_select=d->service_select=0;d->profile=3;d->eval();eq("Metam defaultDIP",d->in1,0xeb);eq("Metam idle fourports1",d->mystic_p12,65535);eq("Metam idle fourports2",d->mystic_p34,65535);
}
static void load(const std::array<unsigned char,128>&nv){d->reset=1;tick(4);for(unsigned a=0;a<128;a++){d->ld_we=1;d->ld_addr=a;d->ld_wdata=nv[a];tick();}d->ld_we=0;tick(4);d->reset=0;tick(4);}
static void bit(unsigned v){d->di=v;d->sclk=0;tick(2);d->sclk=1;tick(2);d->sclk=0;tick(2);}
static void command(unsigned c){d->cs=0;d->sclk=0;tick(3);d->cs=1;tick(3);bit(1);for(int b=10;b>=0;b--)bit((c>>b)&1);}
static unsigned read(unsigned a){command((2u<<9)|a);eq("EEPROM dummy0",d->dout,0);unsigned v=0;for(unsigned b=0;b<8;b++){bit(0);v=(v<<1)|d->dout;}d->cs=0;tick(3);serial_reads++;return v;}
static void write(unsigned a,unsigned v){command((1u<<9)|a);for(int b=7;b>=0;b--)bit((v>>b)&1);d->cs=0;tick(3);serial_writes++;}
static void unlock(){command(3u<<7);d->cs=0;tick(3);}
static void finish_save(unsigned error){d->host_ack=1;tick(2);d->host_ack=0;d->host_done=0;tick(2);d->host_error=error;d->host_done=1;tick(2);d->host_done=0;d->host_error=0;tick(2);}
static void awaitsave(){for(unsigned t=0;t<100&&!d->save_request;t++)tick();eq("save request observed",d->save_request,1);}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=6)return 2;std::array<std::array<unsigned char,128>,4> originals;
 for(unsigned p=0;p<4;p++){std::ifstream f(argv[1+p],std::ios::binary);std::vector<unsigned char>b((std::istreambuf_iterator<char>(f)),{});if(b.size()<128)return 2;std::copy(b.end()-128,b.end(),originals[p].begin());}
 d=new Vtb_m4_controls;input_test();delete d;d=nullptr;
 std::array<unsigned char,128> saved;
 for(unsigned p=0;p<4;p++){
  oldreq=false;d=new Vtb_m4_controls;d->profile=p;load(originals[p]);
  // Fresh original defaults (no existing save), all cells through actual serialREAD.
  for(unsigned a=0;a<128;a++)eq("original EEPROM serialREAD",read(a),originals[p][a]);
  d->loaded=1;d->run=1;unsigned before=save_rises;awaitsave();finish_save(0);eq("initial absent-save creation request",save_rises-before,1);
  // Locked command must leave settings untouched; reset relocks the part.
  unsigned a=17,v=originals[p][41];for(unsigned i=0;i<128&&v==originals[p][a];i++)v=originals[p][i];eq("setting test has distinct original value",v!=originals[p][a],1);write(a,v);eq("locked setting unchanged",read(a),originals[p][a]);eq("locked EEPROM no busy",d->ready,1);
  d->run=0;unsigned paused_edges=save_rises;unlock();unsigned dirty=d->dirty;write(a,v);eq("real serial write togglesdirty",d->dirty,!dirty);eq("write busy",d->ready,0);tick(1000);eq("write ready",d->ready,1);eq("serial setting persisted",read(a),v);
  // Actual autosave keeps dirty while paused, then retries error completion.
  tick(20);eq("pause prevents request",save_rises,paused_edges);d->run=1;awaitsave();finish_save(1);awaitsave();finish_save(0);
  // Dump the actual EEPROM byte read port for later true unloader validation.
  for(unsigned i=0;i<128;i++){d->ld_addr=i;tick(2);unsigned expected=i==a?v:originals[p][i];eq("EEPROM byteport after serialwrite",d->ld_q,expected);if(p==3)saved[i]=d->ld_q;}
  d->reset=1;tick(4);d->reset=0;tick(4);eq("reset keeps EEPROM setting",read(a),v);write(a,originals[p][42]);eq("reset relocks EEPROM",read(a),v);
  delete d;
 }
 // Independent fresh configurations: restore original three games after M4,
 // then original default and stored M4 bytes. Only explicit public loads set cells.
 for(unsigned p:{0u,1u,2u,3u}){oldreq=false;d=new Vtb_m4_controls;load(originals[p]);for(unsigned a=0;a<128;a++)eq("newconfiguration independent defaults",read(a),originals[p][a]);delete d;}
 oldreq=false;d=new Vtb_m4_controls;load(saved);for(unsigned a=0;a<128;a++)eq("existing M4save restored",read(a),saved[a]);delete d;
 std::ofstream f(argv[5],std::ios::binary);f.write(reinterpret_cast<const char*>(saved.data()),128);f.close();
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%u,\"checks\":%u,\"input_cases\":262144,\"serial_reads\":%u,\"serial_writes\":%u,\"save_request_edges\":%u,\"configuration_isolation\":true,\"physical_verified\":false}\n",errors?"false":"true",errors,checks,serial_reads,serial_writes,save_rises);return errors?1:0;
}
