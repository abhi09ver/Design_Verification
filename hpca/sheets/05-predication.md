# Lesson 05 · Predication

3 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Prediction vs predication](#l05-01-prediction-vs-predication)
2. [If-conversion and conditional moves](#l05-02-if-conversion-and-conditional-moves)
3. [Full predication](#l05-03-full-predication)

---

## L05-01 Prediction vs predication

*Predication intro · prediction vs predication*

> Predication runs both paths and keeps one: no mispredict, but always pays for both sides.

**Concepts**

- Rule from your notes: 5-instruction if and else with a 50-instruction mispredict cost: predict if accuracy is above ~90%, otherwise predicate.
- The smaller the if/else, the more predication wins.

| Branch type | Choose | Why |
| --- | --- | --- |
| Loop | predict | predicating iterations keeps doing ever more useless work |
| Call / return | predict | always taken; there is no other path |
| Large if/else | predict | both sides cost more than an occasional mispredict |
| Small hard if/else | predicate | both sides cheaper than mispredicts |

**Numbers & formulas:** `predicate if both-path cost < one-path + miss% × penalty`

**Verification lens**

- Predication changes which instructions have architectural effect. Every instruction type must be tested with predicate true and false.

**Interview**

<details><summary>Why not predicate everything?</summary>

Large blocks and loops waste far more work executing both paths than the occasional mispredict costs.

</details>

---

## L05-02 If-conversion and conditional moves

*If-conversion · conditional move*

> The compiler computes both results and selects one with a conditional move, removing the branch.

**Concepts**

- Replacing the branch with conditional branches gains nothing; you need an instruction that **selects**.
- MIPS: `MOVZ Rd, Rs, Rt` (move if Rt == 0), `MOVN` (if Rt ≠ 0). x86: `CMOVcc`.
- Costs: extra registers for both results, extra instructions, compiler support. Old binaries don’t benefit.
- Which branches? Profiling finds the hard-to-predict ones.

**Numbers & formulas:** `MOVZ R3,R5,R1 · MOVN R2,R4,R1`

**Worked**

| Problem | Answer |
| --- | --- |
| 80% accurate, 40-instr penalty, 2.5 instr average path: before | 2.5 + 0.2 × 40 = 10.5 |
| After if-conversion | 4 instructions |

**Verification lens**

- A conditional move is a data dependence on the condition, not a control dependence. In an OoO core it must wait for the condition and both sources, and must not forward the unselected value.

**Bugs that ship**

- CMOV with false condition still writes (or frees) its destination register incorrectly
- Renamer treats a false CMOV as a no-op and loses the old value

**Interview**

<details><summary>How does an OoO core rename a conditional move?</summary>

It allocates a new physical register and reads the old value of the destination as an extra source, so the false case copies the old value through. Missing that third source is a classic bug.

</details>

---

## L05-03 Full predication

*Full predication · Itanium · break-even quiz*

> Every instruction carries a predicate register; false-predicated instructions simply don’t write.

**Concepts**

- Itanium: `MP.EQZ p1, p2 = R1` sets complementary predicates; then `(p2) ADD …`, `(p1) ADD …`.
- No extra registers, no select instruction; overhead is the predicate-set, like the branch it replaces.
- Requires extensive ISA support.
- Quiz: 3 predicated instructions at CPI 0.5 = 1.5 cycles; branchy code averages 2.5 instructions = 1.25 cycles + miss% × 10. Break-even at 2.5% miss, so predict only if accuracy ≥ **97.5%**.

**Numbers & formulas:** `predicate false ⇒ no effect`

**Worked**

| Problem | Answer |
| --- | --- |
| 1.25 + m × 10 = 1.5 | m = 2.5% → need ≥ 97.5% |

**Verification lens**

- Spec: a predicated-false instruction has no architectural effect, including no exception and no memory access.
- Cover predicate false × every exception type, predicated stores (must not forward to younger loads), and predicate register renaming.

**Bugs that ship**

- Predicated-false load still takes a page fault
- Predicated-false store forwards data to a younger load

**Interview**

<details><summary>A predicated-false load points to an unmapped page. What happens?</summary>

Nothing architectural: no fault, no register write. Test with deliberately unmapped addresses and check the trap is absent when false and precise when true.

</details>
