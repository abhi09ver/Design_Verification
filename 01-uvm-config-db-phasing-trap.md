# Challenge 01: The `uvm_config_db` "Phasing Trap" (and Why the Popular Answer Is Wrong)

> **Level:** Fresher → Senior DV interview
> **Topics:** UVM phasing, `create()` vs `build_phase`, `uvm_config_db`, factory overrides, objections, debug flow

---

## 1. The Problem (as usually posted)

- `my_test::build_phase` does:
  ```systemverilog
  uvm_config_db#(int)::set(this, "env.agt.drv", "num_transactions", 10);
  env = my_env::type_id::create("env", this);
  ```
- `my_driver` is **factory-overridden** to `my_extended_driver`.
- `my_driver::build_phase` does:
  ```systemverilog
  uvm_config_db#(int)::get(this, "", "num_transactions", num_transactions_to_drive);
  ```
- The driver raises an objection in `run_phase` and should drop it after driving N transactions.

**Symptom:** Simulation hangs. Log says `DRIVER_RUN: Driving 0 transactions`.

**Commonly posted "solution":** *"`create()` triggers the child's `build_phase` immediately, so the driver's `get` runs before the test's `set`. Move the `get` to `connect_phase`."*

**That explanation is wrong.** The rest of this file explains why, what the real causes are, and how to fix them properly.

---

## 2. Background a Fresher Must Know First

### 2.1 `create()` is NOT `build_phase`

| Call | What actually happens |
|---|---|
| `my_env::type_id::create("env", this)` | Asks the **factory** which class to build (applies overrides), then calls `new()`. That's it. |
| `build_phase` | Called later by the **UVM phasing engine**, not by `create()`. |

So `create()` gives you an *object that exists* but has **not built its children yet**.

### 2.2 Phase order

```
build_phase              -> top-down   (parent first, then children)
connect_phase            -> bottom-up
end_of_elaboration_phase -> bottom-up
start_of_simulation_phase-> bottom-up
run_phase                -> all components in parallel (task, consumes time)
extract / check / report / final
```

**Why build is top-down:** a parent must create its children before the children can be built. And a parent must finish configuring (`set`) before children read (`get`).

### 2.3 `uvm_config_db` mental model

Think of it as a **global lookup table**. Each entry is keyed by:

1. **Scope** = `cntxt.get_full_name()` + `"." + inst_name` → e.g. `uvm_test_top.env.agt.drv`
2. **Field name** → `"num_transactions"`
3. **Type parameter** → the `T` in `uvm_config_db#(T)`

A `get` succeeds **only if all three match**. If it fails, it returns `0` and **leaves your variable untouched** (so it keeps its default, usually `0`).

---

## 3. Why the Posted Explanation Is Wrong: Actual Timeline

```
build_phase (top-down):

uvm_test_top.build_phase()                       <- my_test
   set(this, "env.agt.drv", "num_transactions", 10)   // stored NOW
   env = create("env")                                // only new(); NO build yet
return

uvm_test_top.env.build_phase()                   <- runs AFTER test's build returns
   agt = create("agt")

uvm_test_top.env.agt.build_phase()
   drv = my_driver::type_id::create("drv")       // factory returns my_extended_driver

uvm_test_top.env.agt.drv.build_phase()           <- my_extended_driver::build_phase
   get(...)                                      // set happened long ago
```

**Key point:** even if the test did `create` first and `set` second, it would still work, because `env.build_phase` cannot start until `my_test::build_phase` has fully returned.

**Timing between test `set` and driver `get` is not the bug.**

---

## 4. Why Does the Sim *Hang* With 0 Transactions?

The challenge does not show `run_phase`, so state your assumption in an interview. A typical buggy driver:

```systemverilog
task run_phase(uvm_phase phase);
  int count = 0;
  phase.raise_objection(this);
  `uvm_info("DRIVER_RUN", $sformatf("Driving %0d transactions", num_transactions_to_drive), UVM_LOW)
  forever begin
    seq_item_port.get_next_item(req);   // blocks if no more items
    drive_item(req);
    seq_item_port.item_done();
    count++;
    if (count == num_transactions_to_drive)   // 0 is never equal to 1,2,3...
      phase.drop_objection(this);
  end
endtask
```

With `num_transactions_to_drive == 0`:
- `count` becomes 1, 2, 3 … and never equals 0 → objection **never dropped**.
- Once the sequence finishes, `get_next_item` blocks forever **with the objection still raised** → **hang** (until UVM's global timeout fires, if any).

> Note: if the loop were `repeat(n) ... ; drop_objection;` then `n = 0` would end the sim almost **immediately**, not hang. A hang tells you the drop is conditional or sits after a blocking call.

---

## 5. The Real Root Causes (ranked by likelihood)

The challenge deliberately mentions the **factory override**. That's the clue.

### Cause 1 (most likely): Extended driver forgets `super.build_phase()`

```systemverilog
class my_extended_driver extends my_driver;
  `uvm_component_utils(my_extended_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    // BUG: super.build_phase(phase) is missing
    // -> my_driver::build_phase never runs -> get never happens
    `uvm_info("EXT_DRV", "Extended driver build", UVM_LOW)
  endfunction
endclass
```

Because the factory returns `my_extended_driver`, only **its** `build_phase` runs. The parent's `get` is silently skipped. Value stays `0`.

**Fix:**
```systemverilog
function void build_phase(uvm_phase phase);
  super.build_phase(phase);   // FIX
  `uvm_info("EXT_DRV", "Extended driver build", UVM_LOW)
endfunction
```

> **Why the "move to `connect_phase`" fix *seems* to work:** if `my_extended_driver` does not override `connect_phase`, then `my_driver::connect_phase` runs normally and the `get` happens there. The symptom disappears, but the real bug (missing `super`) is still there and will bite the next person who adds code to the base `build_phase`. **Band-aid, not a fix.**

### Cause 2: Variable shadowing in the extended class

```systemverilog
class my_extended_driver extends my_driver;
  int num_transactions_to_drive;   // BUG: redeclared, hides the parent's variable
  ...
  task run_phase(uvm_phase phase);
    // reads the CHILD's variable (= 0), not the one the parent's get() filled
  endtask
endclass
```

The base `get` writes `my_driver::num_transactions_to_drive = 10`.
The extended `run_phase` reads `my_extended_driver::num_transactions_to_drive = 0`.

**Fix:** delete the redeclaration in the child.

### Cause 3: Type parameter mismatch

```systemverilog
// test
uvm_config_db#(int)::set(this, "env.agt.drv", "num_transactions", 10);
// driver
int unsigned num_transactions_to_drive;
uvm_config_db#(int unsigned)::get(this, "", "num_transactions", num_transactions_to_drive); // FAILS
```

`int` and `int unsigned` are **different types** → different entries → `get` returns 0.

Also watch out: `+uvm_set_config_int` and `uvm_config_int` use `uvm_bitstream_t`, not `int`.

Note: the snippet in the original post (`uvm_config_db::set(...)` without `#(T)`) will not even compile. The type parameter is mandatory.

**Fix:** use the same type on both sides. Better: a shared `typedef` or a config object (Section 7).

### Cause 4: Path or field-name mismatch

- Env names the agent `"agent"` but the test says `"env.agt.drv"`.
- Agent names the driver `"driver"` instead of `"drv"`.
- `"num_transactions"` vs `"num_transaction"` or `"NUM_TRANSACTIONS"`.

**Fix:** print the topology and compare paths (Section 6).

### Cause 5 (makes every cause above silent): ignoring the return value of `get`

```systemverilog
uvm_config_db#(int)::get(this, "", "num_transactions", num_transactions_to_drive); // result ignored
```

**Fix:**
```systemverilog
if (!uvm_config_db#(int)::get(this, "", "num_transactions", num_transactions_to_drive))
  `uvm_fatal("NOCFG", {"num_transactions not set for ", get_full_name()})
```

Keep this check **in `build_phase`**. Fail fast, at time 0, with a clear message, instead of a hang hours later.

---

## 6. How to Debug This in Real Life (step by step)

1. **Read the hang correctly:** "Driving 0" means the value never arrived. Don't touch phasing yet.
2. **Turn on config tracing:** add `+UVM_CONFIG_DB_TRACE` to the sim command line. You'll see every `set` and `get`, with full paths and whether each `get` matched.
3. **Print the topology** in `end_of_elaboration_phase`:
   ```systemverilog
   uvm_top.print_topology();
   ```
   Confirm the real path is `uvm_test_top.env.agt.drv`.
4. **Check the factory:**
   ```systemverilog
   uvm_factory::get().print();
   ```
   Confirm the override and that `drv` is a `my_extended_driver`.
5. **Find unused sets:** call `uvm_top.check_config_usage();` (e.g., in `report_phase`). Lists `set`s that nobody ever read, which points straight at path/type mismatches.
6. **Read the extended class:** look for a missing `super.build_phase()` and redeclared variables.
7. **Look at the objection logic:** add `+UVM_OBJECTION_TRACE` to see who raised and never dropped.

---

## 7. The Senior-Level Fix (robust design, not just the minimal patch)

### Minimal fix (answer this first in the interview)
- Add `super.build_phase(phase)` in `my_extended_driver` (or remove the shadowed variable / fix the type / fix the path, whichever the trace shows).
- Check `get`'s return value with `` `uvm_fatal ``.

### Robust fix (then show you think beyond the patch)

**a) Use a configuration object instead of scattered scalars**

```systemverilog
class agent_cfg extends uvm_object;
  `uvm_object_utils(agent_cfg)
  int num_transactions = 10;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  function new(string name = "agent_cfg"); super.new(name); endfunction
endclass

// test build_phase
agent_cfg cfg = agent_cfg::type_id::create("cfg");
cfg.num_transactions = 10;
uvm_config_db#(agent_cfg)::set(this, "env.agt*", "cfg", cfg);

// driver build_phase
if (!uvm_config_db#(agent_cfg)::get(this, "", "cfg", cfg))
  `uvm_fatal("NOCFG", "agent_cfg not found")
```
One `set`, one type, one name. No `int` vs `int unsigned` surprises.

**b) Drivers should not own objections**

A driver is a slave to the sequencer. It should loop forever and be killed when the phase ends:

```systemverilog
task run_phase(uvm_phase phase);
  forever begin
    seq_item_port.get_next_item(req);
    drive_item(req);
    seq_item_port.item_done();
  end
endtask
```

The **test** (or the sequence) controls how many transactions and owns the objection:

```systemverilog
task run_phase(uvm_phase phase);
  my_seq seq = my_seq::type_id::create("seq");
  seq.num_items = cfg.num_transactions;
  phase.raise_objection(this);
  seq.start(env.agt.sqr);
  phase.drop_objection(this);
endtask
```

Now a wrong count can never cause a hang. The sim ends when the sequence ends.

---

## 8. Likely Interviewer Follow-ups (with model answers)

**Q1. Does `create()` call `build_phase`?**
No. `create()` = factory lookup + `new()`. `build_phase` is called by the phasing engine, top-down, after the parent's `build_phase` returns.

**Q2. Why is build top-down and connect bottom-up?**
Build: parents must create and configure children before children build. Connect: lower-level ports/exports must exist before higher levels wire them together.

**Q3. Env also does `set(this, "agt.drv", "num_transactions", 5)` and the test sets 10. Who wins?**
During `build_phase`, the **higher context in the hierarchy wins** → test's 10. After build_phase, the **last `set` wins**. This lets tests override env defaults.

**Q4. Why is `set(null, "*", "num_transactions", 10)` risky?**
It matches every component. Any other component reading the same field name silently gets 10. Keep scopes as narrow as possible.

**Q5. The test changes the value in `run_phase`. Does the driver see it?**
Not if the driver only did `get` in `build_phase`. It has a copy. Use `uvm_config_db#(T)::wait_modified()` or share a config object handle so changes are visible.

**Q6. Why did moving `get` to `connect_phase` "fix" it?**
Only if the real bug was a missing `super.build_phase()` and the child didn't override `connect_phase`. The base method ran via a different phase. The real bug is still there.

**Q7. Why `uvm_fatal` instead of `uvm_warning`?**
A missing critical config means every result after that is invalid. Fail at time 0 with a clear message instead of wasting a regression slot on a hang.

---

## 9. Common Fresher Mistakes

- Believing `create()` builds the whole sub-tree.
- Ignoring `get`'s return value.
- Forgetting `super.build_phase(phase)` (and `super.new(...)`) in extended classes.
- Redeclaring parent variables in child classes.
- Mixing `int`, `int unsigned`, `bit [31:0]`, `uvm_bitstream_t` between `set` and `get`.
- Raising/dropping objections in the driver.
- Accepting a fix because the symptom disappeared, without confirming the root cause.

---

## 10. 60-Second Interview Pitch

> "First, I'd challenge the premise that it's a build-order race. `create()` only constructs the object; `build_phase` runs top-down after the parent's build returns, so the test's `set` always precedes the driver's `get`.
>
> 'Driving 0' means the `get` failed or its result never reached `run_phase`. Since the driver is factory-overridden, my first suspect is `my_extended_driver::build_phase` missing `super.build_phase()`, so the base class `get` never runs. Next I'd check for a shadowed variable in the child, a type mismatch like `int` vs `int unsigned`, and a path mismatch. I'd confirm with `+UVM_CONFIG_DB_TRACE`, `print_topology`, and `check_config_usage`.
>
> The hang happens because the objection drop depends on a count that never matches zero, while the driver blocks on `get_next_item`.
>
> Minimal fix: add `super.build_phase` and make the `get` fatal on failure. Long-term fix: move the count into a config object, let the test or sequence own the objection, and keep the driver a simple forever loop so a bad config can't hang the sim."

---

## 11. Self-Check Before the Interview

- [ ] Can I draw the build-phase timeline from memory?
- [ ] Can I explain the three keys of a config_db lookup (scope, name, type)?
- [ ] Can I list 4 reasons a `get` returns 0?
- [ ] Can I explain why the `connect_phase` "fix" is a band-aid?
- [ ] Can I explain config_db precedence during vs after `build_phase`?
- [ ] Can I justify why objections belong in the test/sequence, not the driver?
