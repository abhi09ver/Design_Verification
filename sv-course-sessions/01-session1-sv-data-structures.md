# Session 1 — SystemVerilog Data Structures

Source: `Session1_pdf_SV_Data_Structures.pdf`, page 45 (14 questions) and page 52 (9 array operations).
Code: [`code/session1_data_structures/`](code/session1_data_structures/) · Output: [`logs/s1_data_structures.log`](logs/s1_data_structures.log), [`logs/s1_slide52_array_ops.log`](logs/s1_slide52_array_ops.log)

---

## Part A — Page 45: 14 questions

### Q1 & Q2. Sort ascending / descending
- **Built-ins:** `arr.sort()` / `arr.rsort()`. They sort **in place** and return void, so `b = a.sort();` is illegal.
  Supported on fixed unpacked arrays, dynamic arrays and queues. **Not** on associative arrays.
- **Without built-ins:** bubble sort. Only the comparison flips (`>` for ascending, `<` for descending).
- Pass the array as `ref` into an `automatic` function. By value, you sort a copy.

```systemverilog
function automatic void sort_asc(ref int a[]);
  for (int i = 0; i < a.size()-1; i++)
    for (int j = 0; j < a.size()-1-i; j++)
      if (a[j] > a[j+1]) begin int t = a[j]; a[j] = a[j+1]; a[j+1] = t; end
endfunction
```
**Follow-ups**
- *Sort objects by a field?* `pkts.sort(p) with (p.addr);`
- *Complexity?* O(n²). Add a `swapped` flag for an early exit (O(n) on sorted input).

### Q3. Remove duplicates
- Built-in: `q = q.unique();`. It returns a new queue, and the LRM does not guarantee its output order.
- **Order-preserving version:** use an associative array as a "seen" set. O(n).
```systemverilog
bit seen[int]; int out[$];
foreach (a[i]) if (!seen.exists(a[i])) begin seen[a[i]] = 1; out.push_back(a[i]); end
```
- **No extra memory?** Sort, then drop adjacent equal elements. O(n log n), and the original order is lost.

### Q4. Compare two queues, in order
- Compare sizes first, then elements with `!==`.
- `!=` with an X gives X, so the `if` is not taken and the mismatch is silently missed. `!==` catches it.
- `q1 == q2` works for same-type unpacked arrays, but the loop tells you **which index** failed. That is what a scoreboard needs.

### Q5. Compare queues, out of order (multiset)
```systemverilog
int cnt[int];
if (q1.size() != q2.size()) return 0;
foreach (q1[i]) cnt[q1[i]]++;
foreach (q2[i]) begin
  if (!cnt.exists(q2[i]) || cnt[q2[i]] == 0) return 0;
  cnt[q2[i]]--;
end
return 1;
```
- **The trap:** checking only "every element of q2 exists in q1" passes `{1,2,3,2}` vs `{1,2,3,3}`. Duplicate counts matter.
- **Alternative:** sort copies of both, then compare in order. O(n log n).
- **Real-world link:** an out-of-order scoreboard (e.g. AXI with different IDs).

### Q6. FIFO using a queue (push / pop)
- `push_back` at the tail and `pop_front` from the head. Add a `DEPTH` bound plus `is_full()` and `is_empty()`.
- **LIFO** = `push_back` with `pop_back`.
- **Queue vs mailbox:**
  - A queue is a plain data structure and never blocks.
  - A mailbox is for passing data between threads, and `get()` blocks until data arrives.
  - A bounded `mailbox #(T) mb = new(DEPTH)` makes `put()` block when full, which models an RTL FIFO.

### Q7. Detect underflow
- Underflow = a pop on an empty FIFO. Check `q.size() == 0` **before** calling `pop_front()`.
- `pop_front()` on an empty queue does **not** stop the simulation. It returns the default value (0), with maybe a warning, and your scoreboard silently compares against a fake 0.
- **In RTL:** `assert property (@(posedge clk) rd_en |-> !empty);`

### Q8. Sparse memory with an associative array
```systemverilog
bit [31:0] mem [bit [63:0]];   // storage only for addresses actually written
```
- **Reading an address never written:** returns the default value. Guard with `exists()`, or return `'hDEADBEEF` so uninitialised reads are easy to spot.
- `foreach`, `first()` and `next()` visit keys in **ascending** order.
- Prefer a sized integral key over the wildcard `[*]`.

### Q9. Does a value exist in an associative array?
First clarify whether "value" means the **key** or the **stored data**:
- **Key:** `mem.exists(k)`. Fast.
- **Data:** `idx = mem.find_index with (item == v);` then check `idx.size() != 0`. O(n) scan.

**Trap:** `if (mem[k] != 0)` is wrong for two reasons. A missing key reads as 0, and a key that stores a real 0 looks missing.

### Q10. Which data structure for a memory block?
| Situation | Choice |
|---|---|
| Small, fixed size, fully used (register file) | Fixed-size array |
| Size known at runtime, dense | Dynamic array |
| Huge address space, sparsely touched (DDR model) | **Associative array** |
| Arrival order matters (transaction buffer) | Queue |

**Model answer:** "An associative array indexed by address, because tests touch a tiny fraction of a large address space."

### Q11. Concatenate strings
- `{s1, " ", s2}` joins strings.
- `$sformatf("%s_%0d", s1, n)` is the right tool when mixing in numbers.
- Replication: `{3{"ab"}}` gives `"ababab"`.

### Q12. Reverse a string
- `r[i] = s[s.len()-1-i]`. For an in-place reverse, swap `s[i]` with `s[len-1-i]` for half the length.
- `string` has **no** `reverse()` method. That method exists on queues and arrays.
- **Palindrome check:** `s == str_rev(s)`.

### Q13. Compare strings ignoring case
- `s1.icompare(s2) == 0`, or `s1.tolower() == s2.tolower()`.
- **Trap:** `compare()` and `icompare()` work like C's `strcmp` and return **0 when equal**. `if (s1.icompare(s2))` therefore means "different".

### Q14. Resize array A from 200 to 250
| Type of A | How |
|---|---|
| Dynamic, **keep** data | `A = new[250](A);` keeps elements 0–199; new elements get default values |
| Dynamic, **discard** data | `A = new[250];` allocates fresh storage and the old data is lost |
| Fixed `int A[200]` | **Cannot** be resized (size set at compile time); declare a new array and copy |
| Queue | No resize step needed; just `push_back` |

**Shrink:** `A = new[100](A);` keeps the first 100 elements and truncates the rest.

---

## Part B — Page 52: 9 operations on `int arr[] = '{7,2,9,4,2,7,1}`

| # | Operation | Correct code | Result |
|---|---|---|---|
| 1 | Ascending | `arr.sort();` | 1 2 2 4 7 7 9 |
| 2 | Descending | `arr.rsort();` | 9 7 7 4 2 2 1 |
| 3 | Reverse | `arr.reverse();` | 1 7 2 4 9 2 7 |
| 4 | Smallest | `q = arr.min(); q[0]` | 1 |
| 5 | Largest | `q = arr.max(); q[0]` | 9 |
| 6 | Sum | `arr.sum()` / `arr.sum() with (longint'(item))` | 32 |
| 7 | Remove evens | `arr = arr.find with (item % 2 != 0);` | 7 9 7 1 |
| 8 | First index > 5 | `iq = arr.find_first_index with (item > 5);` | index 0 |
| 9 | Duplicates | count map (below) | 2, 7 |

### ⚠️ Three errors in the slide's answer key
1. **Rows 4–5:** `int min_val = arr.min();` is a **type error**. All locator methods (`min`, `max`, `unique`, `find*`) return a **queue** (IEEE 1800-2017 §7.12.1). The queue can be empty when the array is empty, so there is never a fake value to return.
2. **Row 8:** `int idx = arr.find_index with (item > 5);` has the same type error, **and** it is the wrong method. `find_index` returns **all** matching indices (`{0,2,4,5}`). The question wants `find_first_index`. Check `iq.size()` before reading `iq[0]`.
3. Some simulators accept these forms with only a warning. Strict VCS or Xcelium setups reject them.

### Deep points
- **`reverse()` vs `rsort()`:** they give the same result only on already-sorted data.
- **`sum()` overflow:** the result has the element's width. `bit [7:0] {200,100}.sum()` gives 44. Widen inside `with`.
- **Odd test:** use `item % 2 != 0`, not `== 1`, because `-3 % 2` is `-1`. `item[0] == 1` also works for negatives.
- **`item.index`** inside a `with` clause filters by position.
- **Duplicates, O(n):**
  ```systemverilog
  int cnt[int];
  foreach (arr[i]) cnt[arr[i]]++;
  foreach (cnt[v]) if (cnt[v] > 1) $display("%0d x%0d", v, cnt[v]);
  ```
  The slide's `inside {duplicates}` version rescans the result list on every hit, making it O(n·d).
- **Trick question:** "Do the 9 operations run in sequence on the same array?" If yes, step 7 leaves `{7,9,7,1}`, so step 9 returns only `{7}`. **State your assumption.**
