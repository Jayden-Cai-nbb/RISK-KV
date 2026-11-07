// Full-page build -> hardware seal -> zero-copy pair bind -> returned-token decode.
// Prompt tokens live in DDR; this firmware never creates or uploads KV tensors.
#include <stdint.h>
#include "npu_context_config.h"
static volatile uint32_t *const reg=(volatile uint32_t*)0x40000000u;
static void wr(uint32_t a,uint32_t v){reg[a>>2]=v;}
static uint32_t rd(uint32_t a){return reg[a>>2];}
static void finish(uint32_t c){*(volatile uint32_t*)0x50000000u=c;for(;;){}}
static void check(int yes,uint32_t n){if(!yes)finish(0xdead0000u|n);}
static void id(uint32_t seq){wr(0x20,SESSION_LO);wr(0x24,SESSION_HI);wr(0x28,seq);wr(0x2c,0);wr(0x30,1);wr(0x34,7);}
static void object_command(uint32_t command,uint32_t error){wr(0x200,command);check(rd(0x208)==error,100+command);}
static void load(uint32_t address,uint32_t n){
    wr(0x100,address);wr(0x104,n);wr(0x108,1);check(rd(0x110)==0,10);
    while(!(rd(0x10c)&1)){check(!(rd(0x10c)&4),11);}
    check(rd(0x114)==address&&rd(0x118)==n,12);
}
static void build_args(uint32_t p){
    uint32_t b=KV_BASE,v[8]={0,0u-(p<<2),b,b+p,b+(p<<2),b+(p<<7),p<<2,p<<8};
    for(uint32_t i=0;i<8;i++)wr(0x40+4*i,v[i]);
}
static void decode_args(uint32_t t,uint32_t x,uint32_t y){
    check(x<VOCAB&&y<VOCAB&&t<256,20);
    uint32_t b=KV_BASE,v[8]={0u-(t<<2),b,b+t,b+(t<<2),b+(t<<7),y<<12,t<<8,x<<12};
    for(uint32_t i=0;i<8;i++)wr(0x40+4*i,v[i]);
}
static void submit(uint32_t expected){__asm__ volatile("fence iorw, iorw":::"memory");wr(0xc,2);check(rd(8)==expected,21);}
static void wait_complete(uint32_t sequence,uint32_t status){
    while(!(rd(4)&4)){for(volatile uint32_t i=0;i<32;i++){}}
    check(rd(0x80)==status&&rd(0x8c)==sequence&&rd(0x90)==0,22);
    check(rd(0x84)==SESSION_LO&&rd(0x88)==SESSION_HI&&rd(0x94)==1&&rd(0x98)==7,23);
}
static void consume(void){wr(0xc,3);check(rd(8)==0,24);while(rd(0x204)&(1u<<9)){};}
static uint32_t token(uint32_t bits){
    if(!bits)return 0;
    check(!(bits>>31),30);
    uint32_t e=(bits>>23)&255;check(e>=127&&e<=144,31);
    uint32_t s=150-e,m=(bits&0x7fffff)|0x800000;check(!(m&((1u<<s)-1)),32);
    uint32_t t=m>>s;check(t<VOCAB,33);return t;
}
int main(void){
    check(rd(0)==0x524e5033u,1);wr(0x10,SESSION_LO);wr(0x14,SESSION_HI);wr(0xc,1);check(rd(8)==0,2);id(1);
    object_command(1,0);check((rd(0x204)&7)==1&&rd(0x20c)==0,3);
    object_command(2,4);object_command(3,2); // premature seal and bind
    load(DECODE_ADDR,DECODE_INSNS);decode_args(0,SEED0,SEED1);submit(9);check(rd(0x9c)==0,4);
    load(BUILD_ADDR,BUILD_INSNS);build_args(0);wr(0x34,8);submit(9);wr(0x34,7);
    wr(0x48,KV_BASE+128u);submit(9);build_args(0); // wrong base cannot create progress
    uint32_t sequence=1;
    for(uint32_t p=0;p<256;p+=4){
        check(rd(0x20c)==p,40);id(sequence);build_args(p);submit(0);
        if(!p)object_command(2,3); // busy cannot seal
        if(EXPECT_FAILURE==1&&!p){wr(0xc,4);check(rd(8)==0,41);}
        wait_complete(sequence,(!p)?EXPECT_FAILURE:0);
        if(EXPECT_FAILURE&&!p){
            consume();check((rd(0x204)&7)==4&&rd(0x20c)==0,42);
            object_command(2,2);object_command(3,2);object_command(5,0);
            while(!rd(0x228)){};check(!(rd(0x204)&7),43);
            finish(0x600d3000u|EXPECT_FAILURE);
        }
        check(rd(0x120)&1u,44);check(rd(0x124)==0x3f800000u&&rd(0x128)==0x40800000u,45);
        check(rd(0x20c)==p,46); // completion alone must not advance the committed cursor
        if(p==252)object_command(2,3); // even final CQ must be consumed first
        consume();check(rd(0x20c)==p+4,47);sequence++;
    }
    object_command(2,0);check((rd(0x204)&7)==2&&rd(0x20c)==256,50);
    load(DECODE_ADDR,DECODE_INSNS);id(sequence);decode_args(0,SEED0,SEED1);submit(9); // sealed but unbound
    object_command(3,0);check(rd(0x210)==2,51);
    uint32_t x=SEED0,y=SEED1,n=0;
    for(uint32_t t=0;t<MAX_DECODE;t++){
        id(sequence);decode_args(t,x,y);submit(0);wait_complete(sequence,0);
        check(rd(0x120)&1u,52);x=token(rd(0x124));y=token(rd(0x128));
        *(volatile uint32_t*)0x50000010u=x;*(volatile uint32_t*)0x50000014u=y;
        consume();check(rd(0x214)==t+1,53);sequence++;n++;
        if(x==EOS0||x==EOS1||y==EOS0||y==EOS1)break;
    }
    object_command(5,0);check((rd(0x204)&7)==3&&!rd(0x228),60); // binding pins retirement
    id(sequence);decode_args(n,x,y);submit(9);
    object_command(4,0);while(!rd(0x228)){};
    check((rd(0x204)&7)==0&&rd(0x20c)==256&&rd(0x214)==n&&rd(0x210)==0,61);
    object_command(1,2); // dirty slot is not silently registered again
    check(rd(0x9c)==64+n,62);finish(0x600d4000u|n);return 0;
}
