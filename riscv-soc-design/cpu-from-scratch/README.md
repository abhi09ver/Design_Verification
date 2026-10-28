# cpu-from-scratch

A RISC-V RV32I core built step by step the way *RISC-V System-on-Chip Design*
(Harris, Stine, Thompson, Harris) builds CORE-V Wally, plus a small but real CPU
verification flow around it. Every module is named and partitioned like Wally
(`github.com/openhwgroup/cvw`), so after these labs the real source reads as a
bigger version of code you wrote.

| Lab | What you build | Book | Wally counterpart |
| --- | --- | --- | --- |
| 1 | Single-cycle RV32I core (37 instructions) | 2.7.1, 7.1 | `src/ieu`, `src/ifu`, `src/lsu` |
| 2 | Reference model, random generator, lock-step compare, functional coverage | 5.1, 5.6, 5.9 | Sail/ImperasDV, riscv-dv, riscvISACOV |
| 3 | 5-stage pipeline: forwarding, load-use stall, branch flush; bug hunt | 2.7.2, 7.2 | `src/hazard/hazard.sv`, `src/ieu/controller.sv` |
| 4 | Logic synthesis onto SKY130 with Yosys/ABC, hand-written STA and power estimate | 6 | `synthDC/` (Design Compiler flow) |
| 5 | Machine-mode privileged unit: CSRs, traps, interrupts | 8 | `src/privileged` |
| 6 | AHB bus interface + uncore (RAM, APB bridge, GPIO, CLINT, RXFIFO) | 9 | `src/ebu`, `src/uncore` |
| 7 | Write-back data cache with bursts and flush | 10 | `src/cache` |
| 8 | Data MMU: Sv32 TLB, page-table walker, PMP, U-mode | 11 | `src/mmu` |
| 9 | LSU integration: synchronous-read (SRAM-like) D-cache read in Execute, VIPT, store-to-load re-read | 12 | `src/lsu`, `src/cache` |
| 10 | Branch predictor: BTB with instruction class, bimodal / gshare (+ GHR forwarding), RAS | 13 | `src/ifu/bpred` |
| 11 | Peripherals: GPIO, CLINT, PLIC, 16550 UART, SPI on APB, with a block-level bench and a 14-bug hunt | 20 | `src/uncore` |

## Quick start

```
sudo apt install verilator gcc-riscv64-unknown-elf     # or any RV32I-capable gcc
make book-single     # Lab 1: book's riscvtest on the single-cycle core
make single          # Lab 2: directed + 50 random tests, lock-step vs ISS, coverage
make pipe            # Lab 3: same on the pipeline
make bugs            # inject 5 pipeline bugs, see which tests catch them
python3 dv/pipeview.py tests/directed/hazard_demo.S     # watch the pipeline cycle by cycle
make wave && gtkwave wave.vcd
```

## Lab 4: synthesis (book Ch 6)

```
pip install yowasp-yosys liberty-parser
synth/run_all.sh          # fetches SKY130 HD typical .lib, sweeps 9 targets x 2 adder styles
python3 synth/sta.py synth/net_ks_4000.json synth/hd_tt.lib --period 4      # timing report
python3 synth/minperiod.py synth/net_ks_4000.json synth/hd_tt.lib           # bisect min period
python3 synth/power.py synth/net_ks_4000.json synth/hd_tt.lib --freq-mhz 200
```

* `sta.py` (about 300 lines): NLDM table lookup, rise/fall + unateness, clock polarity traced through
  the clock buffers (the register file is negedge-written, so its paths get half a cycle), WNS/TNS,
  worst path per launch->capture edge class.
* Results (SKY130 HD, TT 1.8 V 25 C, ideal wires): about 91.6k um^2, 12k cells, 1,783 flops; register
  file 60% of area. Min period 5.2 ns, set by the half-cycle register-file write decode; the full-cycle
  forward -> branch -> PC/flush path alone needs 4.0 ns (Kogge-Stone) / 4.6 ns (Yosys default).
  122 pJ/cycle, 82% of it clocking. (These numbers predate `priv.sv`; re-run `synth/run_all.sh` for the
  current core.)

## Lab 5: privileged unit (book Ch 8)

* `rtl/pipe/priv.sv`: M-mode CSRs (mstatus, misa, mie/mip, mtvec direct+vectored, mscratch, mepc, mcause,
  mtval, mcycle/minstret + h, cycle/time/instret views), exceptions (illegal incl. bad CSR / write to
  read-only, ecall, ebreak, fetch/load/store misaligned) and interrupts (timer, software, external).
  Traps are taken in M; the hazard unit flushes D/E/M/W on a trap, D/E/M + refetch on mret and CSR writes,
  and stalls a CSR read-use.
* `tb/tb.sv` has a small CLINT: mtimecmp at 0x8000F010/14, msip at 0x8000F020, external line at 0x8000F024.
* `dv/iss.py` follows the DUT for interrupt timing and nondeterministic CSRs (mcycle, time, mip), and
  flags any interrupt taken while disabled (RVVI style).
* Tests: `tests/priv/trap_basic.S` (8 traps, PASS, 224 trace lines match) and `tests/priv/interrupts.S`
  (vectored, 599 instructions / 1,033 cycles, PASS).
* `python3 dv/privhunt.py`: injected bugs vs self-check and lock-step. mepc + 4 passes the interrupt
  self-check but fails lock-step; CSR_NOFLUSH is invisible here because every CSR effect is consumed in M.

## Lab 6: bus interface (book Ch 9)

```
make bus        # pipeline regression incl. tests/bus, then the block-level AHB bench (5 seeds)
make bushunt    # 6 injected bus bugs vs self-check, lock-step and block-level random
make busperf    # DTIM vs bus RAM, 0..4 wait states
```

* The LSU gets an AHB manager port like Wally's `ahbinterface` + `busfsm` (Adr, Data, Mem3). Loads and stores
  to 0x1xxx_xxxx / 0x9xxx_xxxx go to `rtl/uncore/uncore.sv`; everything else stays in the in-core DTIM.
  A bus access stalls the whole pipeline (StallW); interrupts wait while a transfer is committed.
* Uncore: decoder + HSELD + mux, default subordinate, single-port SRAM (write->read wait state, `-GRAM_WAIT=n`),
  AHB-to-APB bridge, GPIO (Example 9.1), CLINT, and an RXFIFO whose reads pop (a UART receive register).
* `dv/iss.py` models the devices, so lock-step covers bus loads. `tb/tb_ahb.sv` is a block-level
  constrained-random pipelined AHB manager + scoreboard + liveness check, with no CPU.
* Results: 60/60 with and without RAM wait states. A bus access costs exactly 2 stall cycles + waits
  (CPI 1.44 on DTIM vs 1.87 on bus RAM for the same loop). Bug hunt: the CPU-level tests miss
  BUG_HSEL_NOT_DELAYED and BUG_RAM_NO_RAW_WAIT (the LSU never issues back-to-back transfers); the block-level
  bench catches all four uncore bugs; BUG_NO_COMMIT and BUG_BUS_NO_CANCEL need the CPU + lock-step;
  BUG_DEFAULT_HANG hid until tests/bus/bus_unmapped.S touched unmapped space.

## Lab 7: data cache (book Ch 10)

```
make cache       # pipeline regression (incl. tests/cache + 5 random cache seeds) at 4 cache configurations
make cachehunt   # 6 injected cache bugs vs self-check, lock-step, RAM image, cache model
make cacheperf   # miss rate vs associativity at 256 B, plus the stuck-LRU bug
```

* `rtl/pipe/dcache.sv`: write-back, write-allocate, WAYS x SETS x LINEWORDS (default 2 x 8 x 16 B), tree pLRU,
  FSM Access/Writeback/Fetch/WriteLine/Flush/FlushWriteback, AHB INCR4 bursts. 0x9000_xxxx is cacheable,
  0x9100_xxxx is the same RAM uncached; `fence.i` flushes. Same-cycle hits (no Address/Data stages).
* Checks: lock-step (values), `+RAMDUMP` end-of-test RAM image vs the ISS (writebacks), `dv/cachemodel.py`
  transaction-level model over `+CACHELOG` (hit/miss, victim way, writeback/fill addresses, flush order).
* Results: clean miss 7 cycles, dirty miss 12. Bug hunt: NO_MERGE escapes the model; LRU_STUCK escapes
  everything but the model (and is faster on 2 of 3 kernels); FLUSH_SKIP_LAST is hit by only 3/10 random seeds
  but every time by the directed test. A real bug of mine (last burst beat dropped) was caught by lock-step only.

## Lab 8: MMU (book Ch 11)

```
make mmu        # regression incl. tests/mmu + 5 random MMU seeds (lock-step + TLB model), at TLB 4, 1 and 8 entries
make mmuhunt    # 7 injected MMU bugs vs self-check, lock-step and the TLB model
make mmuperf    # walk cost by page-table location; TLB reach with 4 KiB pages vs one megapage
```

* `rtl/pipe/mmu.sv`: Sv32 DTLB (fully associative, `TLB_ENTRIES`, 4 KiB + 4 MiB, Wally's recently-used-bit
  replacement), hardware page-table walker that reads PTEs *through the LSU* (DTIM, D-cache or AHB), Svade page faults
  (V, W-without-R, U, R/W, A, D, misaligned megapage, malformed pointers), and a 4-entry PMP (OFF/TOR/NA4/NAPOT, L)
  that also checks the walker's reads. The LSU sees `GatedStallW = StallW & ~SelHPTW`; a walk is `Committed`.
* `priv.sv` gains U-mode, mstatus.MPP/MPRV, satp, pmpcfg0/pmpaddr0-3, sfence.vma, ecall from U and causes 5/7/13/15.
  Teaching cut: there is no S-mode, so satp translates U-mode (and MPRV) accesses; instruction fetch is not translated.
* `dv/iss.py` walks the page table on every access (no TLB): with "sfence.vma after any PTE change" that *is* the
  architecture. `dv/tlbmodel.py` replays `+TLBLOG` and predicts every hit/miss and replaced entry.
  `dv/genmmu.py` builds random page tables (three level-0 tables read from DTIM, D-cache and bus; megapages; every kind
  of bad PTE), alternates U-mode and MPRV segments, remaps PTEs and reprograms PMP between them.
* Results: 72/72 (plus TLB=1 and TLB=8 with RAM_WAIT=2). A TLB miss costs 3 cycles with PTEs in the DTIM or D-cache
  and 5 when the level-0 PTE comes over the bus. 8 pages round-robin on 4 entries: 5.5 cycles per load vs 2.5 through
  one megapage. Bug hunt: every functional bug is caught by the directed test; BUG_TLB_VICTIM0 is invisible to
  self-check and lock-step and caught only by the TLB model; BUG_WALK_NO_PMP is hit by 6/10 random seeds.

## Lab 9: LSU integration (book Ch 12)

```
make lsu        # regression incl. tests/lsu + genlsu seeds, synchronous read; also Lab 7 combinational read and 4x4 + RAM_WAIT=2
make lsuhunt    # 4 read-path bugs vs the directed test and two random generators (gencache vs genlsu)
make lsuperf    # cycles per memory op: combinational vs synchronous read, plus a performance bug
```

* `dcache.sv` with `SYNC_READ = 1` (default; `-GDC_SYNC=0` is Lab 7): the data array has a registered read. The set
  is presented in Execute from IEUAdrE (virtual; VIPT-safe because set + offset < 12 bits, checked at elaboration),
  the tag compare in Memory uses PAdrM. `SelAdr` re-reads Memory's own set while it is held (stall, miss, walk,
  flush). Any array write (store hit, line fill) makes the next read invalid; a load that finds DataOut invalid for
  its set spends one cycle re-reading (`ReRead`). Wally reaches the same timing with StoreStallD in Decode,
  SelAdr in cachefsm and the walker's separate Adr/Rd states; this cache checks the read instead.
* `tests/lsu/lsu_hazards.S`: 20 self-checks on back-to-back cases (book Fig. 12.16 sequence, store byte then load
  word, load after a fill, two ways of one set, eviction then reload, uncached then cached, sub-word loads).
  `dv/genlsu.py`: base + immediate addressing so loads and stores sit next to each other in the pipeline.
* Results: 78/78 (and 38/38 for each of the other two configurations). Store-then-load costs one cycle:
  copy kernel 1.52 to 2.00 cycles/op, rmw 2.02 to 2.50, pure loads unchanged at 1.02. A page walk through the
  D-cache costs one more cycle per level (+3 to +4), the shape of Wally's Lx_Adr / Lx_Rd states.
  Bug hunt: Lab 7's generator (li + add per access) catches none of the read-path bugs in 10 seeds; genlsu catches
  three of them 10/10; the transaction-level cache model catches none (it sees transactions, not data);
  BUG_SELADR_ON_HIT is performance-only (stride loads 1.02 to 2.00 cycles/op).

## Lab 10: branch prediction (book Ch 13)

```
make bp         # regression incl. tests/bp + 5 genbp programs: lock-step AND an exact predictor model; 4 configurations
make bphunt     # 5 injected predictor bugs vs self-check, lock-step, model; 1024- and 16-entry BTB
make bpperf     # predictor type, PHT size (bimodal vs gshare), BTB size, RAS depth
```

* `rtl/pipe/bpred.sv`, `-GBP_TYPE=`: 0 static not taken (the old core), 1 static BTFN (decoded in Fetch), 2 bimodal,
  3 gshare with committed history (Wally BP_GSHARE_BASIC), 4 gshare whose lookup history also shifts in the branches in
  Memory/Execute (real) and Decode (predicted) (default). Tagless BTB {target, class: branch/jump/call/return}
  (`BTB_BITS`, default 1024 entries), 2-bit PHT (`BHT_BITS`), RAS (`RAS_SIZE`) acting in Decode with a pointer snapshot
  per instruction, restored when Memory flushes or traps it. Everything trains at commit. Execute flushes when the
  PC fetched after an instruction differs from PCCorrectE (`BPWrongE`, replaces PCSrcE in the hazard unit).
* `dv/bpsim.py`: an ideal predictor run over the ISS trace. With GHR forwarding the RTL's misprediction count equals
  it exactly (bench 398 = 398, bp_basic 158 = 158, 10/10 random programs), so regressions check equality.
  `dv/genbp.py`: random structured control flow (loops, data-dependent and periodic ifs, direct/indirect calls,
  csrw in front of calls and returns). `tests/bp/bp_basic.S`: book Code Examples 13.1 and 13.2, deep calls and
  fib(10), changing indirect targets, an addi 4 KiB after a trained jump (BTB alias, needs `.option norelax`), a loop
  exit while Fetch holds a predicted jump, csrw before a call.
* Results (tests/bench, 41,119 instructions): CPI 1.238 (not taken), 1.056 (BTFN), 1.038 (bimodal), 1.022 (gshare,
  committed history), 1.020 (gshare + forwarding). Bug hunt: BP_PRIORITY fails lock-step but passes the directed
  self-check; CFI_ONLY needs aliasing (0/10 with 1024 BTB entries, 10/10 with 16); RAS_NO_REPAIR and PHT_NO_SAT are
  invisible to lock-step and caught only by the exact model. Side effect: with a predictor, Lab 5's BUG_INT_BUBBLE no
  longer fires in tests/priv/interrupts.S (its trigger, a bubble from a taken branch, is gone); with BP_TYPE=0 it does.

## Lab 11: peripherals (book Ch 20)

```
make periph       # block-level bench: 5 seeds, full checks and the book-style loopback plan
make periphhunt   # 14 injected bugs: which verification style notices each
make periphdemo   # one UART character and book Example 20.3, printed cycle by cycle (the notes' GIF)
```

* `rtl/uncore/periph.sv`: GPIO (FE310 map, 2-flop synchronizer, sticky W1C pending bits, out_xor), CLINT
  (64-bit mtime/mtimecmp, msip), PLIC (31 sources, 2 contexts, gateway, lowest-id ties, strict threshold),
  UART (PC16550D subset: DLAB, 16-deep FIFOs, 16x oversampling, parity/stop, LSR/IIR, overrun),
  SPI (FU540 subset: sckdiv, 4 modes, bit order, 1-8 bit frames, CS AUTO/HOLD/OFF, watermarks).
  Wally's base addresses and PLIC ids (GPIO 3, SPI 6, UART 10).
* `tb/tb_periph.sv`: APB driver, register model (reset values, masks, DLAB banking), cycle-exact models of
  GPIO/CLINT/PLIC checking every pin every cycle, an independent UART agent (frame decoder on TX; RX driver
  with +-2% and +3% baud error, parity and framing error injection), an SPI peripheral model for all four
  modes and both bit orders, 81 coverage bins. `+BOOKPLAN` checks only the way the book's plan does
  (UART/SPI in loopback, GPIO read after settling).
* Results: 81/81 bins over 5 seeds. Hunt: the full bench catches all 14 bugs; the book-style plan misses
  BUG_UART_PARITY_INV, BUG_UART_SAMPLE_EARLY, BUG_SPI_IGNORE_PHASE and BUG_SPI_IGNORE_ENDIAN (each is
  self-consistent between transmitter and receiver, so loopback passes).
* Found while building it: an RTL race (an overrun in the same cycle as the LSR read that clears OE was lost;
  set now wins), and two testbench lessons (polling LSR consumes OE; the book's Example 20.1 assumes out_xor = 0).

## Chapter 7 experiments

* `tests/bench/bench.c` (+ `crt0.S`, `c.ld`): sort, CRC-32, list walk, search, fib, compiled `-O2 -march=rv32i`.
  On the pipeline: 41,119 instructions, 50,892 cycles, CPI 1.238, lock-step clean. 33 load-use stall cycles,
  4,869 taken branches/jumps (2 cycles each).
* `tests/directed/x0_loads.S` with `-DPERF_LOADSTALL_X0` (the book text's MatchDE without `RdE != 0`):
  same architectural results, 1,008 vs 808 cycles. A performance bug lock-step cannot see.

## Layout

```
rtl/common/generic.sv     flopr, flopenr, flopenrc, mux2, mux3      (Wally src/generic)
rtl/common/units.sv       regfile, extend, alu, comparator, decoder, subword read/write
rtl/single/core_single.sv Lab 1 core
rtl/pipe/core_pipe.sv     Lab 3 core (with -DBUG_* switches)
rtl/pipe/hazard.sv        stall/flush rules (Wally's rules, fewer causes)
tb/tb.sv                  one testbench for both cores; RVVI-like retirement trace
dv/iss.py                 reference model (independent of the RTL)
dv/gen.py                 constrained-random test generator
dv/compare.py             first-divergence trace compare
dv/coverage.py            functional coverage (ISA + pipeline-hazard coverpoints)
dv/regress.py             regression driver
dv/bughunt.py             bug-injection experiment
dv/pipeview.py            per-cycle pipeline view (book Fig. 7.15 style)
tests/book/               the book's riscvtest (from cvw/examples/verilog/riscvsingle)
tests/directed/           self-checking directed tests
synth/                    Lab 4: Yosys scripts, sta.py, power.py, minperiod.py, addr.sv
```

## Results (as built)

* Pipeline: 53/53 tests (book + 2 directed + 50 random) match the ISS at every instruction; 64/64 coverage bins. Single-cycle: same with 20 seeds.
* Bug hunt (20 random seeds x 300 instructions):

| Injected bug | Book test | Directed self-check | Random lock-step |
| --- | --- | --- | --- |
| ALU OR became + (book 5.11.7; 10 seeds) | caught | caught | 10/10 |
| Forward priority W over M | caught | caught | 20/20 |
| No forwarding from W | caught | caught | 20/20 |
| Forwarding x0 | **missed** | caught | 20/20 |
| No load-use stall | caught | **missed** | 19/20 |
| Branch flushes only one instruction | caught | caught | 20/20 |

The coverage report explains both misses: the book test never reads x0 right after
writing it, and the directed test (100% instruction and branch coverage) never puts
a consumer directly after a load.

## Where to go next (toward Wally)

Labs 5-11 already cover the old list (traps, caches, MMU, branch prediction, peripherals). What is left:

1. M extension: multi-cycle divider that stalls E (Ch 15; Wally `src/mdu`, `DivBusyE`), and the
   divide-busy x mispredict corner from Wally's hazard unit (`BPWrongE & ~DivBusyE`).
2. SVA: bind assertions to the hazard unit (never forward from x0; `StallX |-> StallY` for every older stage),
   the AHB port (Lab 6's list) and the PLIC (claim never returns a source at or below threshold).
3. Replace `dv/iss.py` with Spike or Sail and run riscv-arch-test through the same compare flow; then add the
   riscvISACOV covergroups over an RVVI-style trace.
4. S-mode and instruction-side translation (ITLB through the same walker), to reach Wally's Sv32 behaviour.
5. Re-run `synth/run_all.sh` on the current core (Lab 4 numbers predate priv.sv, the bus and the caches).

Wally source is Solderpad-licensed; the book test program comes from the cvw repository.
