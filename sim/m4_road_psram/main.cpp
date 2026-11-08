// Public CPU/snapshot/external-memory contracts, original sample bytes.
// The RAM responder acknowledges COMMITTED writes at variable 2..32 clock
// latency. This isolates state/ownership; physical PSRAM remains unqualified.
#include "Vtb_m4_road_psram.h"
#include "verilated.h"
#include <array>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <vector>
static Vtb_m4_road_psram d;
static unsigned long long clocks=0,checks=0;
static void require(bool v,const char*s){++checks;if(!v)throw std::runtime_error(s);}
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();++clocks;require(!d.legacy_mismatch,"old/new PSRAM pins/acceptance/readback differ");require(!d.early_ack_error,"write ACK before physical completion");}
static void idle(unsigned n=3){for(unsigned i=0;i<n;i++)tick();}
static void until_ready(){unsigned n=0;while(!d.snapshot_allowed){tick();require(++n<2000000,"idle/initialization bound");}}
static unsigned cpu(unsigned a,bool write=false,unsigned data=0,unsigned lanes=3){
 d.cpu_req=1;d.cpu_addr=a;d.cpu_we=write;d.cpu_wdata=data;d.cpu_be=lanes;
 unsigned n=0;do{tick();require(++n<1000000,"CPU transaction bound");}while(!d.cpu_ack);
 unsigned q=d.cpu_q;
 for(unsigned i=0;i<5;i++){tick();require(!d.cpu_ack,"one CPU ACK per held request");}
 d.cpu_req=0;idle();return q;
}
static void trigger(bool newframe){if(newframe){d.frame_tick=1;tick();d.frame_tick=0;}d.reg4_dma=1;idle();d.reg4_dma=0;tick();}
static void finish_dma(){unsigned n=0;while(d.dma_busy){tick();require(++n<2000000,"DMA completion bound");}until_ready();}
static void begin_snapshot(){until_ready();d.snapshot_begin=1;d.snapshot_active=1;tick();d.snapshot_begin=0;}
static unsigned snapshot(unsigned a){
 d.snapshot_req=1;d.snapshot_addr=a;unsigned n=0;
 do{tick();require(++n<10000,"snapshot read bound");}while(!d.snapshot_ack);
 unsigned q=d.snapshot_q;for(unsigned i=0;i<3;i++){tick();require(!d.snapshot_ack,"one snapshot ACK per held request");}
 d.snapshot_req=0;idle();return q;
}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);if(argc!=3)return 2;try{
 std::ifstream f(argv[1],std::ios::binary);require(bool(f),"original road ROM open");std::vector<unsigned char>b{std::istreambuf_iterator<char>(f),{}};require(b.size()==0x40000,"original road ROM size");
 std::array<unsigned short,2048>A,B,C;
 for(unsigned i=0;i<2048;i++){A[i]=(unsigned(b[2*i])<<8)|b[2*i+1];B[i]=(unsigned(b[0x10000+2*i])<<8)|b[0x10001+2*i];C[i]=(unsigned(b[0x20000+2*i])<<8)|b[0x20001+2*i];}
 d.slow=std::atoi(argv[2])!=0;d.reset=1;idle(8);d.reset=0;until_ready();require(d.initialized&&!d.dma_busy,"state initialization ready");require(d.committed_writes>=12288,"all 24KiB explicitly initialized through physical port");for(unsigned i=0;i<8192;i++)require(cpu(i)==0,"initial CPU RAM zero");
 for(unsigned i=0;i<8192;i++)cpu(i,true,(unsigned(b[2*i])<<8)|b[2*i+1]);
 trigger(true);require(d.dma_busy,"trigger stalls CPU immediately");finish_dma();require(d.page==1,"first DMA flips next-destination page");
 begin_snapshot();for(unsigned i=0;i<2048;i++)require(snapshot(i)==0,"first DMA displays still-empty other page");d.snapshot_active=0;idle();
 for(unsigned i=0;i<2048;i++)cpu(i,true,B[i]);
 trigger(true);finish_dma();require(d.page==0,"second DMA flips to A visible page");
 begin_snapshot();for(unsigned i=0;i<2048;i++)require(snapshot(i)==A[i],"one-DMA delayed original A page");
 // Capture is coherent while a new DMA is queued behind the active snapshot.
 trigger(true);require(d.dma_busy,"queued DMA stalls CPU");unsigned savedpage=d.page;
 for(unsigned i=0;i<32;i++){require(snapshot(i)==A[i],"captured page stable during queued DMA");require(d.page==savedpage,"DMA waits for snapshot ownership release");}
 for(unsigned i=0;i<2048;i++)cpu(i,true,C[i]);
 d.snapshot_active=0;finish_dma();require(d.page==1,"third DMA page ownership");
 begin_snapshot();for(unsigned i=0;i<2048;i++)require(snapshot(i)==B[i],"third DMA displays original B page");d.snapshot_active=0;idle();
 auto priorwrites=d.accepted_writes;trigger(false);idle(200);require(!d.dma_busy&&d.accepted_writes==priorwrites,"one DMA per frame limiter");
 cpu(0x1fff,true,0xabcd);cpu(0x1fff,true,0x1200,2);require(cpu(0x1fff)==0x12cd,"upper-byte write at CPU boundary");cpu(0x1fff,true,0x0034,1);require(cpu(0x1fff)==0x1234,"lower-byte write at CPU boundary");
 // A cancelled public read is drained without ACK, then a fresh request works.
 d.cpu_req=1;d.cpu_addr=0x1fff;d.cpu_we=0;idle(2);d.cpu_req=0;
 for(unsigned i=0;i<100;i++){tick();require(!d.cpu_ack,"cancelled CPU read produces no stale ACK");}require(cpu(0x1fff)==0x1234,"fresh CPU read after cancellation");
 d.reset=1;idle(4);d.reset=0;until_ready();for(unsigned i=0;i<8192;i++)require(cpu(i)==0,"reset reinitializes CPU RAM");begin_snapshot();for(unsigned i=0;i<2048;i++)require(snapshot(i)==0,"reset clears DMA snapshot page");d.snapshot_active=0;require(!d.page,"reset clears page ownership");
 printf("PASS clocks%llu checks%llu accepted%u committed%u pin_write_ends%u old/newpins identical, no early ACK; behavioral PSRAM model, not fitted physical timing\n",clocks,checks,unsigned(d.accepted_writes),unsigned(d.committed_writes),unsigned(d.pin_write_ends));return 0;
 }catch(const std::exception&e){fprintf(stderr,"FAIL clock%llu: %s\n",clocks,e.what());return 1;}}
