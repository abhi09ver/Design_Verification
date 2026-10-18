# Lesson 04 · Branch prediction

12 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Why predict branches](#l04-01-why-predict-branches)
2. [How much prediction is worth](#l04-02-how-much-prediction-is-worth)
3. [Branch target buffer (BTB)](#l04-03-branch-target-buffer-btb)
4. [Direction predictor: BHT with BTB](#l04-04-direction-predictor-bht-with-btb)
5. [1-bit predictor and its limits](#l04-05-1-bit-predictor-and-its-limits)
6. [2-bit saturating counter (2BC)](#l04-06-2-bit-saturating-counter-2bc)
7. [History-based predictors](#l04-07-history-based-predictors)
8. [The cost of long histories](#l04-08-the-cost-of-long-histories)
9. [PShare: private history, shared counters](#l04-09-pshare-private-history-shared-counters)
10. [GShare: global history](#l04-10-gshare-global-history)
11. [Tournament and hierarchical predictors](#l04-11-tournament-and-hierarchical-predictors)
12. [Return address stack (RAS)](#l04-12-return-address-stack-ras)

---

## L04-01 Why predict branches

*Branch in a pipeline · BP requirements*

> The next PC is needed one cycle after fetch, long before the branch is even decoded. So every pipelined CPU guesses.

**Concepts**

- Fetch needs the next PC **immediately**; a branch is only identified at decode and resolved several stages later.
- A predictor must answer, from the **PC alone**: is this a branch? taken? to which target?
- Even “PC + 4” is a predictor, and it always beats “stop fetching until sure”.
- Back-to-back mispredicts: the second branch was on the wrong path, so it is flushed by the first; the penalty is paid once (shadowed).

**Numbers & formulas:** `penalty = stages until resolve` · `predict from PC only`

**Verification lens**

- Prediction never changes architectural results, so co-sim cannot see a bad predictor. Check recovery (flush exactness, redirect PC) and track predictor quality with perf counters.
- Cover a wrong-path branch that itself mispredicts: its recovery must be suppressed by the older flush.

**Bugs that ship**

- Younger wrong-path branch resolves first and redirects fetch
- Redirect PC taken from a flushed instruction

**Interview**

<details><summary>Two branches in flight both mispredict. Which recovery wins?</summary>

The older one. It flushes the younger branch, so the younger branch’s redirect must be cancelled. Cover same-cycle and younger-first resolution orders.

</details>

---

## L04-02 How much prediction is worth

*Branch prediction benefit · predict not-taken*

> The deeper and wider the pipeline, the more each mispredict costs, so the more a good predictor pays back.

**Concepts**

- Same predictor improvement: **15%** CPI gain when branches resolve in stage 3, **61%** when they resolve in stage 10.
- A 4-wide core wastes 4 instruction slots per mispredict cycle, so wide cores gain several times more from better prediction.
- **Predict not-taken** (just fetch PC + 4) is right about **88%** of the time on typical code.
- Method for quizzes: find the ideal CPI by removing the current branch penalty, then add back the new penalty.

**Numbers & formulas:** `CPI = CPI_ideal + br% × miss% × penalty` · `not-taken ≈ 88% right`

**Verification lens**

- Perf verification compares MPKI (mispredicts per 1000 instructions) per benchmark with the perf model; a silent predictor bug shows up only here.

**Interview**

<details><summary>20% branches, 95% accuracy, 15-cycle penalty, ideal CPI 0.25 on a 4-wide core. Real CPI?</summary>

0.25 + 0.2 × 0.05 × 15 = 0.25 + 0.15 = 0.40. Mispredicts add 60% to the cycle count.

</details>

---

## L04-03 Branch target buffer (BTB)

*BTB*

> A small table indexed by PC that remembers where a taken branch went last time.

**Concepts**

- Index with low PC bits; read the predicted next PC in the same cycle as fetch.
- On resolve, if mispredicted, write the correct target at the same index.
- Size: only the branches you will meet soon need entries (a 100-instruction loop needs ~100 entries, not one per PC).
- Timing decides size: e.g. 1024 entries fit in one cycle, so index with **PC[11:2]** (drop the byte offset of 4-byte instructions).
- Simplest mapping (low bits) because index logic + read must fit in one cycle.

**Numbers & formulas:** `1024 entries → 10 index bits` · `index = PC[11:2]`

**Verification lens**

- BTB aliasing is legal (it only costs performance) but must never send fetch to a misaligned or mid-instruction address on variable-length ISAs without a check.
- Cover: alias between two branches, target change of an indirect branch, self-modifying code after a BTB fill.

**Bugs that ship**

- Stale BTB entry after code is rewritten, with no flush on the code-modification path
- Target that crosses a page fetched without a translation check

**Interview**

<details><summary>Which PC bits index a 1024-entry BTB for a fixed 4-byte ISA, and why not bits [9:0]?</summary>

PC[11:2]. Bits [1:0] are always zero for aligned 4-byte instructions, so using them would waste three quarters of the entries.

</details>

---

## L04-04 Direction predictor: BHT with BTB

*Direction predictor · BHT + BTB quizzes*

> Split “taken?” from “where?”: a big 1-bit-per-entry BHT for direction, a small BTB only for taken branches.

**Concepts**

- **BHT** is read for every fetched instruction: is this a taken branch?
- Only if the BHT says taken do we read the **BTB** for the target.
- On resolve: taken → set BHT bit and write target into BTB; not-taken → clear the bit, BTB untouched.
- BHT bits are cheap, so it can be large; the BTB stays small.
- Quiz: in a 100-iteration loop, the loop-back `B` reads the BTB 100 times; a branch taken once reads it once.

**Numbers & formulas:** `BHT: 1 bit/entry, large` · `BTB: target per entry, small`

**Verification lens**

- Model the BHT and BTB update rules in a predictor reference model, and check the update happens on the resolving (or retiring) instance only, not on wrong-path ones (unless the spec says speculative update).

**Interview**

<details><summary>Should the predictor be trained at resolve or at retire?</summary>

Retire avoids training on wrong-path branches but trains late. Resolve trains early but must ignore flushed branches. Either is legal; the spec must say which, and DV checks that choice.

</details>

---

## L04-05 1-bit predictor and its limits

*1-bit predictor · problems*

> Remembers the last outcome. Great for long loops, two mispredicts per anomaly.

**Concepts**

- Predicts the branch does what it did last time.
- Long loop: 1 mispredict on entry, 1 on exit. Your example: **2 mispredicts in ~600 instructions**.
- An anomaly (one odd outcome) costs **two** mispredicts: the odd one, and the next one because the bit flipped.
- Bad for: branches with roughly equal T and NT, and short inner loops inside big loops.

**Numbers & formulas:** `anomaly = 2 mispredicts`

**Verification lens**

- Directed patterns per predictor: long loop, short nested loop, alternating, one anomaly. Expected mispredict counts become self-checking perf tests.

**Interview**

<details><summary>A 3-iteration inner loop runs inside a big loop. 1-bit predictor mispredicts per inner run?</summary>

2: the exit (predicted taken, actually not taken) and the next entry (bit now says not taken).

</details>

---

## L04-06 2-bit saturating counter (2BC)

*2-bit predictor · initialisation · worst case*

> Prediction bit plus a confidence bit: one anomaly costs one mispredict, a real change costs two.

**Concepts**

- States: strong NT (00), weak NT (01), weak T (10), strong T (11). Count up on taken, down on not-taken, saturating at 0 and 3.
- MSB is the prediction; LSB is the conviction.
- Initial state does not matter much; 00 is easiest to reset. Some prefer weak NT.
- Every predictor has a sequence that makes it wrong every time; for 2BC from strong NT: **T, T, NT, T, NT, T…**
- 3-bit counters rarely help: long streaks of anomalies are uncommon.

**Numbers & formulas:** `2 bits/entry` · `anomaly costs 1` · `change costs 2`

**Verification lens**

- Formal is ideal here: prove saturation (never wraps 3→0), one step per update, and correct prediction bit.
- Assertion: counter never changes without an update strobe.

**Bugs that ship**

- Counter wraps from 11 to 00 on taken
- Two updates to the same entry in one cycle lose one

**Interview**

<details><summary>Write the 2BC update in one line and the key assertion.</summary>

`c <= t ? (c==3?3:c+1) : (c==0?0:c-1);` Assert `!(c==3 && upd && t) || $next(c)==3` and the mirror for 0.

</details>

---

## L04-07 History-based predictors

*History-based predictors*

> Use the last few outcomes as context: one counter per history pattern learns repeating patterns perfectly.

**Concepts**

- Counters cannot predict **T, NT, T, NT**; history can.
- Each entry keeps N history bits plus 2^N 2BCs; the history picks which 2BC predicts.
- With 2 history bits: 2 + 4 × 2 = **10 bits per branch**. After warm-up, 100% on short repeating patterns.
- N history bits predict patterns up to length about N + 1.

**Numbers & formulas:** `bits/entry = N + 2·2ᴺ` · `N=2 → 10 bits`

**Verification lens**

- The global or local history register is speculative state: updated at fetch, repaired on mispredict. History repair is where most functional bugs in this area hide.

**Interview**

<details><summary>Why can’t a 2BC predict alternating T/NT?</summary>

It sits in a weak state and flips prediction after each outcome, so it is always one step behind. History captures the alternation.

</details>

---

## L04-08 The cost of long histories

*History length · cost*

> Long histories are needed for loops, but dedicating 2ᴺ counters per branch wastes almost all of them.

**Concepts**

- An 8-iteration inner loop (NNNNNNNT) needs ~8 history bits.
- Per branch that is 2^8 = 256 2BCs, but the pattern only has **9** distinct histories, so 9 are used.
- With N = 16, a pattern like (NT)* uses 2 of 65 536 counters.
- Loop-back branches don’t need history: a single 2BC is enough.
- Fix: **share** a pool of 2BCs between branches and histories, accepting some conflicts.

**Numbers & formulas:** `8-bit history: 256 2BCs, 9 used` · `16-bit: 2 of 65 536 used`

**Verification lens**

- Sharing introduces aliasing: legal but performance-relevant. Perf tests with many branches mapping to one counter show whether hashing works.

**Interview**

<details><summary>Why not give every branch its own 16-bit history table?</summary>

2¹⁶ counters × 2 bits = 16 KB per branch, almost all unused. Shared, hashed tables give nearly the same accuracy for a tiny fraction of the area.

</details>

---

## L04-09 PShare: private history, shared counters

*PShare*

> Each branch keeps its own history; histories XOR PC index a shared table of counters.

**Concepts**

- **Pattern history table (PHT)**: per-branch history bits, indexed by PC.
- `PC ⊕ history` selects a 2BC in a shared counter table.
- On resolve: update that 2BC, then shift the outcome into the branch’s history.
- Good at **self-similar** branches: short loops, even/odd patterns. Short histories are enough.

**Numbers & formulas:** `index = PC ⊕ local hist` · `e.g. 11-bit history, 11 PC bits`

**Verification lens**

- Model the shift-in order exactly: the update must use the same history value that made the prediction, not the already-shifted one.

**Bugs that ship**

- Update indexes the counter with the post-shift history, training the wrong counter

**Interview**

<details><summary>Your example: BEQ_2 alternates within a loop with BEQ_1 and B. History length PShare needs?</summary>

1 bit for BEQ_2 itself (its own outcomes alternate), because PShare tracks each branch’s own history.

</details>

---

## L04-10 GShare: global history

*GShare*

> One global history of all recent branches, XOR PC, indexes shared counters. Catches branches that correlate with others.

**Concepts**

- Global history register (GHR): last N outcomes of **all** branches.
- `PC ⊕ GHR` selects a 2BC.
- Good at **correlated** branches (if (a) … if (a && b) …).
- Needs longer history than PShare for the same branch, because other branches fill it.
- Your example needs 3 global bits to separate the two histories (110, 010) seen before BEQ_2.

**Numbers & formulas:** `index = PC ⊕ GHR`

**Verification lens**

- The GHR is updated speculatively at fetch. On mispredict it must be restored to the value after the mispredicted branch with the corrected outcome. Checkpoint per branch or rebuild.

**Bugs that ship**

- GHR restored to the value *before* the branch instead of after it with the corrected bit
- Multiple branches per fetch block shift the GHR in the wrong order

**Interview**

<details><summary>How do you verify GHR repair?</summary>

Keep a reference GHR built only from retired branches; at each retired branch compare the DUT’s GHR history bits for that branch. Stress with dense branches and random mispredict injection.

</details>

---

## L04-11 Tournament and hierarchical predictors

*Tournament · hierarchical predictors*

> Combine predictors and choose per branch: cheap counter by default, local or global predictor when it does better.

**Concepts**

- **Tournament**: run PShare and GShare, a chooser counter per branch picks the better one.
- **Hierarchical** (your notes): large 2BC array, tagged local predictor, tagged global predictor.
- Lookup: global hit → use global; else local hit → local; else plain 2BC.
- Training: update every level that holds the branch; if the 2BC mispredicts a branch, insert it into the local predictor; if local does poorly, insert into the global one.
- Tags (upper PC bits) say whether this branch owns the entry. Modern cores (TAGE) follow this idea.

**Numbers & formulas:** `hit priority: global › local › 2BC`

**Verification lens**

- Allocation and replacement policies are complex state machines with no architectural effect. Use a cycle-accurate predictor model for perf and assertions for structural invariants (one hit per level, tag compare correct).

**Interview**

<details><summary>Why tag predictor entries?</summary>

Without tags, many branches alias into one entry and train it in conflicting directions. A tag lets the predictor say “not mine” and fall back to a simpler level.

</details>

---

## L04-12 Return address stack (RAS)

*RAS · predecoding*

> Returns are always taken but their target varies. A tiny on-chip stack predicts them.

**Concepts**

- Conditional branches: direction predictor + BTB. Jumps and calls: always taken, BTB target.
- **Returns**: target depends on the caller, so the BTB does poorly.
- Call → push PC + size, increment pointer. Return → decrement pointer, use that entry.
- Separate from the program stack: must be small and next to the predictor to answer in one cycle.
- When full, **wrap around** beats “don’t push”: it keeps predicting the many small leaf calls correctly, losing only the oldest returns.
- **Predecoding** (bits stored with the I-cache) tells fetch “this is a return / branch / length”.

**Numbers & formulas:** `push on call, pop on return` · `full → wrap`

**Verification lens**

- Speculative calls and returns on wrong paths corrupt the RAS. Verify recovery of the pointer (and the overwritten entry, if the design restores it). Cover depth at, one above, and far beyond capacity.

**Bugs that ship**

- Wrong-path return pops, recovery restores pointer but not the overwritten entry
- Call and return in the same fetch block processed in the wrong order

**Interview**

<details><summary>RAS full: don’t push or wrap around?</summary>

Wrap. Programs make many short leaf calls deep in the call tree; wrapping keeps those right and only loses the last few outermost returns.

</details>
