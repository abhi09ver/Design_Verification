# Lesson 08 · Reorder buffer

8 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [What breaks without a ROB](#l08-01-what-breaks-without-a-rob)
2. [The reorder buffer](#l08-02-the-reorder-buffer)
3. [Issue and dispatch with a ROB](#l08-03-issue-and-dispatch-with-a-rob)
4. [Broadcast and commit](#l08-04-broadcast-and-commit)
5. [Mispredict recovery with a ROB](#l08-05-mispredict-recovery-with-a-rob)
6. [Exceptions with a ROB](#l08-06-exceptions-with-a-rob)
7. [ROB cycle-by-cycle](#l08-07-rob-cycle-by-cycle)
8. [Unified RS and superscalar width](#l08-08-unified-rs-and-superscalar-width)

---

## L08-01 What breaks without a ROB

*Exceptions in OoO · mispredicts · phantom exceptions*

> If instructions write registers out of order, exceptions and mispredicts leave state you can’t undo.

**Concepts**

- **Imprecise exception**: DIV (40 cycles) finds divide-by-zero in cycle 40; younger MUL already overwrote F0. Handler returns, DIV re-reads the wrong F0.
- Same for a load page fault: younger instructions already wrote results.
- **Mispredict**: a wrong-path ADD already wrote R3 before the slow branch resolved.
- **Phantom exception**: a wrong-path DIV raises an exception that should never happen.
- Fix: execute OoO, broadcast OoO, but **deposit results in order**.

**Numbers & formulas:** `execute OoO · commit in order`

**Verification lens**

- These three failures are the checklist for any OoO core: precise exceptions, exact mispredict recovery, no wrong-path side effects. Each needs directed tests and a co-sim at commit.

**Interview**

<details><summary>Define a precise exception.</summary>

On a trap at instruction I, all older instructions have completed and all younger have no visible effect; the saved PC is I’s. The handler sees a clean sequential state.

</details>

---

## L08-02 The reorder buffer

*ROB structure*

> A circular table in program order that holds each result until it is safe to write it to the register file.

**Concepts**

- Each entry: **value**, **done** bit, **destination register** (plus exception status, PC, etc.).
- Two pointers: **issue** (where the next instruction goes) and **commit** (oldest, next to retire).
- Entries between commit and issue are in flight.
- Jobs: remember program order; hold results until commit; act as the name (tag) of the result.
- Not its job: holding source operands (RS does that) or choosing the execution unit (RS type does).

**Numbers & formulas:** `in flight = [commit, issue)` · `tag = ROB index`

**Verification lens**

- Pointer wrap is the classic bug: compare ages with an extra wrap bit. Assert full/empty from pointers never disagrees with an occupancy counter.

**Bugs that ship**

- Age compare wrong after wrap: a young entry looks older
- Full and empty indistinguishable when pointers are equal

**Interview**

<details><summary>How do you compare the age of two ROB entries in a circular buffer?</summary>

Store a wrap bit with each pointer. Same wrap bit → lower index is older. Different wrap bits → higher index is older. Formal can prove it for small sizes.

</details>

---

## L08-03 Issue and dispatch with a ROB

*ROB-2 · free RS quiz*

> Issue takes an RS and the next ROB entry and points the RAT at the ROB entry; the RS frees at dispatch.

**Concepts**

- Issue needs **both** a free RS and a ROB entry (at the issue pointer, not any entry).
- RAT[dest] = ROB#; ROB entry marked not done.
- Waiting and dispatch are as in Tomasulo.
- The RS is freed **at dispatch**, because the ROB entry now names the result.
- Quiz: “no free RS” is more likely *without* a ROB, since RSs are held until broadcast.

**Numbers & formulas:** `issue needs RS + ROB` · `RS freed at dispatch`

**Verification lens**

- Resource accounting: RS free count, ROB occupancy. Cover issue blocked by RS-full only, ROB-full only, and both. Assert no RS is freed twice or reused while still selected.

**Interview**

<details><summary>Why can the RS be freed at dispatch once a ROB exists?</summary>

The RS was the name of the result in Tomasulo. With a ROB, the ROB entry is the name, so the RS only has to wait and dispatch.

</details>

---

## L08-04 Broadcast and commit

*ROB-3 · commit · RAT updates on commit*

> Broadcast writes the ROB and marks done; commit, in order, writes the RF and clears the RAT only if it still points here.

**Concepts**

- **Broadcast**: tag = ROB#. RSs capture; ROB entry gets value + done. RAT and RF untouched.
- **Commit**, each cycle: if the entry at the commit pointer is done, write its value to the RF (**always**, even if a younger writer exists).
- Then clear RAT[dest] **only if** it still points to this ROB entry, free the entry, advance the pointer.
- Gotcha from your notes: at issue, read source mappings **before** renaming the destination, or the instruction waits for itself (deadlock).

**Numbers & formulas:** `RF write: always at commit` · `RAT clear: only if RAT[rd]==rob#`

**Verification lens**

- Assertions: commit is in order; RF only changes at commit; RAT entry cleared only when it matches the committing tag; commit never skips a not-done entry.

**Bugs that ship**

- RAT cleared even though a younger instruction renamed the register
- Instruction waits on its own tag (rename before read)
- Two commits in one cycle write the same register in the wrong order

**Interview**

<details><summary>Commit of ROB2 writes R1 = 8, but RAT[R1] = ROB4. What changes?</summary>

RF R1 becomes 8 (latest committed value). RAT[R1] stays ROB4 because a younger producer is pending. ROB2 is freed.

</details>

---

## L08-05 Mispredict recovery with a ROB

*Hardware organisation with ROB · branch mispredict recovery*

> When the mispredicted branch reaches commit: move the issue pointer to it, reset the RAT to the RF, drop RS and units, refetch.

**Concepts**

- Wrong-path instructions may execute and write the **ROB**, never the RF.
- Branch resolves → mark mispredicted in its ROB entry; fetch can restart early from the correct target.
- At commit of the branch: issue pointer = commit pointer (empty ROB), RAT entries all point to the RF, RS and execution units cleared.
- Committed state is exactly the state before the wrong path.

**Numbers & formulas:** `recovery: ROB empty · RAT→RF · RS cleared`

**Verification lens**

- Recovery at commit is simple to verify; early recovery (at resolve, with RAT checkpoints) is faster but harder. Check after any recovery that no surviving entry is younger than the branch and that RAT matches a model rebuilt from older entries.

**Bugs that ship**

- An execution unit still broadcasts a flushed instruction’s tag into a reused ROB entry
- RAT restored but free list not

**Interview**

<details><summary>After a flush, a long-latency DIV from the wrong path completes. What must happen?</summary>

Its result must be dropped. Use a valid/epoch check or kill the unit; otherwise it writes into a ROB entry now reused by a correct-path instruction.

</details>

---

## L08-06 Exceptions with a ROB

*ROB and exceptions · commit as the outside view*

> Treat an exception as just another result, and act on it only when that instruction reaches commit.

**Concepts**

- The faulting instruction writes “exception” into its ROB entry instead of a value.
- At commit: everything older is committed, nothing younger is. Flush it and everything younger, jump to the handler.
- Page fault: same, clean resume point at the load.
- Phantom exceptions vanish: a wrong-path DIV never reaches commit.
- Commit is the **programmer’s view**: executed but uncommitted work is internal and may be undone.

**Numbers & formulas:** `exception handled at commit`

**Verification lens**

- Co-sim compares at commit, which is exactly the programmer’s view. Cover exceptions on: oldest, youngest, wrong-path, two in one commit group, exception + interrupt same cycle.

**Interview**

<details><summary>Wrong-path DIV raises divide-by-zero before the branch resolves. What does the programmer see?</summary>

Nothing. The exception is recorded in the ROB entry; the branch commits first, the mispredict flushes the DIV, so it never commits and never traps.

</details>

---

## L08-07 ROB cycle-by-cycle

*ROB examples · timing quizzes*

> Each instruction now has four timestamps: issue, execute, write result, commit.

**Concepts**

- Commit waits for all older instructions, so a fast instruction can wait many cycles after write.
- Commit width limits how many retire per cycle.
- Example rules: issue + dispatch same cycle allowed; broadcast the cycle after execution.
- Common trap: renaming the destination before reading sources.

| Instr | Issue | Exec | Write | Commit |
| --- | --- | --- | --- | --- |
| ADD | 3 | 4 | 5 | 8 |
| MUL | 4 | 7 | 9 | 10 |
| SUB | 5 | 7 | 8 | 10 |
| ADD | 6 | 9 | 10 | 11 |

**Verification lens**

- Commit lag (write → commit) is a good perf signal; very long lags point to a stuck head (e.g. a missing completion).

**Interview**

<details><summary>An instruction finished but never commits; the core hangs. Where do you look?</summary>

The ROB head: which entry is it, is it done, is it waiting for a store buffer slot, an exception decision or a lost completion? Most hangs are a head waiting on an event that never arrives.

</details>

---

## L08-08 Unified RS and superscalar width

*Unified RS · superscalar · in-order vs OoO stages*

> Share RSs between unit types for utilisation; make every stage N-wide, because the narrowest stage sets IPC.

**Concepts**

- **Unified RS**: same structure for all types, better use of expensive entries; select logic must pick one per unit type.
- Superscalar: fetch, decode, issue, dispatch, broadcast, commit all N-wide.
- RS cost grows with the number of broadcast buses (comparators per operand).
- In order: fetch, decode, issue, commit. Out of order: dispatch, execute, write result.
- Terminology varies: issue/dispatch are swapped in some literature.

**Numbers & formulas:** `IPC ≤ narrowest stage`

**Verification lens**

- Wide pipelines add intra-group interactions: a branch in slot 0 killing slots 1–3, two stores in one commit group, two writers to one register. Cover every slot position.

**Interview**

<details><summary>Which stages are in order in a ROB-based OoO core?</summary>

Fetch, decode, issue (rename/dispatch to RS), and commit. Dispatch to units, execution and write-back are out of order.

</details>
