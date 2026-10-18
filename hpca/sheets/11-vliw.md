# Lesson 11 · VLIW

3 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Superscalar vs VLIW](#l11-01-superscalar-vs-vliw)
2. [VLIW: strengths and weaknesses](#l11-02-vliw-strengths-and-weaknesses)
3. [VLIW ISAs and where they win](#l11-03-vliw-isas-and-where-they-win)

---

## L11-01 Superscalar vs VLIW

*Superscalar vs VLIW*

> OoO finds parallelism in hardware; VLIW executes long instructions in which the compiler already packed independent operations.

**Concepts**

- OoO is “needs nobody’s help” at a big hardware cost.
- In-order superscalar is cheaper but needs the compiler to place independent instructions together.
- VLIW relies on the compiler completely in exchange for simple hardware.

|  | OoO superscalar | In-order superscalar | VLIW |
| --- | --- | --- | --- |
| Per cycle | ≤ N instr | ≤ N instr | 1 instr = N ops |
| Finds parallelism | window ≫ N | next N in order | compiler |
| Hardware | most | less | least |
| Compiler | helps | needed | everything |

**Verification lens**

- VLIW hardware is simpler to verify (no dependence checks within a bundle), but the compiler/ISA contract is wider: verify rules such as what happens if a bundle does contain a dependence (undefined, trap, or defined).

**Interview**

<details><summary>Why can an OoO core look ≫ N instructions ahead but a VLIW can’t?</summary>

It doesn’t need to: the VLIW compiler did the searching ahead of time with unlimited time and visibility.

</details>

---

## L11-02 VLIW: strengths and weaknesses

*VLIW good and bad · code size quiz*

> Compiler-scheduled code is cheap and efficient on regular loops, but struggles with unpredictable latencies, irregular code and NOP bloat.

**Concepts**

- Quiz: 4000 B of 32-bit code → 128-bit, 4-op VLIW: **4000 B** if every bundle fills, up to **16 000 B** if every op depends on the previous (3 NOPs per bundle).

| Good | Bad |
| --- | --- |
| Compiler schedules once, runs many times | Latencies vary (cache miss vs hit) |
| Simpler, cheaper hardware | Irregular, pointer-heavy, decision-heavy code |
| More energy-efficient | Code bloat from NOPs |
| Great on loops and regular code | Binary compatibility across generations |

**Worked**

| Problem | Answer |
| --- | --- |
| Best case size | 4000 B |
| Worst case | 16 000 B |

**Verification lens**

- A static schedule assumes a latency; when a load misses, the whole machine stalls (interlocks) or the result is late. Verify the stall/interlock behaviour on misses explicitly.

**Interview**

<details><summary>Why is a cache miss worse for VLIW than for OoO?</summary>

The compiler scheduled assuming a hit; on a miss nothing else can move around the load, so the whole bundle stream stalls. OoO keeps executing independent work.

</details>

---

## L11-03 VLIW ISAs and where they win

*Backward compatibility · VLIW ISA · examples · target market*

> VLIW ISAs add predication, many registers, branch hints and compaction. They thrive in DSPs, and Itanium shows the risks.

**Concepts**

- Quiz: running 2-op bundles two at a time on a wider machine isn’t VLIW anymore, because the hardware must check dependences between bundles.
- ISA features: full predication, lots of architectural registers, branch hints, instruction compaction (stop bits instead of NOPs).
- **Itanium**: so many ISA features that the hardware became extremely complex, and still weak on irregular code.
- **DSPs**: regular loops, lots of iterations → excellent performance and energy.
- Target quiz, best to worst: sum many numbers › count a linked list › search a maze.

**Numbers & formulas:** `sum › list › maze`

**Verification lens**

- Compaction (stop bits, variable bundle length) makes fetch/decode the complex part. Cover bundle boundaries crossing cache lines and pages, and branch targets inside bundles.

**Interview**

<details><summary>Why did Itanium struggle?</summary>

Performance depended on compilers predicting latencies and paths that only appear at run time (cache misses, pointer-chasing), while the ISA features made the hardware complex anyway. OoO x86 matched it on general code.

</details>
