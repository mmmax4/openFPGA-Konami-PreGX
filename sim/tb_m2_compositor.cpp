// Independent public-interface compositor fixture. Synthetic accepted sprite
// fragments: real sprite Z/ROM/list production and line deadlines are outscope.
#include "Vpregx_mystic_compositor.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

static Vpregx_mystic_compositor d;
static std::array<uint32_t,2048> palette{};
static uint64_t clocks=0,checks=0,pixels=0,stalls=0,orders=0,fragments=0,boundary_waits=0;
static uint64_t same_x_stalls=0;
static unsigned last_sprite_x=0;
static bool have_last_sprite=false;
static unsigned lines=0,cancellations=0,resets=0;
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
    std::array<unsigned,3> alpha{140,0,396};
    std::array<std::array<Tile,288>,4> tiles{};std::vector<Object> objects;
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
        const Tile t=tx<288?active.tiles[l][tx]:Tile{};
        d.tile_pen[l]=t.pen;d.tile_category[l]=t.category;
        d.tile_opaque|=unsigned(t.opaque)<<l;
    }
    d.eval();clocks++;orders+=result.order;fragments+=result.fragment;return result;
}
static Scene make_scene(const std::string& name){
    Scene s;s.name=name;s.k55[45]=31;s.k55[40]=15;
    s.k55[7]=160;s.k55[10]=96;s.k55[13]=96;s.k55[14]=32;
    s.k55[33]=0x96;s.k55[34]=0x9c;s.k38[0]=0x12;s.k38[1]=0x3456;s.k38[15]=1;
    for(unsigned i=0;i<9;i++)s.k38[i+2]=unsigned(-16*int(i%3+1))&511;
    for(unsigned l=0;l<4;l++)for(unsigned x=0;x<288;x++)
        s.tiles[l][x]={32+l*97+(x*13)%97,(x/3+l)%4,((x+l*3)%11)!=0};
    return s;
}
static void configure(const Scene& s){
    d.tile_nonempty=15; // Preserve this component fixture's original scope.
    active=s;for(unsigned i=0;i<48;i++)d.k55regs[i]=s.k55[i];
    for(unsigned i=0;i<16;i++)d.k38regs[i]=s.k38[i];
    d.alpha1=s.alpha[0];d.alpha2=s.alpha[1];d.alpha3=s.alpha[2];
}
static unsigned priority(const Scene&s,unsigned l){return s.k55[std::array<unsigned,4>{7,10,13,14}[l]];}
static std::array<uint32_t,288> reference(const Scene&s){
    std::array<uint32_t,288> color{};std::array<unsigned,288> top,z,pri;
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
            unsigned x=f.x;need(x<288,"reference accepted fragment range");
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
        for(unsigned x=0;x<288;x++){
            auto t=s.tiles[l][x];unsigned mix=(t.category&(~mask&3))|internal;
            unsigned level=mix?s.alpha[mix-1]:255;
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
static void present(const std::array<uint32_t,288>&expected,const std::string&name){
    Scene blank=make_scene("presentation");blank.k55[45]=0;begin(blank);
    for(unsigned x=0;x<288;x++){
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
    for(unsigned x=0;x<288;x++)if(x%7!=0)o.fragments.push_back({x,pen+(x%17),level,false,0,3,20,priority});
    for(unsigned n=0;n<5;n++)o.fragments.push_back({17,pen+n,level,false,0,3,20,priority});
    return o;
}
static void set_brightness(Scene&s,unsigned first=64,unsigned second=128,unsigned third=192){
    s.k38[11]=first;s.k38[12]=(second<<8)|third;
}
static Object flat_object(unsigned pen,unsigned level,bool shadow=false){
    Object o{40,shadow,{}};
    for(unsigned x=0;x<288;x++)o.fragments.push_back({x,pen,level,shadow,0,3,20,40});
    return o;
}
static void brightness_controls(){
    // All cases are legal constructed public compositor inputs. Palette RAM
    // remains the original captured palette; no colour/ROM/register oracle is
    // patched. Original index2 RGB965060 gives distinct fixed RGB at each BRI.
    need(palette[2]==0x965060&&palette[8]==0x3078ee,"original brightness palette colours");
    const std::array<uint32_t,4> expected={0x965060,0x251418,0x4b2830,0x703c48};
    for(unsigned layer=0;layer<4;layer++)for(unsigned selector=0;selector<4;selector++){
        Scene s=make_scene("constructed-BRI-tile-layer"+std::to_string(layer)+"-selector"+std::to_string(selector));
        s.k55[45]=1u<<layer;s.k55[33]=0;s.k55[34]=0;
        s.k55[42]=selector<<(layer*2);set_brightness(s);
        for(auto&t:s.tiles[layer])t={2,0,true};
        auto ref=reference(s);
        need(ref[0]==expected[selector]&&ref[287]==expected[selector],"fixed tile selector RGB");
        run(s);brightness_tile_cases++;
    }
    for(unsigned enable=0;enable<2;enable++)for(unsigned selector=0;selector<4;selector++){
        Scene s=make_scene("constructed-BRI-object-enable"+std::to_string(enable)+"-selector"+std::to_string(selector));
        s.k55[45]=16;s.k55[43]=selector;s.k55[44]=enable;set_brightness(s);
        s.objects={flat_object(2,255)};
        uint32_t value=enable?expected[selector]:expected[0];
        auto ref=reference(s);
        need(ref[0]==value&&ref[287]==value,"fixed object selector/enable RGB");
        run(s);brightness_object_cases++;
    }
    Scene object_alpha=make_scene("constructed-BRI-object-before-alpha");
    object_alpha.k55[45]=16;object_alpha.k55[43]=2;object_alpha.k55[44]=1;
    set_brightness(object_alpha);object_alpha.objects={flat_object(2,128)};
    // RGB4b2830 blended half over unchanged backdrop123456 gives2e2e43.
    need(reference(object_alpha)[17]==0x2e2e43,"fixed object BRI-before-alpha RGB");
    run(object_alpha);brightness_alpha_cases++;
    Scene tile_alpha=make_scene("constructed-BRI-tile-before-alpha");
    tile_alpha.k55[45]=4;tile_alpha.k55[42]=1u<<4;tile_alpha.k55[33]=0;tile_alpha.k55[34]=0;
    set_brightness(tile_alpha);
    for(auto&t:tile_alpha.tiles[2])t={8,1,true};
    // Original RGB3078ee becomes0c1e3b, then alpha140 over123456 gives0e2747.
    need(reference(tile_alpha)[17]==0x0e2747,"fixed tile BRI-before-alpha RGB");
    run(tile_alpha);brightness_alpha_cases++;
    Scene shadow=make_scene("constructed-BRI-shadow-does-not-rescale-destination");
    shadow.k55[45]=17;shadow.k55[42]=1;shadow.k55[43]=2;shadow.k55[44]=1;
    shadow.k55[33]=0;shadow.k55[34]=0;set_brightness(shadow,128,0,192);
    for(auto&t:shadow.tiles[0])t={2,0,true};
    shadow.objects={flat_object(0,255,true)};
    // Half-bright destination4b2830 receives only shadow(-16,-32,-48).
    // Object BRI2=0 must not erase that destination: result3a0901.
    need(reference(shadow)[17]==0x3a0901,"fixed shadow bypasses source BRI RGB");
    run(shadow);brightness_shadow_cases++;
    need(brightness_tile_cases==16&&brightness_object_cases==8&&
         brightness_alpha_cases==2&&brightness_shadow_cases==1,"constructed brightness control coverage");
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc!=3)return 2;
    std::ifstream pf(argv[2],std::ios::binary);std::vector<unsigned char> raw((std::istreambuf_iterator<char>(pf)),{});
    need(raw.size()==8192,"original palette capture size");
    for(unsigned i=0;i<2048;i++)palette[i]=(uint32_t(raw[i*4])<<16)|(uint32_t(raw[i*4+3])<<8)|raw[i*4+2];
    std::ifstream vf(argv[1]);std::string line;unsigned vectors=0;
    while(std::getline(vf,line)){
        unsigned s,t,a,tile,e;need(sscanf(line.c_str(),"%x %x %x %x %x",&s,&t,&a,&tile,&e)==5,"independent RGB vector parse");
        need(blend(s,t,a,tile)==e,"scalar reference agrees independent pinned RGB vectors");vectors++;
    }need(vectors==6726,"scalar RGB oracle coverage count");
    active=make_scene("initial");d.reset=1;tick();tick();d.reset=0;
    d.fragment_valid=1;for(unsigned i=0;i<4;i++){d.eval();need(!d.fragment_ready,"no fragments before first line");tick();}d.fragment_valid=0;
    Scene inter=make_scene("four-tiles-three-partial-groups");
    inter.objects={solid(200,50,140),solid(96,140,140),solid(64,240,396)};run(inter);
    Scene three=make_scene("three-original-palette-alpha-contributions");three.k55[45]=16;
    three.k38[0]=(palette[0]>>16)&255;three.k38[1]=palette[0]&65535;
    three.objects={Object{200,false,{{17,2,140,false,0,3,20,200}}},
                   Object{100,false,{{17,6,140,false,0,3,20,100}}},
                   Object{50,false,{{17,8,140,false,0,3,20,50}}}};
    need(reference(three)[17]==0x5163c1,"three-contributor frozen oracle sequence");run(three);
    Scene ties=make_scene("all-layer-and-sprite-ties");ties.k55[33]=0;ties.k55[34]=0;
    for(unsigned l=0;l<4;l++){ties.k55[std::array<unsigned,4>{7,10,13,14}[l]]=96;for(auto&t:ties.tiles[l])t.category=0;}
    ties.objects={solid(96,11,140),solid(96,31,767),solid(96,71,255)};run(ties);
    for(unsigned mask:std::array<unsigned,4>{0u,5u,16u,31u}){
        Scene enabled=inter;enabled.name="K55-enables-"+std::to_string(mask);enabled.k55[45]=mask;run(enabled);
    }
    Scene kill=inter;kill.name="K38-global-disable";kill.k38[15]=0;run(kill);
    Scene shadow=make_scene("deferred-after-all-tile-passes");shadow.k55[33]=0;shadow.k55[34]=0;
    for(unsigned l=0;l<4;l++){
        shadow.k55[std::array<unsigned,4>{7,10,13,14}[l]]=100-l*20;
        for(auto&t:shadow.tiles[l])t.category=0;
    }
    shadow.k55[40]=7; // D opaque pixels mark top255; holes expose enabled lower tiles
    shadow.objects={solid(200,45,140)};
    for(auto setup:std::array<std::array<unsigned,3>,4>{{{90,2,1},{80,1,50},{40,2,40},{30,1,1}}}){
        Object o{setup[0],true,{}};
        for(unsigned x=0;x<288;x++)o.fragments.push_back({x,0,255,true,0,setup[1],setup[2],setup[0]});
        shadow.objects.push_back(o);
    }run(shadow);
    shadow.name="deferred-allowed-on-front-layer";shadow.k55[40]=15;run(shadow);
    // Accepted old-generation pixels are canceled before retirement; a new
    // line must not inherit them. No private FSM state or RAM is accessed.
    Scene pending=make_scene("canceled");pending.k55[45]=16;begin(pending);
    d.sprite_busy=1;send({7,15,140,false,0,3,20,40});
    Scene fresh=make_scene("new-line-cancellation");fresh.k55[45]=0;fresh.k38[0]=0x76;fresh.k38[1]=0x5432;
    run(fresh);cancellations++;
    begin(pending);d.sprite_busy=1;send({17,41,140,false,0,3,20,40});d.reset=1;tick();d.reset=0;
    fresh.name="reset-cancellation";fresh.k38[0]=0x23;fresh.k38[1]=0x4567;run(fresh);resets++;
    brightness_controls();
    need(same_x_stalls>10,"consecutive same-address public ready stalls observed");need(boundary_waits>100,"tile/clear/drain boundary waits observed");
    printf("RESULT_JSON {\"passed\":true,\"scalar_oracle_vectors\":%u,\"pixel_checks\":%llu,\"completed_lines\":%u,\"order_handshakes\":%llu,\"accepted_sprite_fragments\":%llu,\"fragment_stalls\":%llu,\"same_x_stalls\":%llu,\"boundary_wait_cycles\":%llu,\"line_cancellations\":%u,\"resets_with_inflight\":%u,\"checks\":%llu,\"cycles\":%llu,\"brightness_tile_selector_cases\":%u,\"brightness_object_selector_enable_cases\":%u,\"brightness_alpha_cases\":%u,\"brightness_shadow_cases\":%u,\"brightness_fixture_author\":\"research_rom_exit\",\"brightness_fixture_kind\":\"constructed public inputs, original palette colours\",\"hardware_verified\":false}\n",
        vectors,(unsigned long long)pixels,lines,(unsigned long long)orders,(unsigned long long)fragments,
        (unsigned long long)stalls,(unsigned long long)same_x_stalls,(unsigned long long)boundary_waits,cancellations,resets,
        (unsigned long long)checks,(unsigned long long)clocks,brightness_tile_cases,brightness_object_cases,
        brightness_alpha_cases,brightness_shadow_cases);
    puts("PASS public compositor synthetic accepted-fragment producer; real Z/ROM/renderer/deadlines unqualified");return 0;
}
