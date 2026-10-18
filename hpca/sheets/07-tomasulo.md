# Lesson 07 · Tomasulo

7 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Tomasulo’s algorithm: the big picture](#l07-01-tomasulos-algorithm-the-big-picture)
2. [Issue](#l07-02-issue)
3. [Dispatch and selection](#l07-03-dispatch-and-selection)
4. [Write result (broadcast)](#l07-04-write-result-broadcast)
5. [Same-cycle rules](#l07-05-same-cycle-rules)
6. [Memory dependences in Tomasulo](#l07-06-memory-dependences-in-tomasulo)
7. [Working a Tomasulo timing table](#l07-07-working-a-tomasulo-timing-table)

---

## L07-01 Tomasulo’s algorithm: the big picture

*Tomasulo overview*

> Reservation stations hold waiting instructions, results broadcast on a common data bus, and RS numbers act as rename tags.

**Concepts**

- ~50-year-old (IBM 360/91) OoO scheme; modern cores still follow it, plus a ROB.
- **Instruction queue** (FIFO) → **issue** to a reservation station of the right kind.
- RS captures ready operands from the RF, or waits for a **tag**.
- **Dispatch** to the execution unit when operands are ready. **Broadcast** result + tag on the CDB to RF and all RSs.
- Loads/stores: address unit, then load buffer (address) or store buffer (address + data). Kept in order here.
- Original version had no precise exceptions.

**Numbers & formulas:** `issue · dispatch · broadcast` · `tag = RS number`

**Verification lens**

- The CDB is a fan-out of one result to many consumers: verify tag compare on every operand of every RS, and back-to-back broadcasts.

**Interview**

<details><summary>What does Tomasulo get from reservation stations besides waiting?</summary>

Renaming: the RS number is the name of the future value, so WAR and WAW disappear.

</details>

---

## L07-02 Issue

*Issue*

> In program order: look up sources in the RAT, take a free RS of the right kind, then point the destination’s RAT entry at this RS.

**Concepts**

- Must be **in order** for renaming to be correct.
- RAT empty for a source → read the value from the RF. Otherwise copy the RS tag to wait for.
- No free RS of the right type → issue stalls.
- Last step: RAT[dest] = this RS.

**Numbers & formulas:** `no RS → stall`

**Verification lens**

- Assert: an issued instruction’s source tags equal the RAT state *before* its own rename. Cover RS-full stall for each unit type and issue of an instruction whose source and destination are the same register.

**Bugs that ship**

- ADD R1, R1, R2 waits on its own tag (rename before read)

**Interview**

<details><summary>Why must issue be in order?</summary>

The RAT must reflect program order: each instruction must see the latest older producer of each source. Out-of-order issue would hand out stale or future tags.

</details>

---

## L07-03 Dispatch and selection

*Dispatch · which instruction first*

> When an RS has all operands it can go to the execution unit; if several are ready, a heuristic picks.

**Concepts**

- Each cycle: capture broadcast values by tag compare, then pick ready instructions.
- Heuristics: **oldest first** (common, helps somewhat), most-dependents first (expensive search), random (works, worst).
- All are correct; they only differ in performance.
- Quiz: a ready RS not dispatched last cycle? It was just issued last cycle, or another ready instruction took the unit.

**Numbers & formulas:** `select: oldest first`

**Verification lens**

- Select logic needs a starvation check: every ready instruction eventually dispatches. Use a liveness assertion or a timeout counter per RS entry.

**Bugs that ship**

- Age matrix not updated on flush, so a young instruction looks oldest forever
- Two units pick the same RS entry in one cycle

**Interview**

<details><summary>How would you check the scheduler never starves an instruction?</summary>

Count cycles each RS entry is ready but not selected; assert below a bound. Formal liveness on the select logic if small enough.

</details>

---

## L07-04 Write result (broadcast)

*Write result · broadcast priority · stale results*

> Put tag + value on the CDB; RS entries capture it; RF and RAT update only if the RAT still points to this RS.

**Concepts**

- Broadcast tag and value; free the producing RS.
- Write the RF register whose RAT entry holds this tag, then clear that RAT entry.
- **Stale result**: no RAT entry holds the tag (a younger writer renamed it). Don’t touch RAT or RF; waiting RSs still capture it.
- One bus, two results: give priority to the **slower unit** (MUL/DIV), a cheap proxy for age. Or carry age.
- More buses → more comparators in every RS, more RF write ports.

**Numbers & formulas:** `stale → skip RAT and RF` · `CDB priority: slow unit`

**Verification lens**

- Checker: after a broadcast, RF[r] changes only if RAT[r] held the tag. Cover the stale case deliberately: two writers to one register, older finishing last.

**Bugs that ship**

- Stale broadcast overwrites the RF with an older value
- CDB conflict loses one result

**Interview**

<details><summary>Older ADD and younger MUL both write F2; ADD finishes after MUL. What happens to F2?</summary>

MUL’s broadcast writes F2 (RAT points to it). ADD’s later broadcast is stale: waiting RSs capture it, but RAT and RF are not changed.

</details>

---

## L07-05 Same-cycle rules

*Tomasulo same-cycle questions*

> Everything happens every cycle, so the design must define what may happen together.

**Concepts**

- Quiz state: F0 broadcast 4.4 → RAT F0 cleared, RF F0 = 4.4; RS waiting on it capture; the one with all operands dispatches next cycle.
- Order inside a cycle in worked examples: dispatch, then issue, then broadcast, so a freshly issued instruction isn’t considered for dispatch.
- Not true of Tomasulo: dispatches in order; writes results in order.

| Same cycle? | Default | Note |
| --- | --- | --- |
| Issue + dispatch | no | entry is being written; extra HW can allow |
| Capture + dispatch | no | readiness updates this cycle; extra HW can allow |
| Issue + broadcast update the same RAT entry | yes | issue wins: newest producer |

**Verification lens**

- Write these as assertions and directed tests: issue and broadcast to the same register in the same cycle; capture and dispatch same cycle; RS freed and reallocated same cycle.

**Bugs that ship**

- Broadcast clears a RAT entry that issue rewrote the same cycle

**Interview**

<details><summary>Same cycle: issue renames F0, broadcast of old F0 producer arrives. Final RAT[F0]?</summary>

The issuing instruction’s tag. Later readers must wait for the newest producer; the old value is captured only by RSs that were waiting for it.

</details>

---

## L07-06 Memory dependences in Tomasulo

*Loads and stores in Tomasulo*

> Memory has the same RAW/WAR/WAW hazards as registers; original Tomasulo simply keeps loads and stores in order.

**Concepts**

- Only loads and stores can be dependent through memory.
- Tomasulo: execute memory operations in order.
- Modern cores identify and reorder them (Lesson 9).

| Type | Pattern |
| --- | --- |
| RAW | SW to A, then LW from A |
| WAR | LW from A, then SW to A |
| WAW | two SWs to A |

**Verification lens**

- In-order memory is a valid design point and a useful fallback mode (a chicken bit). Verify both modes.

**Interview**

<details><summary>Why are memory dependences harder than register dependences?</summary>

Addresses are computed late (after register operands arrive), so at issue you cannot know which loads and stores conflict.

</details>

---

## L07-07 Working a Tomasulo timing table

*Tomasulo timing example · quizzes*

> Track issue, execute and write cycles per instruction, with RS and unit counts as constraints.

**Concepts**

- Rules used in the lesson: no issue+dispatch same cycle; write result the cycle after execution ends; one CDB.
- Fast method: mark tentative write cycles, then fix any two writes in the same cycle and shift later dependents.
- Structural stall example: no free ADD RS → instruction 5 issues only when an ADD RS frees (cycle 11), instruction 6 at 13.
- Non-pipelined load unit: second load starts only after the first ends.

| Instr | Issue | Exec start | Write |
| --- | --- | --- | --- |
| 5 (ideal) | 5 | 6 | 7 |
| 5 (RS full) | 11 | 12 | 13 |
| 6 (RS full) | 13 | 14 | 15 |

**Verification lens**

- These hand tables are exactly what a cycle-accurate scoreboard or perf model produces. Interviewers use them to test whether you know where each cycle goes.

**Interview**

<details><summary>In a timing quiz, what three resources do you track?</summary>

Free RS per type, free execution units (and whether pipelined), and the result bus per cycle.

</details>
