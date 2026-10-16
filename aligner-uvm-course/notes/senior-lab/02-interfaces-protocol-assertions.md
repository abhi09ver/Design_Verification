# Interfaces & protocol assertions

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 2 · where pins meet classes

## Interfaces & protocol assertions

The interface is the only thing DUT and testbench share. It's also the best home for protocol rules: an assertion there works in every test, at block and SoC level, and in formal. You'll read your 14 MD assertions and 15 APB assertions, then write the one rule nobody wrote.

SVA sampling semantics$past / $stable / $felldisable iffhas\_checks plumbingrace-free driving

### 2.1One MD handshake, with the assertions that guard it

Transfer A waits 3 cycles for `ready`. Transfer B is illegal (size 2 at offset 1) and gets `err` in its single cycle. Shaded amber is where the stability assertions are active. Red dashes mark the cycles where the other assertions evaluate.

*[Diagram: MD valid/ready waveform with assertion windows. Open the HTML page to see it.]*

Every value in a concurrent assertion is the value *sampled just before* the clock edge (the Preponed region). That's why `$past(ready)` means "ready in the previous cycle", and why NBA-driven signals never race with the assertion.

### 2.2Code walkthrough: `cfs_md_if.sv`

```systemverilog
property valid_high_until_ready_p;
  @(posedge clk) disable iff(!reset_n || !has_checks)
  $fell(valid) |-> $past(ready) == 1;
endproperty
VALID_HIGH_UNTIL_READY_A : assert property(valid_high_until_ready_p);

property stable_data_until_ready_p;
  @(posedge clk) disable iff(!reset_n || !has_checks)
  valid & $past(valid) & !$past(ready) |-> $stable(data) == 1;
endproperty

property err_high_at_valid_and_ready_p;
  @(posedge clk) disable iff(!reset_n || !has_checks)
  err |-> valid & ready;
endproperty

//elaboration-time parameter check (not an assertion)
if($log10(DATA_WIDTH)/$log10(2) - $clog2(DATA_WIDTH) != 0)
  $error("DATA_WIDTH is not a power of two ...");
```

1. **`disable iff` with two terms.** Reset kills any in-flight attempt. `has_checks` lets an error-injection test switch the rules off without editing the interface.
2. **Read it backwards.** "If valid just fell, ready must have been high last cycle." That's the same rule as "valid holds until ready", written so it only evaluates at the moment of a violation.
3. **Stability needs history.** `$past(valid) & !$past(ready)` says "we're still inside the same transfer". Without it, a new back-to-back transfer with different data would falsely fire.
4. **Implication direction matters.** `err |-> valid & ready` forbids err outside a handshake. Writing `valid & ready |-> err` would demand an error on every transfer.
5. **Elaboration-time checks** (a generate `if` with `$error`) catch bad parameters before time 0. They're free, and catch the "someone built it with width 24" mistake.

### 2.3Hidden concepts

has\_checks is policed

The agent config writes `vif.has_checks`, and its `run_phase` watches the signal. If someone flips it directly in the interface, it raises `ALGORITHM_ISSUE`. One source of truth for a knob that two worlds (class and module) can touch.

No clocking blocks, still race-free

Drivers use NBAs (`vif.valid <= 1`) and read right after `@(posedge clk)`, before that edge's NBAs land, so they see the pre-edge value. It works, but it's convention-based. A clocking block makes the same timing explicit and harder to break. Expect "what's a clocking block for?" in interviews.

The monitor's 1 ns skew

The MD monitor waits `sample_delay_start_tr = 1ns` after the edge before testing `valid`. That's a hand-written input skew, the thing a clocking block's `input #1` would give you.

$isunknown guards

Half the assertions are X-checks, gated by `valid` or `psel`. X on data while valid is a real RTL bug (uninitialised flop). X on data while idle is legal, so the gating is the skill.

Interfaces travel; monitors don't

At SoC level your agents may be gone, but the interface (or a `bind`-ed checker) keeps checking. Protocol rules belong in SVA. Data and ordering rules belong in the scoreboard.

APB phases as sequences

`setup_phase_s` is a named `sequence` reused by three properties. Building small named sequences is how you keep a 30-assertion file readable and reviewable.

### 2.4Findings in your interfaces

Missing rule · APB ≤ 5 wait states

The datasheet (§4.3) says more than 5 wait states is illegal. No assertion checks it. The only guard is the monitor's `stuck_threshold` of **1000** cycles. A DUT taking 6 wait states passes every test today.

TB-only rule in a protocol file

`SIZE_PLUS_OFFSET_GT_DATA_WIDTH_A` enforces `size + offset ≤ W/8`, the rule that isn't in the datasheet (Module 0). Applied to `md_tx_if` it checks the DUT. Applied to `md_rx_if` it forbids stimulus the RTL would accept. Know which side each assertion is policing.

No cover properties

Every rule is an `assert` and none is a `cover`. You can't prove the 3-wait-state case or err-on-first-cycle ever happened. Assertion coverage is half of protocol sign-off.

### 2.5Bug hunt

**Q: BUG 1 You rewrite the stability check as valid & !ready |=> $stable(data) . Back-to-back legal transfers now pass, but a DUT bug where data changes in the same cycle ready rises is missed.**

**Root cause:** `|=>` checks the *next* cycle and only while ready is low now. The original form looks at the previous cycle's handshake state, so it covers every cycle up to and including the accept cycle. Draw the waveform before choosing `|->` vs `|=>`.

**Q: BUG 2 Your error-injection test sets vif.has\_checks = 0 from the test to drive illegal traffic, and gets an ALGORITHM\_ISSUE error.**

**Root cause:** the agent config owns the knob. Call `agent_config.set_has_checks(0)`, which updates both the class flag and the interface. Interviewers like this one: "who owns a knob that lives in two places?"

**Q: BUG 3 A reset in the middle of a transfer fires VALID\_HIGH\_UNTIL\_READY\_A .**

**Root cause:** it would, without `disable iff(!reset_n)`. Valid legally drops during reset. The `disable iff` is evaluated asynchronously, so it also aborts attempts that started before reset. Remove it and see the false failure.

### 2.6Interview drill

**Q: Q1 "What's the difference between |-> and |=> , and when does $past beat both?"**

`|->` checks the consequent in the same cycle the antecedent matches; `|=>` checks it one cycle later. `$past` lets you trigger on the *effect* (valid fell) and check the *cause* (ready last cycle), so the assertion only does work at violation points. It's cheaper and its failure message points at the exact cycle.

Cross-questions

- What does `$past` return at the first clock after reset? (The initial value. Guard with reset or `disable iff`.)
- Why are sampled values taken in Preponed? (So the assertion sees a stable, race-free snapshot regardless of process ordering at the edge.)

**Q: Q2 "Assertions in the interface, in a bind -ed checker, or in the monitor: which and why?"**

Pure signal-level protocol goes in the interface or a bound checker: zero-time, reusable at SoC level, and formal-friendly. `bind` wins when you can't edit the interface, or need to reach internal RTL signals. The monitor (procedural checks) is for things needing transaction context, like the stuck-transfer threshold. Data correctness goes to the scoreboard, never SVA.

Cross-question

- How would you formally prove the legality rule? (Assume the APB and MD protocols as constraints, assert `md_rx_err == !legal(offset,size)` at handshake. With 4×8 input combos, it converges in seconds.)

**Q: Q3 "Why does your TB work without clocking blocks? Would you add them?"**

Drivers write with NBAs and sample right after the edge, which reads pre-edge values. The monitor adds a 1 ns skew. That's correct but fragile: a blocking assignment or a `#0` somewhere breaks it. Clocking blocks encode input/output skew in one place and make the synchronisation contract explicit. I'd add them in a production VIP, and keep this pattern only for teaching.

### 2.7Lab

```systemverilog
// add to cfs_apb_if.sv: the rule the datasheet has and the TB doesn't
property max_5_wait_states_p;
  @(posedge pclk) disable iff(!preset_n || !has_checks)
  $rose(penable) |-> ##[0:5] pready;
endproperty
MAX_5_WAIT_STATES_A : assert property(max_5_wait_states_p) else
  $error("APB transfer exceeded 5 wait states");

// and prove the limit case is actually exercised
MAX_5_WAIT_STATES_C : cover property(@(posedge pclk) disable iff(!preset_n)
  $rose(penable) ##0 (!pready)[*5] ##1 pready);
```

- Add the assertion and cover above, run `cfs_algn_test_reg_access`, and check the log for the cover's hit count. Does the DUT ever reach 5 wait states?
- Break it on purpose: change `##[0:5]` to `##[0:1]`. The failures show you which register accesses take wait states.
- Write a cover for "MD transfer accepted with err on its first cycle" on `md_rx_if`.
