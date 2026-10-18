# Session 5 — Functional Coverage Model for APB

Source: `Session5_pdf_SV_Coverage_Measure_what_matters.pdf`, page 35.
Code: [`code/session5_apb_coverage/session5_apb_coverage.sv`](code/session5_apb_coverage/session5_apb_coverage.sv) · Output: [`logs/s5_apb_coverage.log`](logs/s5_apb_coverage.log)

## Requirements
1. A covergroup capturing:
   - the address in 3 regions (low `0x0000–0x0FFF`, mid `0x1000–0x1FFF`, high `0x2000–0xFFFF`),
   - `pwrite` (read or write),
   - the cross of region and `pwrite`.
2. Sample **only** when `penable == 1 && pready == 1 && psel == 1`.
3. A class-based model with a `sample()` method that takes all signals as inputs.
4. Explicit bins for the three regions.

## Solution

```systemverilog
class apb_coverage;
  covergroup apb_cg with function sample(bit [31:0] paddr, bit [31:0] pwdata,
                                         bit [31:0] prdata, bit pwrite);
    option.per_instance = 1;
    cp_addr : coverpoint paddr {
      bins low  = {[32'h0000_0000 : 32'h0000_0FFF]};
      bins mid  = {[32'h0000_1000 : 32'h0000_1FFF]};
      bins high = {[32'h0000_2000 : 32'h0000_FFFF]};
      illegal_bins out_of_map = {[32'h0001_0000 : 32'hFFFF_FFFF]};
    }
    cp_rw      : coverpoint pwrite { bins read = {0}; bins write = {1}; }
    cx_addr_rw : cross cp_addr, cp_rw;          // 3 x 2 = 6 bins
  endgroup

  function new(); apb_cg = new(); endfunction   // embedded cg: construct in new()

  function void sample(bit [31:0] paddr, bit [31:0] pwdata, bit [31:0] prdata,
                       bit pwrite, bit penable, bit pready, bit psel);
    if (psel && penable && pready)               // only completed transfers
      apb_cg.sample(paddr, pwdata, prdata, pwrite);
  endfunction
endclass
```

## Demo result
- I hit 5 of the 6 cross bins on purpose, leaving out "high region READ", and sent 3 cycles that must be gated off: the setup phase, a wait state, and `psel = 0`.
- Coverage was **92.3%** with 3 calls gated off. Adding the high-region read brought it to **100%**.
- Hit counts per bin: low, mid and high = 2 each; read and write = 3 each; every cross bin = 1; `out_of_map` = 0.

## Interview talking points
- **Why `with function sample(...)`?**
  - The covergroup doesn't depend on any interface or hierarchy.
  - The same model can be fed by a monitor, a scoreboard or a C model.
- **Gating options:**
  - Gate in the wrapper (as above). One condition covers every coverpoint.
  - Or use `coverpoint paddr iff (psel && penable && pready)` per coverpoint.
  - Never sample on every clock edge: setup phases and wait states would inflate the counts and could hit bins that real transfers never reach.
- **`illegal_bins` vs `ignore_bins` vs `default`:**
  - `illegal_bins`: a hit is a run-time error. Use it for impossible values.
  - `ignore_bins`: excluded from coverage silently.
  - `default`: catches all other values, but is not counted toward coverage.
- **Embedded covergroup:** it must be constructed in the class's `new()`. It can't be a separately declared handle that gets constructed later.
- **`per_instance = 1`:** reports each instance separately (e.g. two APB ports) instead of merging them.
- **Extensions they may ask for:**
  - transitions: `bins wr_then_rd = (1 => 0);`
  - data corner cases: zero, all ones, walking ones
  - PSLVERR coverage
  - wait-state counts: `bins zero_wait = {0}; bins long = {[3:$]};`
  - back-to-back transfers
- **"100% coverage but bugs remain" — why?** Coverage measures what the stimulus did, not what was **checked**. Every covered scenario needs a checker, plus code coverage, plus assertions.
- **Cross explosion:** use `binsof(...) intersect {...}` with `ignore_bins` to remove meaningless combinations, and cover only the crosses the spec cares about.
- **Where it lives in UVM:** a `uvm_subscriber #(apb_txn)` connected to the monitor's analysis port, whose `write()` calls `sample()`.

## Simulator note
This open-source simulator doesn't yet support per-coverpoint `get_coverage()`, so the file uses `` `ifdef VERILATOR `` to print only the total. On VCS, Xcelium or Questa, the full report prints coverpoint, cross and total percentages.
