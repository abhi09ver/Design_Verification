# Last 30 minutes before the interview

One page. If you only read one file in this repo before walking in, read this one.

## 1. Your project in 45 seconds

> "I verified a parameterized data aligner from spec to regression in UVM 1.2. The environment has APB and MD agents (MD is reactive: master and slave), built on a shared base-class library. There's a register model with a custom predictor that also checks bus responses, and a reference model shaped like the spec's block diagram, using TLM FIFOs and register prediction. The scoreboard has watchdogs for data, responses and a bare IRQ wire. There's split coverage and virtual sequences. I solved three model-vs-RTL synchronization problems. Constrained-random and targeted constraint-only tests found three RTL bugs, one of which was also a spec hole. For debug I used ID-based message control, transaction recording, and expected items that carry their sources."

## 2. The DUT in 6 lines

- APB slave (registers) · MD RX in (DUT is the slave) · MD TX out (DUT is the master) · `irq` pin.
- Registers: CTRL (SIZE[2:0] RW reset 1, OFFSET[9:8] RW, CLR[16] WO) @0x0 · STATUS (CNT_DROP[7:0], RX_LVL, TX_LVL, RO) @0xC · IRQEN @0xF0 RW · IRQ @0xF4 W1C.
- An MD transfer is legal if `size != 0`, `(bytes + offset) % size == 0` and `offset + size <= bytes` (bytes = width / 8).
- Illegal transfer → ERR response, CNT_DROP++ (saturates at 255 → MAX_DROP flag).
- Legal transfer → RX FIFO (8) → intermediate buffer → align/split to CTRL.SIZE at CTRL.OFFSET → TX FIFO (8) → TX.
- 5 sticky IRQ flags (RX/TX FIFO empty/full, MAX_DROP), each AND its enable, all ORed onto `irq` as a pulse on the edge.

## 3. Facts interviewers like to probe

| Topic | One-liner |
|---|---|
| config_db precedence | During build, a set() from higher in the hierarchy wins. After build, the most recent set() wins. The type, path and name must all match. |
| Factory | `type_id::create`, never `new`. Overrides must be registered before the create. A set_inst_override in the constructor works. |
| Seq ↔ driver | start_item (arbitration) → randomize → finish_item (blocks) ⇄ get_next_item → drive → item_done |
| p_sequencer | `` `uvm_declare_p_sequencer(T) `` gives a typed `$cast` of m_sequencer |
| Analysis | `write()` is a function, so you can't block. Start time-consuming work with fork/join_none. `` `uvm_analysis_imp_decl(_x) `` gives you several write_x() methods. |
| Reset handling | Interface class `handle_reset()`. Kill processes through stored `process` handles, flush FIFOs, `reg_block.reset("HARD")` |
| RAL values | mirrored (what the DUT holds) · desired (set/randomize → update) · value (public, constrained) · reset[string] |
| update() | Writes only if desired != mirrored, so after a randomize that changes nothing it does nothing |
| W1C trap | `uvm_reg_field::configure()` forces is_rand=0 for W1C/RO-type fields. Call `FIELD.value.rand_mode(1)` afterwards. |
| Prediction | Explicit predictor on the monitor (used here) vs auto-predict vs passive. Never enable both explicit and auto. |
| Custom predictor | Override `write()`: bus2reg, check status against spec rules (print the reason), `super.write()` only if OK |
| Adapter | bus2reg / reg2bus. It ships in the bus agent's package. bus2reg must handle the driver item too. |
| check_on_read | Off by default: `default_map.set_check_on_read(1)` |
| uvm_tlm_fifo | Blocking put/get model back-pressure. `size()` is capacity, `used()` is the level. |
| Scoreboard | Per output: ordered expected queue + per-entry watchdog + depth limit (RX/TX ≤ 1, IRQ ≤ 5) |
| Same-time race | Use deferred (2 NBA) cancellable setters plus a killer (1 NBA), or a single sampler at negedge |
| Probing RTL | Use it as a timing hint only, with a timeout fallback. Never use it as the expected value. |
| Verbosity | NONE 0 · LOW 100 · MEDIUM 200 (default) · HIGH 300 · FULL 400 · DEBUG 500. Never use NONE for info messages. |
| set_verbosity | `+uvm_set_verbosity=comp*,ID|_ALL_,VERB,time,0`. A specific ID beats _ALL_. Put the lines in a .f file. |
| Recording | do_record + `begin_tr`/`end_tr` in the monitor + `+uvm_set_config_int=…,recording_detail,400` |
| Tests | One random parent test. Children only add constraints or factory overrides (e.g. rx_err). |

## 4. Bugs you can claim (with the story)

1. **SIZE+OFFSET > bus width accepted.** RAL randomization produced SIZE 5, OFFSET 1 on a 32-bit bus. That's legal by the spec's formula, but an MD interface SVA fired. It was a spec gap plus an RTL bug, fixed in four places.
2. **IRQEN reset value was 0x1F.** The random register test caught it only on seeds where the first IRQEN access was a read.
3. **MAX_DROP missing from the `irq` OR.** The illegal-RX test plus the IRQ scoreboard caught it, but only when IRQEN.MAX_DROP is enabled (about 50% of seeds).
4. **Three testbench synchronization issues on IRQs:** same-cycle push/pop, the model running faster than the RTL FIFOs, and overlapping sources ORed onto one pin.

## 5. Questions to ask them back

- "What's your split between simulation, formal and emulation for blocks like this?"
- "How do you decide sign-off: coverage thresholds, mutation qualification, bug-rate trend?"
- "Do you generate RAL from IP-XACT or SystemRDL, or write it by hand?"
