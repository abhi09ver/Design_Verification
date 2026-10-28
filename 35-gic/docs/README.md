# GIC specification and reading map

| File | What it is |
|---|---|
| [`IHI0069H_b_gic_architecture_specification.pdf`](IHI0069H_b_gic_architecture_specification.pdf) | Arm IHI 0069H.b, *GIC Architecture Specification*, GICv3.3 / GICv4.2 (April 2024, Non-Confidential), 952 pages |
| [`IHI0069H_b_gic_architecture_specification.txt`](IHI0069H_b_gic_architecture_specification.txt) | Plain-text copy of the same PDF for searching (`grep -n "GICR_WAKER" *.txt`). Pages are separated by form-feed characters, so text page *N* = PDF page *N* |

Page numbers below are **PDF page numbers** (what your viewer's "go to page" box expects), not the printed `4-56` style numbers.

## Chapters

| Chapter | PDF pages | Read it for | Kit section |
|---|---|---|---|
| 1 Introduction | 17–32 | Version history (v3.0 → v4.2), terminology | Field Guide §01 |
| 2 Distribution and Routing | 33–40 | INTID map (Table 2-1, p.35), special INTIDs, affinity routing, 1-of-N | §02, §06 |
| 3 GIC Partitioning | 41–48 | Distributor / Redistributor / CPU interface / ITS split | §01 |
| 4 Physical Handling & Prioritization | 49–84 | State machine (p.56), groups & security, superpriority/NMI (p.66), preemption & masking (p.71–72) | §03, §04, §05 |
| 5 LPIs and the ITS | 85–150 | LPI tables, ITS tables, command list (table at p.101), command queue | §07 |
| 6 Virtual Interrupt Handling | 151–162 | List registers, maintenance interrupts (p.153) | §08 |
| 7 GICv4.0 Virtual LPIs | 163–166 | Direct injection, vPE scheduling, doorbells | §08 |
| 8 GICv4.1 Virtual Interrupts | 167–178 | vSGIs, vPE table changes | §08 |
| 9 Memory Partitioning and Monitoring | 179–184 | MPAM tagging (rarely asked) | — |
| 10 Armv8-R AArch64 PEs | 185–186 | GICv3.2 R-profile support (rarely asked) | — |
| 11 Power Management | 187–188 | GICR_WAKER handshake | §09 |
| 12 Programmers' Model | 189–854 | Every register; look up exact field encodings here | §10 |
| 13 Pseudocode | 855–874 | Priority/masking functions you can port into a reference model | §12 |
| 14 System Error Reporting | 875–876 | Error handling | §11 |
| 15 Legacy Operation | 877–884 | ARE=0 / GICv2 compatibility | §06 |
| Appendix A GIC Stream Protocol | 885–912 | Redistributor ↔ CPU interface packets (Set at p.906) | §09 |
| Appendix B Pseudocode Definition | 913–942 | Pseudocode language | — |
| Glossary | 943–952 | Terms | — |

## Registers you will be asked about

| Register | PDF page |
|---|---|
| `ICC_IAR1_EL1` (acknowledge) | 255 |
| `ICC_PMR_EL1` (priority mask) | 267 |
| `ICH_LR<n>_EL2` (list registers) | 353 |
| `GICD_IROUTER<n>` (SPI routing) | 534 |
| `GICR_WAKER` (power handshake) | 728 |
| `GITS_CREADR` (ITS command queue) | 833 |

"Kit section" refers to the numbered sections of [`../pages/gic-field-guide.html`](../pages/gic-field-guide.html).
