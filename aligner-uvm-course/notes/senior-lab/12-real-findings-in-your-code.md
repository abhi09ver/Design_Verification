# Real findings in your code

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Reference

## Real findings in your code

Everything below comes from reading your datasheet, RTL and testbench, not from a generic checklist. Each is a ready-made interview example: what you saw, why it matters, how you'd fix it.

| Severity | Where | Finding | Module |
| --- | --- | --- | --- |
| DUT bug | cfs\_regs.v:164 | irq output omits MAX\_DROP (4 of 5 sources ORed). | 10 |
| DUT risk | cfs\_synch.v, cfs\_rx\_ctrl.v | Multi-bit CNT\_DROP through a 1-flop synchronizer, async clear across domains; TB ties all clocks together. | 10 |
| Spec / RTL | cfs\_rx\_ctrl.v vs cfs\_regs.v | `offset+size ≤ W/8` enforced on CTRL writes, not on RX; absent from datasheet. | 0 |
| TB hole | cfs\_apb\_if.sv | No assertion for the datasheet's ≤5 APB wait states. | 2 |
| TB hole | cfs\_algn\_scoreboard.sv | No end-of-test check; unexpected TX item crashes on null. | 7 |
| TB bug | cfs\_md\_pkg.sv (coverage) | Each MD transfer sampled twice; start sample inflates OKAY/length=1 bins. | 8 |
| TB bug | cfs\_algn\_coverage.sv | `cover_split.all`: ≥284 of 336 bins unreachable (TODO left in code). | 8 |
| TB risk | cfs\_algn\_reg\_pkg.sv, coverage | Field widths and bins hard-coded for 32-bit; wrong at 64. | 5 |
| TB risk | cfs\_algn\_model.sv | FIFO depth hard-coded 8; probe-sync failure is only a warning. | 6 |
| TB risk | tests, vseqs, adapter | `void'(randomize())` hides failures (rx\_err unsatisfiable at width 8). | 9 |
| Escape | vseq\_reg\_access\_unmapped | `paddr[1:0]` ignore rule never exercised. | 9 |
| Spec gap | datasheet §4.4, §3.4 | irq pulse vs level; CLR vs err same-cycle priority; reconfig under traffic; md\_tx\_err effect. | 0 |
