// ------------------------------------------------------------------
// YARP RV32I reference model (C++) behind the course DPI API
//   init()                                   reset the architectural state
//   step(instr)                              execute one instruction at the model PC
//   compare_instruction_address(addr)        addr == PC of the last stepped instruction
//   compare_data_memory_access(a,be,wr,wd)   matches the access the last instruction made
//   compare_architecture_register(i,v)       x[i] == v
// Returns 1 on match, 0 on mismatch (and prints expected vs actual).
// Policy (must match the RTL): no traps. Misaligned data accesses are done
// byte-by-byte, JALR clears bit 0, branch/JAL targets are not checked.
// ------------------------------------------------------------------
#include <cstdint>
#include <cstdio>
#include <unordered_map>

#ifndef YARP_RESET_PC
#define YARP_RESET_PC 0x1000u
#endif

namespace {
uint32_t x[32], pc, last_pc, last_instr;
std::unordered_map<uint32_t, uint8_t> mem;
struct Acc { bool valid, wr; uint32_t addr, size, wdata; } acc;
uint64_t steps = 0;

uint32_t ld(uint32_t a, int n) { uint32_t v = 0; for (int i = 0; i < n; i++) { auto it = mem.find(a + i); v |= uint32_t(it == mem.end() ? 0 : it->second) << (8 * i); } return v; }
void     st(uint32_t a, uint32_t v, int n) { for (int i = 0; i < n; i++) mem[a + i] = (v >> (8 * i)) & 0xff; }
int32_t  sx(uint32_t v, int b) { return int32_t(v << (32 - b)) >> (32 - b); }
}

extern "C" void init() {
  for (auto &r : x) r = 0;
  pc = YARP_RESET_PC; last_pc = pc; mem.clear(); acc = {}; steps = 0;
}

extern "C" void step(int instruction) {
  uint32_t i = uint32_t(instruction), op = i & 0x7f, rd = (i >> 7) & 31, f3 = (i >> 12) & 7,
           rs1 = (i >> 15) & 31, rs2 = (i >> 20) & 31, f7 = i >> 25;
  uint32_t a = x[rs1], b = x[rs2], nxt = pc + 4, res = 0; bool wb = false;
  int32_t immI = sx(i >> 20, 12), immS = sx(((i >> 25) << 5) | ((i >> 7) & 31), 12);
  int32_t immB = sx(((i >> 31) << 12) | (((i >> 7) & 1) << 11) | (((i >> 25) & 63) << 5) | (((i >> 8) & 15) << 1), 13);
  int32_t immJ = sx(((i >> 31) << 20) | (((i >> 12) & 255) << 12) | (((i >> 20) & 1) << 11) | (((i >> 21) & 1023) << 1), 21);
  auto alu = [&](uint32_t fn3, uint32_t p, uint32_t q, bool alt) -> uint32_t {
    switch (fn3) {
      case 0: return alt ? p - q : p + q;
      case 1: return p << (q & 31);
      case 2: return int32_t(p) < int32_t(q);
      case 3: return p < q;
      case 4: return p ^ q;
      case 5: return alt ? uint32_t(int32_t(p) >> (q & 31)) : p >> (q & 31);
      case 6: return p | q;
      default: return p & q;
    }
  };
  acc = {};
  switch (op) {
    case 0x33: res = alu(f3, a, b, f7 & 0x20); wb = true; break;
    case 0x13: res = alu(f3, a, uint32_t(immI), f3 == 5 && (f7 & 0x20)); wb = true; break;
    case 0x03: {
      uint32_t ad = a + immI; int n = (f3 & 3) == 0 ? 1 : (f3 & 3) == 1 ? 2 : 4;
      uint32_t v = ld(ad, n);
      res = (f3 & 4) || n == 4 ? v : uint32_t(sx(v, 8 * n)); wb = true;
      acc = {true, false, ad, uint32_t(n), 0}; break; }
    case 0x23: {
      uint32_t ad = a + immS; int n = f3 == 0 ? 1 : f3 == 1 ? 2 : 4;
      st(ad, b, n); acc = {true, true, ad, uint32_t(n), b}; break; }
    case 0x63: {
      bool t = false;
      switch (f3) { case 0: t = a == b; break; case 1: t = a != b; break; case 4: t = int32_t(a) < int32_t(b); break;
                    case 5: t = int32_t(a) >= int32_t(b); break; case 6: t = a < b; break; case 7: t = a >= b; break; }
      if (t) nxt = pc + immB; break; }
    case 0x37: res = i & 0xfffff000u; wb = true; break;
    case 0x17: res = pc + (i & 0xfffff000u); wb = true; break;
    case 0x6f: res = pc + 4; nxt = pc + immJ; wb = true; break;
    case 0x67: res = pc + 4; nxt = (a + immI) & ~1u; wb = true; break;
    default: break;  // unknown opcode: NOP (same as the RTL)
  }
  if (wb && rd) x[rd] = res;
  last_pc = pc; last_instr = i; pc = nxt; steps++;
}

extern "C" int compare_instruction_address(int address) {
  if (uint32_t(address) == last_pc) return 1;
  fprintf(stderr, "[MODEL] PC mismatch: RTL fetched 0x%08x, model expected 0x%08x\n", uint32_t(address), last_pc);
  return 0;
}

extern "C" int compare_data_memory_access(int address, int byte_en, int write, int write_data) {
  static const uint32_t sz[4] = {1, 2, 0, 4};
  uint32_t n = sz[byte_en & 3], m = n == 4 ? ~0u : (1u << (8 * n)) - 1;
  bool ok = acc.valid && acc.addr == uint32_t(address) && acc.size == n && acc.wr == bool(write) &&
            (!write || ((uint32_t(write_data) ^ acc.wdata) & m) == 0);
  if (!ok)
    fprintf(stderr, "[MODEL] mem mismatch @pc 0x%08x: RTL {a=%08x sz=%u wr=%d wd=%08x} model {valid=%d a=%08x sz=%u wr=%d wd=%08x}\n",
            last_pc, uint32_t(address), n, write, uint32_t(write_data), acc.valid, acc.addr, acc.size, acc.wr, acc.wdata);
  return ok;
}

extern "C" int compare_architecture_register(int regnum, int value) {
  if (x[regnum & 31] == uint32_t(value)) return 1;
  fprintf(stderr, "[MODEL] x%d mismatch after pc 0x%08x (instr %08x): RTL 0x%08x model 0x%08x\n",
          regnum, last_pc, last_instr, uint32_t(value), x[regnum & 31]);
  return 0;
}
