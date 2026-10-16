# Session 4 — Constrain the Chaos: 12 Constraint Questions

Source: `Session4_pdf_Contrain the Chaos.pdf`, page 41.
Code: [`code/session4_constraints/session4_constraints.sv`](code/session4_constraints/session4_constraints.sv) · Output: [`logs/s4_constraints.log`](logs/s4_constraints.log)

Every class is randomized 200 times, and the result is **checked by ordinary code** (not just printed). Result: **0 check failures**.

---

### Q1. AXI transfer must not cross a 4KB boundary
```systemverilog
rand bit [31:0] addr; rand bit [7:0] len; rand bit [2:0] size;
constraint c_align { addr % (1 << size) == 0; }
constraint c_4k    { (addr % 4096) + ((32'(len) + 1) << size) <= 4096; }
```
- Total bytes = (AxLEN+1) × 2^AxSIZE.
- **Trap:** without `32'(len)` the expression is only 8 bits wide and wraps. Always widen arithmetic inside constraints.
- **Follow-ups:**
  - WRAP bursts cannot cross 4K by definition.
  - FIXED bursts never move the address.
  - Why 4K at all? It is the minimum slave address space, so a crossing burst could reach two slaves.

### Q2. Two non-overlapping regions (64B and 128B) in 0x20000–0x40000
```systemverilog
constraint c_range { s1 >= 'h20000; s1 + 63 <= 'h40000; s2 >= 'h20000; s2 + 127 <= 'h40000; }
constraint c_no_overlap { (s1 + 64 <= s2) || (s2 + 128 <= s1); }
```
- Constrain each region's **end**, not just its start. Missing this is the most common bug.
- **Generalising to N regions:** use arrays of start and size, with a `foreach (i) foreach (j) if (i < j)` no-overlap constraint.

### Q3. Address aligned to 2, 4 or 8 bytes
```systemverilog
constraint c_align_sel { align inside {2, 4, 8}; }
constraint c_aligned   { addr % align == 0; }
constraint c_order     { solve align before addr; }
```
- Without `solve…before`, the solver is uniform over all valid (align, addr) pairs. Far more addresses are 2-byte aligned, so `align = 2` dominates (≈4/7 of picks).
- With `solve…before`, each alignment gets about 1/3.

### Q4. Pattern 1 2 2 1 1 2 2 1 …
```systemverilog
foreach (a[i]) a[i] == ((i % 4 == 0 || i % 4 == 3) ? 1 : 2);
```
The pattern has period 4, so derive each value from `i % 4`.

### Q5. Sort a dynamic array ascending or descending
```systemverilog
rand bit ascending;
foreach (a[i]) if (i > 0) {
  ascending  -> a[i] > a[i-1];
  !ascending -> a[i] < a[i-1];
}
```
`>` forces unique values; `>=` allows repeats. Say which one you mean.

### Q6. Random even numbers from 50 to 100
- `x inside {[50:100]}; x % 2 == 0;`
- **Alternative:** randomize `k` in 25..50 and compute `x = 2*k` in `post_randomize()`, which avoids `%` in the solver.

### Q7. APB: writes generated more often than reads
- **Probabilistic:** `pwrite dist {1 := 3, 0 := 1};`. The run gave 740 writes / 260 reads out of 1000.
- **Exact:** in a burst of 20, `pwrite.sum() with (int'(item)) == 15;` gives 15 writes and 5 reads.
- **Trap:** `sum()` of 1-bit elements is itself 1 bit wide unless you cast with `int'(item)`, so it could never equal 15.
- **`:=` vs `:/`:** `:=` gives *each* value the weight; `:/` *divides* the weight across a range.

### Q8. Random prime number
```systemverilog
rand int unsigned n;  int unsigned div[200];
constraint c_range { n inside {[2:199]}; }
constraint c_prime { foreach (div[i]) (i >= 2 && i < n) -> (n % i != 0); }
```
- You can't write a loop inside a constraint, so use `foreach` over a dummy array and let the index act as the divisor.
- **Why not `is_prime(n)` as a function call?** Function arguments are solved *before* the function is evaluated. `n` gets picked first, then most picks fail, giving randomize failures or poor distribution.

### Q9. Randomize x and y but not z
1. `obj.randomize(x, y);` — this call only.
2. `obj.z.rand_mode(0);` — until you turn it back on.
3. Declare `z` without `rand`.

The run confirms z stayed at 42 with each method. A related tool is `constraint_mode(0)`, which switches off a constraint block rather than a variable.

### Q10. Odd index holds even values, even index holds odd values
```systemverilog
foreach (a[i]) (i % 2 == 1) ? (a[i] % 2 == 0) : (a[i] % 2 == 1);
```
Use an unsigned type. With signed values, `-3 % 2 == -1`.

### Q11. Insert "101" into a 64-bit number, inside bits 20–25
```systemverilog
rand bit [63:0] num; rand int unsigned pos;
constraint c_pos { pos inside {[20:23]}; }          // pos..pos+2 must stay within 20..25
constraint c_seq { ((num >> pos) & 64'h7) == 64'b101; }
```
The upper bound is **23**, not 25, because the pattern occupies `pos+2`. That off-by-two is what's being tested.

### Q12. Phone numbers by mode
| Mode | Constraint |
|---|---|
| 0 Emergency | `num inside {100, 101, 911}` |
| 1 Local | `num` in a 10-digit range; first 3 digits (`num / 10^7`) ≠ 100, 101, 911 |
| 2 STD | state enum → code (Karnataka 080, Delhi 011, Maharashtra 022, Tamil Nadu 044); `num = code × 10^8 + 8-digit subscriber` |

- Use **64-bit** fields, because 9,999,999,999 doesn't fit in 32 bits.
- Arrays of `mode`, `state` and `num` hold one entry per phone number.
- Splitting the number into code and subscriber fields keeps each constraint simple.
- **Practical note:** in the open-source solver, `!(expr inside {...})` as an expression inside an implication block didn't parse. Separate `!=` constraints did.

---

## General constraint gotchas (quick recall)
- **Width and sign:** every constraint expression is evaluated at its context width, so cast to avoid wrap and sign surprises.
- **`solve…before`** changes the *distribution*, never the solution space.
- **Hard vs soft:** inline `with {}` constraints add to the class constraints. Use `soft` for defaults that a test may override.
- **Debugging:** `randomize()` returns 0 on failure. Always check it (`if (!obj.randomize()) $fatal`). Find the conflict by turning blocks off with `constraint_mode(0)`.
- **`pre_randomize` / `post_randomize`:** use them for derived fields and for things that are hard to express as a constraint.
- **`randc`:** cycles through every value before repeating. Good for exhaustive small ranges.
