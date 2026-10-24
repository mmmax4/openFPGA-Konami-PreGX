#include "Vtb_m2_line_queue05.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

// Expected data are only filter(list,ranges,line), in producer order. No copy
// of the DUT's FIFO pointers/credit implementation is used as a golden model.
struct Source {
    std::string name;
    std::vector<uint32_t> headers;
    std::array<uint32_t,256> ranges{};
    bool original=false;
};
static Vtb_m2_line_queue05 *d;
static uint64_t clocks=0,checks=0,errors=0,takes=0,stable=0;
static unsigned cases=0,original_cases=0,constructed_cases=0,aborts=0,resets=0;
static unsigned full_stalls=0,scan_done_with_data=0,simultaneous_flow=0;
static uint32_t rng=0x5eeda105;
static uint32_t random32(){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
static void equal(const char *what,uint64_t got,uint64_t want){
    checks++;
    if(got!=want){if(errors<20)printf("ERROR %s got=%llx expected=%llx clock=%llu\n",what,
       (unsigned long long)got,(unsigned long long)want,(unsigned long long)clocks);errors++;}
}
static void edge(){d->clk=0;d->eval();d->clk=1;d->eval();clocks++;}
static int sign11(unsigned x){x&=2047;return (x&1024)?int(x)-2048:int(x);}
static uint32_t range(int lo,int hi){return (unsigned(lo)&2047)*2048+(unsigned(hi)&2047);}
static std::vector<uint32_t> expected(const Source&s,unsigned line){
    std::vector<uint32_t> v;
    for(auto h:s.headers){auto r=s.ranges[(h>>8)&255];
        if(int(line)>=sign11(r>>11)&&int(line)<=sign11(r))v.push_back(h);}
    return v;
}
static void reset(){
    d->reset=1;d->line_start=0;d->ready=0;edge();
    equal("reset empty",d->valid,0);equal("reset scanner inactive",d->scan_done,0);
    d->reset=0;edge();resets++;
}
static void setup(const Source&s){
    reset();d->reset=1;
    for(unsigned i=0;i<512;i++){
        d->setup_we=1;d->setup_range=0;d->setup_addr=i;
        d->setup_data=i<s.headers.size()?s.headers[i]:0xdeadbeef;edge();}
    for(unsigned i=0;i<256;i++){
        d->setup_range=1;d->setup_addr=i;d->setup_data=s.ranges[i];edge();}
    d->setup_we=0;d->reset=0;edge();
}
static void start(const Source&s,unsigned line){
    d->line=line;d->list_count=s.headers.size();d->line_start=1;d->ready=0;edge();
    d->line_start=0;
    equal("new epoch empty",d->valid,0);equal("new epoch index",d->list_idx,0);
    equal("count0 done on start",d->scan_done,s.headers.empty());
}
static bool readiness(unsigned policy,unsigned tick){
    if(policy==0)return true;
    if(policy==1)return tick>=40; // fill and keep head stalled before draining
    if(policy==2)return (random32()&7)>=3;
    return tick%11==0;
}
static void drain(const Source&s,unsigned line,unsigned policy){
    auto ref=expected(s,line);unsigned at=0,wait=0,old_issue=d->list_idx;
    bool previous_issue=false,previous_stall=false;uint32_t held=0;
    // At entry all metadata valid tags are empty, unless an abort caller
    // already started the replacement epoch. The caller never advances it.
    while(wait++<20000){
        // Inputs are deliberately changed after start to verify line/count
        // latching. The producer memories remain unchanged throughout the run.
        d->line=(line+137+wait)&511;d->list_count=(wait&1)?0:512;
        d->ready=readiness(policy,wait-1);d->clk=0;d->eval();
        if(previous_stall){stable++;equal("held valid",d->valid,1);equal("held entry32",d->entry,held);}
        bool take=d->valid&&d->ready;
        if(d->valid){equal("head reference exists",at<ref.size(),1);
            if(at<ref.size())equal("full32-bit ordered head",d->entry,ref[at]);}
        previous_stall=d->valid&&!d->ready;held=d->entry;
        if(take){at++;takes++;}
        bool done_before=d->scan_done;
        if(done_before&&d->valid)scan_done_with_data++;
        edge();
        unsigned now=d->list_idx;
        equal("issued monotonic or stationary",now==old_issue||now==old_issue+1,1);
        equal("never issue beyond snapshotted count",now<=s.headers.size(),1);
        bool issued=now==old_issue+1;
        // Infer response tags from PUBLIC issued-index changes. This verifies
        // exact scan_done timing without duplicating credit/FIFO state logic.
        bool done=now==s.headers.size()&&!issued&&!previous_issue;
        equal("exact public scanner completion",d->scan_done,done);
        if(issued&&take)simultaneous_flow++;
        if(policy==1&&wait>=12&&wait<35&&s.headers.size()>=4&&ref.size()==s.headers.size()){
            equal("full queue stops at four reserved headers",now,4);full_stalls++;}
        old_issue=now;previous_issue=issued;
        if(d->scan_done&&!d->valid){equal("no loss/duplicates total",at,ref.size());break;}
    }
    equal("bounded eventual completion",wait<20000,1);
    for(unsigned i=0;i<5;i++){d->ready=1;edge();equal("no duplicate tail",d->valid,0);equal("done remains stable",d->scan_done,1);}
    cases++;if(s.original)original_cases++;else constructed_cases++;
}
static void run(const Source&s,unsigned line,unsigned policy){setup(s);start(s,line);drain(s,line,policy);}
static Source load(const char *path){
    Source s;s.original=true;std::ifstream f(path);std::string key,value;unsigned count,frame,n;
    if(!(f>>key>>frame>>count)||key!="ORIGINAL"||count>512)std::exit(2);
    s.name="original"+std::to_string(frame);f>>key>>n;if(key!="HEADERS"||n!=count)std::exit(2);
    for(unsigned i=0;i<n;i++){f>>value;s.headers.push_back(std::stoul(value,nullptr,16));}
    f>>key>>n;if(key!="RANGES"||n!=256)std::exit(2);
    for(auto &r:s.ranges){f>>value;r=std::stoul(value,nullptr,16);}
    if(!f)std::exit(2);return s;
}
static Source control(unsigned count,int kind){
    Source s;s.name="control"+std::to_string(count)+"-"+std::to_string(kind);
    for(unsigned i=0;i<count;i++){
        // Every full header field is exercised, including mode/deferred/table.
        // Duplicate exact headers in the512 case remain separate operations.
        unsigned j=i%256;
        unsigned mode=j%6,pri=mode>=4?j*37U%256:(j%8)*32;
        unsigned condition=mode>=4?j%4:0,table=mode==4?j%3:0;
        s.headers.push_back(pri<<24|(j*19U%256)<<16|(j<<8)|(mode<<4)|(condition<<2)|table);
    }
    for(unsigned i=0;i<256;i++){
        int lo=-1024,hi=1023;
        if(kind==1){lo=-1024;hi=-1;}
        if(kind==2){lo=int(i)*2-128;hi=lo+((i*13)%90);if(hi>1023)hi=1023;}
        if(kind==3){lo=i%2?511:0;hi=lo;}
        s.ranges[i]=range(lo,hi);
    }
    return s;
}
static void cancel_case(bool hard,unsigned count,unsigned elapsed){
    Source s=control(count,0);setup(s);start(s,130);
    for(unsigned i=0;i<elapsed;i++){d->ready=0;edge();}
    if(elapsed==1&&count)equal("abort after list-response issued",d->list_idx,1);
    if(elapsed==2&&count==1)equal("abort after range-response pending",d->scan_done,0);
    if(elapsed>=8&&count>=4)equal("abort at full stalled head",d->valid,1);
    // Reuse the immutable producer memories; only the new line/count snapshot
    // changes. Reset and line-start are the defined epoch cancellation API.
    if(hard)reset();
    start(s,511);drain(s,511,2);aborts++;
}
int main(int argc,char **argv){
    Verilated::commandArgs(argc,argv);if(argc!=3)return 2;
    d=new Vtb_m2_line_queue05;d->clk=0;d->reset=1;d->line_start=0;
    d->line=0;d->list_count=0;d->ready=0;d->setup_we=0;d->setup_range=0;d->setup_addr=0;d->setup_data=0;d->eval();
    Source a=load(argv[1]),b=load(argv[2]);
    equal("original141 entries",a.headers.size(),141);equal("original98 entries",b.headers.size(),98);
    equal("original intro raw130 hits",expected(a,130).size(),12);
    equal("original intro raw146 hits",expected(a,146).size(),55);
    equal("original snow raw130 hits",expected(b,130).size(),59);
    for(auto &s:{a,b})for(unsigned line:{0U,16U,130U,146U,147U,239U,511U})
        for(unsigned policy=0;policy<4;policy++)run(s,line,policy);
    for(unsigned count:{0U,1U,512U})for(int kind=0;kind<4;kind++)
        for(unsigned line:{0U,130U,511U})for(unsigned policy=0;policy<4;policy++)run(control(count,kind),line,policy);
    // Empty, stage1 only, stage2 only, both stages, and full FIFO cancellation.
    for(bool hard:{false,true}){
        cancel_case(hard,0,0);cancel_case(hard,1,1);cancel_case(hard,1,2);
        cancel_case(hard,512,2);cancel_case(hard,512,8);
    }
    equal("original case matrix",original_cases,56);
    equal("constructed including cancellations",constructed_cases,154);
    equal("cancellation matrix",aborts,10);
    equal("stalled-head checks exercised",stable>100,1);
    equal("full-credit checks exercised",full_stalls>0,1);
    equal("scan_done while data retained exercised",scan_done_with_data>0,1);
    equal("simultaneous progress exercised",simultaneous_flow>0,1);
    printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"cases\":%u,\"original_cases\":%u,\"constructed_cases\":%u,\"aborts\":%u,\"resets\":%u,\"accepted_headers\":%llu,\"head_stability_checks\":%llu,\"full_credit_stall_checks\":%u,\"done_with_queued_data_checks\":%u,\"simultaneous_issue_accept\":%u,\"cycles\":%llu,\"hardware_verified\":false}\n",
      errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,cases,original_cases,constructed_cases,aborts,resets,
      (unsigned long long)takes,(unsigned long long)stable,full_stalls,scan_done_with_data,simultaneous_flow,(unsigned long long)clocks);
    delete d;return errors?1:0;
}
