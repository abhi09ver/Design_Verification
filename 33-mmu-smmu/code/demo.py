"""Guided tour of the teaching SMMU model. Run:  python3 demo.py

Each step prints what happened and the interview point it illustrates.
"""
from smmu_model import (Access, CD, STE, Memory, PageTableBuilder, Smmu,
                        nested_walk_cost, page_offset, slice_va)
from smmu_model.smmu import NESTED, S1_ONLY


def step(title):
    print(f"\n=== {title}")


def show(r):
    if r.pa is not None:
        return f"PA=0x{r.pa:x}{' (TLB hit)' if r.from_tlb else ''}"
    if r.stalled:
        return f"STALLED, event {r.event.type} stag={r.event.stag}"
    return f"TERMINATED{', event ' + r.event.type if r.event else ' (no event)'}"


step("1. Slice a VA (4KB granule, 48-bit VA)")
va = 0x0000_7F12_3456_7ABC
print(", ".join(f"L{s.level}[{s.hi}:{s.lo}]={s.index}" for s in slice_va(va)),
      f"offset=0x{page_offset(va):x}")

step("2. Stage-1 stream: StreamID 5 -> STE -> CD(ASID 7) -> page tables")
mem = Memory()
pt = PageTableBuilder(mem)
pt.map(0x1000, 0x9000)
pt.map(0x2000, 0xA000, writable=False)
smmu = Smmu(mem)
smmu.stream_table[5] = STE(config=S1_ONLY, cds={0: CD(ttb0=pt.root, asid=7)})
reads = mem.reads
print("read  0x1ABC ->", show(smmu.translate(5, 0x1ABC)), f"[{mem.reads - reads} memory reads]")
reads = mem.reads
print("read  0x1ABC ->", show(smmu.translate(5, 0x1ABC)), f"[{mem.reads - reads} memory reads]")
print("write 0x2000 ->", show(smmu.translate(5, 0x2000, Access(write=True))))
print("read  0x7000 ->", show(smmu.translate(5, 0x7000)))
print("unknown SID 6 ->", show(smmu.translate(6, 0x1000)))

step("3. The classic bug: unmap without TLB invalidation")
pt.unmap(0x1000)
print("after unmap, no TLBI ->", show(smmu.translate(5, 0x1ABC)), "<- stale but legal until TLBI+SYNC")
smmu.submit("CMD_TLBI_NH_VA", asid=7, va=0x1000)
smmu.submit("CMD_SYNC")
smmu.process_commands()
print("after TLBI + SYNC   ->", show(smmu.translate(5, 0x1ABC)))

step("4. Stall model: fault, software fixes the mapping, CMD_RESUME retries")
smmu.stream_table[5].cds[0].stall = True
smmu.submit("CMD_CFGI_CD", sid=5, ssid=0)
smmu.submit("CMD_SYNC")
smmu.process_commands()
r = smmu.translate(5, 0x5000)
print("read 0x5000 ->", show(r))
pt.map(0x5000, 0xB000)
smmu.submit("CMD_RESUME", stag=r.event.stag, retry=True)
print("after RESUME ->", show(smmu.process_commands()[0]))

step("5. Nested translation cost")
mem = Memory()
s1 = PageTableBuilder(mem, alloc_base=0x1000_0000)
s2 = PageTableBuilder(mem, alloc_base=0x7000_0000)
s1.map(0x4000_0000, 0x2000_0000)
for t in range(0x1000_0000, s1.next_table, 0x1000):
    s2.map(t, t)
s2.map(0x2000_0000, 0x3_0000_0000)
smmu = Smmu(mem)
smmu.stream_table[9] = STE(config=NESTED, vmid=3, s2_ttb=s2.root, cds={0: CD(s1.root, 1)})
reads = mem.reads
print("VA 0x40000123 ->", show(smmu.translate(9, 0x4000_0123)),
      f"[{mem.reads - reads} reads; formula (4+1)(4+1)-1 = {nested_walk_cost(4, 4)}]")
