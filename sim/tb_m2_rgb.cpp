// Public-pin arithmetic/pipeline verification. Expected RGB comes exclusively
// from independent pinned-MAME vectors; feedback dst comes from the actual DUT.
#include "Vpregx_rgb_blend.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <deque>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

struct Vector {unsigned src,dst,level,tile,expected;};
struct Pending {uint64_t due;unsigned expected,index;};
struct Output {bool valid;unsigned rgb;};
static Vpregx_rgb_blend *dut;
static std::deque<Pending> pending;
static uint64_t cycles=0,accepted=0,compared=0,cancelled=0,errors=0;
static uint64_t valid_errors=0,rgb_errors=0,bubbles=0,resets=0,reset_inputs_ignored=0;
static void fail(const char *message,unsigned got,unsigned expected,unsigned index){
    if(errors<20)std::printf("ERROR %s cycle=%llu vector=%u actual=%06x expected=%06x\n",message,(unsigned long long)cycles,index,got,expected);
    errors++;
}
static Output step(const Vector&v,bool valid=false,bool reset=false,unsigned index=0){
    cycles++;
    if(reset){cancelled+=pending.size();pending.clear();resets++;reset_inputs_ignored+=valid;}
    else if(valid){pending.push_back({cycles+2,v.expected,index});accepted++;}
    else bubbles++;
    dut->clk=0;dut->reset=reset;dut->valid_in=valid;dut->src=v.src;dut->dst=v.dst;dut->level=v.level;dut->is_tile=v.tile;dut->eval();
    dut->clk=1;dut->eval();
    bool expected_valid=!pending.empty()&&pending.front().due==cycles;
    if(!pending.empty()&&pending.front().due<cycles){fail("scoreboard overdue",0,0,index);pending.pop_front();}
    if(bool(dut->valid_out)!=expected_valid){valid_errors++;fail("valid latency/reset",dut->valid_out,expected_valid,index);}
    if(expected_valid){
        auto p=pending.front();pending.pop_front();
        if(dut->valid_out){compared++;if(dut->rgb!=p.expected){rgb_errors++;fail("RGB oracle",dut->rgb,p.expected,p.index);}}
    }
    return {bool(dut->valid_out),unsigned(dut->rgb)};
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    if(argc!=3){std::fprintf(stderr,"usage: rgb vectors.txt sequences.tsv\n");return 2;}
    std::vector<Vector> rows;std::ifstream input(argv[1]);std::string line;
    while(std::getline(input,line)){
        Vector v{};char extra;
        if(std::sscanf(line.c_str(),"%x %x %x %x %x %c",&v.src,&v.dst,&v.level,&v.tile,&v.expected,&extra)!=5||v.src>0xffffff||v.dst>0xffffff||v.level>1023||v.tile>1||v.expected>0xffffff){std::fprintf(stderr,"bad vector line\n");return 2;}
        rows.push_back(v);
    }
    if(rows.size()!=6726){std::fprintf(stderr,"expected6726 independent rows\n");return 2;}
    dut=new Vpregx_rgb_blend;
    Vector idle{0xabcdef,0x123456,0x3ff,1,0};
    for(unsigned i=0;i<3;i++)step(idle,false,true);
    uint64_t before=compared;
    for(unsigned i=0;i<rows.size();i++)step(rows[i],true,false,i);
    for(unsigned i=0;i<3;i++)step(idle);
    uint64_t back_to_back=compared-before;
    before=compared;
    for(unsigned i=0;i<rows.size();i++){
        // Input changes on invalid cycles must not become output operations.
        if(i%7==0){step(idle);step(rows[(i*17+31)%rows.size()]);}
        if(i%11==0)step(rows[(i*29+83)%rows.size()]);
        step(rows[i],true,false,i);
    }
    for(unsigned i=0;i<3;i++)step(idle);
    uint64_t bubble_vectors=compared-before;
    for(unsigned age=1;age<=3;age++){
        for(unsigned n=0;n<age;n++)step(rows[6144+age*8+n],true,false,6144+age*8+n);
        // Reset at each occupied stage, also driving a valid input during reset.
        step(rows[6200+age],true,true,6200+age);
        step(rows[6230+age],true,true,6230+age);
        for(unsigned n=0;n<4;n++)step(idle);
        step(rows[6260+age],true,false,6260+age);
        for(unsigned n=0;n<3;n++)step(idle);
    }
    std::ifstream sequence_input(argv[2]);unsigned sequence_count=0,feedback_steps=0;
    std::vector<std::string> sequence_results;
    while(std::getline(sequence_input,line)){
        std::istringstream in(line);unsigned first,count,background,expected_final;std::string name;
        in>>std::dec>>first>>count>>std::hex>>background>>expected_final>>name;
        if(!in||count!=3||first+count>rows.size()){std::fprintf(stderr,"bad sequence contract\n");return 2;}
        unsigned accumulator=background;
        std::ostringstream actual_destinations;
        for(unsigned i=0;i<count;i++){
            Vector v=rows[first+i];v.dst=accumulator;
            if(i)actual_destinations<<",";
            actual_destinations<<accumulator;
            step(v,true,false,first+i);step(idle);Output out=step(idle);
            if(!out.valid)fail("feedback requires actual valid result",0,1,first+i);
            accumulator=out.rgb;feedback_steps++;
        }
        bool pass=accumulator==expected_final;
        if(!pass)fail("ordered final RGB",accumulator,expected_final,first);
        std::ostringstream result;
        result<<"{\"name\":\""<<name<<"\",\"actual_destinations\":["<<actual_destinations.str()<<"],\"final_rgb\":"<<accumulator<<",\"expected_final\":"<<expected_final<<",\"passed\":"<<(pass?"true":"false")<<"}";
        sequence_results.push_back(result.str());sequence_count++;
    }
    for(unsigned n=0;n<4;n++)step(idle);
    if(sequence_count!=2||feedback_steps!=6)fail("sequence coverage",sequence_count,2,0);
    if(back_to_back!=rows.size()||bubble_vectors!=rows.size())fail("complete vector coverage",back_to_back+bubble_vectors,2*rows.size(),0);
    if(!pending.empty()||accepted!=compared+cancelled)fail("pipeline accounting",accepted,compared+cancelled,0);
    if(cancelled!=5||reset_inputs_ignored!=6)fail("reset stage coverage",cancelled,5,0);
    std::printf("RESULT_JSON {\"passed\":%s,\"independent_vectors\":%u,\"back_to_back_compared\":%llu,\"bubble_schedule_compared\":%llu,\"accepted\":%llu,\"compared\":%llu,\"reset_discarded\":%llu,\"reset_asserted_cycles\":%llu,\"inputs_ignored_during_reset\":%llu,\"invalid_cycles\":%llu,\"valid_errors\":%llu,\"rgb_errors\":%llu,\"errors\":%llu,\"latency_cycles\":2,\"feedback_steps\":%u,\"cycles\":%llu,\"hardware_verified\":false,\"sequences\":[",
        errors?"false":"true",unsigned(rows.size()),(unsigned long long)back_to_back,(unsigned long long)bubble_vectors,(unsigned long long)accepted,(unsigned long long)compared,(unsigned long long)cancelled,(unsigned long long)resets,(unsigned long long)reset_inputs_ignored,(unsigned long long)bubbles,(unsigned long long)valid_errors,(unsigned long long)rgb_errors,(unsigned long long)errors,feedback_steps,(unsigned long long)cycles);
    for(unsigned i=0;i<sequence_results.size();i++)std::printf("%s%s",i?",":"",sequence_results[i].c_str());
    std::printf("]}\n%s M2 RGB arithmetic/pipeline\n",errors?"FAIL":"PASS");
    delete dut;return errors?1:0;
}
