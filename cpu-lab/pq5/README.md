# pq5 - a 5-stage pipelined RV32I CPU (companion to the "Pequeno Study Guide")
Original code following the architecture described in Chipmunk Logic's
"Designing Pequeno RISC-V CPU from scratch" series (Parts 1-6), finished through
execute, memory, writeback and verification. Not the series' own RTL.

| file | what |
|---|---|
| rtl/pq5.sv | one module per stage: pq5_fetch, pq5_decode, pq5_regfile, pq5_execute, pq5_mem, pq5_core |
| tb/tb_pq5.sv | loads +PROG=, commit trace, perf counters, +PIPE picture, 4 assertions |
| tools/rv32i.py | RV32I assembler with labels + golden ISS |
| tools/run_pq5.py | assemble -> ISS -> sim -> compare |
| tools/gen_rand.py | constrained-random programs that always halt |
| tools/mutate_pq5.py | removes one hazard mechanism at a time (needs VERILATOR env) |
| tests/p01..p10 | ALU, forwarding, load-use, loop, if/else, calls, bubble sort, bytes, multiply, fibonacci |

```
make obj/sim VERILATOR=verilator
make regress
make pipe T=tests/p03_load_use.s
```
