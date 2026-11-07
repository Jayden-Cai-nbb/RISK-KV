// Host-side observation only. No model arithmetic or input-memory writes.
#include <cstdio>
#include <cstdlib>
#include <string>
extern "C" void rkv_m1_progress(const char* directory, const char* event,
                                unsigned long long cycle, unsigned int built) {
    const std::string base = std::string(directory) + "/live-progress.json";
    const std::string temporary = base + ".tmp";
    FILE* file = std::fopen(temporary.c_str(), "w");
    if (!file) std::abort();
    if (std::fprintf(file, "{\"status\":\"running\",\"event\":\"%s\",\"cycles\":%llu,\"built_tokens\":%u}\n",
                     event, cycle, built) < 0 || std::fclose(file) != 0) std::abort();
    if (std::rename(temporary.c_str(), base.c_str()) != 0) std::abort();
}
