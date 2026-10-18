# 35 · Arm GIC (Generic Interrupt Controller) — Cheat Sheet

One-stop revision sheet for GICv3 / GICv4 interviews (Senior CPU DV, e.g. NVIDIA / Arm / Qualcomm).
Built from **Arm IHI 0069H.b** (GICv3.3 / GICv4.2, April 2024).

**Companion material in [`35-gic/`](35-gic/):**

| File | What it is |
|---|---|
| [`35-gic/pages/gic-from-zero.html`](35-gic/pages/gic-from-zero.html) | Beginner page: 14 levels with everyday stories, diagrams, quiz checks and a clickable "be the CPU" simulator |
| [`35-gic/pages/gic-field-guide.html`](35-gic/pages/gic-field-guide.html) | Senior page: architecture diagrams, ITS/v4 detail, bug-hunt list, 16 interview Q&As, 60-second pitch |
| [`35-gic/code/python/gic_ref_model.py`](35-gic/code/python/gic_ref_model.py) | Small readable GICv3 reference model (state machine, priority, routing, sleep, mini ITS) |
| [`35-gic/code/python/test_gic_ref_model.py`](35-gic/code/python/test_gic_ref_model.py) | 21 unit tests, one per interview corner case |
| [`35-gic/code/sv/gic_cpu_if_sva.sv`](35-gic/code/sv/gic_cpu_if_sva.sv) | SVA checker: masking, liveness, spurious IAR, WAKER handshake, ITS queue + covers |
| [`35-gic/code/sv/gic_scoreboard_pkg.sv`](35-gic/code/sv/gic_scoreboard_pkg.sv) | UVM scoreboard that checks IAR against the **set** of legal answers |

Open the HTML pages in any browser (download the file, double-click). Run the model tests with `cd 35-gic/code/python && python3 -m unittest -v`.

---

## 1. The picture to draw first

```
 wired devices ──► Distributor (GICD_*)  ── SPIs ──┐
 MSI devices  ──► ITS (GITS_*) ── LPIs ────────────┤
                    │ tables in memory             ▼
 software SGIs ─────────────────────────► Redistributor (GICR_*)  one per PE
                                                   │  GIC Stream Protocol
                                                   ▼
                                     CPU interface (ICC_/ICH_/ICV_ sysregs) ──► IRQ / FIQ
```

* **Distributor**: one per system. Config + state for SPIs; routing via `GICD_IROUTER<n>`.
* **Redistributor**: one per PE. SGIs, PPIs, LPIs; picks the HPPI for its PE; `GICR_WAKER`.
* **CPU interface**: inside the core. Group enables, PMR, running priority, IAR/EOIR/DIR.
* **ITS**: translates `(DeviceID, EventID)` → `(LPI INTID, target RD)`.

## 2. INTID map

| INTID | Type | Owner |
|---|---|---|
| 0–15 | SGI | Redistributor (per PE) |
| 16–31 | PPI | Redistributor (per PE) |
| 32–1019 | SPI | Distributor |
| 1020–1023 | Special | 1020/1021 EL3 hints, 1022 NMI (v3.3), **1023 spurious** |
| 1056–1119 | Extended PPI (v3.1) | Redistributor |
| 4096–5119 | Extended SPI (v3.1) | Distributor |
| 8192+ | LPI | RD + memory tables |

## 3. State machine

`Inactive → Pending (assert) → Active (IAR read) → Inactive (EOI/DIR)`;
new edge while Active → **Active & Pending**. Level still high at IAR → Active & Pending.
**LPIs have no Active state**; IAR clears pending, EOIR still does the priority drop.

## 4. Groups → IRQ or FIQ

| Group (IGROUPR/IGRPMODR) | PE in Secure EL1/2 | PE Non-secure | PE at EL3 |
|---|---|---|---|
| Group 0 (0/0) | FIQ | FIQ | FIQ |
| Secure G1 (0/1) | **IRQ** | FIQ | FIQ |
| Non-secure G1 (1/0) | FIQ | **IRQ** | FIQ |

Rule: "your world → IRQ, other world → FIQ (to EL3)". NS priority view: stored as `(p>>1)|0x80`.

## 5. Priority

* 8-bit, **lower = more urgent**. ≥32 levels with two Security states, ≥16 with one.
* Signalled only if: group enabled **and** `prio < PMR` **and** group-priority `< running priority`.
* `ICC_BPR0/1` splits group priority (preempts) from subpriority (orders only).
* Active priorities: one bit per level in `ICC_AP0Rn/AP1Rn`; EOIs must be nested (reverse order).
* `EOImode=1`: EOIR = priority drop only, `ICC_DIR_EL1` = deactivate (used by Linux and hypervisors).
* NMI (v3.3): superpriority, ack with `ICC_NMIAR1_EL1`, masked by `PSTATE.ALLINT`.

## 6. Routing & SGIs

* `IROUTER.IRM=0` → exact Aff3.Aff2.Aff1.Aff0; `IRM=1` → any one participating PE (IMP DEF choice).
* SGIs: `ICC_SGI1R_EL1` / `ASGI1R` / `SGI0R` with TargetList + RS + Aff fields; `IRM=1` = all except self.

## 7. LPIs & ITS

* LPI config table (`GICR_PROPBASER`, 1 byte/LPI) and pending table (`GICR_PENDBASER`, 1 bit/LPI).
* Lookup: Device table[DeviceID] → ITT[EventID] → (INTID, ICID) → Collection table[ICID] → RD.
* Command queue: `GITS_CBASER` ring, `GITS_CWRITER` (SW), `GITS_CREADR` (ITS), 32-byte commands.
* Commands: MAPD, MAPC, MAPTI/MAPI, MOVI, MOVALL, INT, CLEAR, DISCARD, INV, INVALL, SYNC; v4: VMAPP, VMAPTI, VMOVI, VMOVP, VSYNC, VINVALL; v4.1: VSGI, INVDB.
* Config edits need **INV/INVALL + SYNC** to be guaranteed visible.

## 8. Virtualization

* v3: hypervisor writes `ICH_LR<n>_EL2` (vINTID, pINTID, HW, group, prio, state); VM uses `ICV_*`.
  HW=1 → VM's EOI deactivates the physical interrupt. Maintenance interrupt (PPI 25): UIE, NPIE, LRENPIE, VGrp*.
* v4.0: direct vLPI injection into the vPE's pending table; non-resident vPE → **doorbell**.
* v4.1: direct vSGIs, per-vPE default doorbell. v4.2: virtual NMIs.

## 9. Power

`GICR_WAKER`: set `ProcessorSleep` → wait `ChildrenAsleep=1` → power off. While asleep, interrupts raise a wake request. Wake: clear `ProcessorSleep`, wait `ChildrenAsleep=0`.

## 10. Verification mindset (say this)

1. **Predict a set of legal outcomes**, not one (timing, Clear-vs-IAR races, 1-of-N are open in the spec).
2. **Check at architectural points**: IAR value, IRQ/FIQ pins, register readback, memory written by the GIC.
3. **Cut at the GIC Stream Protocol** for block-level throughput; SVA on the handshake.
4. **Stress the races**: config writes vs traffic, ITS commands vs in-flight MSIs, power vs arrivals.
5. **Run many configs**: DS=1, no ITS, 1 PE, max PEs, odd IDbits, each GICv4.x level.
6. Final gate: Linux `irq-gic-v3` / TF-A boot with interrupt stress.

## 11. Top corner cases (have 3–4 as stories)

| Scenario | Must hold |
|---|---|
| Level SPI drops after ack, before EOI | Active only, no re-fire |
| Edge during IAR read | Active & Pending, fires once more |
| PMR raised while IRQ high | IRQ drops; IAR gives 1023 or old INTID |
| 1-of-N SPI, chosen PE sleeps | Re-routed or wake request, never stuck, never taken twice |
| MOVI with LPI pending, MSI racing | Exactly one pending instance on the new RD after SYNC |
| LPI config edited without INV | Old or new until INV/SYNC, then new |
| Command queue full / wrap | No overrun, correct wrap at CBASER.Size |
| vPE descheduled with vLPI in flight | In VPT or doorbell, never lost |
| NS write to Secure field | RAZ/WI, no side effects |

## 12. 60-second pitch

> GICv3 has four blocks. The Distributor owns shared SPIs; a Redistributor per core owns SGIs, PPIs and memory-backed LPIs; the ITS turns device MSIs into LPIs through Device, ITT and Collection tables driven by a command queue; the CPU interface lives in system registers and applies group, PMR and running-priority checks before raising IRQ or FIQ based on group and Security state. Software acks with IAR and ends with EOIR, optionally split from DIR. v3 virtualizes with list registers; v4 injects vLPIs and vSGIs directly. To verify it I model the set of outcomes the spec allows, check at architectural observation points, cut at the stream protocol for block-level speed, and focus stress on races between config, ITS commands, power and traffic.

## 13. Self-check

- [ ] Draw the 4-block diagram and name each register prefix
- [ ] Recite the INTID ranges including 1020–1023 meanings
- [ ] Fill the IRQ/FIQ table from memory
- [ ] Work a PMR + BPR + preemption example
- [ ] Explain EOImode=1 and the HW=1 list register
- [ ] Walk an MSI through the three ITS tables
- [ ] Explain why a GIC scoreboard must accept a set of answers
- [ ] Describe two GIC bugs you would target and how you would catch them
