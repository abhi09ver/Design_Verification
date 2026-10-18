#include <cstdio>
#include <cstdint>
#include <vector>
extern "C" { void init(); void step(int); uint32_t model_pc(); uint32_t model_reg(int); }
int main(int, char** v){ std::vector<uint32_t> w; FILE*f=fopen(v[1],"r"); unsigned t; while(fscanf(f,"%x",&t)==1) w.push_back(t);
  init(); uint32_t pc=model_pc(); for(int n=0;n<100000;n++){ uint32_t i = pc/4<w.size()? w[pc/4]:0x13; if(i==0x6f) break; step(int(i)); pc=model_pc(); }
  for(int r=0;r<32;r++) printf("%08x\n", model_reg(r)); }
