# Challenge 23: SystemVerilog OOP for Verification — Handles, Inheritance, Polymorphism, Copying, Casting

> **Level:** Fresher → Senior DV interview
> **Topics:** class vs. struct, handles vs. objects, shallow vs. deep copy, `virtual` methods and polymorphism, `$cast`, abstract classes and pure virtual methods, interface classes, constraint inheritance, inheritance vs. composition for transactions, access qualifiers, static members, how UVM uses all of this
> **Related:** [07 – Factory](07-uvm-pillars-phasing-factory-config-db.md), [16 – Pass-by-handle bug](16-uvm-tlm-ports-exports-fifos.md)

---

## 1. The Post (summary)

A LinkedIn post says SystemVerilog OOP "drives today's silicon" and claims:

1. A `packet` class lets "**the same packet object travel through drivers, monitors, and scoreboards** without copy-paste errors."
2. A three-level inheritance chain (`transaction → mem_req → mem_req_rd / mem_req_wr`) "cuts duplicated code by roughly **40%**".
3. Declare `virtual task drive();` and "**the UVM scheduler calls `driver.drive()`**" without knowing the subclass, so the same test can verify "**an Intel Xeon CPU core, an NVIDIA tensor engine, or a RISC-V accelerator simply by swapping the driver instance**".
4. Exercise: derive child classes that override "**a virtual `do_compare()` task**".

Classes, inheritance and polymorphism really are core to UVM. The specifics are wrong in ways interviewers specifically test.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| "The **same packet object** travels through drivers, monitors and scoreboards" | The **class definition** is shared; the **objects must not be**. The driver's item and the monitor's observed transaction are **different objects** (the monitor builds its own from the pins). Sharing one object across components is the **pass-by-handle bug** (Challenge 16, Section 4.1) |
| Deep inheritance `mem_req_rd / mem_req_wr` | Often a poor fit for transactions: you **can't randomize the class type**, so a sequence can't randomly choose read vs. write. The usual design is **one class with a `kind` field** and constraints (Section 7) |
| "**The UVM scheduler calls `driver.drive()`**" | UVM calls **phase methods** (`build_phase`, `run_phase` …). `drive()` is your own task, called from your `run_phase` |
| Same test verifies a Xeon core, a GPU, a RISC-V accelerator "by swapping the driver" | Different designs have different interfaces and protocols; swapping a driver can't retarget a testbench like that. Polymorphism lets you swap **variants of the same role** (e.g., an error-injecting driver for a normal one) |
| "Virtual `do_compare()` **task**" | `do_compare()` is a virtual **function** (returns `bit`, zero time) |
| "40%", "zero extra compile time" | Invented / irrelevant |

---

## 3. Background a Fresher Must Know

### 3.1 Class vs. struct
| | `struct` | `class` |
|---|---|---|
| Storage | Value (copied on assignment) | **Handle** to a dynamically created object |
| Methods | No | Yes |
| Inheritance / polymorphism | No | Yes |
| Randomization | Members of a `rand` struct inside a class | `rand`/`randc`, constraints, `randomize()` |
| Use | Simple bundles, packed buses | Transactions, components, models |

### 3.2 Handles vs. objects (the source of most OOP bugs)
```systemverilog
packet p1, p2;
p1 = new();        // object A created; p1 points to A
p2 = p1;           // p2 ALSO points to A (no new object!)
p2.addr = 5;       // p1.addr is now 5 too
p1 = null;         // A still alive (p2 refers to it); freed when no handles remain
```
- `p2 = p1` copies the **handle**, not the object.
- Objects are freed automatically when no handle refers to them (no `delete`).

### 3.3 Shallow vs. deep copy
```systemverilog
class header; rand bit [7:0] id; endclass
class packet;
  rand bit [31:0] addr;
  rand header hdr;                       // handle to another object
  function new(); hdr = new(); endfunction
endclass

packet a = new();
packet b = new a;      // SHALLOW copy: b.addr copied, but b.hdr == a.hdr (same header object!)
b.hdr.id = 9;          // changes a.hdr.id too
```
**Deep copy:** write a `copy()` that also creates new nested objects:
```systemverilog
function void copy_from(packet src);
  addr = src.addr;
  hdr  = new();             // new nested object
  hdr.id = src.hdr.id;
endfunction
```
In UVM: `clone()` = create + `copy()`, and `copy()` calls your `do_copy()`, which must deep-copy nested objects.

---

## 4. Inheritance and `virtual` Methods

```systemverilog
class base_txn;
  rand bit [31:0] addr;
  virtual function string to_str();  return $sformatf("addr=%0h", addr); endfunction
  function string kind();            return "base";                       endfunction  // NOT virtual
endclass

class wr_txn extends base_txn;
  rand bit [31:0] data;
  virtual function string to_str();  return {super.to_str(), $sformatf(" data=%0h", data)}; endfunction
  function string kind();            return "write"; endfunction
endclass

base_txn b;
wr_txn   w = new();
b = w;                    // base handle → derived object (always allowed: upcast)
$display(b.to_str());     // "addr=.. data=.."  → VIRTUAL: resolved by the OBJECT type
$display(b.kind());       // "base"             → NON-virtual: resolved by the HANDLE type
```

**The #1 OOP interview question:** "A base handle points to a derived object; which method runs?"
- `virtual` → the **object's** (derived) version.
- non-`virtual` → the **handle's** (base) version.
- Once a method is `virtual` in a base class, it's virtual in all derived classes.
- `super.method()` calls the parent's version (use it to **extend** instead of replace).

---

## 5. `$cast`: Going Back Down

```systemverilog
base_txn b = w;       // upcast: automatic
wr_txn   w2;
w2 = b;               // COMPILE ERROR: can't assign base handle to derived handle directly
if (!$cast(w2, b))    // downcast: checked at runtime
  `uvm_fatal("CAST", "b does not point to a wr_txn")
```
- As a **function**, `$cast` returns 0 on failure (check it!).
- As a **task** (`$cast(w2, b);` without using the result), a failure is a runtime error.
- UVM uses `$cast` everywhere: `clone()` returns `uvm_object`, `do_compare(uvm_object rhs, ...)` receives a base handle.

```systemverilog
virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
  wr_txn r;
  if (!$cast(r, rhs)) return 0;
  return super.do_compare(rhs, comparer) && (addr == r.addr) && (data == r.data);
endfunction
```

---

## 6. Abstract Classes, Pure Virtual Methods, Interface Classes

```systemverilog
virtual class scoreboard_base;                              // abstract: can't be new()'d
  pure virtual function bit check(base_txn exp, base_txn act);  // must be implemented
endclass

class mem_sb extends scoreboard_base;
  virtual function bit check(base_txn exp, base_txn act); /* ... */ endfunction
endclass
```

**Interface classes** (SystemVerilog 2012): a class can `implements` several interface classes, giving multiple-inheritance of **APIs** (not implementation).
```systemverilog
interface class printable;  pure virtual function string to_str(); endclass
interface class checkable;  pure virtual function bit self_check(); endclass
class my_txn extends base_txn implements printable, checkable;
  virtual function string to_str(); return "..."; endfunction
  virtual function bit self_check(); return 1; endfunction
endclass
```

---

## 7. Inheritance vs. Composition for Transactions

**Problem with `rd_txn` and `wr_txn` as separate subclasses:** `randomize()` can't pick the class. A sequence that wants "random reads and writes" must decide the type in procedural code.

**Common design:** one class, a `kind` field, and constraints:
```systemverilog
typedef enum {READ, WRITE} kind_e;
class mem_txn extends uvm_sequence_item;
  rand kind_e     kind;
  rand bit [31:0] addr;
  rand bit [31:0] data;
  constraint c_kind { kind dist {READ := 50, WRITE := 50}; }
  constraint c_rd   { kind == READ -> data == 0; }   // data unused on reads (if spec says so)
endclass
```
**Where inheritance is right:** extending a transaction or component for a **variant of the same role**, e.g., `err_txn extends mem_txn` adding error-injection knobs, swapped in by **factory override** (Challenge 07). That's the real "swap at runtime" power.

**Composition:** a transaction **has** a header object, a payload object, etc. Use it when parts are reusable on their own (e.g., a PCIe TLP with header + payload).

---

## 8. Constraints and Inheritance
- A derived class **inherits** constraints.
- A constraint with the **same name** in the derived class **replaces** the parent's.
- A **new name** adds a constraint (both apply).
```systemverilog
class small_txn extends mem_txn;
  constraint c_addr_small { addr < 256; }        // adds
  constraint c_kind { kind == WRITE; }           // REPLACES parent's c_kind
endclass
```
- `pre_randomize()` / `post_randomize()` are called automatically (call `super.` versions if overriding).
- `constraint_mode(0)` / `rand_mode(0)` turn constraints/variables off per object.

---

## 9. Other Things Interviewers Ask

| Topic | Key point |
|---|---|
| `local` / `protected` | `local`: only this class; `protected`: this class and derived classes |
| `static` members | One copy shared by all objects (e.g., an ID counter); static methods can't access non-static members |
| `extern` methods | Declare in the class, define outside: `function void my_class::f(); ... endfunction` |
| Constructors | `new()` is never virtual; always call `super.new()` first (with arguments if the parent needs them) |
| Parameterized classes | `class fifo #(type T = int);` — each specialization is a **different type** (matters for factory/config_db, Challenge 07) |
| Typed handles in containers | `base_txn q[$]` can hold any derived object; use `$cast` to get the derived type back |
| Garbage collection | Automatic; objects live while referenced (watch growing queues in scoreboards) |

---

## 10. How UVM Uses OOP (tie it together)
- **Inheritance:** every component extends `uvm_component`, every item extends `uvm_sequence_item`.
- **Virtual methods:** phases (`build_phase`, `run_phase` …) and `do_copy`/`do_compare`/`do_print` are virtual, so UVM calls **your** override through base handles.
- **Factory:** creates a **derived** class when the base is requested (Challenge 07). Works only because of inheritance + virtual methods.
- **`$cast`:** used in `clone()`, `do_compare`, `p_sequencer` (Challenge 05).
- **Parameterized classes:** `uvm_sequencer #(REQ)`, `uvm_analysis_port #(T)`, `uvm_config_db #(T)`.
- **Callbacks:** polymorphic hook objects registered at runtime.

---

## 11. Likely Follow-ups (with model answers)

**Q. Base handle, derived object, method not declared virtual. Which version runs?**
The base (handle's) version. Only virtual methods dispatch on the object's type.

**Q. Shallow vs. deep copy?**
`new src` copies member values, but nested object handles still point to the same nested objects. A deep copy creates new nested objects too. In UVM, implement `do_copy` to deep-copy.

**Q. When does `$cast` fail?**
When the source handle doesn't point to an object of the target type (or a subtype). Always check its return value.

**Q. Why not separate read and write transaction classes?**
You can't randomize the class type, so mixing reads and writes randomly becomes procedural. One class with a `kind` field and constraints keeps it random and simpler.

**Q. Can you call `randomize()` on a derived object through a base handle?**
Yes. `randomize()` is virtual, so the derived class's variables and constraints are all used.

**Q. What's an abstract class?**
A `virtual class` that can't be instantiated, often with `pure virtual` methods that derived classes must implement.

---

## 12. Common Fresher Mistakes
- Assigning a handle and expecting a copy.
- Shallow copies of objects with nested handles.
- Forgetting `virtual`, then wondering why the override doesn't run.
- Not checking `$cast`.
- Overriding a constraint by accidentally reusing its name.
- One shared transaction object passed between components.
- Calling `do_compare` a task.

---

## 13. 60-Second Interview Pitch

> "Classes give me handles, not values, so assignment copies the handle. I'm careful with copies: `new` with a source object is shallow and shares nested objects, so in UVM I implement do_copy as a deep copy and clone transactions before storing them.
>
> Polymorphism depends on virtual methods. A base handle pointing to a derived object calls the derived version only if the method is virtual; otherwise the handle type decides. Going back down needs $cast, which I always check. UVM is built on this: phases and do_copy, do_compare and do_print are virtual, and the factory substitutes derived classes.
>
> For transactions I usually prefer one class with a kind field and constraints, because you can't randomize the class type. I use inheritance for variants of the same role, like an error-injecting transaction or driver swapped in by factory override. A constraint with the same name in a child replaces the parent's; a new name adds to it. I use abstract classes and pure virtual methods for common APIs, and interface classes when a class needs several."

---

## 14. Self-Check
- [ ] Can I explain handle assignment vs. object copy, and shallow vs. deep copy?
- [ ] Can I predict which method runs with virtual vs. non-virtual?
- [ ] Can I write a correct `$cast` in `do_compare`?
- [ ] Can I explain why one transaction class with `kind` often beats subclasses?
- [ ] Can I explain constraint override vs. addition in derived classes?
