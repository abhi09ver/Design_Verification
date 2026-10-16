# Read the spec like a verifier

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 0 · before any code

## Read the spec like a verifier

Senior interviews at NVIDIA and Google often open with "here's a block, how would you verify it?" The answer starts with the spec, not with UVM. This module turns the 14-page aligner datasheet into a verification plan and shows where the spec, the RTL and the testbench disagree.

spec → features → checks → coveragelegality rulesticky IRQ semanticsspec review findings

### 0.1The DUT in one picture, annotated for verification

Datasheet Figure 1, redrawn. Each amber note is something you must check: a *rule* (assertion or predictor), a *transform* (reference model + scoreboard), or *state* (register mirror + coverage).

*[Diagram: Aligner block diagram with verification callouts. Open the HTML page to see it.]*

### 0.2The verification plan: feature → how it's checked → what proves it's covered

This is the table interviewers want to hear you build out loud. Each row maps to a component you'll study in later modules. SB scoreboard/model, SVA assertion in an interface, RAL register predictor/mirror.

| Feature (datasheet §) | Check | Coverage that proves it |
| --- | --- | --- |
| Data alignment (4.1) | SB Model splits/merges every legal RX item using the mirrored CTRL.SIZE/OFFSET; scoreboard compares each TX item in order. | CTRL.SIZE × CTRL.OFFSET × RX size × RX offset; cross with "split into N" (the `split_info` coverage). |
| RX legality → md\_rx\_err (4.2.1) | SB Model predicts OKAY/ERR per item; scoreboard compares with the monitored response. | Every (offset, size) cell, legal and illegal; err at back-to-back items. |
| CNT\_DROP saturation + CTRL.CLR | RAL Mirror updated by model on each err; STATUS read compares. Saturates at 255, no wrap. | Counter at 0, mid, 254→255, 255+more errs; CLR while at max; CLR in the same cycle as an err. |
| Back-pressure (md\_rx\_ready) | SB Model's RX FIFO level vs `algn_if` push/pop probes; ready low only when full. | RX FIFO full; TX side stalled (slave never ready) for long stretches. |
| MD protocol (valid/ready) | SVA valid stays high until ready; data/offset/size stable; err only with valid&ready; size≠0. | Assertion cover: wait states 0, 1, many; err on RX and TX. |
| APB error responses (3, 4.3) | RAL Custom predictor computes expected pslverr; errored writes must not update the mirror. | Unmapped addr, write STATUS, illegal CTRL write, read WO field. |
| APB wait states ≤ 5 | SVA In the APB interface: psel&penable → pready within 6 clocks. | Cover 0…5 wait states actually observed. |
| paddr[1:0] ignored | RAL Access 0x01/0x02/0x03 must hit CTRL. | Low address bits ≠ 0 on mapped registers. |
| IRQ sticky + W1C (3.4) | SB Model sets IRQ bit on the *transition* event; W1C clears; does not re-set while condition persists. | Clear while still full/empty/max; clear then re-trigger; W1C with 0. |
| irq = OR(IRQ & IRQEN) (4.4) | SB Model publishes expected irq; scoreboard compares with `algn_if.irq`. | Each source × enable on/off; multiple sources together. |
| Reset | SB Every component flushes state in `handle_reset()`; registers back to reset values. | Reset with FIFOs non-empty, mid-APB, mid-MD transfer. |

### 0.3Legality explorer: the one equation that drives half the testbench

The datasheet says a transfer is legal when `(ALGN_DATA_WIDTH/8 + offset) % size == 0`. Pick a bus width and click any cell. Watch the amber cells: they pass the datasheet equation but would put bytes past the end of the bus.

ALGN\_DATA\_WIDTH

legal
illegal (err)
spec gap

Real finding in your code · spec vs RTL vs TB

Three places implement the rule, and they don't agree:

**cfs\_regs.v** (CTRL write) checks size≠0, the modulo rule *and* `offset + size > W/8`. **cfs\_rx\_ctrl.v** (MD RX) checks only size≠0 and the modulo rule. **cfs\_algn\_model.sv** checks all three for RX. So for size 3 at offset 2 on a 32-bit bus, the RTL would accept the RX item while the model expects ERR.

It never shows up as a failure because the TB can't generate it: `cfs_md_sequence_simple_master::item_hard` constrains `size + offset <= W/8`, the master driver `uvm_fatal`s on it, and the coverage `ignore_bins` it. That's a classic hidden hole: **constraints written from the TB writer's reading of the spec, not from the spec.** In an interview, this is the kind of observation that marks you as senior.

### 0.4Spec review: questions you'd raise with the designer before writing a line

Ambiguity · IRQ output

§4.4 says the interrupt "is generated as a pulse (1 for one clock)", but Figure 11 ANDs the *sticky* IRQ bits with IRQEN. Is `irq` a level (stays high until W1C) or a one-cycle pulse? Your model and scoreboard need one answer.

Unspecified priority

CTRL.CLR written in the same cycle an illegal RX transfer arrives: does CNT\_DROP end at 0 or 1? Same question for W1C on IRQ in the same cycle as a new event.

Missing rule

The overflow condition `offset + size ≤ W/8` is enforced by the RTL CTRL write but never stated in the datasheet. Ask for a spec update rather than inferring it.

Edge vs level

"RX FIFO **became** full" is an edge: after W1C while still full, the bit must stay 0. A model that sets bits on level fails here. Easy to miss, often asked.

Doc defects

Figure 10 text says `CTRL.SIZE = 11` (caption says 1). `pslverr` width is blank. Status/IRQ tables are titled "fields of the Control register". Small, but list them; reviewers notice.

Reset during traffic

Nothing says what happens to in-flight MD transfers or a half-done APB access on reset. Your TB needs a defined behaviour to check against.

### 0.5Interview drill

**Q: Q1 "Here's the aligner datasheet. You have 10 minutes. How would you verify it?"**

Strong answer shape  
Start from the plan, not the tools. (1) Interfaces: APB slave, MD RX (DUT is the slave), MD TX (DUT is the master), irq. That gives one APB agent, one MD master agent, one MD reactive slave agent. (2) Behaviour splits into a transform (alignment), rules (legality, APB errors, protocol) and state (FIFO levels, counters, IRQs). (3) Transforms go to a reference model plus a scoreboard. Rules go to SVA and the register predictor. State goes to the RAL mirror. (4) Coverage on the config × traffic cross. (5) Tests: register access, random legal, all-illegal, back-pressure, IRQ, reset-mid-traffic.

Cross-questions they'll push

- Why is the TX agent reactive instead of just driving `ready=1`? (You need back-pressure to fill the FIFOs and to hit full/empty IRQs.)
- Would you use formal for any of this? (Yes: the legality rule and the APB error conditions are small, closed-form properties. Formal proves all (offset, size) combos in minutes.)
- What's the riskiest feature? (IRQ edge semantics and CNT\_DROP/CLR races. These are timing interactions that a random test rarely hits by chance.)

**Q: Q2 "Your constraints only generate legal-by-construction traffic. Is that a problem?"**

Yes, if the constraint is narrower than the spec. Your constraints define what the DUT is *never* asked to handle. Here, `item_hard` removes the overflow cells, so the RTL's missing overflow check in `cfs_rx_ctrl.v` can't be found. A senior engineer keeps constraints that model *physical* limits (here the bus cannot carry byte 4) apart from constraints that model *legality*. Legality belongs in the checker, and illegal stimulus gets its own test, as you did with `rx_err`.

Cross-question

- Then how would you drive size 3 at offset 2 if the driver fatals? (Override the driver check behind a config knob, or decide with the designer that it's a protocol violation and cover it with an assertion on the DUT input.)
