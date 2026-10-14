# Challenge 13: SVA Beyond the Happy Path — Reset, Errors, Illegal States, and Assertion Coverage

> **Level:** Fresher → Senior DV interview
> **Topics:** `default clocking` / `default disable iff`, what `disable iff` hides, reset properties, mid-transaction reset, error responses, illegal FSM states, "never" properties, AXI write-channel rules done right, testing your checkers, what assertion coverage really measures
> **Prerequisites:** [08 – SVA](08-sva-assertions.md), [10 – Ready/Valid](10-ready-valid-handshake-assertions.md)

---

## 1. The Post (summary)

A LinkedIn post says "stop writing SVA that only fires on the happy path" and recommends:

1. **Wrap every assertion in `clocking cb @(posedge clk);`** and add `disable iff (!reset_n)` so properties never trigger during reset.
2. Model the protocol: "the write-data channel **must not assert `wvalid` without a preceding `wready`**", with the property `wvalid |-> ##[1:3] wready`. Mentions an Intel Xeon memory controller.
3. "Enable **`assertion_coverage` in your UVM environment**"; a good suite "typically reaches **≈85%**"; if it stalls, **add properties until you see a steady climb**.

The title's idea is excellent: most escaped bugs live in reset, error and illegal-state behaviour. **But the post itself only shows a happy-path check, and gets that wrong.**

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| "Wrap every assertion in `clocking cb`" | Assertion **statements can't be placed inside a clocking block** (it can hold signal declarations, `sequence`/`property` declarations). The right tools are **`default clocking`** and **`default disable iff`** at module/interface scope (Challenge 08). Also don't confuse this with the testbench's **driver clocking block** (Challenge 07) |
| `disable iff (!reset_n)` on every assertion "eliminates false positives" | It also **switches off every check during reset**, so reset bugs become invisible. You need **separate reset properties without** `disable iff` (Section 3) |
| "`wvalid` must not be asserted without a preceding `wready`" | **Backwards.** AXI says the source **must not wait for `ready`** before asserting `valid`. A master that waits for `wready` can deadlock against a slave that waits for `wvalid` |
| `wvalid \|-> ##[1:3] wready` | Not an AXI rule: the slave may stall `wready` for any number of cycles. It's also level-sensitive (a new attempt every cycle `wvalid` is high, so it fires falsely during legal long stalls), and it's still a happy-path check |
| "`assertion_coverage` in your UVM environment" | Assertion coverage is a **simulator/coverage-tool** feature, not a UVM setting |
| "Typically ≈85%"; "add properties until it climbs" | Unsourced number. And adding a new assertion that isn't exercised yet **lowers** the percentage. Chasing the number is metric gaming (Section 7) |

---

## 3. Reset: The Most Common Unhappy Path

`default disable iff (!rst_n)` is right for **normal-operation** properties. Add reset-specific properties **without** it:

```systemverilog
// (a) During reset: outputs idle. AXI requires VALID signals low during reset.
a_idle_in_reset:   assert property (@(posedge clk) !rst_n |-> !wvalid && !awvalid && !bvalid);

// (b) First cycle after reset: known values, no X
a_known_after_rst: assert property (@(posedge clk) $rose(rst_n) |-> !$isunknown({state, count, wvalid}));

// (c) Registers come out of reset with spec values
a_reset_values:    assert property (@(posedge clk) $rose(rst_n) |-> state == IDLE && count == 0);

// (d) Reset in the middle of a transaction: nothing half-done afterwards
a_no_stale_resp:   assert property (@(posedge clk) $rose(rst_n) |-> outstanding == 0 && !bvalid);
```

Then **cover** the risky cases so you know tests exercised them:
```systemverilog
c_reset_mid_burst:  cover property (@(posedge clk) wvalid && !wlast ##1 !rst_n);
c_reset_during_stall: cover property (@(posedge clk) (wvalid && !wready) ##1 !rst_n);
```

**Bugs these catch:** registers missing from the reset list, FSMs that leave reset in the wrong state, FIFOs whose pointers reset but whose `count` doesn't, stale responses after reset.

Note on (d): adapt to your design's spec; the point is to **write down** what "clean after reset" means and check it.

---

## 4. Error Responses: The Other Unhappy Path

Example spec: *"A write to an unmapped address returns DECERR; memory is not modified; the response is still returned."*

```systemverilog
// Response still arrives (no hang on error)
a_err_resp_returns: assert property (@(posedge clk) disable iff (!rst_n)
  (awvalid && awready && !addr_mapped(awaddr)) |-> ##[1:MAX_LAT] (bvalid && bresp == 2'b11));

// No side effect: the internal memory write enable never fires for an unmapped address
// (white-box check on RTL internals: adapt signal names)
a_no_write_on_err:  assert property (@(posedge clk) disable iff (!rst_n)
  mem_we |-> addr_mapped(mem_addr));

c_decerr: cover property (@(posedge clk) bvalid && bready && bresp == 2'b11);
c_slverr: cover property (@(posedge clk) bvalid && bready && bresp == 2'b10);
```

Unhappy-path checklist for any interface:
- Error **response** generated (SLVERR/DECERR, NACK, parity error flag).
- **No side effects** on error (no write, no state change).
- **Recovery**: next transaction after an error works normally.
- **Error + backpressure** at the same time.
- **Error on the last beat** of a burst.

---

## 5. Illegal States and "Never" Properties

```systemverilog
// FSM: only legal states, only legal transitions
a_state_legal:  assert property (state inside {IDLE, ADDR, DATA, RESP});
a_idle_next:    assert property ($past(state) == IDLE |-> state inside {IDLE, ADDR});

// One-hot / mutual exclusion
a_onehot_state: assert property ($onehot(state_oh));
a_grant_mutex:  assert property ($onehot0(grant));

// Overflow / underflow
a_no_overflow:  assert property (count == DEPTH |-> !push || pop);
a_no_underflow: assert property (count == 0     |-> !pop);

// Never: write and read the same bank in the same cycle (if the spec forbids it)
a_no_bank_conflict: assert property (!(wr_en && rd_en && wr_bank == rd_bank));
```
(Using the module's `default clocking` and `default disable iff`.)

These are cheap to write, rarely fire on happy paths, and catch the bugs that random tests hit once in a thousand seeds.

---

## 6. AXI Write Channel, Done Right

The real rules for the W channel (and the B response):

```systemverilog
// Source rules: hold and stability (never "wait for ready")
a_w_hold:    assert property (wvalid && !wready |=> wvalid);
a_w_stable:  assert property (wvalid && !wready |=> $stable({wdata, wstrb, wlast}));

// WLAST on exactly the last beat: count beats against AWLEN
// (simplified: one write burst at a time, AW accepted before W)
logic [7:0] beat_cnt, exp_len;
always_ff @(posedge clk or negedge rst_n)
  if (!rst_n) beat_cnt <= 0;
  else if (wvalid && wready) beat_cnt <= wlast ? 0 : beat_cnt + 1;
always_ff @(posedge clk) if (awvalid && awready) exp_len <= awlen;

a_wlast_pos: assert property (wvalid && wready |-> (wlast == (beat_cnt == exp_len)));

// Write response only after the last data beat (AXI4: after both AW and last W)
a_b_after_last: assert property ($rose(bvalid) |-> wr_done_pending);  // wr_done_pending set by AW+WLAST handshakes in aux code

// Deadlock guard (bounded, from spec)
a_w_no_hang: assert property (wvalid && !wready |-> ##[1:MAX_WAIT] wready);

// Covers for the unhappy paths
c_w_long_stall: cover property ((wvalid && !wready)[*8] ##1 wready);
c_w_before_aw:  cover property (wvalid && !awvalid);   // AXI allows W data before AW
```

Note `c_w_before_aw`: AXI allows write data to arrive **before** the address. Slaves that assume AW comes first are a classic bug, so the **cover** proves your tests tried it, and the beat counter above would need extending for that case.

---

## 7. What Assertion Coverage Really Measures

For each **assertion**, the simulator can report:
- **Attempts**: how many times evaluation started.
- **Real (non-vacuous) successes**: the antecedent matched and the consequent held.
- **Vacuous successes**: the antecedent never matched (nothing checked).
- **Failures**.

For each **cover property**: number of matches.

**The goal is not a percentage. The goal is:**
1. Every assertion has **at least one non-vacuous success** (it actually checked something).
2. Every cover property is **hit**.
3. Any assertion that is only ever vacuous is investigated: either tests don't reach it (stimulus gap), or the antecedent is written wrong (assertion bug).

Adding unexercised assertions **lowers** the number. That's fine: it shows real gaps. Never write assertions just to "make it climb".

---

## 8. Testing the Checkers Themselves

An assertion that can never fail is worse than none: it gives false confidence.
- **Mutation / bug injection**: deliberately break the RTL (e.g., force `wlast` one beat early) and confirm the assertion fires.
- **Negative tests**: drive illegal stimulus on purpose (protocol error injection) and confirm the right assertion fails. In UVM, use a **report catcher** to demote the expected error so the test passes only if the error happened.
- **Formal**: assertions that are proven too easily may be vacuous or over-constrained; check covers are reachable.

---

## 9. Likely Follow-ups (with model answers)

**Q. Isn't `disable iff (!rst_n)` always right?**
For normal-operation rules, yes. But it hides reset bugs, so I add separate reset properties without it: outputs idle during reset, known values and spec reset values after reset, and clean behaviour after a mid-transaction reset.

**Q. Can a master wait for `wready` before asserting `wvalid`?**
No. Valid must not depend on ready, otherwise master and slave can deadlock waiting for each other.

**Q. What does assertion coverage tell you?**
Whether each assertion was actually exercised non-vacuously, and whether covers were hit. An assertion that's only vacuously passing checked nothing.

**Q. How do you know an assertion would catch a bug?**
Inject the bug (mutation) or illegal stimulus and confirm it fires; check its cover and non-vacuous count.

**Q. Name three unhappy-path categories you always check.**
Reset (during, after, mid-transaction), error responses (returned, no side effects, recovery), and illegal states (FSM legality, one-hot, overflow/underflow, mutual exclusion).

---

## 10. Common Fresher Mistakes
- `disable iff` everywhere and no reset properties.
- Getting the valid/ready dependency backwards.
- Inventing latency windows the protocol doesn't require.
- No covers on error and reset scenarios.
- Treating assertion coverage as a percentage to push up.
- Never testing that an assertion can fail.

---

## 11. 60-Second Interview Pitch

> "Happy-path handshake checks are the baseline. Most escapes are in reset, errors and illegal states, so I write properties for those deliberately.
>
> I use default clocking and default disable iff for normal-operation rules. Because that hides reset behaviour, I add reset properties without it: valids low during reset, known spec values after reset, and nothing stale after a mid-transaction reset, with covers on reset during a burst and during a stall.
>
> For errors, I check that a response still returns, there are no side effects, and the next transaction recovers. For illegal states, I check legal FSM states and transitions, one-hot, mutual exclusion and overflow. On AXI I check the real source rules, never 'valid waits for ready', and I cover W before AW.
>
> For assertion coverage, I make sure every assertion has a non-vacuous success and every cover is hit, rather than chasing a percentage. And I prove the checkers work by injecting bugs and confirming they fire."

---

## 12. Self-Check
- [ ] Can I explain what `disable iff` hides and write 3 reset properties?
- [ ] Can I list the unhappy-path checklist for an interface?
- [ ] Can I explain why "valid waits for ready" deadlocks?
- [ ] Can I explain vacuous vs. non-vacuous success in assertion coverage?
- [ ] Can I describe how to prove an assertion actually catches a bug?
