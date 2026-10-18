# CPU Lab — one-stop interview kit (OOO core · pipelined CPU · single-cycle YARP · RTL ladder)

Everything built while studying a 3-wide RISC-V out-of-order (Tomasulo) core for Senior DV interviews:
the code, the testbenches, the tools, the results, and three interactive study pages.
The written cheatsheets live next to the other challenges in the repo root (**26–31** and **37–39**).

## Read first (night before an interview)

| What | Where |
|---|---|
| OOO core architecture, module by module | [26 – Tomasulo core](../26-ooo-cpu-tomasulo-core.md) |
| The 15 bugs: symptom → cause → fix → lesson | [27 – Bug hunt](../27-ooo-core-bug-hunt.md) |
| How they were found: ISS, random, SVA, mutation | [28 – CPU verification](../28-cpu-verification-iss-random-sva-mutation.md) |
| 5-stage pipelined CPU, hazards, CPI (Pequeno series) | [29 – Pipelined CPU](../29-pipelined-in-order-cpu-hazards.md) |
| Fundamentals: 11 levels from adder to tiny OOO | [30 – CPU From Zero](../30-cpu-from-zero-rtl-ladder.md) |
| All questions + model answers + key numbers | [31 – Question bank](../31-cpu-interview-question-bank.md) |
| Single-cycle YARP: 4 RTL bugs, valid/ready spec gap, interface review | [37 – YARP core review](../37-yarp-single-cycle-core-review.md) |
| Class-based TB (gen/drv/mon/sb + DPI ISS): 17 TB bugs fixed, coverage closure, mutation 9/9 | [38 – YARP testbench review](../38-yarp-class-based-testbench-review.md) |
| **Everything on one page per concept (skim this last)** | [39 – RISC-V Core & DV Atlas](pages/riscv_dv_atlas.html) |

## Interactive pages (open in a browser, work offline except fonts)

| Page | What it has |
|---|---|
| [`pages/tomasulo_core_lab.html`](pages/tomasulo_core_lab.html) | architecture map, cycle stepper from a real trace, 15 bug cards with reveal, exercises, interview drill, bug catalog |
| [`pages/cpu_from_zero.html`](pages/cpu_from_zero.html) | beginner ladder with stories, pictures, run/break-it results, quizzes |
| [`pages/pequeno_study_guide.html`](pages/pequeno_study_guide.html) | Parts 1–6 of the Pequeno series explained + parts 7–9, real pipeline diagrams, CPI table, mutation table |
| [`pages/riscv_dv_atlas.html`](pages/riscv_dv_atlas.html) | 27 one-page infographics: ISA → design → pipeline/OOO/memory → verification → bug catalog, debug playbook, rapid-fire drills |

GitHub shows `.html` as source; download the file (or the branch as a zip) and open it locally.

## Code map

| Folder | Contents |
|---|---|
| `original_upload/` | the core exactly as uploaded (`result_3.zip`, line endings normalised) + the failing `xrun.log` |
| `rtl/` | the core with only the 4 compile/elab fixes (FIX-0a..d) — **start here** |
| `solutions/` | all fixes, each marked `FIX-n` in a comment |
| `patches/` | `diff -u rtl solutions`, one per file |
| `tb/tb_lab.sv` | program loader (`+PROG=`), commit monitor, watchdog, `+TRACE`, `+DEBUG`, `+MMUDBG` |
| `tb/core_sva.sv` | 7 SVA properties attached with `bind` |
| `tools/` | `rv.py` (assembler + ISS), `run_test.py` (scoreboard), `gen_random.py`, `trace2json.py` |
| `tests/` | `t00_original` + `b01..b19` bug hunts |
| `unit/tb_btb_plru.sv` | BTB replacement unit test |
| `yarp/orig/`, `yarp/fixed/`, `yarp/fixes.patch` | YARP single-cycle core as uploaded, with fixes Y1–Y4 |
| `yarp/tb/`, `yarp/tools/`, `yarp/tests/`, `yarp/if/` | commit-trace TB vs Python ISS, 13 directed + random programs, reviewed interface with SVA |
| `yarp/qs/course/` → `yarp/qs/course_fixed/` | your class-based course TB as written → fixed in place (`[FIX ..]` tags, `course_fixes.patch`) |
| `yarp/qs/rtl_vr/`, `yarp/qs/rtl_mut/` | YARP with valid/ready ports; same core with 9 bugs selectable by `+MUT=n` |
| `yarp/qs/model/` | C++ RV32I model behind the DPI calls (cross-checked 213/213 vs the Python ISS) |
| `yarp/qs/results/` | mutation tables: original course TB vs fixed TB |
| `generators/atlas/` | Python source that builds the atlas page |
| `examples/demo_stepper.s` | program used for the cycle stepper |
| `beginner/` | 11 levels (`L01_adder.sv` … `L11_tiny_ooo.sv`), `run_all.sh`, `mutate.py` |
| `pq5/` | 5-stage pipelined RV32I CPU, labelled assembler + ISS, 10 programs, random generator, mutation script, `results/` |
| `generators/` | Python that produced the three pages and the cheatsheets (reference; paths assume the original working layout) |

## Run (Verilator ≥ 5.026, tested 5.048; `pip install verilator` works)

```bash
cd cpu-lab
make sim RTL=rtl && make sim RTL=solutions
make regress RTL=solutions                 # 19/20 pass; b11_branch = capstone
make test T=tests/b03_rob_tag0.s RTL=rtl   # watch a bug fail
python3 tools/gen_random.py 42 build/r42.s && SIM_BIN=obj_solutions/sim python3 tools/run_test.py build/r42.s

cd beginner && ./run_all.sh && python3 mutate.py
cd ../pq5   && make regress && make pipe T=tests/p03_load_use.s
```

Xcelium: `xrun -sv -timescale 1ns/1ns -incdir rtl rtl/design.sv tb/core_sva.sv tb/tb_lab.sv +PROG=$PWD/build/x.hex`.
If Verilator's C++ build complains about `<coroutine>`, add `-fcoroutines` to `CFG_CXXFLAGS_COROUTINES` in `$VERILATOR_ROOT/include/verilated.mk`.

## Results at a glance

| | Result |
|---|---|
| Original OOO core | 1/20 directed (scoreboard only; 0/20 with SVA on), 0/720 random |
| Fixed OOO core | 19/20 directed, 720/720 random, 0 SVA firings |
| Beginner ladder | 11/11 levels pass, 11/11 injected mistakes caught |
| pq5 pipelined CPU | 10/10 programs, 500/500 random, cycles = 4 + N + stalls + 2 × flushes exactly |

Credit: Part summaries in challenge 29 refer to *Designing Pequeno RISC-V CPU from scratch* by Mitu Raj (Chipmunk Logic); pq5 is original code following that architecture.
