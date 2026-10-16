#!/usr/bin/env python3
"""Remove one hazard mechanism at a time and see which test notices (and how CPI changes)."""
import os, re, shutil, subprocess, sys
V = os.environ['VERILATOR']; ROOT = os.path.abspath('.')
M = [
 ("no forwarding from MEM (distance 1)", "if (r != 0 && fwd_mem.valid && fwd_mem.we && !fwd_mem.is_load && fwd_mem.rd == r) return fwd_mem.result;", ""),
 ("no forwarding from WB (distance 2)", "if (r != 0 && fwd_wb.valid  && fwd_wb.we  && fwd_wb.rd == r)                         return fwd_wb.wdata;", ""),
 ("forwarding priority reversed", "if (r != 0 && fwd_mem.valid && fwd_mem.we && !fwd_mem.is_load && fwd_mem.rd == r) return fwd_mem.result;\n    if (r != 0 && fwd_wb.valid  && fwd_wb.we  && fwd_wb.rd == r)                         return fwd_wb.wdata;",
     "if (r != 0 && fwd_wb.valid  && fwd_wb.we  && fwd_wb.rd == r)                         return fwd_wb.wdata;\n    if (r != 0 && fwd_mem.valid && fwd_mem.we && !fwd_mem.is_load && fwd_mem.rd == r) return fwd_mem.result;"),
 ("forward a load's ADDRESS from MEM", "fwd_mem.we && !fwd_mem.is_load && fwd_mem.rd", "fwd_mem.we && fwd_mem.rd"),
 ("no register-file write-through (distance 3)", "rd1 = (ra1 == 0) ? '0 : (we && wa == ra1) ? wd : r[ra1];", "rd1 = (ra1 == 0) ? '0 : r[ra1];"),
 ("no load-use stall", "assign stall = if_id.valid", "assign stall = 1'b0 && if_id.valid"),
 ("flush forgets the instruction in IF/ID", "pc <= redirect_pc; if_id.valid <= 1'b0;", "pc <= redirect_pc;"),
 ("flush forgets the instruction in decode", "if (rst || flush || stall) id_ex.valid <= 1'b0;", "if (rst || stall) id_ex.valid <= 1'b0;"),
 ("x0 can be written", "if (d.rd == 0) d.we = 0;", ""),
 ("PERF: no branch prediction (always pc+4)", "if (instr[6:0] == 7'b1101111)                     pred_npc = pc + imm_j;  // jal\n    else if (instr[6:0] == 7'b1100011 && instr[31])   pred_npc = pc + imm_b;  // backward branch", ""),
]
tests = sorted(os.listdir('tests'))
for name, a, b in M:
    d = os.path.join('build', 'mut'); shutil.rmtree(d, ignore_errors=True); os.makedirs(d + '/rtl')
    s = open('rtl/pq5.sv').read(); assert a in s, name; s = s.replace(a, b)
    if name.startswith('x0'): s = s.replace("always_ff @(posedge clk) if (we && wa != 0) r[wa] <= wd;", "always_ff @(posedge clk) if (we) r[wa] <= wd;").replace("rd1 = (ra1 == 0) ? '0 :", "rd1 =").replace("rd2 = (ra2 == 0) ? '0 :", "rd2 =")
    open(d + '/rtl/pq5.sv', 'w').write(s)
    subprocess.run(f"{V} --binary -j 8 -Wno-fatal -Wno-lint -Wno-style --timing --assert -sv --top-module tb_pq5 -CFLAGS -std=c++20 --Mdir {d}/obj {d}/rtl/pq5.sv tb/tb_pq5.sv -o sim > {d}/b.log 2>&1", shell=True, check=True)
    fails, cpi = [], {}
    for t in tests:
        r = subprocess.run(['python3', 'tools/run_pq5.py', f'tests/{t}'], env={**os.environ, 'SIM_BIN': f'{d}/obj/sim'}, capture_output=True, text=True).stdout
        if 'FAIL' in r: fails.append(t.split('_')[0])
        m = re.search(r'CPI\s+([\d.]+)', r)
        if m: cpi[t.split('.')[0]] = m[1]
    rnd = 0
    for k in range(1, 101):
        r = subprocess.run(['python3', 'tools/run_pq5.py', f'build/rand/r{k}.s'], env={**os.environ, 'SIM_BIN': f'{d}/obj/sim'}, capture_output=True, text=True).stdout
        rnd += 'FAIL' in r
    extra = f"  CPI p04_loop_sum={cpi.get('p04_loop_sum')} p09_multiply={cpi.get('p09_multiply')}" if name.startswith('PERF') else ''
    print(f"{name:<45} directed fails: {len(fails):2d}/10 {','.join(fails):<30} random fails: {rnd:3d}/100{extra}")
