# 04 · Interview Drill

Answer out loud first, then open the answer. Answers are the length a strong senior candidate gives before the interviewer asks for more.

---

<details><summary><b>Q01.</b> Why did SMMUv3 move configuration into memory?</summary>

v2's register context banks capped the number of concurrently live streams. Systems with thousands of PCIe functions and many processes per device need every stream always configured, because DMA can start at any time. In-memory Stream Table and CD tables scale with memory; the SMMU caches what is hot. Cost: v3 is not backward compatible with v2.
</details>

<details><summary><b>Q02.</b> Walk me through a translation from transaction to PA.</summary>

SID → STE (linear or 2-level stream table). Check V and Config. If S1 is on, SSID → CD (through S2 if nested). Look up the TLB with StreamWorld/VMID/ASID/VA. On a miss, S1 walk with each table address translated by S2, then S2 walk of the output IPA. Apply permissions, attributes, MPAM, GPC. Emit PA, or record a fault.
</details>

<details><summary><b>Q03.</b> How many memory accesses does a cold nested walk take?</summary>

`(n+1)(m+1) − 1`: 24 for 4×4, plus the STE and CD fetches (the CD fetch itself needs an S2 walk when nested). Walk caches and S2 caching exist to cut this. Proven in `code/tests/test_smmu_model.py::test_nested_walk`.
</details>

<details><summary><b>Q04.</b> What does CMD_SYNC guarantee?</summary>

When it completes, all earlier commands have completed including their effect on in-flight transactions: nothing will use an invalidated config or translation, and outstanding ATC invalidations are done. Completion is signalled by MSI, SEV, or CONS moving past it.
</details>

<details><summary><b>Q05.</b> Why ATC invalidation after SMMU TLB invalidation?</summary>

If the ATC is cleared first, the device can send a new Translation Request that hits the still-stale SMMU TLB and refills its ATC with the old mapping. TLBI → SYNC → ATC_INV → SYNC closes that window.
</details>

<details><summary><b>Q06.</b> Stall vs terminate?</summary>

Stall holds the faulting transaction so software can fix the mapping and `CMD_RESUME`: demand paging for devices that tolerate latency. Terminate aborts (or RAZ/WI) immediately. Never stall PCIe: stalled posted writes can deadlock the fabric. PCIe uses ATS + PRI instead.
</details>

<details><summary><b>Q07.</b> What happens when the Event queue is full?</summary>

Non-stall events are discarded and overflow is flagged by toggling `PROD.OVFLG`. Stall events are not discarded: the transaction waits, retries, or records later when the queue becomes writable. `Config=abort` and prefetch errors never record anyway.
</details>

<details><summary><b>Q08.</b> How does SVA (Shared Virtual Addressing) work with an SMMU?</summary>

The device's PASID selects a CD whose TTB0 and ASID are the process's own page tables and ASID. With BTM the SMMU snoops CPU TLBIs, so the kernel's normal munmap path also cleans SMMU TLBs. With ATS/PRI the device can fault pages in on demand.
</details>

<details><summary><b>Q09.</b> What is a StreamWorld?</summary>

The translation regime of a stream (NS-EL1, EL2, EL2-E2H, Secure, EL3), from STE.STRW and Security state. It tags TLB entries so TLBI commands and broadcasts hit only their target regime, the same as CPU TLB regime tagging.
</details>

<details><summary><b>Q10.</b> Which SMMU bug worries you most, and how would you catch it?</summary>

A walk in flight across an invalidation that fills a stale TLB entry after CMD_SYNC completed. It gives a wrong PA silently. Catch with an invalidation-aware scoreboard, directed race tests with controllable memory latency, and coverage that the TLBI scope overlapped in-flight walks.
</details>

<details><summary><b>Q11.</b> How do you build a reference model when caching makes outcomes non-deterministic?</summary>

Keep a timestamped history of table and config writes. For each transaction, the legal translations are those from versions alive between its arrival and the last completed sync that covers them. Pass if the DUT's result is in that set. See `smmu_scoreboard` in `code/sv/smmu_dv_pkg.sv`.
</details>

<details><summary><b>Q12.</b> What is split-stage ATS?</summary>

`STE.EATS=0b10`: ATS completions return the stage-1 result (IPA). Translated transactions still get stage 2 in the SMMU, so the hypervisor keeps VM isolation while the device caches guest translations.
</details>

<details><summary><b>Q13.</b> How does RME change the SMMU?</summary>

Adds a Root programming interface and Granule Protection Checks on every output PA against the GPT, the same structure the CPUs use. A GPC fault on a client access returns like an external abort and is not recorded in the Event queue. RME DA adds the Realm interface and DPT for ATS Translated traffic.
</details>

<details><summary><b>Q14.</b> Compare a CPU MMU, an SMMU and a GPU MMU.</summary>

CPU MMU: context from system registers, synchronous precise faults, TLBI + DSB + ISB. SMMU: context from transaction IDs and in-memory tables, asynchronous faults through queues, command-based maintenance, thousands of streams, ATS/PRI. GPU MMU (vendor-specific): very high parallel miss rates, large pages, often replayable faults through a fault buffer, frequently sits alongside an SMMU for system isolation.
</details>

<details><summary><b>Q15.</b> How would you verify the command queue alone?</summary>

Random command streams with random PROD updates, sizes and wrap points; SVA for full/empty and pointer stepping; illegal opcodes and read aborts at every position to check CONS.ERR, GERROR and restart; cover all CMD_SYNC completion modes. Example SVA: `code/sv/smmu_queue_ptr.sv`.
</details>

<details><summary><b>Q16.</b> What does SMMUEN=0 do?</summary>

Translation is off. Transactions follow `SMMU_GBPA`: bypass with overridden attributes, or abort. Queues can still be enabled (SMMUEN=0 does not imply EVENTQEN=0). Clearing SMMUEN terminates stalled transactions.
</details>

<details><summary><b>Q17.</b> How do you make one testbench cover many SMMU configurations?</summary>

Read IDR0–IDR6, AIDR and the S_/R_/ROOT_ ID registers at test start; use them to constrain stimulus, enable checkers and select coverage. Run a regression matrix across RTL parameter sets so each optional feature is exercised present and absent.
</details>

<details><summary><b>Q18.</b> What is the contiguous bit and why does it matter for verification?</summary>

A hint that a group of adjacent entries (16 for 4KB) map an aligned contiguous region with identical attributes, so one TLB entry can cover it. If software misprograms it, results are constrained-unpredictable but must stay within legal outcomes. Cover TLBI of one page inside a contiguous range.
</details>

<details><summary><b>Q19.</b> Why can't you just reuse the CPU's MMU checker for the SMMU?</summary>

Context comes from transaction IDs not registers, maintenance is asynchronous through queues, faults are delivered as events (or stalls) not exceptions, and many streams run in parallel with interleaved invalidations. The page-table walker logic can be shared; the context, caching and fault-delivery checks cannot.
</details>

<details><summary><b>Q20.</b> A test shows a correct PA but the wrong memory attributes on egress. Where do you look?</summary>

Attribute transformation chain: incoming attributes → STE overrides (MTCFG/MemAttr, SHCFG, ALLOCCFG) → S1 MAIR attributes → S2 MemAttr combine (or FWB) → output. Check which stages were enabled, whether S2FWB is on, and whether a TLB entry cached attributes from an older mapping.
</details>

---

## Behavioural framing

Use STAR with an MMU bug story you can defend in detail:

* **Situation:** nested translation block, random regression stable.
* **Task:** close coverage on invalidation races.
* **Action:** added a latency knob on the table-walk memory port, wrote a directed TLBI-during-walk sequence, made the scoreboard invalidation-aware.
* **Result:** found a stale fill after CMD_SYNC; added the check to every regression.

Only quote numbers and stories you personally measured or lived.

Next: [05 · Cheat sheet](05-cheat-sheet.md)
