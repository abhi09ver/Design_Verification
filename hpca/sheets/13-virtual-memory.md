# Lesson 13 · Virtual memory

6 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Why virtual memory](#l13-01-why-virtual-memory)
2. [Pages, frames and the page table](#l13-02-pages-frames-and-the-page-table)
3. [Multi-level page tables](#l13-03-multi-level-page-tables)
4. [The TLB](#l13-04-the-tlb)
5. [Page faults](#l13-05-page-faults)
6. [Protection and sharing](#l13-06-protection-and-sharing)

---

## L13-01 Why virtual memory

*Why virtual memory*

> Each program sees its own large, private address space; the OS and hardware map it onto real memory in pages.

**Concepts**

- Programmer’s view: huge flat memory, private per process, code/data/heap/stack where it wants.
- Machine’s view: limited physical memory shared by many processes, plus disk.
- Virtual memory maps virtual pages to physical frames, or to disk when not resident.
- Benefits: isolation and protection, sharing (shared libraries), more memory than DRAM, simpler loading.

**Numbers & formulas:** `virtual page → physical frame`

**Verification lens**

- Translation sits on every instruction fetch and data access, so MMU bugs are both functional (wrong data, missed fault) and security bugs (access across processes).

**Interview**

<details><summary>Two processes use virtual address 0x1000. How can both work?</summary>

Each has its own page table, so the same virtual page maps to different physical frames (or the same frame, for shared pages).

</details>

---

## L13-02 Pages, frames and the page table

*Pages · page table · translation*

> Split addresses into page number and page offset; the page table maps virtual page number to physical frame number.

**Concepts**

- Page size typically **4 KB** (12 offset bits); larger pages (2 MB, 1 GB) exist.
- VA = VPN | offset. PA = PFN | same offset.
- Page table entry (PTE): valid, frame number, permissions (R/W/X/User), accessed, dirty.
- The page table base register points at the current process’s table (CR3, satp, TTBR).

**Numbers & formulas:** `4 KB → 12-bit offset` · `PA = PFN ‖ offset`

**Worked**

| Problem | Answer |
| --- | --- |
| 32-bit VA, 4 KB pages | 20-bit VPN, 1 M entries |

**Verification lens**

- Random page-table generators: random mappings, mixed page sizes, aliases (two VAs → one PA), invalid and permission-restricted pages.

**Interview**

<details><summary>What changes between VA and PA?</summary>

Only the page number; the offset within the page is copied unchanged.

</details>

---

## L13-03 Multi-level page tables

*Page table size · multi-level page tables*

> A flat table is too big; a tree of tables only allocates the parts the program uses.

**Concepts**

- Flat: 32-bit VA, 4 KB pages, 4 B PTE → 2²⁰ × 4 B = **4 MB per process**. For 64-bit VA it is impossible.
- Multi-level: the VPN is split into fields; each indexes one level; unused subtrees are not allocated.
- x86-64 / RISC-V Sv48: 4 levels of 9 bits + 12-bit offset = 48-bit VA.
- Cost: a miss needs one memory access per level (4), more under virtualisation.

**Numbers & formulas:** `walk = 1 access / level`

**Worked**

| Problem | Answer |
| --- | --- |
| Flat table, 32-bit VA, 4 KB, 4 B PTE | 4 MB |
| Sv48 levels | 4 × 9 + 12 = 48 bits |

**Verification lens**

- Superpage leaves at upper levels (2 MB, 1 GB) are a top source of walker bugs: misaligned superpages must fault; offset bits widen.

**Bugs that ship**

- Misaligned superpage PPN accepted instead of faulting
- Walker reads a non-leaf PTE with R/W/X set as a pointer

**Interview**

<details><summary>Why does a multi-level table save memory?</summary>

Only the paths that map real pages exist. A small program touches a few leaf tables and one path of upper levels instead of a full 4 MB table.

</details>

---

## L13-04 The TLB

*Fast translation · TLB*

> A small cache of recent translations so most accesses skip the page walk.

**Concepts**

- TLB entry: VPN tag → PFN + permissions (+ ASID/PCID, global bit).
- Small (64–128 L1 entries), often highly associative; larger L2 TLB (1–2K entries).
- **TLB reach** = entries × page size: 64 × 4 KB = 256 KB. Huge pages extend it.
- Miss → hardware page walk (most ISAs) or software trap (some MIPS).

**Numbers & formulas:** `reach = entries × page`

**Worked**

| Problem | Answer |
| --- | --- |
| 64 entries × 4 KB | 256 KB reach |
| 64 entries × 2 MB | 128 MB reach |

**Verification lens**

- TLB coherence is software-managed: after the OS changes a PTE it must issue a fence/invalidate. Verify the invalidate removes matching entries and races correctly with walks in flight.

**Bugs that ship**

- In-flight walk refills a TLB entry after the invalidate
- ASID-filtered flush also drops global entries (or misses them)

**Interview**

<details><summary>Why tag TLB entries with an ASID?</summary>

So a context switch need not flush the TLB. Entries of different processes coexist; only matching ASIDs (or global entries) hit.

</details>

---

## L13-05 Page faults

*Page faults · OS role*

> A missing or forbidden translation traps precisely; the OS loads the page or kills the access, then the instruction re-executes.

**Concepts**

- Invalid PTE → page fault: OS picks a frame (evicting if needed), reads the page from disk, updates the PTE, returns.
- Permission violation (write to read-only, user to kernel) → access fault.
- Faults must be **precise**: the faulting instruction re-executes after the handler.
- Accessed/dirty bits help the OS choose victims and know what to write back.

**Numbers & formulas:** `fault → handler → re-execute`

**Verification lens**

- Fault priority and cause encoding must match the spec exactly (page fault vs access fault vs misaligned). Cover faults on fetch, load, store, page-crossing accesses and during a page walk itself.

**Interview**

<details><summary>A load crosses a page boundary; the second page is unmapped. What happens?</summary>

The whole load faults with the address of the second page (per ISA), and no part of it is visible. The first half must not have forwarded or written anything architectural.

</details>

---

## L13-06 Protection and sharing

*Protection · sharing*

> PTE permission bits enforce isolation; mapping one frame into several page tables gives sharing.

**Concepts**

- Bits: valid, read, write, execute, user/supervisor, global, accessed, dirty.
- Shared libraries: one physical copy mapped read-only/execute into many processes.
- Copy-on-write: share read-only, copy on the first write fault.
- Synonyms/aliases: two VAs map to one PA (matters for virtually indexed caches).

**Numbers & formulas:** `V R W X U G A D`

**Verification lens**

- Security-relevant: speculative execution must not leak data across permission boundaries (Meltdown). Verify faulting loads return no data to dependents, even speculatively, where the spec requires it.

**Interview**

<details><summary>What is Meltdown in one sentence, and what does DV check?</summary>

A faulting kernel-address load forwarded data to dependent instructions speculatively, leaking it through the cache. DV checks that permission failures squash data before any dependent can use it.

</details>
