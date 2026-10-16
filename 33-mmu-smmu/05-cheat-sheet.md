# 05 · One-Page Cheat Sheet

Read this 10 minutes before the interview.

## Numbers

| Thing | Value |
|---|---|
| Version register | `SMMU_AIDR[7:0]` 0x00…0x05 → v3.0…v3.5 |
| Structure sizes | STE 64B · CD 64B · L1STD 8B · L1CD 8B |
| Queue entry sizes | Command 16B · Event 32B · PRI 16B |
| ID widths | StreamID ≤ 32b · SubstreamID ≤ 20b · ASID 8/16b · VMID 8/16b |
| Stream table | Linear or 2-level, SPLIT = 6 / 8 / 10 |
| 4KB, 48-bit VA | L0[47:39] L1[38:30] L2[29:21] L3[20:12] off[11:0]; blocks 1GB, 2MB |
| 64KB, 48-bit VA | L1[47:42] L2[41:29] L3[28:16] off[15:0]; block 512MB |
| Nested cold walk | (n+1)(m+1) − 1 → **24** for 4×4 |

## Rules

| Rule | |
|---|---|
| Queue empty | PROD == CONS |
| Queue full | IDX equal, WRAP differs |
| Global error active | `GERROR.x != GERRORN.x` |
| Events per transaction | At most one (config error **or** translation fault) |
| Never reported | `Config=abort`, prefetch errors, GPC fault on client output PA (→ `ROOT_GPF_FAR`) |
| Change STE | write → `CFGI_STE` → `SYNC` |
| Change CD | write → `CFGI_CD` → `SYNC` |
| Unmap page | PTE → `TLBI` → `SYNC` → `ATC_INV` → `SYNC` |
| Enable order | tables + queues → CR1/CR2 → CMDQEN, EVTQEN, PRIQEN → invalidate all → SMMUEN (poll CR0ACK each time) |
| Don't stall PCIe | Use ATS + PRI |
| TLB tag | StreamWorld + VMID + ASID + VA (not StreamID) |

## STE.Config

`000` abort (silent) · `100` bypass · `101` S1 · `110` S2 · `111` nested

## Event IDs to know

`0x02 C_BAD_STREAMID` · `0x04 C_BAD_STE` · `0x08 C_BAD_SUBSTREAMID` · `0x0A C_BAD_CD` · `0x0B F_WALK_EABT` · `0x10 F_TRANSLATION` · `0x11 F_ADDR_SIZE` · `0x12 F_ACCESS` · `0x13 F_PERMISSION` · `0x20 F_TLB_CONFLICT`

## Commands to know

`0x03 CFGI_STE` · `0x05 CFGI_CD` · `0x12 TLBI_NH_VA` · `0x28 TLBI_S12_VMALL` · `0x2A TLBI_S2_IPA` · `0x40 ATC_INV` · `0x41 PRI_RESP` · `0x44 RESUME` · `0x45 STALL_TERM` · `0x46 CMD_SYNC`

## The five sentences

1. SMMU = MMU for devices; StreamID → STE → SubstreamID → CD → page tables.
2. Config and queues live in memory; the SMMU caches config, so edits need CFGI + SYNC.
3. Stage 1 is the OS's (ASID), stage 2 the hypervisor's (VMID); nesting multiplies walk cost.
4. Faults go to the Event queue; stall + RESUME for tolerant devices, ATS + PRI for PCIe.
5. The bug that matters most is a stale translation used after CMD_SYNC; check it with an invalidation-aware scoreboard.
