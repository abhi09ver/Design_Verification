// bench.c -- a small mixed integer workload for CPI measurements on the Lab 3 pipeline.
// Kernels: insertion sort, bitwise CRC-32, linked-list walk, string search, recursive fib.
// Built for rv32i (no M extension): no multiplies or divides anywhere.
#include <stdint.h>
#ifndef EXPECT
#define EXPECT 0
#endif
#define N 48
static uint32_t a[N];
static uint8_t buf[256];
struct node { struct node *next; uint32_t v; };
static struct node nodes[64];
static uint32_t seed = 12345;
static uint32_t rnd(void) { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed; }

static void isort(uint32_t *x, int n) {
  for (int i = 1; i < n; i++) { uint32_t k = x[i]; int j = i - 1;
    while (j >= 0 && x[j] > k) { x[j + 1] = x[j]; j--; } x[j + 1] = k; }
}
static uint32_t crc32(const uint8_t *p, int n) {
  uint32_t c = 0xFFFFFFFF;
  for (int i = 0; i < n; i++) { c ^= p[i]; for (int b = 0; b < 8; b++) c = (c >> 1) ^ (0xEDB88320 & -(c & 1)); }
  return ~c;
}
static uint32_t walk(void) {
  for (int i = 0; i < 64; i++) { nodes[i].v = rnd() & 0xFFFF; nodes[i].next = &nodes[(i * 37 + 11) & 63]; }
  uint32_t s = 0; struct node *p = &nodes[0];
  for (int i = 0; i < 200; i++) { s += p->v; p = p->next; }
  return s;
}
static int find(const char *h, const char *n) {
  for (int i = 0; h[i]; i++) { int j = 0; while (n[j] && h[i + j] == n[j]) j++; if (!n[j]) return i; }
  return -1;
}
static uint32_t fib(uint32_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

uint32_t run(void) {
  for (int i = 0; i < N; i++) a[i] = rnd();
  isort(a, N);
  uint32_t ok = 1;
  for (int i = 1; i < N; i++) ok &= a[i - 1] <= a[i];
  for (int i = 0; i < 256; i++) buf[i] = (uint8_t)rnd();
  uint32_t c = crc32(buf, 256);
  uint32_t w = walk();
  int f = find("the quick brown fox jumps over the lazy dog, the lazy dog sleeps", "lazy dog s");
  return ok + (c ^ w) + (uint32_t)f + fib(15) + a[N / 2];
}
#ifdef HOST
#include <stdio.h>
int main(void) { printf("0x%08x\n", run()); return 0; }
#else
int main(void) { return run() == EXPECT ? 1 : 3; }
#endif
