# Lesson 17 · Fault tolerance

4 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Faults, errors and failures](#l17-01-faults-errors-and-failures)
2. [Reliability of systems](#l17-02-reliability-of-systems)
3. [Fault-tolerance techniques](#l17-03-fault-tolerance-techniques)
4. [RAID](#l17-04-raid)

---

## L17-01 Faults, errors and failures

*Dependability · faults, errors, failures*

> A fault is a defect, an error is wrong internal state it causes, a failure is wrong behaviour seen outside.

**Concepts**

- **Fault** (latent until activated) → **error** (incorrect state) → **failure** (service deviates from spec).
- Not every fault becomes an error, nor every error a failure (masking).
- Types: hardware (permanent, transient like particle strikes, intermittent), design bugs, operator and environment.
- **Reliability**: continuous correct service (MTTF). **Availability** = MTTF / (MTTF + MTTR).

**Numbers & formulas:** `A = MTTF / (MTTF + MTTR)`

**Worked**

| Problem | Answer |
| --- | --- |
| MTTF 1000 h, MTTR 1 h | A ≈ 99.9% |

**Verification lens**

- A design bug is a fault that is present in every chip. DV’s job is to prevent faults; RAS features (ECC, parity, machine checks) handle the rest and need their own fault-injection testing.

**Interview**

<details><summary>Give an example of a fault that never becomes a failure.</summary>

A bit flip in an invalid cache line, or in a register that is overwritten before being read: the error is masked.

</details>

---

## L17-02 Reliability of systems

*Reliability calculations*

> With independent components in series, failure rates add: MTTF_sys = 1 / Σ(1 / MTTFᵢ).

**Concepts**

- Failure rate λ = 1 / MTTF (constant-rate assumption).
- Series system (any failure kills it): λ_sys = Σλᵢ.
- N identical components: MTTF / N.
- Redundancy (parallel) raises MTTF; repair (low MTTR) raises availability.

**Numbers & formulas:** `λ = 1/MTTF` · `λ_sys = Σλᵢ`

**Worked**

| Problem | Answer |
| --- | --- |
| 10 disks, MTTF 100 000 h each | 10 000 h |
| CPU 1M h + memory 500k h | 333k h |

**Verification lens**

- FIT rates of SRAM arrays drive which arrays get parity vs ECC. DV verifies the chosen protection (detection, correction, reporting) for every array.

**Interview**

<details><summary>CPU MTTF 1M hours, memory 500k hours. System MTTF?</summary>

λ = 1e-6 + 2e-6 = 3e-6 /h → 333 333 hours.

</details>

---

## L17-03 Fault-tolerance techniques

*Techniques: checkpointing, redundancy, ECC*

> Detect and recover (checkpoint, DMR), or mask (TMR, ECC).

**Concepts**

- Checkpointing: save state periodically; on error, roll back and redo.
- DMR detects, TMR masks by majority vote.
- SECDED on 64 data bits uses 8 check bits (72-bit words).

| Technique | Detects | Corrects | Cost |
| --- | --- | --- | --- |
| Parity | 1-bit | no | 1 bit/word |
| SECDED ECC | 2-bit | 1-bit | 8 bits/64 |
| Checkpoint + rollback | with a detector | by re-execution | state save time |
| DMR (2 copies) | mismatch | no | 2× |
| TMR (3 copies, vote) | yes | 1 of 3 | 3× |

**Numbers & formulas:** `SECDED: 64 + 8`

**Verification lens**

- Fault injection: flip bits in each protected array (single, double, multi-bit) and check correction, detection, logging, poison propagation and machine-check reporting. Also check that clean data is never ‘corrected’.

**Bugs that ship**

- Corrected data written back to the wrong way
- Uncorrectable error consumed silently (no poison, no machine check)

**Interview**

<details><summary>How would you verify ECC on an L2 data array?</summary>

Error-injection hooks in the array model: single-bit flips must be corrected and logged; double-bit flips must be detected, poisoned and reported. Cover errors on hit, eviction, snoop and fill paths.

</details>

---

## L17-04 RAID

*RAID*

> Arrays of disks for performance (striping) and reliability (mirroring or parity).

**Concepts**

- RAID 5 small write: read old data, read old parity, write new data, write new parity = **4** accesses.
- New parity = old parity ⊕ old data ⊕ new data.
- RAID 4’s single parity disk is a write bottleneck; RAID 5 spreads it.

| Level | Scheme | Survives | Small write cost |
| --- | --- | --- | --- |
| 0 | striping | nothing (MTTF/N) | 1 write |
| 1 | mirroring | 1 disk | 2 writes |
| 4 | striping + parity disk | 1 disk | parity disk bottleneck |
| 5 | distributed parity | 1 disk | 4 accesses |
| 6 | two parities | 2 disks | 6 accesses |

**Numbers & formulas:** `P′ = P ⊕ D ⊕ D′`

**Verification lens**

- The same XOR-parity update idea appears in hardware (parity across memory channels, RAID-like memory). Verify the read-modify-write order and the case where two writes to one stripe race.

**Interview**

<details><summary>Why does RAID 5 need 4 accesses for a small write?</summary>

To update parity without reading the whole stripe: read old data and old parity, compute P ⊕ D ⊕ D′, then write data and parity.

</details>
