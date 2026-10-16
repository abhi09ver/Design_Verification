# CPU From Zero - beginner track (11 levels)
Read alongside the "CPU From Zero" page. Each file = one level = one design + its self-checking testbench.

| level | file | you build |
|---|---|---|
| 1 | L01_adder.sv | 32-bit adder from full adders |
| 2 | L02_counter.sv | a clocked counter (flip-flops) |
| 3 | L03_alu.sv | the ALU |
| 4 | L04_regfile.sv | 32-entry register file, x0 = 0 |
| 5 | L05_fifo.sv | FIFO with valid/ready |
| 6 | L06_tiny_cpu.sv | single-cycle RISC-V CPU (uses L03 + L04) |
| 7 | L07_scoreboard.sv | busy-bit scoreboard (why in-order CPUs stall) |
| 8 | L08_rename.sv | rename table (RAT) |
| 9 | L09_rs_cdb.sv | reservation station + CDB wakeup/select |
| 10 | L10_rob.sv | reorder buffer |
| 11 | L11_tiny_ooo.sv | a working tiny out-of-order CPU |

```
./run_all.sh        # all levels  (VERILATOR=/path/to/verilator ./run_all.sh if not on PATH)
./run_all.sh 11     # one level
python3 mutate.py   # injects one classic mistake per level and shows each test catches it
```
Best way to learn: delete a module's body, retype it from the page's explanation, run the test.
