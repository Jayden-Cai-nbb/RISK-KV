// Simulation memory only: no model operators, approximate arithmetic or oracle.
// Anonymous mmap supplies zeroed pages over the FULL configured address space.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <string>
#include <vector>
#include <sys/mman.h>

namespace {
[[noreturn]] void fail(const char* what) {
    std::fprintf(stderr,"RKV_DPI_DRAM_ERROR: %s\n",what);std::fflush(stderr);std::abort();
}
struct Write {std::uint32_t word,value,mask;};
struct Memory {
    std::uint64_t words=0; std::uint32_t* data=nullptr; std::string dir;
    std::vector<Write> pending;
    ~Memory(){if(data)munmap(data,static_cast<std::size_t>(words*4));}
};
std::vector<std::unique_ptr<Memory>> memories;
Memory& get(int sid) {
    if(sid<0 || static_cast<std::size_t>(sid)>=memories.size() || !memories[sid])fail("uninitialized slice");
    return *memories[sid];
}
void address(Memory& m,std::uint32_t a){if(a>=m.words)fail("word address outside configured capacity");}
}
extern "C" void rkv_mem_init(int sid,unsigned long long words,const char* dir) {
    std::uint32_t endian=1;
    if(*reinterpret_cast<unsigned char*>(&endian)!=1)fail("little-endian host required");
    if(sid<0 || sid>63 || !words || words>std::numeric_limits<std::size_t>::max()/4 || !dir || !*dir)
        fail("invalid configuration");
    if(memories.size()<=static_cast<std::size_t>(sid))memories.resize(sid+1);
    if(memories[sid])fail("slice initialized twice");
    auto m=std::make_unique<Memory>();m->words=words;m->dir=dir;m->pending.reserve(64);
    void* p=mmap(nullptr,static_cast<std::size_t>(words*4),PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    if(p==MAP_FAILED)fail("mmap failed");m->data=static_cast<std::uint32_t*>(p);
    std::string input=m->dir+"/dram_"+std::to_string(sid)+".bin";
    if(FILE* f=std::fopen(input.c_str(),"rb")) {
        std::vector<unsigned char> buf(1<<20);std::uint64_t at=0;std::size_t n;
        while((n=std::fread(buf.data(),1,buf.size(),f))>0) {
            if(n%4 || at+n/4>words)fail("input is unaligned or exceeds capacity");
            for(std::size_t i=0;i<n;i+=4)
                m->data[at++]=(std::uint32_t(buf[i])<<24)|(std::uint32_t(buf[i+1])<<16)|
                               (std::uint32_t(buf[i+2])<<8)|std::uint32_t(buf[i+3]);
        }
        if(std::ferror(f))fail("input read failed");std::fclose(f);
    }
    std::printf("RKV_DPI_DRAM sid=%d bytes=%llu\n",sid,words*4);std::fflush(stdout);
    memories[sid]=std::move(m);
}
extern "C" unsigned int rkv_mem_read(int sid,unsigned int word) {
    auto& m=get(sid);address(m,word);return m.data[word];
}
extern "C" void rkv_mem_queue(int sid,unsigned int word,unsigned int value,unsigned int mask) {
    auto& m=get(sid);address(m,word);if(mask&~15u)fail("invalid byte enable");
    m.pending.push_back({word,value,mask});
}
extern "C" void rkv_mem_commit(int sid) {
    auto& m=get(sid);
    for(const auto& w:m.pending) {
        std::uint32_t mask=0;
        for(unsigned b=0;b<4;b++)if(w.mask&(1u<<b))mask|=0xffu<<(8*b);
        m.data[w.word]=(m.data[w.word]&~mask)|(w.value&mask);
    }
    m.pending.clear();
}
extern "C" void rkv_mem_dump(int sid) {
    auto& m=get(sid);std::string output=m.dir+"/dram_out_"+std::to_string(sid)+".bin";
    FILE* f=std::fopen(output.c_str(),"wb");if(!f)fail("cannot create dump");
    const auto bytes=static_cast<std::size_t>(m.words*4);
    if(std::fwrite(m.data,1,bytes,f)!=bytes)fail("short dump");
    if(std::fclose(f))fail("dump close failed");
}
