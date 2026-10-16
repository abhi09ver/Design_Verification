# Lecture companion: Register model (RAL)

> Card-by-card notes for Cristian Slav's course. Diagrams and toys are in `pages/uvm-from-zero.html`.

Chapter · the UVM register model (15 videos)

## RAL: a mirror of the Aligner's registers

The Aligner has four registers: CTRL, STATUS, IRQEN and IRQ. This chapter models them with the UVM register layer (RAL) and connects the model to the APB agent twice. The **monitor path** keeps the model's copy (the "mirror") up to date and checks every read and every APB response. The **sequencer path** lets tests write `CTRL.write()` instead of building APB sequences. The chapter ends with the course's first real bug, in both the RTL and the spec.

*[Diagram: Register model connected to the APB agent through the sequencer and through the monitor. Open the HTML page to see it.]*

Every access starts on path ① or in a plain APB sequence, and the monitor then sees it on path ②. That's why the mirror stays correct without the register model predicting its own writes: auto-predict stays off, which is the default.

---

R1

## What is a register model?

Introduction to the UVM register layer · lecture

Think of it like…

You keep a notebook of what's in your friend's lunchbox. When you see them put an apple in (a **write**), you note "apple". When they open it in front of you (a **read**), you check it matches your note. If it says banana, something's wrong. The register model is that notebook for the chip's registers. Its notes are called the **mirror**.

job 1

#### Track writes

Every OK write seen on APB updates the mirrored field values. For example, `0x101` to address 0 sets SIZE=1 and OFFSET=1.

job 2

#### Check reads

Every read compares the RTL's data with the mirror. A mismatch raises an error automatically, with no code in the scoreboard.

job 3

#### Abstract the tests

`CTRL.write()`, `read()` and `update()` replace APB sequences. If APB is swapped for AHB or I2C, you change the agent and the tests stay the same.

helper

#### The predictor

Translates monitor items into register operations, and here also checks that each APB response (OKAY or SLVERR) is the expected one.

| Class | Models | Extend it? | Aligner uses it? |
| --- | --- | --- | --- |
| `uvm_reg_field` | A group of bits that behave as one (SIZE, OFFSET…) | No, use as is | ✅ 16 fields |
| `uvm_reg` | A register: a container of fields | Yes, one class per register | ✅ 4 classes |
| `uvm_reg_block` | Container of registers, files, memories and other blocks | Yes | ✅ `cfs_algn_reg_block` |
| `uvm_reg_map` | Addresses as seen through one physical bus | No | ✅ `default_map` (APB) |
| `uvm_reg_file` | A repeated group of registers (A,B,C ×N) | Yes | ❌ no repeated groups |
| `uvm_mem` | A memory | No | ❌ no memory |

Vocabulary

- An **instance** of a register block is called a **register model**.
- Blocks nest. A system-level environment builds one big block from each module's block.
- One **map per physical interface**. If registers can be reached over two buses, each gets its own map, possibly with different addresses.
- Documentation: Class Reference → "Register Layer". User Guide → chapter 5, "Using the Register Layer Classes".

**Q: "Why use RAL instead of checking registers in the scoreboard?"**

RAL gives you, for free: a mirror updated from observed traffic, automatic read checks, access-policy behaviour (W1C, RO, WO…), reset values, randomizable fields with constraints, and a protocol-independent API for tests and sequences. It's also reusable vertically: the module's block becomes a sub-block at system level. Writing that by hand means re-implementing all of it per project.

**Q: "What's a uvm\_reg\_map and when do you need more than one?"**

It maps each register to an offset as seen through one bus, with the bus width, endianness and addressing mode, and holds the sequencer/adapter for front-door access. You need one per physical interface that can access the registers, for example a CPU bus and a debug JTAG port with different address layouts.

---

R2

## uvm\_reg\_field: four values per field

The UVM register field · lecture

Every field carries four values. Knowing which one each API touches is the most-asked RAL interview topic.

| Value | Visibility | Meaning | Changed by | Read with |
| --- | --- | --- | --- | --- |
| **mirrored** | local | Best guess of what's in the RTL right now | Observed writes (predictor), `predict()`, `reset()` | `get_mirrored_value()` |
| **desired** | local | What you want the RTL to hold next | `set()`, `randomize()` (via post\_randomize), `reset()` | `get()` |
| **value** | **public** | The randomization variable. Public so constraints can reference it. | `randomize()` | (copied to desired after randomize) |
| **reset** | local, assoc array `[string]` | Reset value per reset kind; default key `"HARD"` | `configure()`, `set_reset()` | `get_reset()`, `has_reset()` |

The workflows

- **set → update**: `SIZE.set(2); OFFSET.set(2); CTRL.update(status);` → one APB write of `0x202`. Afterwards mirror = desired.
- **randomize → update**: constraints on `.value` → post\_randomize copies to desired → `update()` writes it.
- **reset()** copies the reset value into mirrored, desired and value. Call it on the **block** when you detect the RTL reset; it cascades to every register and field.
- **predict()** is for fields the **hardware** changes (status counters, IRQ bits). Bus-written fields are predicted automatically by the predictor.

```systemverilog
field.configure(
  .parent(this),            // the uvm_reg that owns it
  .size(2), .lsb_pos(8),    // OFFSET = bits [9:8]
  .access("RW"),            // RO, RW, WO, W1C… (User Guide table 7)
  .volatile(0),             // 1 = hardware changes it too fast to model: NO read check
  .reset(0), .has_reset(1), // reset value only stored if has_reset = 1
  .is_rand(1),              // 0 = randomize() leaves this field alone
  .individually_accessible(0)); // APB always writes the whole register
```

Reserved bits

- The User Guide allows leaving them **unmodeled**: "assumed to be read-only fields filled with zeros". The Aligner does this.
- Alternatives: model them, or model them and disable checking with `set_compare(0)`. The lecturer hints at one advantage of modeling them, which comes later in the course.
- Helpers: `get_lsb_pos()` (SIZE 0, OFFSET 8, CLR 16) and `get_n_bits()` (3, 2, 1).

**Q: "Mirrored vs desired value?"**

Mirrored is what the testbench believes the DUT contains; it's updated by observed bus traffic or `predict()` and used to check reads. Desired is what the test wants the DUT to contain; it's changed by `set()`/`randomize()` and pushed by `update()`. `update()` only issues a bus access when `needs_update()` sees desired ≠ mirrored.

**Q: "When do you set volatile = 1, and what does it cost?"**

When the hardware changes the field in ways you can't predict cycle-accurately, such as a free-running counter. The cost is that read checks are skipped for that field, so you lose checking. The Aligner keeps CNT\_DROP non-volatile and models it precisely instead; your model calls `CNT_DROP.predict(+1)` on every dropped transfer, saturating at 255.

**Q: "Why is 'reset' an associative array?"**

Designs can have several resets (HARD, SOFT, warm…) with different reset values per field. Each kind is a key. `configure()` fills "HARD"; `set_reset(val, "SOFT")` adds others; `reg_block.reset("SOFT")` applies one.

**Q: "What does individually\_accessible mean?"**

Whether the bus can access just that field without touching its neighbours, for example byte-enabled writes where the field fills whole byte lanes. APB without PSTRB always writes the full register, so it's 0 for every Aligner field, and a field-level `write()` becomes a full-register write.

---

R3

## uvm\_reg and the four Aligner registers

The UVM register · lecture + practice

rule 1–2

#### Public, same name

A public property per field, named exactly as in the datasheet.

rule 3

#### `rand`

So randomizing the register randomizes each field's `value`.

rule 4

#### UPPERCASE

Field names **and your own methods** in uppercase (`SET_ALGN_DATA_WIDTH`), so they never collide with uvm\_reg's lowercase API.

rule 5–6

#### `build()`

Create every field and call its `configure()`. uvm\_reg has no build() of its own: you add it, and the block calls it.

```systemverilog
class cfs_algn_reg_ctrl extends uvm_reg;
  rand uvm_reg_field SIZE;      // [2:0]  RW reset 1
  rand uvm_reg_field OFFSET;    // [9:8]  RW reset 0
  rand uvm_reg_field CLR;       // [16]   WO reset 0
  `uvm_object_utils(cfs_algn_reg_ctrl)
  function new(string name = "");
    super.new(.name(name), .n_bits(32), .has_coverage(UVM_NO_COVERAGE));
  endfunction
  virtual function void build();
    SIZE = uvm_reg_field::type_id::create(.name("SIZE"), .parent(null), .contxt(get_full_name()));
    SIZE.configure(this, 3, 0, "RW", 0, 3'b001, 1, 1, 0);
    // ... OFFSET (2, 8, "RW") and CLR (1, 16, "WO") the same way
  endfunction
endclass
```

| Register | Offset | Map rights | Fields (lsb:width, access) |
| --- | --- | --- | --- |
| CTRL | 0x00 | RW | SIZE 0:3 RW (reset 1) · OFFSET 8:2 RW · CLR 16:1 WO |
| STATUS | 0x0C | RO | CNT\_DROP 0:8 · RX\_LVL 8:4 · TX\_LVL 16:4, all RO |
| IRQEN | 0xF0 | RW | RX\_FIFO\_EMPTY, RX\_FIFO\_FULL, TX\_FIFO\_EMPTY, TX\_FIFO\_FULL, MAX\_DROP at bits 0–4, RW |
| IRQ | 0xF4 | RW | the same five bits, **W1C** (write 1 to clear) |

Practice notes

- Register classes live in their own package, `cfs_algn_reg_pkg` (User Guide packaging rule). The env package includes and imports it.
- Fields are created with `.parent(null)` (they're objects, not components) and `.contxt(get_full_name())` so the factory can still target them by path.
- IRQ is a copy of IRQEN with only the access changed, which is exactly where copy-paste bugs hide. The lecturer double-checks every lsb against the spec.
- `has_coverage`: `UVM_NO_COVERAGE` for now. Other options enable bit, address-map or field coverage models.

**Q: "Why must custom members of a uvm\_reg be uppercase?"**

uvm\_reg already has hundreds of lowercase members (`read`, `write`, `get`, `set`, `reset`, `predict`…). A field called `reset` or a method called `write` would silently shadow them and break the register layer. Uppercase is guaranteed collision-free. Register generators follow the same rule.

**Q: "Map rights vs field access: what's the difference?"**

Field access (RW, RO, WO, W1C, RC, …) defines per-field behaviour on read and write. Map rights (RW, RO, WO only) describe the whole register as seen through that map. STATUS is RO in the map because every field is RO. IRQ is RW in the map even though its fields are W1C, because it can be written.

**Q: "Would you hand-write these classes on a real project?"**

Rarely. Register descriptions usually live in IP-XACT, SystemRDL or a spreadsheet, and a generator emits the RAL classes, RTL register file, C headers and documentation from one source. Hand-writing them once, as here, is how you learn what the generator produces and how to debug it.

---

R4

## The register block, its map, and where it lives

The UVM register block · lecture + practice

```systemverilog
class cfs_algn_reg_block extends uvm_reg_block;
  rand cfs_algn_reg_ctrl   CTRL;     // exact type, datasheet name, rand, UPPERCASE
  rand cfs_algn_reg_status STATUS;
  rand cfs_algn_reg_irqen  IRQEN;
  rand cfs_algn_reg_irq    IRQ;
  virtual function void build();
    default_map = create_map(.name("apb_map"), .base_addr('h0), .n_bytes(4),
                             .endian(UVM_LITTLE_ENDIAN), .byte_addressing(1));
    default_map.set_check_on_read(1);          // OFF by default!
    CTRL = cfs_algn_reg_ctrl::type_id::create(.name("CTRL"), .parent(null), .contxt(get_full_name()));
    CTRL.configure(.blk_parent(this));        // regfile_parent = null, hdl_path = ""
    CTRL.build();
    default_map.add_reg(.rg(CTRL), .offset('h0), .rights("RW"));
    // ... STATUS 'hC "RO", IRQEN 'hF0 "RW", IRQ 'hF4 "RW"
  endfunction
endclass
```

| create\_map argument | Aligner value | Why |
| --- | --- | --- |
| base\_addr | 0x0 | Absolute address = base + offset. CTRL sits at 0. |
| n\_bytes | 4 | The APB data bus is 32 bits. |
| endian | little | Byte 0 is the least significant byte. |
| byte\_addressing | 1 | Consecutive addresses are 1 byte apart (0x0, 0x4, 0x8…). With 0, address 1 would mean byte 4. |

The model component

- The block is instantiated inside `cfs_algn_model` (a uvm\_component that will also model the Aligner's behaviour), and the model inside the env.
- `if(reg_block == null)` before creating it: at system level the top env creates the big block and just hands this env a pointer.
- Then `reg_block.build()` and **`lock_model()`**, which freezes the structure and finalizes address lookups. After locking, no registers can be added.
- `hdl_path` is for **back-door** access (peek/poke the RTL signals directly, without using the bus). It's not used here.
- The lecturer flags a typo in his copy of the docs: check-on-read is **off** by default.

**Q: "Front-door vs back-door access?"**

Front door goes through the real bus via the map's sequencer and adapter: realistic, takes simulation time, exercises the bus logic. Back door reads or writes the RTL storage directly through HDL paths (`uvm_hdl_deposit`/`read`): zero time, used for fast initialization, and for checking that the front door wrote the right flops. It needs correct `hdl_path`s, and bypasses side effects such as W1C or clear-on-read logic.

**Q: "What does lock\_model() do and when do you call it?"**

After building the whole hierarchy, on the top-level block only. It prevents further structural changes and builds the internal address-to-register lookup tables used by `get_reg_by_offset()` and the predictor. Forgetting it makes those lookups fail, and some versions error when you start using the model.

**Q: "Why check reg\_block == null before creating it?"**

Vertical reuse. At block level this env owns the register model. At subsystem or SoC level, the top env builds the full block hierarchy (this block becomes a sub-block at some base address) and assigns the pointer before build. The module env must use that shared instance, not create its own private one.

---

R5

## Connecting the model to the APB monitor

Integration with the bus monitor · lecture + practice

```systemverilog
// cfs_apb_pkg: the adapter belongs to the bus agent, not the register model
virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
  cfs_apb_item_mon item_mon;
  if($cast(item_mon, bus_item)) begin
    rw.kind   = item_mon.dir == CFS_APB_WRITE ? UVM_WRITE : UVM_READ;
    rw.addr   = item_mon.addr;
    rw.data   = item_mon.data;
    rw.status = item_mon.response == CFS_APB_OKAY ? UVM_IS_OK : UVM_NOT_OK;
  end
endfunction

// env connect_phase
predictor.map     = model.reg_block.default_map;
predictor.adapter = adapter;
apb_agent.monitor.output_port.connect(predictor.bus_in);
```

uvm\_reg\_predictor #(BUSTYPE)

#### The bridge

BUSTYPE = `cfs_apb_item_mon`. Its `bus_in` is an analysis imp, so the monitor's port connects straight to it.

uvm\_reg\_adapter

#### The translator

A virtual class with two methods: `bus2reg()` (bus item → `uvm_reg_bus_op`) and `reg2bus()` (the reverse, used in R7).

uvm\_reg\_bus\_op

#### A struct, not a class

kind, addr, data, status (plus n\_bits, byte\_en). It's the generic transaction every adapter speaks.

reset

#### Same pattern as the agents

Env and model implement `uvm_ext_reset_handler`. The env's run\_phase loops: wait\_reset\_start → `handle_reset()` → wait\_reset\_end. The model calls `reg_block.reset("HARD")`.

Debug trick from the practice

- Turn on the register layer's own messages without touching code:  
  `+uvm_set_verbosity=*,REG_PREDICT,UVM_HIGH,run`  
  (component `*`, ID `REG_PREDICT`, verbosity, phase). The log then shows "Observed WRITE transaction to register … value 0x202".
- Forced-failure check: the lecturer sets SIZE's reset value to 0, reads CTRL first, and gets the mismatch error "read 0x1, mirrored 0x0". This proves the read checks work, the same practice as in earlier chapters.

**The problem it uncovers:** writing SIZE = 0 (illegal) gets PSLVERR from the RTL, which keeps its old value. The **default** uvm\_reg\_predictor ignores `status` and updates the mirror to 0x200 anyway, so the next read "fails" even though the RTL behaved correctly. R6 fixes this.

**Q: "Explicit vs implicit (auto) vs passive prediction?"**

**Implicit**: `map.set_auto_predict(1)`, so the model updates itself when its own API completes an access. It's simple, but misses traffic from other masters or plain sequences. **Explicit**: a uvm\_reg\_predictor on the monitor updates the mirror from everything observed on the bus. This is the recommended approach, and the one used here. **Passive**: no sequencer connected at all; only the monitor path runs, typical at SoC level where the register bus is driven by a CPU. Don't enable auto-predict together with an explicit predictor, or you predict twice.

**Q: "Why does the adapter belong in the agent's package?"**

The User Guide says the adapter is specific to the bus agent, not to the register model, so it ships as part of a UVM-compliant bus UVC. Any register model of any DUT that sits behind APB reuses the same `cfs_apb_reg_adapter`.

**Q: "What is +uvm\_set\_verbosity's syntax?"**

`+uvm_set_verbosity=<comp>,<id>,<verbosity>,<phase>[,<time>]`. It's useful to enable one message ID (here REG\_PREDICT) at high verbosity without flooding the log with everything else.

---

R6

## A custom predictor that also checks the response

Custom register predictor · lecture + practice

Two jobs. **Filter**: only OK accesses reach the mirror. **Check**: the RTL's OK/ERROR answer can be wrong too, so compare it with an expected response computed from the datasheet rules.

```systemverilog
class cfs_algn_reg_predictor#(type BUSTYPE = uvm_sequence_item)
      extends uvm_reg_predictor#(.BUSTYPE(BUSTYPE));   // stay generic
  cfs_algn_env_config env_config;                     // has_checks, algn_data_width

  virtual function void write(BUSTYPE tr);            // bus_in's imp calls this
    uvm_reg_bus_op operation;
    adapter.bus2reg(tr, operation);
    if(env_config.get_has_checks()) begin
      cfs_algn_reg_access_status_info exp = get_exp_response(operation);
      if(exp.status != operation.status)
        `uvm_error("DUT_ERROR", $sformatf("Mismatch ... expected: %0s, received: %0s on access: %0s - reason: %0s",
                   exp.status.name(), operation.status.name(), tr.convert2string(), exp.info))
    end
    if(operation.status == UVM_IS_OK) super.write(tr);  // filter: errors never reach the mirror
  endfunction
endclass
```

| # | Datasheet error rule | How it's computed |
| --- | --- | --- |
| 1 | Access to an address with no register | `map.get_reg_by_offset(addr, is_read) == null` |
| 2 | Write to a full read-only register | `map.get_reg_map_info(reg).rights == "RO"` |
| 3 | Read from a full write-only register | `rights == "WO"` (no Aligner register is full WO, so this never fires here) |
| 4a | CTRL write with SIZE = 0 | extract SIZE from the bus data |
| 4b | CTRL write where (bytes + OFFSET) % SIZE ≠ 0 | bytes = `algn_data_width / 8` from env\_config |
| 4c | CTRL write where OFFSET + SIZE > bytes | added in R8 after the bug was found |

```systemverilog
// extract a field from a full 32-bit bus value
uvm_reg_data_t mask = (('h1 << fld.get_n_bits()) - 1) << fld.get_lsb_pos();
return (mask & reg_data) >> fld.get_lsb_pos();
// OFFSET: n_bits 2, lsb 8 → (1<<2)-1 = 0b11 → <<8 = 0x300 → (data & 0x300) >> 8
```

The lecture's slide used a 3-bit OFFSET for the example. In the code and the datasheet OFFSET is 2 bits, so the mask is 0x300. Rule 4a is checked before 4b on purpose: SIZE = 0 would otherwise be a modulo by zero.

> Interactive: Try it · be the predictor. Open the HTML page to use it.

The debug trick: return the reason, not just the verdict

The first version returned a bare `uvm_status_e`. When the check fires you'd have to work out by hand which of six rules produced NOT\_OK. The fix: return a tiny class `cfs_algn_reg_access_status_info` with two **const** fields (`status`, `info`), set once in the constructor, plus a `static new_instance()` factory function. The error message then ends with, for example, "reason: Illegal access to CTRL -> OFFSET: 2, SIZE: 2, aligner data width: 32". A small change that saves a lot of debug time.

Also built in this video

- `cfs_algn_env_config` (a uvm\_component) with **local** fields and getters/setters: `has_checks` and `algn_data_width`.
- The setter validates the width: at least 8 and a power of 2 (`$countones(value) == 1`), with `uvm_fatal` otherwise.
- The env passes the `ALGN_DATA_WIDTH` parameter into it and gives the predictor a pointer in connect\_phase.
- Forced-failure check again: change one comparison to `==` and confirm "expected UVM\_NOT\_OK, received UVM\_IS\_OK" appears.

**Q: "The default predictor updated the mirror on a SLVERR write. How do you fix it?"**

Extend `uvm_reg_predictor`, override the public virtual `write()` (the imp method behind `bus_in`), convert the item with `adapter.bus2reg()`, and call `super.write(tr)` only when `status == UVM_IS_OK`. Keep BUSTYPE as a parameter so the predictor stays bus-independent.

**Q: "Why not just trust PSLVERR?"**

The response is DUT output, so it's something to verify, not an input. If the RTL wrongly returns OK for an illegal CTRL write, filtering alone would happily update the mirror and you'd never notice the missing error path. Computing the expected response from the spec turns every APB access into a checked access.

**Q: "How do you find which register an address maps to, and its rights?"**

`map.get_reg_by_offset(offset, read)` returns the uvm\_reg or null. `map.get_reg_map_info(rg)` returns a `uvm_reg_map_info` whose `rights` string is what you passed to `add_reg()`. Field position comes from `get_lsb_pos()` and `get_n_bits()`.

---

R7

## Connecting the model to the APB sequencer

Integration with the bus sequencer · lecture + practice

```systemverilog
// adapter: register op → APB driver item
virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
  cfs_apb_item_drv item = cfs_apb_item_drv::type_id::create("item");
  void'(item.randomize() with {
    item.dir  == (rw.kind == UVM_WRITE) ? CFS_APB_WRITE : CFS_APB_READ;
    item.data == rw.data;
    item.addr == rw.addr;
  });
  return item;
endfunction
// bus2reg() must ALSO accept cfs_apb_item_drv (status = UVM_IS_OK: no response field)

// env connect_phase
model.reg_block.default_map.set_sequencer(apb_agent.sequencer, adapter);
```

| Before (protocol in the test) | After (register API) |
| --- | --- |
| `seq = cfs_apb_sequence_simple::type_id::create(…); seq.randomize() with {addr == 0; dir == WRITE; data == 'h202;}; seq.start(env.apb_agent.sequencer);` | `CTRL.write(status, 'h202);` or, without knowing bit positions: `CTRL.SIZE.set(2); CTRL.OFFSET.set(2); CTRL.update(status);` and `CTRL.read(status, data);` |

Constraint rules (User Guide 5.5.2.1)

- One constraint block per aspect, named for its purpose: `legal_size`, `legal_size_offset`.
- Constrain the field's **`.value`**: `SIZE.value != 0;`
- Extra state variables are allowed if they help the constraints, in UPPERCASE: `local int unsigned ALGN_DATA_WIDTH` with `SET_/GET_ALGN_DATA_WIDTH()`. The model sets it from env\_config in `end_of_elaboration_phase`.
- Wrap register accesses in a sequence extending **`uvm_reg_sequence`**: `cfs_algn_seq_reg_config` holds a `reg_block` pointer and is started on `reg_block.default_map.get_sequencer()`.

```systemverilog
constraint legal_size        { SIZE.value != 0; }
constraint legal_size_offset {
  ((ALGN_DATA_WIDTH / 8) + OFFSET.value) % SIZE.value == 0;
  OFFSET.value + SIZE.value <= (ALGN_DATA_WIDTH / 8);   // added in R8
}
```

**Bug hunt in your own reg2bus().** `==` binds tighter than `?:`, so the first constraint actually parses as `(item.dir == (rw.kind == UVM_WRITE)) ? CFS_APB_WRITE : CFS_APB_READ`. It only works because `CFS_APB_READ = 0` and `CFS_APB_WRITE = 1` happen to equal false and true. Swap the enum encoding and every register write becomes a read. Write `item.dir == ((rw.kind == UVM_WRITE) ? CFS_APB_WRITE : CFS_APB_READ)`, and check the result of `randomize()` instead of using `void'()`.

**Q: "Walk me through what happens when a test calls CTRL.write(status, 'h202)."**

The register builds a `uvm_reg_item` and asks its map. The map turns it into a `uvm_reg_bus_op` (kind=WRITE, addr=0x0 from the map, data), calls `adapter.reg2bus()` to get a `cfs_apb_item_drv`, and runs start\_item/finish\_item on the sequencer from `set_sequencer()`. The driver drives APB. The map then calls `bus2reg()` on the same item to fill in the status. Meanwhile the monitor sees the transfer, and the explicit predictor checks the response and updates the mirror.

**Q: "Why does bus2reg() need to handle the driver item too?"**

After the access, the map calls `adapter.bus2reg()` on the item it sent (or on the response, if `provides_responses = 1`) to get the final status and read data. Without a branch for `cfs_apb_item_drv`, the `$cast` fails and the fatal fires.

**Q: "Can you trust the status returned by CTRL.write() in this testbench?"**

No. The driver item has no response field, so bus2reg reports `UVM_IS_OK` even when PSLVERR was 1. The predictor's check is what catches bad responses. To make the API status real, have the driver copy PSLVERR (and PRDATA) back into the item, or send a response with `provides_responses = 1`, and translate it in bus2reg. This is a good senior-level observation to bring up.

**Q: "write() vs update() vs set()?"**

`set()` only changes desired values; no bus traffic. `update()` writes the register only if desired ≠ mirrored, combining all field values into one access. `write()` always performs the access with the full value you give, so you need the bit layout. Use set+update in tests, so the tests don't depend on bit positions.

---

R8

## The first real bug: SIZE 5 on a 4-byte bus

From the bus-sequencer practice video

With the first constraint in place, `CTRL.randomize()` produced SIZE = 5, OFFSET = 1. It satisfies the datasheet formula, (4 + 1) % 5 = 0, and the RTL accepted it with OKAY. But you can't output 5 bytes on a 4-byte bus.

| Step | What happened |
| --- | --- |
| 1. Smell | A legal-by-formula value that's physically impossible. The read-back returns 0x105, so the RTL really stored it. |
| 2. Provoke | Start the TX responder, then send two 4-byte RX transfers. |
| 3. Catch | The MD interface SVA fires: *size + offset is greater than the data width* (in `cfs_md_if.sv`). The RTL tried to output a size-5 transfer. |
| 4. Confirm | Temporarily comment out the assertion and look at the waves: the TX output has size 5. Restore the assertion afterwards. |
| 5. Root cause | The **spec** is incomplete (it lacks OFFSET + SIZE ≤ bytes), so the **RTL** is too. |
| 6. Fix all four places | Datasheet v1.1 · `cfs_regs.v` returns SLVERR · predictor rule 4c · constraint in `legal_size_offset`. |

Lessons the lecturer draws

- Finding RTL **and** spec bugs while still building the environment is normal. The concept engineer and the designer both missed this case.
- The assertion caught it, and it was written "because it made sense", not because the spec required it. Your own protocol knowledge is a checker too.
- After the fix the predictor fired immediately ("expected OK, got NOT\_OK") until rule 4c was added. A model that disagrees with fixed RTL is a model bug.
- In a real project the designer fixes the RTL; here the lecturer does it so the course can continue.

Interview answer: "tell me about a bug you found"

"While integrating the register model, I randomized the control register under the datasheet's alignment formula. One seed produced SIZE 5, OFFSET 1 on a 32-bit bus. The formula allowed it and the RTL accepted it. Sending traffic tripped an interface assertion I'd added on the output: size plus offset exceeded the bus width. The spec was missing a constraint, OFFSET + SIZE ≤ bus bytes, so the RTL didn't reject the write. We updated the spec, the RTL now returns SLVERR, and I added the rule to the predictor and to the register constraints. Constrained-random found a case nobody had written down."

**Q: "The spec and the RTL agree, but you think they're both wrong. What do you do?"**

Build a minimal reproducing test and waveform. Explain the physical impossibility (5 bytes can't fit a 4-byte bus) and its consequence (an illegal output transfer). Then raise it with the spec owner and the designer together, because only the spec owner can decide the intended behaviour. Don't silently "fix" your model to match the RTL, and don't wait: track it as a spec bug with an owner.

**Q: "Why did constrained-random find this when directed tests didn't?"**

Directed tests encode what people already thought of, which here were exactly the spec's rules. Random generation within the stated rules explored combinations nobody enumerated, and an independent checker (the interface SVA) judged the result on physical grounds. Good random tests need both broad stimulus and checks that don't share the spec's blind spot.

---

R9

## Register field callback: CLR clears CNT\_DROP

Register field callback · lecture + practice

A **callback** is "a function stored as data and designed to be called by another function". In SystemVerilog that means a method inside a class, plus a stored handle to an object of that class. The function that calls it is `uvm_reg_field::predict()`, which calls `post_predict()` on every callback registered for the field.

```systemverilog
class cfs_algn_clr_cnt_drop extends uvm_reg_cbs;   // uvm_reg_cbs → uvm_callback → uvm_object
  uvm_reg_field cnt_drop;                           // pointer to STATUS.CNT_DROP
  virtual function void post_predict(input uvm_reg_field fld, input uvm_reg_data_t previous,
                                     inout uvm_reg_data_t value,   // INOUT: you may change it
                                     input uvm_predict_e kind, input uvm_path_e path, input uvm_reg_map map);
    if(kind == UVM_PREDICT_WRITE && value == 1) begin
      void'(cnt_drop.predict(0));   // model the hardware side effect
      value = 0;                    // CLR is a pulse: don't leave 1 in the model
    end
  endfunction
endclass

// model connect_phase
cbs.cnt_drop = reg_block.STATUS.CNT_DROP;
uvm_callbacks#(uvm_reg_field, cfs_algn_clr_cnt_drop)::add(reg_block.CTRL.CLR, cbs);
```

| post\_predict argument | Meaning |
| --- | --- |
| `fld` | the field this callback is attached to (CTRL.CLR) |
| `previous` | mirror value before this prediction |
| `value` (inout) | newly predicted value; overwrite it to change what the mirror stores |
| `kind` | `UVM_PREDICT_WRITE`, `UVM_PREDICT_READ` (or DIRECT for a plain predict call) |
| `path`, `map` | front door or back door, and through which map |

How the practice test proves it

- Send two illegal RX transfers (size 3). The RTL drops both, so CNT\_DROP = 2 in the RTL. Reading STATUS gives a mismatch, because the model doesn't count drops yet.
- As a temporary hack, the test calls `CNT_DROP.predict(2)`. The lecturer labels it **"Don't do this in a real project"**: prediction is the model's job (your final `cfs_algn_model.sv` does it).
- Write CLR = 1 and read again: the RTL returns 0 but the mirror still says 2, which is a mismatch. Add the callback: the mismatch is gone, and the log shows "Clearing …CNT\_DROP" at UVM\_HIGH.
- `uvm_callbacks#(T, CB)::add(obj, cb, ordering)`: T = object type (uvm\_reg\_field), CB = callback type. `ordering` decides the order when several callbacks are attached.

**Q: "How do you model a register side effect, e.g. writing one field clears another?"**

A `uvm_reg_cbs` subclass whose `post_predict()` detects the triggering write and calls `predict()` on the affected field, attached with `uvm_callbacks#(uvm_reg_field, MyCb)::add(field, cb)`. It runs on every predicted write, whether from the explicit predictor or auto-prediction, so the side effect follows any source of traffic. Alternatives are a custom field class overriding `do_predict`, or handling it in the reference model; callbacks keep it local to the register layer.

**Q: "Why set value = 0 inside post\_predict?"**

CLR is a self-clearing pulse in the RTL; it never holds 1. If the mirror stored 1, the model would disagree with the hardware, and `update()` logic based on desired vs mirrored would behave oddly the next time someone sets CLR. Because `value` is inout, the callback can correct what gets stored.

**Q: "Name other UVM callback uses."**

Driver or monitor hooks such as error injection (`` `uvm_register_cb `` / `` `uvm_do_callbacks ``), register pre/post read/write hooks (`pre_write`, `post_read` in `uvm_reg_cbs`), and report catchers (`uvm_report_catcher`, a callback that demotes or rewrites messages). The trade-off versus factory overrides: callbacks add behaviour to existing instances without replacing the class.

---

R10

## What the register layer bought us

Conclusions video

modeled

#### 4 registers, 16 fields

`uvm_reg_field` inside `uvm_reg` inside `cfs_algn_reg_block` (the register model) inside the model component.

checked

#### Every APB access

Read data against the mirror, plus the response (OKAY/SLVERR) against six datasheet rules in the custom predictor.

abstracted

#### Protocol-free tests

`read()`, `write()` and `update()` through the sequencer path. Swap APB for another bus and the tests don't change.

side effects

#### Callbacks

CLR → CNT\_DROP cleared in the model, exactly as in the RTL.

Housekeeping for the next projects

- The register classes are merged into `cfs_algn_reg_pkg.sv`, and the adapter moves to the end of `cfs_apb_pkg.sv`. This is only to keep the EDA Playground project tidy. In a real project keep one class per file.
- Next section: model the Aligner's behaviour and build the remaining env components (model, scoreboard, coverage).

60-second RAL drill: say each out loud

- Four field values, and which API touches each.
- Explicit vs auto vs passive prediction, and why not both at once.
- What bus2reg and reg2bus do, and why the adapter lives in the agent's package.
- Why the custom predictor filters *and* checks.
- `update()` only writes when desired ≠ mirrored.
- Front door vs back door; volatile; check\_on\_read is off by default; lock\_model.
- The SIZE-5 bug story.

Interview line

"I built the register model for a 4-register block: field classes, the block and APB map, an adapter in the APB agent, and a custom explicit predictor. The predictor filters errored accesses out of the mirror and checks every response against the spec's error rules, with the reason in the message. Tests use set/update/read, so they're bus-independent. I modeled the clear-on-write side effect with a field callback. Randomizing the control register exposed a spec and RTL hole that we fixed together."

---

