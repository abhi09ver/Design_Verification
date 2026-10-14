# Challenge 08: SystemVerilog Assertions (SVA) — Writing, Reading, and Debugging a Failing Property

> **Level:** Fresher → Senior DV interview
> **Topics:** immediate vs. deferred vs. concurrent assertions, sampling, implication, sequence operators, system functions, `disable iff`, vacuity, local variables, stalls, liveness, assume/cover in formal, `bind`, debugging a failure

---

## 1. The Post (summary)

A LinkedIn post says "if you can't explain why a single SVA property fails, you'll never survive an interview at Google or NVIDIA", and recommends:

1. Master `assert`, `assume`, `cover` and "the two clocking styles, `@posedge clk` and **`@(*)`**".
2. For a 2-cycle request→ack handshake, "the correct SVA is **`req # ack`**"; also use `disable iff (reset)` or **`iff (!busy)`** for gating.
3. Use **`let` to factor out common sub-sequences**; use `assume` to shrink state space "for formal tools like **Synopsys VCS**"; handle arbitrary pipeline stalls by combining **`##[0:$]` with `disable iff (stall)`**.

The core message (you must be able to explain why a property fails) is exactly right. **But the post's code and tool claims are wrong in five places.**

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| Clocking styles `@posedge clk` and `@(*)` | `@(*)` is the combinational sensitivity list for `always` blocks. **Concurrent assertions need a clock event**: explicit `@(posedge clk)`, a `default clocking` block, or one inferred from the enclosing `always_ff`. Syntax is `@(posedge clk)` with parentheses |
| `req # ack` is the handshake | **Not valid SVA.** Delays use `##`. Correct form depends on the spec, e.g. `req \|-> ##2 ack` (exactly 2 cycles) or `req \|-> ##[1:2] ack` (within 1–2) |
| `iff (!busy)` for gating a property | `iff` is valid in a **clocking event** (`@(posedge clk iff !busy)`, which only samples when not busy) and in coverpoints, not as a general property operator. Gating a property normally uses implication or `disable iff` |
| `let` factors sub-sequences | `let` factors **expressions**. For temporal sub-patterns, use a named **`sequence`** |
| Synopsys **VCS** is a formal tool | VCS is a **simulator**. Formal tools are e.g. Synopsys **VC Formal**, Cadence **Jasper**, Siemens **Questa Formal** |
| Handle stalls with `##[0:$]` + `disable iff (stall)` | **Wrong and dangerous.** `disable iff` **cancels** the check whenever `stall` is high, so any bug that happens during a stall passes silently. Stalls are modeled with **goto repetition `[->n]`**, `throughout`, or a counter (Section 7) |
| "Rewrite a race condition as a concurrent property" | Races are scheduling problems, usually in the testbench. Concurrent assertions sample in the **Preponed** region, so they themselves don't race with RTL updates; that's a point to explain, not a "rewrite" |

Also: there are **four** verification directives, not three: `assert`, `assume`, `cover`, and `restrict` (formal only).

---

## 3. Background a Fresher Must Know

### 3.1 Three kinds of assertions

| Kind | Example | When evaluated | Use |
|---|---|---|---|
| **Immediate** | `assert (a == b) else $error(...);` | When the statement executes (procedural) | Checks inside procedural code, e.g. after `randomize()` |
| **Deferred immediate** | `assert #0 (a == b);` / `assert final (...)` | At the end of the time step | Combinational checks without glitch false-fails |
| **Concurrent** | `assert property (@(posedge clk) a \|-> b);` | On every clock, **sampled values** | Temporal rules across cycles |

### 3.2 Sampling: the key to reading any waveform
Concurrent assertions use values **sampled just before the clock edge** (Preponed region), the same values flops see. On the waveform, **look at the value immediately before the edge**, not after. Most "the assertion is wrong" confusion comes from reading values after the edge.

### 3.3 The building blocks

```
sequence  →  temporal pattern          (a ##1 b ##[1:3] c)
property  →  rule built from sequences (antecedent |-> consequent)
directive →  assert / assume / cover / restrict
```

### 3.4 Implication
| Operator | Meaning |
|---|---|
| `a \|-> b` | If `a` this cycle, then `b` **same** cycle (overlapping) |
| `a \|=> b` | If `a` this cycle, then `b` **next** cycle. Same as `a \|-> ##1 b` |

**Vacuous pass:** if the antecedent never matches, the property "passes" without checking anything. A property that only ever passes vacuously is **useless**; that's why every assertion needs a matching `cover`.

### 3.5 Sequence operators

| Operator | Meaning | Example |
|---|---|---|
| `##n` | n cycles later | `a ##2 b` |
| `##[m:n]` | between m and n cycles later | `a ##[1:4] b` |
| `##[1:$]` | eventually (unbounded) | `req ##[1:$] ack` |
| `[*n]` | consecutive repetition | `busy[*3]` = 3 cycles in a row |
| `[*m:n]` | consecutive, m to n times | |
| `[->n]` | **goto**: n-th occurrence (not necessarily consecutive), **ends on it** | `ack[->1]` = wait until next `ack` |
| `[=n]` | non-consecutive, may continue after last occurrence | |
| `throughout` | condition holds during a whole sequence | `en throughout (a ##[1:5] b)` |
| `within`, `intersect`, `and`, `or` | combine sequences | |

### 3.6 Useful system functions
`$rose(x)`, `$fell(x)`, `$stable(x)`, `$past(x, n)`, `$changed(x)`, `$isunknown(x)`, `$onehot(x)`, `$onehot0(x)`, `$countones(x)`.

---

## 4. Handshake Properties (correct versions)

Spec: *"After `req` rises, `ack` must come within 1 to 4 cycles. `req` stays high until `ack`. Data is stable while waiting."*

```systemverilog
module hs_checker (input logic clk, rst_n, req, ack, input logic [31:0] data);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // 1. ack within 1..4 cycles of req rising
  a_ack_latency: assert property ($rose(req) |-> ##[1:4] ack)
    else $error("ack not received within 4 cycles of req");

  // 2. req held until ack
  a_req_hold:    assert property (req && !ack |=> req);

  // 3. data stable while waiting
  a_data_stable: assert property (req && !ack |=> $stable(data));

  // 4. no X on control after reset
  a_no_x:        assert property (!$isunknown({req, ack}));

  // Covers: prove the interesting cases actually happened
  c_fast_ack:    cover property ($rose(req) ##1 ack);
  c_slow_ack:    cover property ($rose(req) ##4 ack);
  c_b2b:         cover property (ack ##1 $rose(req));
endmodule

bind my_dut hs_checker u_hs_chk (.*);   // attach without editing RTL
```

Why `disable iff (!rst_n)` is right here: during reset, the protocol doesn't apply, so cancelling is correct. **Use `disable iff` only for reset (or similar "rules don't apply" conditions), never for normal operating conditions like stalls.**

---

## 5. Parameterized AXI-Lite Example (what the post asked for, done properly)

```systemverilog
module axil_rd_chk #(parameter int ADDR_W = 32, DATA_W = 32, MAX_LAT = 16)
  (input logic clk, rst_n,
   input logic arvalid, arready, input logic [ADDR_W-1:0] araddr,
   input logic rvalid,  rready,  input logic [DATA_W-1:0] rdata,
   input logic [1:0] rresp);

  default clocking @(posedge clk); endclocking
  default disable iff (!rst_n);

  // VALID must stay high, and payload stable, until READY (AXI rule)
  a_ar_hold:  assert property (arvalid && !arready |=> arvalid && $stable(araddr));
  a_r_hold:   assert property (rvalid  && !rready  |=> rvalid  && $stable({rdata, rresp}));

  // Every accepted read address gets a read response within MAX_LAT cycles
  // (assumes one outstanding read, as in many simple AXI-lite slaves)
  a_rd_resp:  assert property (arvalid && arready |-> ##[1:MAX_LAT] (rvalid && rready));

  c_rd_stall: cover property (arvalid && !arready ##1 arvalid && !arready ##1 arready);
endmodule
```

Note what the parameters do: widths scale the ports; `MAX_LAT` makes the latency bound configurable per instance.

---

## 6. Debugging "Why Did This Property Fail?" (the real interview skill)

1. **Read the message**: simulators report the **start time** of the failing attempt and the **fail time**. Two different times.
2. **Go to the start time**: which cycle matched the antecedent? Look at **sampled** values (just before the edge).
3. **Walk forward cycle by cycle** through the consequent until the cycle where it couldn't match.
4. **Multiple attempts overlap**: a new attempt starts every cycle the antecedent matches. The failing one may not be the one you think. Check `$rose` vs. level-sensitive antecedents (level → many attempts).
5. **Decide: RTL bug, assertion bug, or spec ambiguity?**
   - Off-by-one: `|->` vs. `|=>`, `##1` vs. `##0`.
   - Level vs. edge in antecedent.
   - Wrong reset polarity in `disable iff`.
   - X values (use `$isunknown` checks).
   - Clock: is it the right clock / edge for that signal's domain?
6. **Use tool support**: assertion debug views in Verdi / SimVision / Visualizer show each attempt's threads.
7. **Confirm the fix with the `cover`**: the scenario actually happens and the assertion passes **non-vacuously**.

### Worked example
```systemverilog
a_bad: assert property (req |-> ##2 ack);
```
Waveform: `req` high for 3 cycles (t1–t3), `ack` at t3.
- Attempt at t1: needs ack at t3 → ✅
- Attempt at t2: needs ack at t4 → ❌ **fails at t4**
- Attempt at t3: needs ack at t5 → ❌

The RTL may be fine: the assertion is **level-sensitive** and starts a new check every cycle `req` is high. Fix: `$rose(req) |-> ##2 ack`, or encode "req held until ack" separately (Section 4).

---

## 7. Stalls and Pipelines (correct approach)

Spec: *"Each accepted input appears at the output, in order, after 3 non-stalled cycles."* `stall` can last any number of cycles.

**Wrong (from the post):** `disable iff (stall)` → any check overlapping a stall is thrown away.

**Right options:**

**a) Count non-stalled cycles with goto repetition**
```systemverilog
property p_pipe;
  logic [31:0] v;                                   // local variable
  (in_valid && !stall, v = in_data)                 // capture data on accept
  |-> ##1 (!stall)[->3] ##0 (out_valid && out_data == v);
endproperty
a_pipe: assert property (p_pipe);
```
`(!stall)[->3]` means "wait until the 3rd non-stalled cycle", however many stalled cycles are in between. The local variable `v` checks **data integrity**, not just timing. (Model as given: fixed-latency, in-order; adjust the count to your pipeline.)

**b) Keep outputs quiet during stalls**
```systemverilog
a_no_out_on_stall: assert property (stall |-> !out_valid);   // if that's the spec
```

**c) For deep or variable-latency, out-of-order designs**: a **scoreboard** is usually clearer than one huge property. Say this in interviews; it shows judgment.

### Liveness: `##[1:$]`
- `req |-> ##[1:$] ack` is **weak** by default in simulation: if the sim ends before `ack`, it does **not** fail.
- `req |-> s_eventually ack` or `strong(##[1:$] ack)` fails at end of simulation if `ack` never came.
- In formal, unbounded liveness proves "never deadlocks"; in simulation, prefer a **bounded** window (`##[1:MAX]`) so failures are real and debuggable.

---

## 8. Assert, Assume, Cover in Formal vs. Simulation

| Directive | Simulation | Formal |
|---|---|---|
| `assert` | Checked; fails report errors | Tool tries to **prove** it for all legal inputs, or gives a counterexample |
| `assume` | Checked like an assert (useful to catch illegal stimulus) | **Constrains inputs**: the tool only explores behaviours that satisfy it |
| `cover` | Counts hits | Tool finds a trace that reaches it (proves reachability) |
| `restrict` | Ignored | Constrains like `assume` but isn't checked |

**Same file, both worlds:** a property on DUT **inputs** is an `assume` for block-level formal and an `assert` when that block is integrated (its driver is now real RTL). Typically controlled with a macro or parameter.

**Over-constraining danger:** too strong an `assume` makes formal prove properties over an unrealistically small space, or makes the design look correct because the failing inputs are excluded. Every assumption must come from the spec and be reviewed; covers catch over-constraint (unreachable cover = suspicious).

---

## 9. Likely Follow-ups (with model answers)

**Q. `|->` vs. `|=>`?**
Overlapping (same cycle) vs. non-overlapping (next cycle). `a |=> b` ≡ `a |-> ##1 b`.

**Q. What is a vacuous pass and why care?**
The antecedent never matched, so nothing was checked. Pair each assertion with a cover of its antecedent/scenario.

**Q. `[->1]` vs. `[=1]`?**
Goto `[->1]` ends exactly on the occurrence; non-consecutive `[=1]` allows extra cycles after it before the next sequence element.

**Q. Why does an assertion fail one cycle later than you expect?**
Reading post-edge instead of sampled values; `|=>` vs `|->`; level-sensitive antecedent starting extra attempts.

**Q. How do you attach assertions without touching RTL?**
`bind` a checker module to the RTL module or instance.

**Q. When would you not use SVA?**
Complex out-of-order, high-latency data checking → scoreboard/reference model. SVA shines for local protocol and control rules.

**Q. How do you check across clock domains?**
Each property uses one clock. Check each side in its own domain; CDC correctness itself is for CDC tools and formal, plus specific properties on synchronizer handshakes.

---

## 10. Common Fresher Mistakes
- Level-sensitive antecedent where an edge (`$rose`) was intended.
- Using `disable iff` for anything other than reset-like conditions.
- No covers → vacuous passes go unnoticed.
- Reading values after the clock edge.
- Unbounded `##[1:$]` in simulation and assuming it would have caught a hang.
- Writing one giant property instead of several small, debuggable ones.
- Over-constraining formal with unreviewed `assume`s.

---

## 11. 60-Second Interview Pitch

> "I use immediate assertions for procedural checks and concurrent assertions for temporal rules. Concurrent properties sample values just before the clock edge, so I always read the waveform there.
>
> I write small properties: for a handshake, `$rose(req) |-> ##[1:4] ack`, plus 'req held until ack' and 'data stable while waiting', each with a cover so I know none pass vacuously. I use `disable iff` only for reset. Stalls are modeled with goto repetition, like `(!stall)[->3]`, plus a local variable to check data integrity.
>
> When a property fails, I go to the attempt's start time, check the antecedent with sampled values, and walk forward to the failing cycle. The usual suspects are level versus edge antecedents, `|->` versus `|=>`, reset polarity and X's.
>
> In formal, input properties become assumes, and I review them carefully because over-constraining hides bugs. Covers that turn out unreachable are my warning sign."

---

## 12. Hands-on Exercise (corrected version of the post's "do this next")
1. Write the handshake checker from Section 4 and `bind` it to a simple DUT.
2. Inject a bug (ack at cycle 5) and practice reading the failure: start time, fail time, sampled values.
3. Change `$rose(req)` to `req` and observe the extra failing attempts.
4. Write the stall pipeline property (Section 7) and test with random stalls.
5. If you have access to a formal tool, run the same checker with input rules as `assume`; compare with simulation.

---

## 13. Self-Check
- [ ] Can I explain immediate vs. deferred vs. concurrent?
- [ ] Can I explain sampling and read a failure on a waveform?
- [ ] Can I write the 3 handshake properties + covers from memory?
- [ ] Can I explain why `disable iff (stall)` is wrong, and write the goto version?
- [ ] Can I explain assert/assume/cover in sim vs. formal, and over-constraining?

---

## 14. Addendum: A Second Post on the Same Topic

A follow-up post repeats the AXI "ready within N cycles" myth (Challenge 10, Section 2) and adds two subtle errors worth knowing.

| Claim | Reality |
|---|---|
| `##[1:3]` "**catches off-by-one errors**" | A **range accepts every latency inside it**. If the spec says *exactly 3 cycles* and the RTL responds in 2, `##[1:3]` **passes**. Use `##3` (plus `!grant` in cycles 1–2 if early grants are illegal) for a fixed latency; use a range only when the spec allows a range |
| "**`disable_if`** for reset or power-down" | The keyword is **`disable iff`**. And disabling during power-down hides power-sequencing bugs: write separate power-state properties (Challenge 13, Section 3) |
| Add **`$isunknown`** checks to **prevent X from triggering spurious failures** | Backwards. In SVA a boolean that evaluates to **X is treated as false**, so an X on the **antecedent** makes the property **silently not fire**. That hides X bugs. Use `$isunknown` in **its own assertion** to **detect** X (`assert property (!$isunknown(req))`), never to suppress checks |
| Cover "**hits 95% of the time**" means the critical path is exercised | A cover counts **matches**; "% of cycles" isn't a meaningful target. A high hit count on the **happy path** says nothing about corners. What matters: covers for the **specific corner scenarios** (minimum latency, maximum latency, back-to-back, during back-pressure) are **each hit** |
| "3-cycle request→grant latency is **typical for a PCIe controller**" | Latency bounds come from **your design spec**, not from a "typical" value |
| Review covers in "**Cadence Incisive**" | Older simulator name (now Xcelium). Tool choice doesn't matter here |

### Exact vs. range latency (the off-by-one point)

```systemverilog
// Spec: grant exactly 3 cycles after req rises
a_exact:   assert property ($rose(req) |-> ##1 !gnt ##1 !gnt ##1 gnt);   // cycle 1: no, 2: no, 3: grant

// Spec: grant within 1 to 3 cycles
a_range:   assert property ($rose(req) |-> ##[1:3] gnt);             // accepts 1, 2 or 3

// Corner covers for the range version: each must be hit
c_lat_min: cover property ($rose(req) ##1 gnt);
c_lat_max: cover property ($rose(req) ##1 !gnt ##1 !gnt ##1 gnt);
```
(`##3 gnt` alone wouldn't fail on an **early** grant at cycle 1 or 2; the `!gnt` terms make early grants fail too. Count carefully: the consequent starts in the **same** cycle as `$rose(req)` (cycle 0), so the leading `##1` is needed to put `gnt` at cycle 3. Writing `!gnt ##1 !gnt ##1 gnt` without it would check cycle 2, an off-by-one in the assertion itself.)

### X in the antecedent

```systemverilog
// If req is X, this property never starts an attempt: X → treated as false
a_hs:     assert property ($rose(req) |-> ##[1:3] gnt);
// So check X explicitly, separately:
a_req_x:  assert property (!$isunknown(req));
a_gnt_x:  assert property (req |-> !$isunknown(gnt));
```

---

## 15. Addendum: AXI-Lite Write Ordering and Printing Values in Action Blocks

A third SVA post. Corrections:

| Claim | Reality |
|---|---|
| SVA in simulation means "**the tool will prove it works**" | Simulation **checks** the scenarios you ran. Only **formal** proves a property for all inputs (Challenge 14) |
| AXI-Lite write is the sequence **AW → W → B**, "a one-line property" | **AW and W are independent**: W may come before AW, or in the same cycle. The rule is that **B comes only after both** handshakes (needs a little tracking, 15.1) |
| A "**single-cycle** property for the address handshake" | Handshake rules (valid held until ready, payload stable) span **two cycles**: `awvalid && !awready \|=> awvalid && $stable(awaddr)` (Challenge 10) |
| Simulators "**automatically** generate coverage for each assertion" | Assertion coverage must be **enabled** with compile/run options; it reports attempts, successes, vacuous successes and failures. To see which **scenarios** happened, write **`cover property`** statements (Challenge 13, Section 7) |
| "Eliminates **90%** of spurious bugs" | Invented number |
| Print the offending values in the `$error` message | Good advice, with a trap (15.2) |

### 15.1 B only after both AW and W (one outstanding write)

```systemverilog
logic aw_done, w_done;
always_ff @(posedge clk or negedge rst_n)
  if (!rst_n) begin aw_done <= 0; w_done <= 0; end
  else if (bvalid && bready) begin aw_done <= 0; w_done <= 0; end
  else begin
    if (awvalid && awready) aw_done <= 1;
    if (wvalid  && wready)  w_done  <= 1;
  end

a_b_after_aw_w: assert property (@(posedge clk) disable iff (!rst_n)
  $rose(bvalid) |-> aw_done && w_done)
  else $error("BVALID before both AW and W handshakes (aw_done=%0b w_done=%0b)",
              $sampled(aw_done), $sampled(w_done));

c_w_before_aw: cover property (@(posedge clk) disable iff (!rst_n)
  (wvalid && wready && !aw_done && !(awvalid && awready)));
c_same_cycle:  cover property (@(posedge clk) disable iff (!rst_n)
  (awvalid && awready && wvalid && wready));
```
(BVALID can't rise in the same cycle as the last handshake, so the registered `*_done` flags are already set when it rises. For multiple outstanding writes, use counters instead of flags.)

### 15.2 The action-block trap: printed values aren't the sampled values

The property is evaluated with values **sampled before** the clock edge, but the **action block** (`else $error(...)`) runs **later in the same time step**, after the design's flops have updated. Printing a signal directly can show the **new** value, not the one that failed:

```systemverilog
// Misleading: 'wdata' here may already be the post-edge value
a_bad_msg:  assert property (wvalid && !wready |=> $stable(wdata))
  else $error("wdata changed: %h", wdata);

// Correct: print the values the assertion actually saw
a_good_msg: assert property (wvalid && !wready |=> $stable(wdata))
  else $error("wdata changed while stalled: now %h (sampled)", $sampled(wdata));
```
Use **`$sampled()`** in action blocks. Include IDs/addresses (as the post suggests), but sampled.

---

## 16. Addendum: Where Assertions Can Live, and a Classic "Complex Property" Question

A fourth SVA post. Corrections:

| Claim | Reality |
|---|---|
| "**Instantiate the property inside a UVM monitor**" | **Concurrent assertions can't be written in classes** (monitors, scoreboards). They live in **modules, interfaces, or `checker` blocks**, attached with **`bind`** (Section 4). Classes can only use **immediate** assertions. Link to coverage via `cover property` in the same checker, or by having the monitor observe the same scenario |
| "Immediate vs. concurrent: know when to use **assert vs. cover**" | Two separate ideas. **Immediate vs. concurrent** is *how* it's evaluated (procedural vs. clocked, Section 3.1). **assert vs. assume vs. cover** is *what* it does (Section 8). Both immediate and concurrent assertions can be used with assert/cover |
| "`disable iff` is **not optional**; red flag if omitted" | Use it for normal-operation rules, but it **hides reset behaviour**: you also need reset properties without it (Challenge 13, Section 3) |
| "One-line **data integrity** assertion for a FIFO" | Data integrity needs **tracking**: a reference queue (Challenge 10, Section 5) or symbolic tracking in formal (Challenge 14, Section 7) |
| "IEEE 1800-2017 intent"; "a real bug at Intel or NVIDIA" | Current standard is 1800-2023; and tell **your own** bug story (Challenge 24) |

### 16.1 The question: "`req` → `ack` within 5 cycles, and no second `req` until `ack`"

**Clarify first** (interviewers reward this): is `req` a one-cycle **pulse** or a **level** held until `ack`? Can a new `req` come in the **same cycle** as `ack`? Here: `req` is a one-cycle pulse, and a new `req` is allowed only **after** the `ack` cycle.

```systemverilog
checker req_ack_chk (logic clk, rst_n, req, ack, int MAX_LAT = 5);   // reusable, parameterized
  default clocking @(posedge clk); endclocking
  default disable iff (!rst_n);

  // 1. ack within 1..MAX_LAT cycles of req
  a_ack_in_time: assert property (req |-> ##[1:MAX_LAT] ack)
    else $error("ack not seen within %0d cycles of req", MAX_LAT);

  // 2. no new req until ack has been seen (up to and including the ack cycle)
  a_no_2nd_req:  assert property (req |=> (!req until_with ack))
    else $error("second req before ack");

  // 3. no ack without an outstanding req
  // (aux tracking: outstanding is set by req, cleared by ack)
  logic outstanding;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) outstanding <= 0;
    else if (req) outstanding <= 1;
    else if (ack) outstanding <= 0;
  a_no_spurious_ack: assert property (ack |-> outstanding);

  // Covers: the interesting latencies and back-to-back
  c_lat_min:    cover property (req ##1 ack);
  c_lat_max:    cover property (req ##MAX_LAT ack);
  c_back2back:  cover property (req ##[1:MAX_LAT] ack ##1 req);
endchecker

// Reuse across several agents/instances without touching RTL:
bind dut_top req_ack_chk u_chk0 (.clk(clk), .rst_n(rst_n), .req(req0), .ack(ack0), .MAX_LAT(5));
bind dut_top req_ack_chk u_chk1 (.clk(clk), .rst_n(rst_n), .req(req1), .ack(ack1), .MAX_LAT(8));
```
Notes worth saying out loud:
- `until_with` means "`!req` holds **up to and including** the cycle where `ack` holds". Use plain `until` if a new `req` is allowed **in** the `ack` cycle.
- `until_with` is **weak**: alone it would pass if `ack` never came. Assertion 1 supplies the bound.
- If `req` is a **level** held until `ack`, use `$rose(req)` as the antecedent and add "req held until ack" (Section 4) instead of assertion 2.
- If you can't use `checker` blocks (tool support), the same code works in a **module** with `parameter int MAX_LAT = 5`, attached with `bind`. Cycle-delay bounds like `##[1:MAX_LAT]` must be **elaboration-time constants**; the module-parameter form guarantees that on every tool.
- Assertion 3 uses the auxiliary `outstanding` flag: same idea as the tracking code in 15.1. It assumes `req` and `ack` never occur in the same cycle, which assertion 2 enforces.

### 16.2 A fifth SVA post (truncated): assertions inside UVM components

The post suggests "an `uvm_analysis_imp` that fires an `assert` every time a transaction hits the monitor". That's a **valid technique**, but be precise about what it is:

| | Concurrent SVA (module / interface / checker, via `bind`) | Immediate assertion in a UVM subscriber's `write()` |
|---|---|---|
| Sees | Signals, **every clock**, sampled values | **Completed transactions** only |
| Good for | Cycle-level rules: handshakes, stability, latency, X | Transaction-level rules: legal field combinations, response vs. request, ordering |
| Reuse | `bind` into RTL; also usable in **formal** | Testbench only (simulation) |
| Example | `valid && !ready \|=> $stable(data)` | `` assert (t.resp != EXOKAY) else `uvm_error(...) `` |

Use both: they catch different classes of bugs. Other points in the post are covered above: **four** directives including `restrict` (Section 2), `##1` vs. `##[1:3]` (Section 14), and assertion options differ by simulator, so check your tool's documentation rather than a remembered flag name.

---

## 17. Worked Review: "Find the Bugs in This Assertion"

A sixth SVA post offered this FIFO property as an example of catching real bugs. Interviewers often hand you exactly this kind of code and ask you to review it.

```systemverilog
property p_fifo_write;
  @(posedge clk) disable iff (reset)
  (wr_en && !full) |-> ##1 (wr_ptr == $past(wr_ptr)+1);
endproperty
assert property (p_fifo_write) else $error("FIFO write pointer mismatch");
```

### Bug 1 (real false failure): pointer wrap-around and expression width
`1` is a **32-bit** integer literal, so `$past(wr_ptr)+1` is computed in **32 bits**. With a 3-bit pointer at 7: `$past(wr_ptr)+1 = 8`, but the RTL correctly wraps `wr_ptr` to 0, so `0 == 8` is false: **the assertion fails on correct hardware**, every time the pointer wraps.

Fix (keep the arithmetic at pointer width):
```systemverilog
(wr_en && !full) |=> (wr_ptr == $past(wr_ptr) + 1'b1);                 // 1-bit literal: result sized to wr_ptr
// or explicitly:  wr_ptr == ptr_t'($past(wr_ptr) + 1)
```
For a **non-power-of-2** depth, the wrap is explicit: `wr_ptr == (($past(wr_ptr) == DEPTH-1) ? 0 : $past(wr_ptr) + 1'b1)`.

### Bug 2 (missing half of the rule): pointer must NOT move otherwise
The property only checks that the pointer advances on a write. A bug where the pointer **moves without a write** (or **moves when full**) passes silently.
```systemverilog
!(wr_en && !full) |=> $stable(wr_ptr);
```

### Bug 3 (design assumption): it's white-box and implementation-specific
It checks an **internal pointer**, so it only works for this implementation. An **asynchronous FIFO** usually uses **Gray-coded** pointers, which don't increment by 1 in binary; the same property would fail everywhere. Prefer black-box properties on the **interface** (no accept when full, data integrity via a reference queue, Challenge 10, Section 5) and keep white-box ones clearly tied to the micro-architecture.

### Smaller points
- `|-> ##1` is the same as `|=>`; the latter is clearer.
- `disable iff (reset)` assumes an **active-high** reset; check the polarity, and add reset properties separately (Challenge 13).
- The message should print **sampled** values, e.g. `$error("wr_ptr=%0d after write", $sampled(wr_ptr))`, and let the waveform show the history (Section 15.2).
- Add **covers**: write when one entry from full, write at pointer wrap, write and read in the same cycle.
- Claims from the post: it "runs in parallel with every stimulus" but only fires when stimulus **reaches** the scenario; "a scoreboard would miss the temporal relationship": a scoreboard catches the **data** effect, the assertion **localizes** it (Challenge 25, Section 6); "synthesizable-friendly": a subset of SVA can be synthesized for emulation, but that's a tool feature, not why it catches bugs.

**Interview takeaway:** when reviewing an assertion, check (1) **expression widths and wrap**, (2) the **other direction** of the rule, (3) **black-box vs. white-box** assumptions, (4) reset polarity and vacuity/covers.
