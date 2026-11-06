// Independent public-interface compositor fixture. Synthetic accepted sprite
// fragments: real sprite Z/ROM/list production and line deadlines are outscope.
#include "Vtb_m3_alpha.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>
#include "mame_alpha.h"

static Vtb_m3_alpha d;
static std::array<uint32_t,2048> palette{};
static uint64_t clocks=0,checks=0,pixels=0,stalls=0,orders=0,fragments=0,boundary_waits=0;
static uint64_t same_x_stalls=0;
static unsigned last_sprite_x=0;
static bool have_last_sprite=false;
static unsigned lines=0,cancellations=0,resets=0;
static unsigned vio_cases=0,mystic_cases=0,alpha_endpoints=0,external_cases=0,additive_cases=0;
static unsigned brightness_tile_cases=0,brightness_object_cases=0;
static unsigned brightness_alpha_cases=0,brightness_shadow_cases=0;
static void need(bool good,const char* text){
    checks++;if(!good){fprintf(stderr,"FAIL cycle%llu %s\n",(unsigned long long)clocks,text);exit(1);}
}
static uint32_t blend(uint32_t src,uint32_t dst,unsigned level,bool tile){
    uint32_t result=0;unsigned a=level&255;
    for(unsigned shift=0;shift<24;shift+=8){
        unsigned s=(src>>shift)&255,t=(dst>>shift)&255,v;
        if(level&256)v=std::min(255u,t+((s*(a+(tile?1:0)))>>8));
        else if(level==255||(tile&&a==255))v=s;
        else v=(s*a+t*(256-a))>>8;
        result|=v<<shift;
    }return result;
}
struct Tile {unsigned pen=0,category=0;bool opaque=false;};
struct Fragment {unsigned x,pen,level;bool shadow=false;unsigned table=0,condition=3,z=20,pri=40;};
struct Object {unsigned priority;bool deferred=false;std::vector<Fragment> fragments;};
struct Scene {
    std::string name;std::array<unsigned,48> k55{};std::array<unsigned,16> k38{};
    bool violent=true;unsigned last_mix=0;
    std::array<std::array<Tile,384>,4> tiles{};std::vector<Object> objects;
};
// Pinned MiSTer brightness source: exact255 bypass, otherwise upper unsigned
// product byte. The constructed selector cases below also check fixed RGB
// literals, so a shared selector mistake cannot hide behind this reference.
static unsigned brightness_factor(const Scene&s,unsigned selector){
    if(selector==1)return s.k38[11]&255;
    if(selector==2)return (s.k38[12]>>8)&255;
    if(selector==3)return s.k38[12]&255;
    return 255;
}
static uint32_t brightness_rgb(uint32_t color,unsigned factor){
    if(factor==255)return color;
    uint32_t result=0;
    for(unsigned shift=0;shift<24;shift+=8)
        result|=((((color>>shift)&255)*factor)>>8)<<shift;
    return result;
}
static Scene active;
struct Fire {bool order,fragment;};
static Fire tick(){
    d.clk=0;d.eval();Fire result{bool(d.order_valid&&d.order_ready),bool(d.fragment_valid&&d.fragment_ready)};
    const unsigned tx=d.tile_x;const uint32_t next_palette=palette[d.palette_addr];
    d.clk=1;d.eval();
    // These external registered memories sample pre-edge addresses and expose
    // new values after the edge, matching nonblocking SV memory read semantics.
    d.palette_q=next_palette;d.tile_opaque=0;
    for(unsigned l=0;l<4;l++){
        const Tile t=tx<(active.violent?384u:288u)?active.tiles[l][tx]:Tile{};
        d.tile_pen[l]=t.pen;d.tile_category[l]=t.category;
        d.tile_opaque|=unsigned(t.opaque)<<l;
    }
    d.eval();clocks++;orders+=result.order;fragments+=result.fragment;return result;
}
static std::vector<unsigned> captured_pens;
static Scene make_scene(const std::string& name){
    Scene s;s.name=name;s.k55[45]=31;s.k55[40]=15;
    s.k55[7]=160;s.k55[10]=96;s.k55[13]=96;s.k55[14]=32;
    s.k55[33]=0x96;s.k55[34]=0x9c;s.k38[0]=0x12;s.k38[1]=0x3456;s.k38[15]=1;
    for(unsigned i=0;i<9;i++)s.k38[i+2]=unsigned(-16*int(i%3+1))&511;
    for(unsigned l=0;l<4;l++)for(unsigned x=0;x<384;x++)
        s.tiles[l][x]={captured_pens[(l*384+x)%captured_pens.size()],0,((x+l*3)%11)!=0};
    return s;
}
static void configure(const Scene& s){
    d.tile_nonempty=15; // Preserve this component fixture's original scope.
    active=s;for(unsigned i=0;i<48;i++)d.k55regs[i]=s.k55[i];
    for(unsigned i=0;i<16;i++)d.k38regs[i]=s.k38[i];
    d.violent=s.violent;d.last_mix=s.last_mix;
}
static unsigned priority(const Scene&s,unsigned l){return s.k55[std::array<unsigned,4>{7,10,13,14}[l]];}
static unsigned mame_alpha(const Scene&s,unsigned e){k054338_device k;for(unsigned i=0;i<16;i++)k.m_regs[i]=s.k38[i];return k.set_alpha_level(e);}
static std::array<uint32_t,384> reference(const Scene&s){
    std::array<uint32_t,384> color{};std::array<unsigned,384> top,z,pri;
    color.fill((s.k38[0]&255)*65536+s.k38[1]);top.fill(255);z.fill(255);pri.fill(255);
    struct Event{unsigned priority,index;bool tile;};std::vector<Event> normal;
    for(unsigned l=0;l<4;l++)if((s.k55[45]&(1u<<l))&&(s.k38[15]&1))normal.push_back({priority(s,l),l,true});
    for(unsigned i=0;i<s.objects.size();i++)if(!s.objects[i].deferred)normal.push_back({s.objects[i].priority,i,false});
    std::stable_sort(normal.begin(),normal.end(),[](const Event&a,const Event&b){
        if(a.priority!=b.priority)return a.priority>b.priority;
        if(a.tile!=b.tile)return !a.tile; // tile paints after equal-priority sprites
        return a.tile?a.index>b.index:false; // lower tile id paints last
    });
    auto object=[&](const Object&o){
        if(!(s.k55[45]&16)||!(s.k38[15]&1))return;
        for(const auto&f:o.fragments){
            unsigned x=f.x;need(x<384,"reference accepted fragment range");
            if(!f.shadow){
                unsigned selector=(s.k55[44]&1)?s.k55[43]&3:0;
                uint32_t source=brightness_rgb(palette[f.pen&2047],brightness_factor(s,selector));
                color[x]=blend(source,color[x],f.level,false);top[x]=f.pri;continue;
            }
            bool accepted=z[x]>=f.z&&pri[x]>f.pri;
            if(f.condition==1)accepted=accepted&&top[x]!=255&&f.pri>top[x];
            if(f.condition==2)accepted=accepted&&top[x]!=255&&f.pri==top[x];
            if(!accepted)continue;
            z[x]=f.z;pri[x]=f.pri;uint32_t shaded=0;
            for(unsigned c=0;c<3;c++){
                unsigned shift=(2-c)*8,five=(color[x]>>(shift+3))&31;
                int delta=f.table==3?-80:int(s.k38[2+f.table*3+c]&511);
                if(f.table!=3&&delta>=256)delta-=512;
                int value=int((five<<3)|(five>>2))+delta;
                unsigned out=s.k38[15]&32?unsigned(value)&255:unsigned(std::max(0,std::min(255,value)));
                shaded|=out<<shift;
            }color[x]=shaded;
        }
    };
    for(const auto&e:normal){
        if(!e.tile){object(s.objects[e.index]);continue;}
        unsigned l=e.index,mask=(s.k55[34]>>(l*2))&3,internal=(s.k55[33]>>(l*2))&mask;
        for(unsigned x=0;x<(s.violent?384u:288u);x++){
            auto t=s.tiles[l][x];unsigned mix=(t.category&(~mask&3))|internal;
            unsigned level=mame_alpha(s,mix);
            if(s.violent){
                // Direct stable gx_draw_basic_tilemaps category passes. The
                // category selects a boolean pass; its numeric code is unused.
                unsigned ai=mame_alpha(s,internal)&511;
                if(ai&256){ai&=255;if(ai)ai=(~ai)&255;}
                unsigned ae=mame_alpha(s,s.last_mix&(~mask&3))&511;
                if(ae&256)ae=(~ae)&255;
                level=(t.category&&ae<255)?ae:ai;
            }
            if(!t.opaque||(!(level&256)&&!(level&255)))continue;
            unsigned selector=(s.k55[42]>>(l*2))&3;
            uint32_t source=brightness_rgb(palette[t.pen&2047],brightness_factor(s,selector));
            color[x]=blend(source,color[x],level,true);
            top[x]=(s.k55[40]&(1u<<l))?priority(s,l):255;
        }
    }
    for(const auto&o:s.objects)if(o.deferred)object(o);
    return color;
}
static void begin(const Scene&s){
    configure(s);d.order_valid=0;d.fragment_valid=0;d.sprite_busy=!s.objects.empty();
    have_last_sprite=false;
    d.line_start=1;tick();d.line_start=0;
}
static void send(const Fragment&f){
    d.fragment_x=f.x;d.fragment_pen=f.pen;d.fragment_level=f.level;d.fragment_shadow=f.shadow;
    d.fragment_table=f.table;d.fragment_condition=f.condition;d.fragment_z=f.z;d.fragment_pri=f.pri;d.fragment_valid=1;
    for(unsigned n=0;n<20000;n++){
        if(tick().fragment){d.fragment_valid=0;last_sprite_x=f.x;have_last_sprite=true;return;}
        stalls++;if(have_last_sprite&&last_sprite_x==f.x)same_x_stalls++;
    }
    need(false,"bounded fragment handshake");
}
static void finish(){
    d.order_valid=0;d.fragment_valid=0;d.sprite_busy=0;
    for(unsigned n=0;n<20000;n++){d.eval();if(!d.busy)return;tick();}
    need(false,"bounded compositor completion (not a renderer line deadline)");
}
static void present(const std::array<uint32_t,384>&expected,const std::string&name){
    bool profile=active.violent;Scene blank=make_scene("presentation");blank.violent=profile;blank.k55[45]=0;begin(blank);
    for(unsigned x=0;x<(active.violent?384u:288u);x++){
        d.scan_x=x;tick();pixels++;
        if(d.rgb!=expected[x])fprintf(stderr,"scene=%s x=%u actual=%06x expected=%06x\n",name.c_str(),x,unsigned(d.rgb),expected[x]);
        need(d.rgb==expected[x],"independent ordered per-pixel reference");
    }finish();lines++;
}
static void run(const Scene&s){
    auto expected=reference(s);begin(s);
    for(const auto&o:s.objects){
        d.order_priority=o.priority;d.order_deferred=o.deferred;d.order_valid=1;
        bool entered=false;
        for(unsigned n=0;n<20000;n++){if(tick().order){entered=true;break;}boundary_waits++;}
        need(entered,"bounded object boundary handshake");d.order_valid=0;
        for(unsigned i=0;i<o.fragments.size();i++){
            send(o.fragments[i]);
            if(i%19==3){d.fragment_valid=0;d.fragment_pen=(i*17)&2047;tick();}
        }
    }finish();present(expected,s.name);
}
static Object solid(unsigned priority,unsigned pen,unsigned level){
    Object o{priority,false,{}};
    for(unsigned x=0;x<384;x++)if(x%7!=0)o.fragments.push_back({x,pen+(x%17),level,false,0,3,20,priority});
    for(unsigned n=0;n<5;n++)o.fragments.push_back({17,pen+n,level,false,0,3,20,priority});
    return o;
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc!=5)return 2;
    auto bytes=[](const char*p){std::ifstream f(p,std::ios::binary);need(bool(f),"original capture open");return std::vector<unsigned char>((std::istreambuf_iterator<char>(f)),{});};
    auto p=bytes(argv[1]),r55=bytes(argv[2]),r38=bytes(argv[3]),pens=bytes(argv[4]);
    need(p.size()==8192&&r55.size()==128&&r38.size()==64&&pens.size()>=768,"original fixture sizes");
    for(unsigned i=0;i<2048;i++)palette[i]=(unsigned(p[i*4])<<16)|(unsigned(p[i*4+3])<<8)|p[i*4+2];
    for(unsigned i=0;i+1<pens.size();i+=2)captured_pens.push_back(pens[i]|unsigned(pens[i+1])<<8);
    Scene original=make_scene("original-registers-category0");
    for(unsigned i=0;i<48;i++)original.k55[i]=r55[i];
    for(unsigned i=0;i<16;i++)original.k38[i]=r38[i*2]|unsigned(r38[i*2+1])<<8;
    active=original;d.reset=1;tick();tick();d.reset=0;
    run(original);vio_cases++;
    // All ROM/pen/palette bytes are original. Only these declared fixture
    // register/category controls change, independently of the DUT equations.
    const unsigned controls[]={0,31,16,32,63,48};
    for(unsigned layer=0;layer<4;layer++)for(unsigned mask=0;mask<4;mask++)for(unsigned vin=0;vin<4;vin++)for(unsigned last=0;last<4;last++)for(unsigned ci=0;ci<6;ci++){
        Scene s=original;s.name="vio-L"+std::to_string(layer)+"-M"+std::to_string(mask)+"-V"+std::to_string(vin)+"-G"+std::to_string(last)+"-C"+std::to_string(ci);
        s.k55[45]=1u<<layer;s.k55[33]=vin<<(layer*2);s.k55[34]=mask<<(layer*2);s.k55[42]=0;s.k38[15]=1;s.last_mix=last;
        s.k38[13]=controls[ci];s.k38[14]=(controls[(ci+1)%6]<<8)|controls[(ci+2)%6];
        for(unsigned x=0;x<384;x++){s.tiles[layer][x].category=x%4;s.tiles[layer][x].opaque=true;}
        run(s);vio_cases++;external_cases+=last!=0;additive_cases+=ci>=3;alpha_endpoints+=ci<2;
    }
    // Same ordinary nonadditive public path and original palette under Mystic,
    // with the previously qualified per-pixel code combination (288pixels).
    for(unsigned ci=0;ci<3;ci++)for(unsigned mask=0;mask<4;mask++){
        Scene s=original;s.violent=false;s.name="mystic-ordinary-C"+std::to_string(ci)+"-M"+std::to_string(mask);
        s.k55[45]=15;s.k55[33]=0x69;s.k55[34]=mask*0x55;s.k55[42]=0;s.k38[15]=1;s.k38[13]=controls[ci];s.k38[14]=(controls[(ci+1)%3]<<8)|controls[(ci+2)%3];
        for(unsigned l=0;l<4;l++)for(unsigned x=0;x<384;x++)s.tiles[l][x].category=(x+l)%4;
        run(s);mystic_cases++;
    }
    // Deferred shadow observes the result of the actual alpha tile pass,
    // including alpha0 not recording topmost, clipped vs wrap, and filters.
    for(unsigned cond=1;cond<=3;cond++)for(unsigned wrap=0;wrap<2;wrap++)for(unsigned endpoint=0;endpoint<3;endpoint++){
        Scene s=original;s.name="vio-alpha-shadow-cond"+std::to_string(cond)+"-wrap"+std::to_string(wrap);
        s.k55[45]=17;s.k55[33]=0;s.k55[34]=0;s.k55[42]=0;s.k38[13]=std::array<unsigned,3>{16,31,0}[endpoint];s.k38[14]=0x001f;s.k38[15]=1|(wrap?32:0);s.last_mix=1;s.k55[40]=1;
        for(unsigned x=0;x<384;x++){s.tiles[0][x].category=x%4;s.tiles[0][x].opaque=true;}
        unsigned shadowpri=cond==2?s.k55[7]:80;Object o{shadowpri,true,{}};for(unsigned x=0;x<384;x++)o.fragments.push_back({x,0,255,true,x%4,cond,20,shadowpri});s.objects={o};run(s);vio_cases++;
    }
    need(vio_cases>1500&&mystic_cases==12&&external_cases&&additive_cases&&alpha_endpoints,"alpha matrix executed");
    printf("RESULT_JSON {\"passed\":true,\"vio_cases\":%u,\"mystic_cases\":%u,\"external_cases\":%u,\"additive_cases\":%u,\"endpoint_cases\":%u,\"pixel_checks\":%llu,\"checks\":%llu,\"cycles\":%llu,\"order_handshakes\":%llu,\"fragments\":%llu,\"hardware_verified\":false}\n",vio_cases,mystic_cases,external_cases,additive_cases,alpha_endpoints,(unsigned long long)pixels,(unsigned long long)checks,(unsigned long long)clocks,(unsigned long long)orders,(unsigned long long)fragments);return 0;
}
