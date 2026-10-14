# Challenge 21: Verifying a Protocol Bridge (AXI ↔ PCIe) — End-to-End Scoreboards, Splitting, Errors, Clock Ratios

> **Level:** Fresher → Senior DV interview
> **Topics:** AXI ordering limits (no read-after-write guarantee), AXI4-Lite vs. AXI4, PCIe credit gating vs. credit return policy, LCRC/replay vs. malformed TLPs, bridge architecture, address translation, transaction splitting, byte enables, completion handling, error mapping, end-to-end scoreboard, clock-ratio testing
> **Prerequisite:** [17 – AXI, AHB-Lite, PCIe](17-bus-protocols-axi-ahb-pcie.md)

---

## 1. The Post (summary)

A LinkedIn post lists "three verification patterns Google and NVIDIA use":

1. **AXI/AHB ordering**: a scoreboard for 8–16-beat bursts that proves **read-after-write ordering is preserved**; mention **AXI4-Lite**; sketch a "reorder buffer" model.
2. **PCIe flow control**: model receive-buffer credits; "**simulate back-pressure when the credit count drops below a threshold**" (exercise: "**stall when credits fall below 20% of buffer depth**"); error injection with malformed headers or **CRC failures**; a "credit-watchdog" component.
3. **AXI-to-PCIe bridge**: unified coverage over address translation; "**enforce timing constraints across the bridge**"; a "**dual-clock UVM sequencer that synchronizes AXI clock domains to the PCIe reference clock**".

Bridge verification is a very real senior topic. Several claims are wrong.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| "Prove **read-after-write ordering** is preserved" on AXI | AXI gives **no ordering between the read and write channels**, even for the same ID. A master that needs the read to see the write must **wait for the write response (B)** before issuing the read. Your scoreboard must **not** assume RAW ordering unless the DUT spec adds it |
| AXI4-Lite with 8–16-beat bursts and reordering | **AXI4-Lite has no bursts and no IDs**: every transfer is one beat, and responses come back in order. Burst and reorder questions are about **full AXI4** |
| Stall when credits "**drop below a threshold / 20% of buffer**" | The **transmitter** sends a TLP only if credits of **its type** are **sufficient for that TLP** (Challenge 17). A threshold is a **receiver policy** for *when to send UpdateFC*, not a transmit rule |
| "**CRC failures**" as a generic error | Two different mechanisms: **LCRC** errors are handled by the **data link layer** (Nak → **replay**, invisible to the transaction layer if recovery succeeds); **ECRC** (optional, end-to-end) and **malformed TLPs** are transaction-layer errors reported via error messages/AER and may cause **UR/CA** completions |
| "Enforce **timing constraints** across the bridge" | Timing constraints are for **STA**. DV checks **latency** and **throughput** against the spec |
| "**Dual-clock UVM sequencer** that synchronizes AXI clock to the PCIe reference clock" | Sequencers are **untimed**. Each agent runs on **its own interface clock**; crossing clocks is the **DUT's** job (its CDC logic). The TB's job is to **randomize clock frequencies/ratios** and check the bridge still works |
| "Patterns Google and NVIDIA use to vet every candidate" | Unverifiable; skip it |

---

## 3. Bridge Architecture (what you're verifying)

```
        AXI side (slave port)                          PCIe side
 ┌──────────────┐   AW/W/AR    ┌──────────────────────────┐   TLPs   ┌──────────────┐
 │ AXI master   │ ───────────► │  Outbound:               │ ───────► │ PCIe link    │
 │ agent (VIP)  │ ◄─── B / R ─ │  addr translation (ATU), │ ◄─────── │ partner VIP  │
 └──────────────┘              │  split, tag mgmt,        │   CplD   │ (Root Port / │
                               │  completion reassembly,  │          │  Endpoint)   │
 ┌──────────────┐              │  error mapping           │          └──────────────┘
 │ AXI slave    │ ◄─────────── │  Inbound:                │ ◄─────── MWr/MRd from PCIe
 │ agent (VIP)  │ ──────────►  │  PCIe → AXI master port  │ ───────► CplD back
 └──────────────┘              └──────────────────────────┘
    clk_axi                       (internal CDC)               PCIe core / user clock
```

**Outbound** (AXI master → PCIe): AXI write → **Memory Write TLP(s)**; AXI read → **Memory Read TLP(s)** → **Completion(s) with data** → AXI R beats.
**Inbound** (PCIe → AXI): MWr → AXI write; MRd → AXI read → CplD back.

---

## 4. What Can Go Wrong in a Bridge (the bug classes)

| Area | What must be true | Typical bug |
|---|---|---|
| **Address translation** | AXI address in window *n* → PCIe address = base_n + offset; outside all windows → error | Off-by-one window boundary, wrong window priority, 32 vs. 64-bit address TLP format |
| **Splitting** | Large AXI bursts split into TLPs respecting **Max Payload Size** (writes) and **Max Read Request Size** (reads), and the **4KB boundary** | Wrong split length, lost bytes at a split boundary |
| **Byte enables** | AXI `WSTRB` → TLP **First/Last DW Byte Enables**; unaligned/narrow transfers correct | Wrong BEs on first/last DW, partial writes corrupting neighbours |
| **Tags & completions** | Each non-posted read gets a unique **tag**; completions may come back **split** (by the completer's read-completion boundary) and **out of order across tags**; bridge reassembles into correct AXI R beats with correct `RID` | Tag reuse before completion, wrong reassembly order, wrong RID |
| **Ordering** | PCIe ordering rules (posted may pass non-posted, etc.) and AXI per-ID rules both respected | Read completion returned to AXI before an earlier same-ID read |
| **Flow control** | Bridge never sends without sufficient credits; doesn't deadlock when one credit type is exhausted | Shared queue: posted writes stuck behind blocked reads |
| **Error mapping** | Completion status UR/CA, **completion timeout**, **poisoned** TLP → defined AXI response (SLVERR/DECERR) | Hang on completion timeout; OKAY returned for a poisoned completion |
| **Clock domains** | Correct at any legal clock ratio | Data loss or duplication at extreme ratios (CDC bug) |

---

## 5. End-to-End Scoreboard

The key idea: **predict the PCIe side from the AXI side** (and vice versa), using a **reference model** of the bridge's translation and splitting rules, written from the spec.

```
AXI monitor ──► [reference model: translate, split, BE map] ──► expected TLP queue
                                                                        │ compare
PCIe monitor ──────────────────────────────────────────────────► actual TLPs

PCIe monitor (completions) ──► [model: reassemble per tag, map status] ──► expected R beats / BRESP
                                                                                  │ compare
AXI monitor (R / B) ───────────────────────────────────────────────────────► actual
```

Practical rules:
- **Compare at byte level** for writes: model the target address space as bytes; apply AXI writes through the model, apply observed TLP writes to a second copy; compare **affected bytes**. This handles different split choices that are all legal.
- For reads: track outstanding reads **per tag** (PCIe side) and **per ID** (AXI side); reassemble completions by tag and byte count; check AXI R data and `RLAST` per burst.
- **Allow legal variation**: the spec may let the bridge split differently; check the **rules** (sizes, boundaries, totals) rather than one exact split, unless the DUT spec fixes it.
- `check_phase`: no outstanding tags, no un-completed AXI transactions.

---

## 6. Stimulus and Corner Cases

- AXI bursts: lengths 1 … 256, sizes, **unaligned starts**, narrow transfers, bursts that **cross a 4KB** boundary on the PCIe side after translation, bursts at **window edges**.
- PCIe partner VIP: **split completions**, completions **out of order across tags**, long completion delays (near **completion timeout**), **UR/CA** status, **poisoned** completions, small advertised credits, delayed UpdateFC.
- Link-level: LCRC errors injected by the VIP → expect **replay** with **no** visible transaction-layer effect.
- **Clock ratios**: randomize each clock in `tb_top` per test (fast AXI/slow PCIe core clock and the reverse, plus near-equal clocks), not in a sequencer.
- **Concurrency**: inbound and outbound traffic at the same time; reads and writes mixed; all tags in use.
- **Reset** during outstanding traffic.

```systemverilog
// tb_top: per-test random clock periods, read from plusargs or randomized at time 0
real axi_period, core_period;
initial begin
  if (!$value$plusargs("AXI_PERIOD=%f",  axi_period))  axi_period  = 4.0;
  if (!$value$plusargs("CORE_PERIOD=%f", core_period)) core_period = 4.0;
end
always #(axi_period/2)  clk_axi  = ~clk_axi;
always #(core_period/2) clk_core = ~clk_core;
```

---

## 7. Coverage (unified across both sides)

| Coverpoint / cross | Why |
|---|---|
| Translation window × hit/miss × window edge | Address-translation bugs |
| AXI burst length × alignment × 4KB-crossing-after-translation | Splitting bugs |
| Number of TLPs per AXI burst (1, 2, many) | Split logic paths |
| `WSTRB` pattern on first/last beat × First/Last DW BE | Byte-enable mapping |
| Completions per read (1, split, many) × arrival order across tags | Reassembly |
| Completion status (SC, UR, CA, poisoned, timeout) × resulting AXI response | Error mapping |
| Credit type exhausted × traffic type still flowing | Deadlock avoidance |
| Clock ratio bucket (AXI ≫ core, ≈, ≪) × traffic mix | CDC robustness |
| Outstanding tags = max | Tag management |

---

## 8. Assertions Worth Adding
- AXI and PCIe interface rules from VIP/protocol checkers (don't rewrite them).
- No tag reused while outstanding.
- Every non-posted request gets a completion or a timeout error within the configured timeout.
- No TLP transmitted without sufficient credits (with infinite-credit handling).
- Bridge internal FIFOs: no overflow/underflow (white-box, Challenge 13).

---

## 9. Likely Follow-ups (with model answers)

**Q. Does AXI guarantee a read sees an earlier write to the same address?**
No. Read and write channels are independent. The master must wait for the write response before issuing the read if it needs that ordering, unless the DUT spec guarantees more.

**Q. How do you scoreboard a bridge that may split bursts differently?**
Predict effects, not packets: compare at byte level for writes and check split rules (payload size, boundaries, totals) rather than one exact split, unless the spec fixes the split.

**Q. An LCRC error is injected. What should the AXI side see?**
Nothing different, if replay succeeds: the data link layer retransmits. Only the link error counters change.

**Q. How do you test the bridge's clock domain crossing?**
Randomize clock frequencies and ratios per test in tb_top, stress full/empty internal FIFOs, and rely on CDC tools for structural checks. The TB doesn't synchronize clocks; the DUT does.

**Q. Completion timeout: what do you check?**
The AXI transaction completes with the defined error response within the timeout, the tag is freed, and no late completion is later delivered to a wrong transaction.

---

## 10. Common Fresher Mistakes
- Assuming AXI read-after-write ordering.
- Talking about bursts and IDs on AXI4-Lite.
- Comparing exact TLP splits when the spec allows several.
- Treating LCRC errors as transaction-layer failures.
- Trying to "synchronize clocks" in the testbench.
- No completion-timeout or poisoned-completion tests.

---

## 11. 60-Second Interview Pitch

> "For an AXI-to-PCIe bridge I use protocol VIPs on both sides and an end-to-end scoreboard driven by a reference model of the bridge: address translation windows, splitting by max payload and read request size and the 4KB rule, and WSTRB to first and last DW byte enables. Writes are compared at byte level, so any legal split passes. Reads are tracked per tag on PCIe and per ID on AXI, reassembling split and out-of-order completions into R beats.
>
> I don't assume AXI read-after-write ordering, since the channels are independent. On PCIe I gate on sufficient credits per type and check posted traffic still flows when non-posted credits run out.
>
> For errors, I map UR, CA, poisoned completions and completion timeouts to the specified AXI responses, and LCRC errors should be invisible after replay. I randomize clock ratios per test in tb_top, because the DUT handles the crossing. Coverage spans windows and edges, split counts, byte-enable patterns, completion splits and ordering, error mapping and clock-ratio buckets."

---

## 12. Self-Check
- [ ] Can I explain why AXI has no read-after-write guarantee?
- [ ] Can I list the bridge bug classes (translation, split, BE, tags, ordering, credits, errors, CDC)?
- [ ] Can I sketch the end-to-end scoreboard and explain byte-level comparison?
- [ ] Can I explain LCRC vs. malformed/ECRC errors?
- [ ] Can I explain how the TB tests clock ratios without "synchronizing" clocks?
