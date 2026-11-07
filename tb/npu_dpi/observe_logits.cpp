// Read-only verification observer. Never computes or supplies model outputs.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
extern "C" unsigned int rkv_mem_read(int sid, unsigned int word);
extern "C" void rkv_observe_logits(int sid, const char* directory, int step, int address, int words) {
    if (step < 1 || step > 256 || address < 0 || address % 4 || words <= 0) std::abort();
    const std::string path = std::string(directory) + "/observed-logits-" + std::to_string(step) + ".bin";
    FILE* file = std::fopen(path.c_str(), "wb");
    if (!file) std::abort();
    for (int i = 0; i < words; ++i) {
        const uint32_t value = rkv_mem_read(sid, unsigned(address / 4 + i));
        const unsigned char bytes[4] = {static_cast<unsigned char>(value), static_cast<unsigned char>(value >> 8),
                                        static_cast<unsigned char>(value >> 16), static_cast<unsigned char>(value >> 24)};
        if (std::fwrite(bytes, 1, 4, file) != 4) std::abort();
    }
    if (std::fclose(file)) std::abort();
}
