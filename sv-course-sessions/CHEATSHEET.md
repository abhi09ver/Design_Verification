# Last-Minute Cheatsheet — SV Course Sessions 1–5

One page to read before the interview. Details are in the session notes; every snippet here was compiled and run (see [`logs/`](logs/)).

---

## 1. Arrays & queues — method quick reference

| Need | Code | Gotcha |
|---|---|---|
| Sort / reverse sort | `a.sort(); a.rsort();` | In place, returns void. Not for assoc arrays |
| Sort by field | `pkts.sort(p) with (p.addr);` | |
| Reverse order | `a.reverse();` | ≠ `rsort()` unless already sorted |
| Min / max | `q = a.min(); q[0]` | **Returns a queue**, never an `int` |
| Sum | `a.sum() with (longint'(item))` | Result has element width: widen it or it wraps |
| Filter | `a = a.find with (item % 2 != 0);` | Use `!= 0` (negatives: `-3 % 2 == -1`) |
| First matching index | `iq = a.find_first_index with (item > 5);` | `find_index` = **all** matches. Check `iq.size()` |
| Unique | `q = a.unique();` | Order not guaranteed by the LRM |
| By position | `a.find with (item.index > 2)` | |
| Queue FIFO | `push_back` + `pop_front` | Check `size()` before pop: an empty pop returns 0 silently |
| Queue LIFO | `push_back` + `pop_back` | |
| Assoc array | `exists(k) num() delete(k) first(k) next(k)` | `foreach` visits keys in ascending order |
| Search assoc by *value* | `mem.find_index with (item == v)` | `mem[k] != 0` is **not** an existence test |
| Resize keeping data | `A = new[250](A);` | `new[250]` alone discards the data. Fixed arrays can't resize |
| String compare, ignore case | `s1.icompare(s2) == 0` | Returns **0 when equal** (like strcmp) |
| String concat / format | `{s1, " ", s2}` · `$sformatf("%s_%0d", s, n)` | `string` has no `reverse()` |
| Exact compare | `foreach ... if (a[i] !== b[i])` | `!==` catches X/Z; `!=` doesn't |
| Out-of-order compare | count map `cnt[v]++` / `--` | Duplicates! `{1,2,3,2}` ≠ `{1,2,3,3}` |
| Dedup, keep order | `bit seen[int];` + `exists()` | O(n) |

**Memory model:** sparse address space → **associative array** keyed by address.
**Queue vs mailbox:** a queue is data and never blocks; a mailbox is for inter-thread passing and `get()` blocks. A bounded mailbox gives back-pressure.

---

## 2. Constraints — the 12 patterns

| Problem | Core constraint |
|---|---|
| AXI no 4KB cross | `(addr % 4096) + ((32'(len)+1) << size) <= 4096` |
| Non-overlap regions | `(s1+SZ1 <= s2) \|\| (s2+SZ2 <= s1)`, and constrain the **end** of each range |
| 2/4/8-aligned | `align inside {2,4,8}; addr % align == 0; solve align before addr;` |
| Repeating pattern | `foreach (a[i]) a[i] == f(i % period);` |
| Sorted array | `foreach (a[i]) if (i>0) a[i] > a[i-1];` (knob for direction) |
| Even in range | `x inside {[50:100]}; x % 2 == 0;` |
| More writes than reads | `pwrite dist {1:=3, 0:=1};` or exact `pwrite.sum() with (int'(item)) == N` |
| Prime | `foreach (div[i]) (i>=2 && i<n) -> n % i != 0;` |
| Don't randomize z | `randomize(x,y)` · `z.rand_mode(0)` · no `rand` |
| Index-parity rule | `foreach (a[i]) (i%2) ? a[i]%2==0 : a[i]%2==1;` |
| Bit pattern in a window | `pos inside {[lo : hi-W+1]}; ((num >> pos) & mask) == pat;` |
| Mode-based fields | `if (mode == X) { ... }` blocks + enum → code mapping, 64-bit for 10 digits |

**Gotchas**
- Width and sign wrap inside expressions: cast with `32'()`, `int'()`.
- `solve…before` changes the distribution, never the solution space.
- `:=` gives each value the weight; `:/` splits the weight across a range.
- Function calls in constraints are solved *after* their arguments.
- Always check `randomize()`'s return value.
- `soft` makes a default overridable; `constraint_mode(0)` turns a block off; `randc` cycles through all values.

---

## 3. Testbench building (Session 3, no UVM)

- **Flow:** gen → mailbox → driver (`vif1`/`vif2`, routed by `txn.port`) → `drv2sb`. The passive monitor (one thread per port) → `mon2sb`. The scoreboard keeps per-port expected queues and a reference memory.
- **APB timing:** SETUP (`psel=1, penable=0`) → ACCESS (`penable=1`) → wait for `pready`. **Sample at `psel && penable && pready`.**
- **Copy before `put()`** so the scoreboard never shares a handle that later changes.
- **End of test:** `fork @(sb.done); #timeout; join_any; disable fork;`
- ⚠️ `apb_txn t = new();` in a loop inside `initial` runs **once** (static). Use `t = new();` inside the loop.
- ⚠️ **Prove the scoreboard can fail.** Random reads of unwritten addresses hid an injected bug until reads were constrained to written addresses.

## 4. Coverage (Session 5)

```systemverilog
covergroup cg with function sample(bit [31:0] paddr, bit pwrite);
  cp_addr : coverpoint paddr { bins low = {[0:'hFFF]}; bins mid = {['h1000:'h1FFF]};
                               bins high = {['h2000:'hFFFF]}; illegal_bins oob = {['h10000:$]}; }
  cp_rw   : coverpoint pwrite { bins rd = {0}; bins wr = {1}; }
  cx      : cross cp_addr, cp_rw;
endgroup
// sample only completed transfers:  if (psel && penable && pready) cg.sample(...);
```
- Construct an embedded covergroup in `new()`.
- `illegal_bins` = error on a hit; `ignore_bins` = excluded silently; `default` = not counted.
- Coverage ≠ checking. 100% coverage with bugs means a checker is missing.

## 5. Layered agent (Session 2)

- **Upper sequencer** (generic `bus_txn`, no driver) → a **translation sequence on the lower sequencer** pulls with `up_sqr.get_next_item()` → `start_item`/`finish_item` of protocol items → `up_sqr.item_done()` **after the last lower item**.
- **Upward path:** monitors → `axi2bus` / `ahb2bus` subscribers → a protocol-independent scoreboard.
- **Protocol rules live in exactly one place:**
  - AXI: no **4KB** crossing; AxLEN = beats − 1 (≤ 256 INCR); AxSIZE = log2(bytes).
  - AHB: no **1KB** crossing; NONSEQ then SEQ; INCR4/8/16 or SINGLE.
- **Same as the RAL adapter idea** (`reg2bus`/`bus2reg`). One config knob swaps the protocol, and the tests stay unchanged.

---

## Slide answer-key errors to point out (shows depth)
1. **Session 1, p52:** `int m = arr.min();` and `int i = arr.find_index with (...)` both assign a queue to an `int`, and `find_index` ≠ "first index". Use `find_first_index`.
2. **Session 3:** monitor sampling at `PSEL && PENABLE` alone double-counts transfers when there are wait states. Add `PREADY`.

## Universal interview moves
- **State your assumption** before answering ("do the operations run in sequence?", "value = key or data?").
- Give the **built-in**, then the **manual** version, then the **complexity**.
- Name the **trap** before they ask: width wrap, X with `!=`, an empty-queue pop, a static initializer.
- Say how you'd **prove** it: an assertion, a checker, or a test that must fail.
