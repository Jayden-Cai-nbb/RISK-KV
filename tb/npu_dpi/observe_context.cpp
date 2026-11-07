// Read-only context snapshot observer; never supplies KV to the computation.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
extern "C" unsigned int rkv_mem_read(int sid,unsigned int word);
extern "C" void rkv_observe_context(const char* directory,const char* name,int address,int bytes){
    if(address<0||address%4||bytes<=0||bytes%4||bytes>(64<<20))std::abort();
    FILE* file=std::fopen((std::string(directory)+"/"+name).c_str(),"wb");if(!file)std::abort();
    for(int i=0;i<bytes/4;i++){
        uint32_t v=rkv_mem_read(0,unsigned(address/4+i));
        const unsigned char b[4]={static_cast<unsigned char>(v),static_cast<unsigned char>(v>>8),static_cast<unsigned char>(v>>16),static_cast<unsigned char>(v>>24)};
        if(std::fwrite(b,1,4,file)!=4)std::abort();
    }
    if(std::fclose(file))std::abort();
}
