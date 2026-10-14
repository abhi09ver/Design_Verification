# Challenge 18: Coverage Architecture — Where Covergroups Live, Controlling Cross Explosion, Merging

> **Level:** Fresher → Senior DV interview
> **Topics:** cycle-level vs. transaction-level vs. scenario-level coverage, placing covergroups, `sample()` with arguments, bins/ignore/illegal, cross explosion, per-instance vs. type coverage, merging and ranking, "static vs. dynamic" closure, worked AXI-Lite slave plan
> **Related:** [06 – Verification Plan](06-verification-plan.md), [09 – Coverage Plateau](09-coverage-plateau-closure.md), [11 – Functional vs. Code Coverage](11-functional-vs-code-coverage.md), [13 – Beyond the Happy Path](13-sva-beyond-happy-path.md)

---

## 1. The Post (summary)

A LinkedIn post says the question that separates owners from testbench-runners is "dynamic vs. static coverage closure strategies", and claims:

1. Diagram a **three-tier covergroup hierarchy** (module, interface, transaction); a flat one "would explode the sample space on a **7nm NVIDIA GPU**", but collapse it "for a **low-power Intel FPGA where resource budget is the bottleneck**".
2. Assertions in Google's "formal-first" flow are "**synthesized into a hardware monitor, reducing false positives by ~30%**".
3. Build VIP that "**survives a process-node migration**" by "parameterizing the sequencer for a **10nm to 14nm** jump", and run regressions "on two simulated **process corners**".

The useful core: **coverage should be layered**, and **crosses must be designed, not dumped**. The rest is wrong, and much of it repeats myths from earlier challenges.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| Collapse covergroups for an FPGA "resource budget" | Covergroups are **simulation-only**; they are never synthesized and use no FPGA or silicon resources. The cost is **simulation memory and runtime** |
| Cross explosion depends on the **process node** (7nm GPU) | It depends on **how many bins you cross**. Node is irrelevant (same myth as in Challenge 03) |
| Synthesizing assertions **reduces false positives** | Synthesizing assertions (for emulation or on-chip debug) changes **where** they run, not their logic. False positives come from wrong properties or missing assumptions (Challenges 08, 14) |
| VIP parameterized for a **10nm→14nm** migration; **process corners** in RTL simulation | VIP models a **protocol**; it has nothing to do with process node (Challenge 03). **Process corners** (slow/fast silicon, voltage, temperature) apply to **timing sign-off (STA)** and **SDF-annotated gate-level simulation**, not RTL regressions |
| "Dynamic vs. static coverage closure" as a named strategy | Not a standard term. The sensible reading: **dynamic** = closure through simulation; **static** = closure through analysis without stimulus (formal unreachability, reviewed exclusions). Both are needed (Challenge 09) |
| ~30%, "2-hour increase offset by 40%" | Unsourced numbers |

---

## 3. Three Levels of Functional Coverage

| Level | Where it lives | Samples | Sees | Example |
|---|---|---|---|---|
| **Cycle / signal** | Interface or a module attached with `bind` | Clock events, `cover property` | Timing: stall lengths, back-to-back, FSM states, handshake orderings | `AWVALID` before `WVALID`, `WVALID` before `AWVALID`, same cycle |
| **Transaction** | `uvm_subscriber` connected to the monitor's analysis port | One completed transaction | Field values and crosses | `wstrb` patterns × address region × response |
| **Scenario / system** | Scoreboard or a dedicated collector seeing several streams | Sequences of transactions, across interfaces | Interactions | Read-after-write same address; read while write pending; error then recovery |

**Why layered:**
- Each level sees what the others can't: a transaction covergroup can't see how long `VALID` waited; a cycle covergroup can't easily see "same address as the previous write".
- **Reuse:** protocol-level coverage (levels 1–2) can live in the **VIP**; DUT-specific scenario coverage (level 3) lives in the **env** (Challenge 03).
- Plus **register coverage** from RAL (Challenge 15) and **code coverage** (Challenge 11).

### Placement example (transaction level)
```systemverilog
class axil_cov extends uvm_subscriber #(axil_txn);
  `uvm_component_utils(axil_cov)

  covergroup cg_wr with function sample(axil_txn t);
    cp_region: coverpoint t.addr[11:8] { bins ctrl = {0}; bins status = {1}; bins buf_[] = {[2:3]}; bins unmapped = default; }
    cp_strb:   coverpoint t.wstrb      { bins full = {4'hF}; bins none = {4'h0}; bins single[] = {1, 2, 4, 8}; bins partial = default; }
    cp_resp:   coverpoint t.resp       { bins okay = {0}; bins slverr = {2}; bins decerr = {3}; illegal_bins exokay = {1}; }
    x_region_resp: cross cp_region, cp_resp;
    x_strb_region: cross cp_strb, cp_region {
      ignore_bins strb_on_status = binsof(cp_region.status) && !binsof(cp_strb.full);  // RO region: only full writes matter
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_wr = new();
  endfunction

  function void write(axil_txn t);
    if (t.is_write) cg_wr.sample(t);       // sample completed transactions only
  endfunction
endclass
```
Note `illegal_bins exokay`: AXI-Lite doesn't support exclusive access, so EXOKAY is a **protocol error**. `illegal_bins` reports an error if sampled, an extra cheap check (but don't use coverage as your only checker).

---

## 4. Controlling Cross Explosion

Crossing three coverpoints with 16, 32 and 64 bins gives **32,768** cross bins. Most are meaningless, and you'll never close them.

| Technique | How |
|---|---|
| **Group values into meaningful bins** | Corners + ranges: `{0}, {1}, [2:MAX-2], {MAX-1}, {MAX}` instead of every value |
| **Cross only what interacts** | Ask "is there a bug class where these two interact?" If not, don't cross them |
| **`ignore_bins`** | Combinations that are legal but irrelevant |
| **`illegal_bins`** | Combinations that must never happen (error if seen) |
| **`binsof(...) intersect {...}` selections** | Keep only specific slices of a cross |
| **Split into several small crosses** | Two 2-way crosses instead of one 3-way, when the 3-way interaction isn't a real bug class |
| **`option.weight`, `option.goal`, `option.at_least`** | Weight what matters; require multiple hits for rare-but-critical bins |
| **Per-instance vs. type coverage** | `option.per_instance = 1` when instances behave differently (e.g., 4 ports with different configs); otherwise merge into type coverage to save memory |

**Senior rule:** every cross should trace to a **vplan test point and a bug class** (Challenge 11, Section 6). A cross nobody can justify is a cross nobody will close.

---

## 5. Sampling Correctly
- Sample **completed** transactions (after the response), so fields like `resp` are valid.
- Use `with function sample(...)` and pass the transaction; don't rely on class members changing underneath.
- Use `iff` for conditional sampling at cycle level (`covergroup @(posedge clk iff valid)`).
- Construct covergroups in `new()` (embedded covergroups must be constructed in the constructor).
- A bin at 0 that you **can see** happening in the waveform = a **sampling bug** (Challenge 09).

---

## 6. Merging and Ranking
- Each test/seed writes a coverage database; **merge** them for the regression view (e.g., `urg` for VCS, `imc` for Xcelium, `vcover merge` for Questa).
- **RTL changes** between runs can make code-coverage merges inconsistent; merge only compatible snapshots, or use the tool's change-aware merge options.
- **Rank** tests by unique contribution to build efficient nightly suites (Challenge 02).
- Track coverage **per feature** (from the vplan), not just a total percentage.

---

## 7. Static vs. Dynamic Closure (the sensible reading of the post's question)

| | Dynamic | Static |
|---|---|---|
| How | Simulation (random, directed, emulation) | Analysis without stimulus |
| Tools | Constraints, sequences, regression | Formal unreachability, cover witnesses, code reviews, waiver reviews |
| Closes | Reachable holes | Proves holes **unreachable** → exclusions |
| Risk | Misses what stimulus never reaches | Exclusions are only as good as assumptions/reviews |

A closure plan uses **both**: simulation for reachable holes, formal + review to justify exclusions (Challenge 09, Section 6).

---

## 8. Worked Example: AXI-Lite Slave — One-Page Coverage & Assertion Plan

**DUT:** AXI-Lite slave, 4 regions (CTRL RW, STATUS RO, two buffers RW), unmapped → DECERR, write to RO → SLVERR.

### Features → coverage level → checker

| Feature | Coverage (level) | Checker |
|---|---|---|
| Independent AW / W arrival | AW-first, W-first, same-cycle (**cycle**) | SVA: B only after both AW and W handshakes |
| Back-pressure | `BREADY`/`RREADY` low for 0, 1, N cycles (**cycle**) | SVA: valid hold + payload stable on B, R |
| Byte strobes | full, single bytes, partial, none × region (**transaction**) | Scoreboard: memory model applies `wstrb` per byte |
| Region decode | each region × read/write (**transaction**) | Scoreboard data compare |
| Error responses | DECERR on unmapped, SLVERR on RO write (**transaction**) | Scoreboard expected response; SVA: no state change on error |
| Read/write interaction | read same address right after write; read while write pending (**scenario**) | Scoreboard ordering model |
| Reset | reset mid-write, mid-read (**cycle**) | SVA reset properties (Challenge 13) |

### Assertion checklist
- [ ] VALID held until READY, payload stable, on all 5 channels
- [ ] No X on VALID/READY after reset; VALIDs low during reset
- [ ] B only after both AW and W handshakes; R only after AR handshake
- [ ] One outstanding per channel if the design says so (counter ≤ 1)
- [ ] `RRESP`/`BRESP` never EXOKAY
- [ ] Bounded response latency (from spec)
- [ ] Covers for each of the above (no vacuous passes)

---

## 9. Likely Follow-ups (with model answers)

**Q. Where should a covergroup for "stall length" live?**
At cycle level, in the interface or a bound module (or as `cover property`). A transaction-level subscriber only sees the completed transaction.

**Q. Your cross has 20,000 bins and is at 12%. What do you do?**
Re-derive it from bug classes: group values into corner bins, split into smaller crosses, ignore irrelevant combinations, mark illegal ones. Then close what's left.

**Q. Does coverage cost hardware resources?**
No, it's simulation-only. It costs simulation memory and runtime (emulators have limited support).

**Q. Per-instance vs. type coverage?**
Per-instance when instances differ meaningfully (different configs/ports); type coverage merges all instances and saves memory.

**Q. Static vs. dynamic coverage closure?**
Dynamic closes reachable holes through simulation; static uses formal unreachability and reviews to justify exclusions. You need both.

---

## 10. Common Fresher Mistakes
- One giant covergroup with every field crossed with every other.
- Sampling before the transaction completes.
- No covergroup construction in `new()`.
- Using coverage as the only checker (illegal_bins is a bonus, not a scoreboard).
- Thinking coverage relates to process node, FPGA resources, or process corners.

---

## 11. 60-Second Interview Pitch

> "I layer functional coverage in three levels. Cycle-level coverage lives in the interface or a bound module and covers timing: stall lengths, back-to-back and channel orderings. Transaction-level coverage lives in a subscriber off the monitor and covers fields and crosses on completed transactions. Scenario-level coverage lives in the scoreboard or a collector, for interactions like read-after-write to the same address. Protocol coverage can sit in the VIP; DUT scenarios stay in the env.
>
> Every cross traces to a bug class. I group values into corner bins, split large crosses, and use ignore and illegal bins, so the model stays closable. I sample only completed transactions, through sample() with arguments.
>
> Closure is both dynamic, through simulation for reachable holes, and static, with formal unreachability and reviewed exclusions for the rest. Coverage is simulation-only, so it's about simulation cost, never hardware resources."

---

## 12. Self-Check
- [ ] Can I name the 3 coverage levels and where each lives?
- [ ] Can I write a transaction covergroup with `ignore_bins` and `illegal_bins`?
- [ ] Can I list 5 ways to control cross explosion?
- [ ] Can I explain static vs. dynamic closure?
- [ ] Can I fill a feature → coverage level → checker table for a small slave?
