# Challenge 17: Protocol Questions — AXI Ordering, AHB-Lite Pipelining & Errors, PCIe Flow-Control Credits

> **Level:** Fresher → Senior DV interview
> **Topics:** AXI channels, IDs, ordering and interleaving, burst rules; AHB-Lite pipelining, wait states, two-cycle error response, HMASTLOCK; PCIe layers, flow-control credit types, infinite credits, credit-gating checks, deadlock avoidance
> **Related:** [10 – Ready/Valid](10-ready-valid-handshake-assertions.md), [13 – Beyond the Happy Path](13-sva-beyond-happy-path.md), [16 – TLM / Scoreboards](16-uvm-tlm-ports-exports-fifos.md)

---

## 1. The Post (summary)

A LinkedIn post says "stop memorizing specs, master the patterns" and gives three protocol scenarios:

1. **AXI**: "the **3-stage handshake** (ARVALID/ARREADY, RVALID/RREADY)"; a master issues "a **5-cycle burst**, then a **higher-priority read appears mid-burst**"; show a sequence that captures reordering and "asserts that **data returns in the exact order** required by the spec".
2. **AHB-Lite**: tests "**single-cycle transfers** and bus-locking"; the right answer is a monitor that "**flags any HRESP ≠ OKAY while HLOCK is asserted**"; mention "Cadence Incisive".
3. **PCIe Gen4**: track credits per VC, inject DLLP credit updates, assert "**no TLP is sent when available credits = 0**".
4. Build one TB for all three; aim for ">90% protocol bins".

The **pattern-based** framing is good: interviewers test understanding, not recitation. **But each protocol scenario contains a real technical error.** And you *do* need to know the signals: you can't reason about patterns without them.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| AXI "**3-stage handshake**" | AXI has **5 independent channels** (AW, W, B, AR, R), each with its own **2-signal** VALID/READY handshake. A read uses 2 channels (AR, R) |
| "5-**cycle** burst" | Bursts are counted in **beats** (`AxLEN+1`), not cycles; a 5-beat burst may take any number of cycles. (5 beats is legal for INCR, **not** for WRAP, which allows 2/4/8/16) |
| "**Higher-priority** read appears mid-burst" and is reordered | AXI has **no preemption** of an accepted burst. `AxQOS` is only a hint to the interconnect. What *does* happen: responses for **different IDs** may return **out of order**, and in AXI4 **read data beats of different IDs may be interleaved** |
| Assert data returns "in the exact order" | Ordering is **per ID**: same ID → in order; different IDs → any order. Beats within one burst are always in order |
| AHB-Lite "**single-cycle transfers**" | AHB-Lite is **pipelined**: each transfer has an **address phase** and a **data phase**, overlapping the next transfer's address phase; **wait states** (`HREADY` low) extend the data phase |
| AHB-Lite **HLOCK** | AHB-Lite has **`HMASTLOCK`**. `HLOCK` is the full-AHB master's request to an arbiter, which AHB-Lite doesn't have |
| Flag **any HRESP ≠ OKAY while locked** | An **ERROR response during a locked sequence is legal**: a slave may return ERROR anytime. The check is whether it's a **correct two-cycle error response** and whether the master/interconnect **handles** it (terminates correctly, releases lock) |
| "No TLP sent when **credits = 0**" | Wrong twice: (1) the check is **sufficient** credits for that TLP **type** (header *and* data); (2) an **advertised initial value of 0 means infinite credits** for that type. A "credits == 0 → block" assertion would fire falsely on infinite-credit types |
| ">90% protocol bins" | See Challenge 09: sign-off is planned bins closed or reviewed |
| "Cadence Incisive" | Older simulator (succeeded by Xcelium); name-dropping a tool adds nothing technical |

---

## 3. AXI4: The Concepts Interviewers Actually Probe

### 3.1 The five channels

| Channel | Direction | Key signals |
|---|---|---|
| AW (write address) | M → S | `AWID, AWADDR, AWLEN, AWSIZE, AWBURST` |
| W (write data) | M → S | `WDATA, WSTRB, WLAST` (no `WID` in AXI4) |
| B (write response) | S → M | `BID, BRESP` |
| AR (read address) | M → S | `ARID, ARADDR, ARLEN, ARSIZE, ARBURST` |
| R (read data) | S → M | `RID, RDATA, RRESP, RLAST` |

### 3.2 Rules that create bugs
- **Burst types**: FIXED, INCR (1–256 beats), WRAP (2/4/8/16 beats, aligned start address).
- **4KB boundary**: a burst must not cross a 4KB address boundary.
- **Ordering**: same ID → in order. Different IDs → may reorder.
- **Read interleaving**: R beats of different IDs may be interleaved (slave-dependent). **Write data interleaving was removed in AXI4**: W beats come in AW order.
- **W may arrive before AW** (slaves that assume AW first are a classic bug).
- **B** comes only after **both** the AW handshake and the **last W beat**.
- **Narrow transfers**: `AxSIZE` smaller than the bus width means byte lanes shift each beat.

### 3.3 Verifying out-of-order reads

**Stimulus:**
- Master sequences issue **many outstanding** reads with a mix of **same and different IDs**.
- Slave responder (or reactive slave sequence) **randomly reorders** responses across IDs, **interleaves** beats, and inserts random `RVALID` gaps and `RREADY` back-pressure.

**Scoreboard (per-ID model):**
```systemverilog
// expected bursts queued per ID, in issue order
typedef struct { bit [31:0] addr; int beats; int beat_idx; } burst_t;
burst_t exp_by_id[int][$];                 // ID → queue of bursts

function void write_ar(axi_ar_txn t);
  burst_t b = '{t.addr, t.len + 1, 0};
  exp_by_id[t.id].push_back(b);
endfunction

function void write_r_beat(axi_r_beat t);  // monitor sends one item per R beat
  if (!exp_by_id.exists(t.id) || exp_by_id[t.id].size() == 0) begin
    `uvm_error("SB", $sformatf("R beat with no outstanding read, ID %0d", t.id)) return;
  end
  // always the OLDEST burst of this ID (same-ID ordering rule)
  check_data(exp_by_id[t.id][0], t.data);  // compare with memory model at beat address
  exp_by_id[t.id][0].beat_idx++;
  if (t.last != (exp_by_id[t.id][0].beat_idx == exp_by_id[t.id][0].beats))
    `uvm_error("SB", "RLAST on wrong beat")
  if (t.last) void'(exp_by_id[t.id].pop_front());
endfunction
```
(Beat addresses depend on burst type and size: compute them in `check_data` with the AXI address formula.)

**Assertions:** VALID/READY hold and stability on all 5 channels (Challenge 10); no 4KB crossing; WRAP length legal; `RID` matches an outstanding ID.

**Coverage:** `burst_type × len` (incl. 1 and max), same-ID back-to-back, different-ID reordering seen, interleaved beats seen, `RRESP`/`BRESP` = SLVERR/DECERR, narrow transfers, W-before-AW, max outstanding.

---

## 4. AHB-Lite: Pipelining, Wait States, Errors, Lock

### 4.1 Pipelined transfers

```
cycle:     1        2        3        4
HADDR:   [A1 ]    [A2 ]    [A2 ]    [A3 ]       address phase of next transfer
HWDATA:           [D1 ]    [D1 ]    [D2 ]       data phase of previous transfer
HREADY:    1        0        1        1         wait state in cycle 2 extends D1
```
- **Address phase** of transfer *n+1* overlaps **data phase** of transfer *n*.
- When `HREADY` is low, the master must **hold** the address-phase signals of the pending transfer and the write data.
- `HTRANS`: IDLE, BUSY, NONSEQ (first of burst / single), SEQ (rest of burst).
- Bursts: SINGLE, INCR, INCR4/8/16, WRAP4/8/16; must not cross a **1KB** boundary.

### 4.2 The two-cycle error response
AHB-Lite `HRESP` is 1 bit (OKAY/ERROR). An ERROR takes **two cycles**:
1. `HRESP = ERROR`, `HREADYOUT = 0`
2. `HRESP = ERROR`, `HREADYOUT = 1`

The two cycles give the master time to **cancel** the next transfer (it may change `HTRANS` to IDLE in the second cycle).

```systemverilog
a_err_two_cycle: assert property (@(posedge HCLK) disable iff (!HRESETn)
  (HRESP && !HREADYOUT) |=> (HRESP && HREADYOUT));
a_err_first:     assert property (@(posedge HCLK) disable iff (!HRESETn)
  ($rose(HRESP)) |-> !HREADYOUT);                      // ERROR never starts with HREADYOUT high
a_addr_hold:     assert property (@(posedge HCLK) disable iff (!HRESETn)
  (HTRANS inside {NONSEQ, SEQ} && !HREADY) |=> $stable({HADDR, HWRITE, HSIZE, HBURST, HTRANS}));
```
(The address-hold check applies to the transfer waiting in its address phase; BUSY/IDLE subtleties apply, so tune to your master's spec.)

### 4.3 `HMASTLOCK`
- Marks a **locked sequence** (e.g., atomic read-modify-write). The interconnect must not let another master access the slave in between (relevant in multi-layer systems).
- **ERROR during a locked sequence is legal.** Verify:
  - The two-cycle error response is correct.
  - The master either completes or **cleanly terminates** the locked sequence and **deasserts** `HMASTLOCK`.
  - The interconnect **releases** the lock afterwards (other masters get access).
- Coverage: lock with OKAY completion, lock with ERROR on first/middle/last transfer, lock with wait states, lock followed by IDLE.

---

## 5. PCIe: Flow-Control Credits (what to really say)

### 5.1 Layers in one table

| Layer | Unit | Job |
|---|---|---|
| Transaction | **TLP** (memory read/write, completions, config, messages) | Requests/completions, ordering rules |
| Data Link | **DLLP** (Ack/Nak, InitFC, UpdateFC) | Reliable delivery: sequence numbers, LCRC, **replay**; **flow control** |
| Physical | Symbols / encoded blocks | Link training (LTSSM), encoding (128b/130b in Gen3/4), lanes |

### 5.2 Credit types (per Virtual Channel)

| Category | Header credit | Data credit |
|---|---|---|
| Posted (memory writes, messages) | **PH** | **PD** |
| Non-Posted (reads, config, I/O) | **NPH** | **NPD** |
| Completions | **CplH** | **CplD** |

- 1 header credit = one TLP header; 1 **data credit = 16 bytes (4 DW)**.
- Receiver advertises initial credits with **InitFC** DLLPs; returns credits with **UpdateFC** as it frees buffers.
- **An advertised value of 0 means "infinite"** for that type (common, e.g., completion credits at an endpoint).
- The transmitter **gates** each TLP: it may send only if **both** header and data credits of the **right type** are sufficient. Counters are fixed-width and **wrap**, so the check uses **modular arithmetic** (consumed vs. limit), not a simple `>= 0`.

### 5.3 Verifying credit gating

**Credit model in the testbench (per VC, per type):**
```systemverilog
class fc_model;
  bit infinite[fc_type_e];          // set when InitFC advertised 0
  int unsigned limit[fc_type_e];    // from InitFC/UpdateFC
  int unsigned consumed[fc_type_e]; // from transmitted TLPs

  function bit can_send(fc_type_e h, fc_type_e d, int hdr_cr, int data_cr);
    return (infinite[h] || avail(h) >= hdr_cr) && (infinite[d] || avail(d) >= data_cr);
  endfunction
  // avail() computed with the spec's modular arithmetic on the counter width
endclass
```
The monitor on the DUT's transmit side checks **every TLP**: `if (!fc.can_send(...)) uvm_error("FC", "TLP sent without sufficient credits")`.

**Stimulus to stress it:**
- Receiver (VIP) advertises **small** credits; delays UpdateFC; sends UpdateFC **while** the DUT is blocked.
- Mix of **infinite** and finite types.
- Large payloads needing many data credits; max-payload-size TLPs.
- Long runs to hit **counter wraparound**.
- Nak/replay while credits are low (replayed TLPs must **not** consume credits again).

**Deadlock avoidance (the real "never deadlocks" question):**
- Separate credit pools per type mean exhausting **non-posted** credits must **not** block **posted** writes or **completions**. PCIe **ordering rules** require that posted requests can pass blocked non-posted requests; a DUT with one shared queue can deadlock.
- Test: exhaust NPH completely, then send posted writes and completions → they must still flow.
- Bounded-progress assertion: a pending TLP whose credits are available must be sent within N cycles.

**Coverage:** exhaustion of each of the 6 credit types, infinite vs. finite per type, UpdateFC while blocked, wraparound, posted passing blocked non-posted, replay with low credits.

**Practical note:** for standard protocols like PCIe, teams use a **commercial VIP** for protocol compliance. DV effort focuses on the DUT's controller and application-side logic, plus the scenarios above.

---

## 6. Likely Follow-ups (with model answers)

**Q. Can AXI responses come back out of order?**
For different IDs, yes. For the same ID, no. Beats within a burst are always in order. AXI4 allows read-data interleaving across IDs, but not write-data interleaving.

**Q. How do you check AXI out-of-order reads in a scoreboard?**
Queue expected bursts per ID; on each R beat, match the oldest outstanding burst for that RID, compare data against the memory model at the computed beat address, check RLAST on the final beat, then retire it.

**Q. Why is AHB's error response two cycles?**
Because of pipelining: the next transfer's address phase is already on the bus, so the first cycle warns the master and the second completes the error, letting the master cancel the next transfer.

**Q. Is an ERROR during HMASTLOCK a protocol violation?**
No. Check the response is correctly formed and that the master and interconnect terminate the locked sequence and release the lock.

**Q. What does a 0 in InitFC mean?**
Infinite credits for that type; the transmitter must not gate on it.

**Q. How can a PCIe device deadlock with credits?**
If posted traffic gets stuck behind non-posted requests waiting for credits. Ordering rules and separate credit pools exist to prevent that; verify by exhausting one type and checking the others still progress.

---

## 7. Common Fresher Mistakes
- Calling AXI a "3-stage" handshake; counting bursts in cycles.
- Expecting global in-order responses across IDs.
- Forgetting W can precede AW.
- Treating AHB transfers as single-cycle; forgetting address-phase hold during wait states.
- Calling an ERROR during lock "illegal".
- Checking PCIe credits as `credits > 0` and ignoring types, data credits, infinite credits and wraparound.

---

## 8. 60-Second Interview Pitch

> "For AXI, five channels each have their own valid/ready handshake. Ordering is per ID: same ID in order, different IDs may reorder, and AXI4 allows read-data interleaving but not write. My scoreboard queues expected bursts per ID, matches each R beat to the oldest burst for that RID, compares against a memory model, and checks RLAST. My slave responder reorders, interleaves and back-pressures randomly.
>
> AHB-Lite is pipelined, so I check address-phase signals are held during wait states and that an ERROR response is two cycles. An error during HMASTLOCK is legal; I check that the lock is released correctly.
>
> For PCIe flow control, there are six credit types per VC, header and data, and a zero in InitFC means infinite. My model gates every transmitted TLP on sufficient credits of its type, with modular counter arithmetic. I stress small credits, delayed UpdateFC, wraparound and replay, and I verify that exhausting non-posted credits never blocks posted writes or completions, since that's how credit deadlocks happen."

---

## 9. Self-Check
- [ ] Can I name the 5 AXI channels and the per-ID ordering rule?
- [ ] Can I write a per-ID AXI read scoreboard?
- [ ] Can I draw AHB-Lite pipelining with a wait state?
- [ ] Can I explain the two-cycle ERROR response and why?
- [ ] Can I list the 6 PCIe credit types and explain "0 = infinite"?
- [ ] Can I explain how credit deadlock happens and how to test for it?
