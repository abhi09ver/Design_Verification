# SV Course Sessions 1–5 — Solved Questions, Code & Cheatsheet

Worked solutions to the exercise slides from five SystemVerilog / UVM course sessions. Every answer comes with **runnable code that was compiled and simulated** (Verilator 5.052 + Accellera UVM), with the outputs saved in [`logs/`](logs/).

**Start here before an interview → [CHEATSHEET.md](CHEATSHEET.md)** (one page, every pattern and trap).

## Contents

| # | Session / slide | Notes | Code | Verified result |
|---|---|---|---|---|
| 1 | SV Data Structures — p45 (14 Qs) + p52 (9 array ops) | [01-session1-sv-data-structures.md](01-session1-sv-data-structures.md) | [code/session1_data_structures](code/session1_data_structures/) | All outputs correct; 3 errors found in the slide's answer key |
| 2 | UVM Agent Deep Dive — p20 layered AXI/AHB agent | [02-session2-layered-axi-ahb-agent.md](02-session2-layered-axi-ahb-agent.md) | [code/session2_layered_uvm_agent](code/session2_layered_uvm_agent/) | Same test passes on AXI (4KB split) and AHB (1KB split), 0 UVM errors |
| 3 | SV OOP — p45 dual-port APB driver/monitor/scoreboard | [03-session3-apb-dual-port-testbench.md](03-session3-apb-dual-port-testbench.md) | [code/session3_apb_dual_port_tb](code/session3_apb_dual_port_tb/) | Clean run PASSED; `+BUG` run caught by the scoreboard |
| 4 | Constrain the Chaos — p41 (12 constraint Qs) | [04-session4-constraints.md](04-session4-constraints.md) | [code/session4_constraints](code/session4_constraints/) | 200 randomizations per question, self-checked: 0 failures |
| 5 | Coverage — p35 APB functional coverage model | [05-session5-apb-functional-coverage.md](05-session5-apb-functional-coverage.md) | [code/session5_apb_coverage](code/session5_apb_coverage/) | 92.3% with a deliberate hole → 100% after closing it; gating verified |

Each note has the question, the solution code, why it works, traps, likely interviewer follow-ups, and model answers.

## Running the code

```bash
# Verilator >= 5.030 (5.052 used here) and z3 must be on PATH
# Session 2 also needs UVM:
git clone --depth 1 https://github.com/accellera-official/uvm-core.git
export UVM_HOME=$PWD/uvm-core

./run_all.sh        # every session, outputs written to logs/
./run_all.sh 4      # just session 4
```

Every file is plain IEEE 1800 SystemVerilog and also runs on VCS, Xcelium or Questa. Use the commercial tool's usual compile command; the Verilator-only `` `ifdef `` in session 5 drops away automatically.

## Simulator notes (worth knowing, not worth memorising)
- Ubuntu's packaged Verilator 5.020 handles Session 1 but not randomization with constraints or covergroups. Build ≥ 5.030 from source.
- Verilator 5.052 limitations found along the way:
  - no per-coverpoint `get_coverage()`;
  - `!(x inside {...})` inside an implication block doesn't parse;
  - a `dist` combined with an inline `with` was wrongly reported as unsatisfiable.
  Workarounds are in the code comments.
