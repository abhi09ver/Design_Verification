# 33 · MMU and SMMUv3: One-Stop Interview Kit

Everything for MMU / SMMU interviews (Senior CPU / SoC DV, NVIDIA-style), built from Arm IHI 0070 H.a (*SMMU Architecture Specification*, SMMUv3.0–v3.5).

## Reading order

| # | File | Level | Time |
|---|---|---|---|
| 01 | [MMU From Zero](01-mmu-from-zero.md) | Fresher: hotel/sticky-note analogies, 14 levels | 45 min |
| 02 | [SMMUv3 Deep Dive](02-smmuv3-deep-dive.md) | Senior: STE/CD, commands, events, ATS/PRI, RME, microarchitecture | 90 min |
| 03 | [Verification Playbook](03-verification-playbook.md) | Testbench, checkers, coverage, scenarios, sign-off | 45 min |
| 04 | [Interview Drill](04-interview-drill.md) | 20 questions with model answers | 30 min |
| 05 | [Cheat Sheet](05-cheat-sheet.md) | One page, read right before the interview | 10 min |

## Interactive pages (open in any browser, work offline)

| Page | What's inside |
|---|---|
| [`html/mmu-from-zero.html`](html/mmu-from-zero.html) | Beginner path with toys: address splitter, "be the MMU", TLB sticky-note simulator, 6-question quiz |
| [`html/smmuv3-field-guide.html`](html/smmuv3-field-guide.html) | Senior guide with schematic diagrams, VA slicer, nested-walk calculator, 18 collapsible Q&A |

GitHub shows `.html` files as source. To view them: download and open locally, or enable GitHub Pages on this repo.

## Code ([`code/`](code/))

| Piece | Language | Verified with |
|---|---|---|
| SMMU reference model (STE/CD, S1/S2/nested, TLB, queues, faults, commands) | Python | 24 unittest scenarios |
| Queue pointer RTL + SVA + random testbench + injectable bug | SystemVerilog | Verilator 5.020 (passes clean, fails with bug) |
| UVM transaction, invalidation-aware scoreboard, coverage | SystemVerilog/UVM | Elaborated with slang against Accellera UVM, 0 errors |

```bash
cd 33-mmu-smmu/code && python3 -m unittest discover -s tests -v && python3 demo.py
```

## The five sentences to remember

1. SMMU = MMU for devices; StreamID → STE → SubstreamID → CD → page tables.
2. Config and queues live in memory; the SMMU caches config, so edits need CFGI + SYNC.
3. Stage 1 belongs to the OS (ASID), stage 2 to the hypervisor (VMID); nesting multiplies walk cost (24 reads for 4×4).
4. Faults go to the Event queue; stall + RESUME for tolerant devices, ATS + PRI for PCIe.
5. The bug that matters most is a stale translation used after CMD_SYNC; catch it with an invalidation-aware scoreboard.

## Accuracy note

Field values, opcodes and event IDs come from the spec. The TBU/TCU split, DTI and testbench structure describe common implementation practice, not architecture. Check exact encodings in spec chapters 5–7 before quoting them in a design review.
