import subprocess, os, shutil, sys
V = os.environ['VERILATOR']
M = [
 ("01", "L01_adder.sv", "assign cout = (a & b) | (cin & (a ^ b));", "assign cout = (a & b);", "forgot carry-in in the carry"),
 ("02", "L02_counter.sv", "else if (en) count <= count + 1'b1;", "else count <= count + 1'b1;", "ignored enable"),
 ("03", "L03_alu.sv", "SRA:  y = $signed(a) >>> b[4:0];", "SRA:  y = a >>> b[4:0];", "SRA on an unsigned value"),
 ("04", "L04_regfile.sv", "if (we && wa != 0) r[wa] <= wd;", "if (we) r[wa] <= wd;", "x0 writable (+ read guard removed)"),
 ("05", "L05_fifo.sv", "assign in_ready  = (count < DEPTH);", "assign in_ready  = 1'b1;", "ignore 'full'"),
 ("06", "L06_tiny_cpu.sv", "wire  [31:0] imm_i  = {{20{instr[31]}}, instr[31:20]};", "wire  [31:0] imm_i  = {20'b0, instr[31:20]};", "zero-extended immediate (B02)"),
 ("07", "L07_scoreboard.sv", "assign stall = issue_valid && (busy[rs1] || busy[rs2] || (rd != 0 && busy[rd]));", "assign stall = issue_valid && (rd != 0 && busy[rd]);", "no RAW check"),
 ("08", "L08_rename.sv", "if (commit_valid && map_valid[commit_rd] && map_tag[commit_rd] == commit_tag)", "if (commit_valid && map_valid[commit_rd])", "clear RAT without tag match"),
 ("09", "L09_rs_cdb.sv", "if (e[i].busy && !e[i].a_rdy && cdb_valid && e[i].a_tag == cdb_tag)", "if (e[i].busy && !e[i].a_rdy && cdb_valid && e[i].a_tag == cdb_tag && e[i].a_tag != 0)", "tag 0 as 'no tag' (B04)"),
 ("10", "L10_rob.sv", "assign commit_valid = valid[head] && done[head];", "assign commit_valid = valid[head];", "retire before finished"),
 ("11", "L11_tiny_ooo.sv", "if (rob_done[tag])                        val = rob_val[tag];", "if (1'b0)                        val = rob_val[tag];", "missed wakeup: value already broadcast"),
]
extra = {"04": [("assign rd1 = (ra1 == 0) ? '0 : r[ra1];", "assign rd1 = r[ra1];")]}
files = {"06": "L03_alu.sv L04_regfile.sv L06_tiny_cpu.sv"}
for n, f, a, b, why in M:
    d = f"mut/L{n}"; shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    for x in os.listdir('.'):
        if x.endswith('.sv'): shutil.copy(x, d)
    s = open(f).read(); assert a in s, (n, a); s = s.replace(a, b)
    for x, y in extra.get(n, []): assert x in s; s = s.replace(x, y)
    open(f"{d}/{f}", 'w').write(s)
    src = files.get(n, f)
    r = subprocess.run(f"{V} --binary -Wno-fatal -Wno-lint -Wno-style --timing -sv --top-module tb_L{n} -CFLAGS -std=c++20 --Mdir o {src} -o sim > b.log 2>&1 && timeout 20 ./o/sim", shell=True, cwd=d, capture_output=True, text=True)
    line = [l for l in r.stdout.splitlines() if l.startswith(f"L{n}")]
    res = line[0] if line else "(no result line: hang/timeout)"
    print(f"L{n} mutation [{why}] -> {'CAUGHT' if 'PASS' not in res else 'MISSED'}: {res[:80]}")
