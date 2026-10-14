# Challenge 10: Checking a Ready/Valid Handshake with SVA — Stalls, Dropped Data, Deadlock, Variable Latency

> **Level:** Fresher → Senior DV interview
> **Topics:** ready/valid rules (AXI-style), what assertions can and can't catch, assertion + modeling code, bounded wait (deadlock), variable latency with outstanding IDs, action blocks and severity, why two simulators may disagree
> **Prerequisite:** [08 – SVA](08-sva-assertions.md) (operators, sampling, vacuity, debugging)

---

## 1. The Post (summary)

A LinkedIn post says "stop writing SVA just to prove a signal toggles" and recommends:

1. Write properties for the **ready && valid** handshake; "use the **`#` delay** to enforce the one-cycle relationship", and add an **`else` clause that flags any stray `valid` without a matching `ready`**. Mentions NVIDIA GPU accelerators using AXI-4 Lite.
2. Model variable latency with "**bounded repeats**": `##[0:$]` or `##[5:10]`, citing Intel Xeon response times of 5–10 cycles.
3. "Pair **immediate** assertions with coverage": "an `assert property` will **stop the simulation on the first failure**"; running in VCS and Xcelium "often reveals an **80% jump** in uncovered corner cases".
4. "Run in both VCS and Xcelium, compare the false-positive count, and **adjust the bounds until they converge**."

The opening line is good advice: protocol-level properties beat toggle checks. **Nearly everything after it is wrong**, and point 4 is actively harmful.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| Use `#` delay in a property | `#` is a procedural delay. SVA cycle delay is **`##`** (also covered in Challenge 08) |
| "One-cycle relationship" between valid and ready | There is none. A transfer happens **in the cycle both are high**. Ready may come 0, 1, or 100 cycles after valid |
| `else` clause "flags stray valid without ready" | `valid && !ready` is a **legal stall**, not an error. The `else` is just the **action block** run when an assertion fails; it doesn't add a check |
| `##[0:$]` and `##[5:10]` are "bounded repeats" | `##[m:n]` is a **cycle-delay range**. Repetition is `[*n]`, `[->n]`, `[=n]`. And `##[0:$]` is **unbounded**, not bounded; in simulation it's weak and never fails if the event never comes |
| "Pair **immediate** assertions with coverage" then shows `assert property` | `assert property` is a **concurrent** assertion |
| "`assert property` stops the simulation on the first failure" | Default failure action is **`$error`: the sim continues**. It stops only if the action block uses `$fatal`, or your UVM quit-count is reached |
| "VCS vs. Xcelium shows an 80% jump in uncovered corners" | Same RTL + same TB + same assertions should give the **same results** on any compliant simulator. A difference points to a **race or non-determinism** in your code (Section 7) |
| "**Adjust the bounds until the tools converge**" | Never. Bounds come from the **spec**. Tuning a bound until failures disappear is hiding bugs |
| Handshake assertions catch "dropped data" and "deadlocks" | Not by themselves. Dropped data needs **counting or a reference queue**; deadlock needs a **bounded-wait** property (Sections 4–5) |

---

## 3. The Ready/Valid Rules (AXI-style)

| # | Rule | Who must obey |
|---|---|---|
| R1 | Transfer happens when `valid && ready` in the same cycle | — |
| R2 | Once `valid` is high, it **stays high until the transfer** | Source |
| R3 | **Payload stable** while `valid && !ready` | Source |
| R4 | Source must **not wait for `ready`** before raising `valid` (avoids deadlock) | Source |
| R5 | `ready` **may** wait for `valid`, and may go high/low freely before `valid` | Sink (no rule to check) |
| R6 | `valid` low during reset; no X on `valid` after reset | Source |

**Common mistake:** writing an assertion that `ready` must stay high, or that `valid` must be followed by `ready` in N cycles. Neither is in the basic protocol (the second is a **design-specific latency** requirement).

### Assertions for R2, R3, R6

```systemverilog
module rv_checker #(parameter int W = 32, MAX_WAIT = 64)
  (input logic clk, rst_n, valid, ready, input logic [W-1:0] data);

  default clocking @(posedge clk); endclocking
  default disable iff (!rst_n);

  wire fire = valid && ready;

  // R2: valid held until transfer
  a_valid_hold:  assert property (valid && !ready |=> valid)
    else `uvm_error("RV", "valid dropped before handshake")

  // R3: payload stable while stalled
  a_data_stable: assert property (valid && !ready |=> $stable(data))
    else `uvm_error("RV", "data changed while stalled")

  // R6: no X on valid (outside reset); data known when valid
  a_valid_known: assert property (!$isunknown(valid));
  a_data_known:  assert property (valid |-> !$isunknown(data));

  // Covers: prove the interesting cases happen
  c_stall_1:     cover property (valid && !ready ##1 fire);
  c_stall_long:  cover property ((valid && !ready)[*8] ##1 fire);
  c_b2b:         cover property (fire ##1 fire);
  c_ready_first: cover property (ready && !valid ##1 fire);
endmodule
```

Note: `` `uvm_error `` in the action block makes the failure count in the UVM report summary and respects UVM verbosity/quit-count settings. Plain `$error` doesn't. The checker module then needs `` `include "uvm_macros.svh" `` and `import uvm_pkg::*;`; use `$error` instead if the checker must also run without UVM (e.g., in formal).

(R4 can't be fully checked by a property, since "doesn't depend on" is a causal claim. Covers like `c_ready_first` and its opposite, plus formal with `ready` tied low, catch violations: with `ready` held low, a correct source must still raise `valid`.)

---

## 4. Deadlock: Bounded Wait

"Valid stuck forever" is a deadlock. An unbounded `##[1:$]` won't fail in simulation. Use a **bound from the spec** (or a generous system-level timeout):

```systemverilog
a_no_deadlock: assert property (valid && !ready |-> ##[1:MAX_WAIT] ready)
  else `uvm_error("RV", $sformatf("stalled > %0d cycles", MAX_WAIT))
```
In formal, use a liveness form (`s_eventually ready`) with fairness assumptions on the sink.

---

## 5. Dropped or Duplicated Data: Assertions + Modeling Code

Handshake rules can all pass while the design **loses** a transfer internally (e.g., a FIFO overwrite). You need to **track** what went in.

**Example: FIFO with in/out ready-valid ports.** Put a small reference queue in the checker module ("auxiliary modeling code") and check on every pop:

```systemverilog
module fifo_data_chk #(parameter int W = 32, DEPTH = 8)
  (input logic clk, rst_n,
   input logic in_valid, in_ready, input logic [W-1:0] in_data,
   input logic out_valid, out_ready, input logic [W-1:0] out_data);

  logic [W-1:0] model_q[$];
  wire push = in_valid  && in_ready;
  wire pop  = out_valid && out_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) model_q.delete();
    else begin
      if (pop) begin
        a_not_empty: assert (model_q.size() > 0)
          else `uvm_error("FIFO", "pop from empty: duplicated/spurious data")
        if (model_q.size() > 0) begin
          a_order: assert (out_data == model_q[0])
            else `uvm_error("FIFO", $sformatf("exp %h got %h", model_q[0], out_data))
          void'(model_q.pop_front());
        end
      end
      if (push) model_q.push_back(in_data);
    end
  end

  // Structural: never accept when full, never offer when empty
  a_no_overflow:  assert property (@(posedge clk) disable iff (!rst_n)
                    model_q.size() == DEPTH |-> !in_ready);
  a_no_underflow: assert property (@(posedge clk) disable iff (!rst_n)
                    model_q.size() == 0 |-> !out_valid);
endmodule
```

Note the order inside the `always_ff`: pop is checked **before** this cycle's push is added, so a same-cycle push/pop with an empty FIFO correctly flags a spurious output. Adjust if your FIFO supports bypass (data in and out the same cycle).

For a whole bus with many transactions, this is the job of a **UVM scoreboard**; inside a block-level checker or formal setup, auxiliary code is the standard technique.

---

## 6. Variable Latency the Right Way

Spec: *"Each read request gets its response in 5 to 10 cycles. Up to 4 reads may be outstanding, with unique IDs."*

**Naive (wrong with multiple outstanding):**
```systemverilog
assert property (ar_fire |-> ##[5:10] r_fire);
// passes if ANY response arrives in the window — possibly for a different request
```

**Correct: tie request and response with a local variable on the ID:**
```systemverilog
property p_rd_latency;
  logic [3:0] id;
  (ar_valid && ar_ready, id = ar_id)
    |-> ##[5:10] (r_valid && r_ready && r_id == id);
endproperty
a_rd_latency: assert property (p_rd_latency);
```

Plus outstanding-count checks with a tiny counter:
```systemverilog
int outstanding;
always_ff @(posedge clk or negedge rst_n)
  if (!rst_n) outstanding <= 0;
  else outstanding <= outstanding + (ar_valid && ar_ready) - (r_valid && r_ready);

a_max_out:  assert property (@(posedge clk) disable iff (!rst_n) outstanding <= 4);
a_no_ghost: assert property (@(posedge clk) disable iff (!rst_n)
              (r_valid && r_ready) |-> outstanding > 0);
c_full_out: cover property  (@(posedge clk) outstanding == 4);
```

Where do 5 and 10 come from? **The spec or the micro-architecture document**, never from what the simulation happens to show.

---

## 7. When Two Simulators Disagree

Same code giving different results on VCS and Xcelium (or Questa) is a **bug in your environment**, not a coverage opportunity. Usual causes:

| Cause | Example | Fix |
|---|---|---|
| **Race in TB** | Driver uses blocking assignment at `@(posedge clk)`; DUT/assertion sees old or new value depending on scheduler order | Drive through a **clocking block** or nonblocking `<=` |
| **Unspecified ordering** | Two `initial`/`always` blocks depending on execution order at time 0 | Remove the dependency |
| **X handling** | `if (x)` behaviour, X-propagation options differ | Explicit X checks; same X-prop settings |
| **Random stability** | Different seeds/random generators across tools | Expected: random tests don't match across tools; compare **directed** tests or pass/fail, not stimulus |
| **Tool-specific options/defaults** | Different time precision, coverage options | Align compile/run options |

**Never** change spec-derived bounds to make tools agree.

---

## 8. Controlling Assertions at Runtime
- `$assertoff(0, top.dut.u_chk)` / `$asserton` / `$assertkill`: disable checks during deliberate error-injection windows or power-down, then re-enable.
- Prefer `disable iff` for reset and `$assertoff` for **test-specific** windows, documented in the test.
- Severity: `$info`, `$warning`, `$error`, `$fatal`; use `$fatal` only where continuing is meaningless.

---

## 9. Likely Follow-ups (with model answers)

**Q. Is `valid && !ready` an error?**
No, it's a stall. The rules are that valid stays high and data stays stable until the transfer.

**Q. Why can all handshake assertions pass while data is lost?**
They check each interface locally. Loss happens inside the design. You need a reference queue or a scoreboard comparing in vs. out.

**Q. How do you check latency when several requests are outstanding?**
Capture the ID in a local variable at request time and match the response with the same ID. Also check the outstanding count.

**Q. Why does `##[1:$]` not catch a hang in simulation?**
It's weak: if the sim ends before the event, there's no failure. Use a bound, or `s_eventually` / `strong()` to fail at end of sim.

**Q. Does a failing `assert property` stop the simulation?**
Not by default (`$error`). It stops with `$fatal` in the action block or when the UVM error quit-count is hit.

**Q. Two simulators give different assertion results. First thing you check?**
Races between TB drive and DUT/assertion sampling: blocking assignments at the clock edge without clocking blocks.

---

## 10. Common Fresher Mistakes
- Treating stall (`valid && !ready`) as an error.
- Asserting a fixed valid→ready delay that the protocol doesn't require.
- Expecting handshake assertions to catch dropped data.
- Unbounded `##[1:$]` as a deadlock check in simulation.
- Matching responses to requests without the ID.
- Tuning assertion bounds to make failures go away.

---

## 11. 60-Second Interview Pitch

> "For a ready/valid interface I check the source rules: valid held until the transfer, payload stable while stalled, no X on valid, with covers for single-cycle stalls, long stalls, back-to-back transfers and ready-before-valid. A stall itself is legal.
>
> Those properties are local, so they can't see dropped or duplicated data. For that I add a reference queue in the checker, or a scoreboard at UVM level, and compare every pop in order. For deadlock I use a bounded wait from the spec, since an unbounded delay is weak in simulation.
>
> For variable latency with multiple outstanding requests, I capture the ID in a local variable and match the response with the same ID inside the spec's window, plus a counter for the outstanding limit. If two simulators disagree, I look for a race in the testbench, usually blocking drives at the clock edge, and never adjust spec bounds to make the failures go away."

---

## 12. Self-Check
- [ ] Can I list the 6 ready/valid rules and which side owns each?
- [ ] Can I write valid-hold and data-stable assertions with covers?
- [ ] Can I explain why dropped data needs modeling code or a scoreboard?
- [ ] Can I write the ID-matched latency property?
- [ ] Can I list 3 reasons two simulators would disagree?
