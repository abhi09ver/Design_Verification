# Lesson 06 · ILP

5 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Why CPI can’t reach zero](#l06-01-why-cpi-cant-reach-zero)
2. [False dependences](#l06-02-false-dependences)
3. [Register renaming and the RAT](#l06-03-register-renaming-and-the-rat)
4. [ILP: definition and how to compute it](#l06-04-ilp-definition-and-how-to-compute-it)
5. [IPC on real processors](#l06-05-ipc-on-real-processors)

---

## L06-01 Why CPI can’t reach zero

*ILP intro · executing in parallel*

> Infinite execution units still can’t beat true (RAW) dependences: dependent instructions must wait.

**Concepts**

- If all instructions were independent, a 5-wide ideal machine would reach CPI 0.2.
- RAW dependences serialise: the consumer needs the producer’s result.
- Writes must still appear in program order: if a later write to R4 finishes early, the processor must order it after earlier writes.
- With forwarding: 1 stall after an ALU producer, 2 after a load (in this lesson’s machine).

**Numbers & formulas:** `independent → CPI = 1/width` · `RAW chain sets the floor`

**Verification lens**

- Random generators need a dependency-chain-length knob: long chains test forwarding and wakeup; zero chains test width and structural limits.

**Interview**

<details><summary>What limits IPC on an ideal machine with unlimited hardware?</summary>

Only true data dependences (with perfect branch prediction). That limit is the program’s ILP.

</details>

---

## L06-02 False dependences

*False dependences · duplicating registers*

> WAR and WAW exist only because values share a register name; we can execute anyway if we keep several versions.

**Concepts**

- RAW: must delay. WAR/WAW: can execute, but must manage multiple values for one register.
- Option 1: duplicate registers and keep versions; each reader must find the latest older version. Correct but complicated.
- Option 2: **register renaming**, which is manageable in hardware (next sheet).

**Verification lens**

- Any design that keeps multiple versions of a register needs a checker that every read gets the youngest older version. That is the core invariant of renaming.

**Interview**

<details><summary>Why is keeping multiple versions per architectural register hard?</summary>

Each reader must find the youngest version older than itself among several in flight: an age-ordered search on every read. Renaming turns that into a single table lookup at decode.

</details>

---

## L06-03 Register renaming and the RAT

*Register renaming · RAT quizzes*

> Rewrite the program at decode to use physical registers; the RAT maps each architectural register to its newest physical copy.

**Concepts**

- Each new write gets a fresh physical register; the RAT entry for that architectural register now points to it.
- Sources read the RAT **before** the destination is renamed.
- Quiz result: MULs all write R2 but get P7, P9, P11, so the three MUL→ADD pairs become independent.
- Final RAT: R1→P8, R2→P11, R3→P10, R4→P4, R5→P12, R6→P6.
- After renaming: all MULs in cycle 1, all ADDs in cycle 2.

| Original | Renamed |
| --- | --- |
| MUL R2,R2,R2 | MUL P7,P2,P2 |
| ADD R1,R1,R2 | ADD P8,P1,P7 |
| MUL R2,R4,R4 | MUL P9,P4,P4 |
| ADD R3,R3,R2 | ADD P10,P3,P9 |
| MUL R2,R6,R6 | MUL P11,P6,P6 |
| ADD R5,R5,R2 | ADD P12,P5,P11 |

**Verification lens**

- Invariants: each physical register is free, mapped, or waiting to be freed, never two at once; free list has no duplicates; total count is conserved after any flush.
- Same-cycle renames of the same register in a wide rename group must chain (the second reads the first’s new mapping).

**Bugs that ship**

- Two instructions in one rename group write R2; the second instruction’s source reads the old mapping
- Destination renamed before sources read → instruction waits for itself

**Interview**

<details><summary>Rename group: I1 writes R2, I2 reads R2, same cycle. What must the renamer do?</summary>

Bypass within the group: I2’s source gets I1’s new physical register, not the RAT’s current value. Cover every intra-group dependence pattern.

</details>

---

## L06-04 ILP: definition and how to compute it

*ILP definition · computing ILP*

> ILP = IPC on an ideal machine: one-cycle ops, unlimited units, perfect branch prediction, only RAW obeyed.

**Concepts**

- ILP is a property of the **program**, not of a processor. A processor has an **IPC** for a program.
- To compute it, ignore WAR/WAW (renaming removes them), ignore structural limits, assume perfect prediction.
- Find the longest RAW chain (in cycles); ILP = instructions / cycles.
- Control dependences don’t count: with perfect prediction we already know which instructions run.

**Numbers & formulas:** `ILP = N / critical-path cycles` · `IPC ≤ ILP`

**Worked**

| Problem | Answer |
| --- | --- |
| 7 instructions, longest RAW chain 4 | ILP = 7/4 = 1.75 |

**Verification lens**

- Use ILP-controlled tests: high-ILP code checks issue width and structural hazards; low-ILP code checks wakeup and forwarding latency. Expected IPC per test becomes a perf check.

**Interview**

<details><summary>Is ILP a property of the processor?</summary>

No. ILP depends only on the program’s data dependences. IPC is what a specific processor achieves on that program.

</details>

---

## L06-05 IPC on real processors

*ILP vs IPC · real processors*

> Real machines add structural limits (width, units, latencies), so IPC falls below ILP.

**Concepts**

- Ideal processor example: IPC 2.5 (only RAW).
- Config 1 (limited units): still 2.5, the structural limit happened not to bind.
- Config 2 (narrower): instructions spread over 4 cycles, lower IPC.
- Typical ILP is well above 4; real OoO cores issue about 4–8 per cycle.
- Getting close needs: renaming, OoO execution, branch prediction, large windows. Next lessons show how.

**Verification lens**

- Structural hazards (ports, units, write-back buses) need coverage: all units busy, write-back conflicts, issue-port collisions.

**Interview**

<details><summary>Name three things that keep IPC below ILP in a real core.</summary>

Finite window (ROB/RS size), limited issue width and functional units, branch mispredicts and cache misses (non-ideal latency).

</details>
