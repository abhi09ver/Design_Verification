#!/usr/bin/env python3
"""
run_test.py  <test.s> [--rtl DIR] [--keep]
  1. assembles test.s  -> build/<name>.hex
  2. runs golden ISS   -> expected commit trace / ARF / memory
  3. runs the RTL sim  -> actual commit trace / ARF / memory   (needs a built sim, see Makefile)
  4. compares them like a real CPU scoreboard:
       - commit ORDER (pc stream)  -> catches dropped / duplicated / reordered retirement
       - committed VALUE per rd    -> catches datapath / forwarding / wakeup bugs
       - final ARF + memory        -> catches lost stores / ordering violations
       - liveness                  -> HANG = deadlock / lost wakeup / lost instruction
"""
import os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv import assemble, ISS

def main():
    test = sys.argv[1]
    sim = os.environ.get('SIM_BIN', 'obj_dir/sim')
    name = os.path.splitext(os.path.basename(test))[0]
    os.makedirs('build', exist_ok=True)
    words, text = assemble(open(test).read().splitlines())
    hexf = os.path.abspath(f'build/{name}.hex')
    open(hexf, 'w').write('\n'.join(f'{w:08x}' for w in words) + '\n')

    iss = ISS(); exp = iss.run(words, len(words))

    out = subprocess.run([sim, f'+PROG={hexf}'], capture_output=True, text=True, timeout=600).stdout
    tag = os.path.basename(os.path.dirname(os.path.abspath(sim)))
    open(f'build/{name}.{tag}.log', 'w').write(out)
    got = [(int(m[0], 16), int(m[1]), int(m[2], 16)) for m in
           re.findall(r'COMMIT .* pc=(\w+) rd=(\d+) val=(\w+)', out)]
    status = re.search(r'STATUS (\w+) cycles=(\d+) commits=(\d+)', out)
    arf = {int(r): int(v, 16) for r, v in re.findall(r'ARF x(\d+)=(\w+)', out)}
    mem = {int(i): int(v, 16) for i, v in re.findall(r'MEM (\d+)=(\w+)', out)}

    errs = []
    sva = re.findall(r'(\[SVA A\d+\][^\n]*)', out)
    for a in sva[:3]:
        errs.append(f'ASSERTION: {a.strip()}')
    st = status.group(1) if status else ('ASSERTION_STOP' if sva else 'NO_STATUS')
    if st != 'DONE':
        errs.append(f'LIVENESS: simulation ended with {st} after {status.group(2) if status else "?"} cycles '
                    f'({len(got)}/{len(exp)} instructions retired)')
    for k, (e, g) in enumerate(zip(exp, got)):
        if e[0] != g[0]:
            errs.append(f'ORDER  : commit #{k}: expected pc={e[0]:#06x} ({text[e[0]//4]})  '
                        f'got pc={g[0]:#06x} ({text[g[0]//4] if g[0]//4 < len(text) else "?"})')
            break
        if e[1] != 0 and (g[1] != e[1] or g[2] != e[2]):
            errs.append(f'VALUE  : pc={e[0]:#06x} {text[e[0]//4]:<22} expected x{e[1]}={e[2]:#010x} '
                        f'got x{g[1]}={g[2]:#010x}')
    if len(got) > len(exp):
        errs.append(f'ORDER  : {len(got) - len(exp)} EXTRA commits (duplicated instructions?)')
    if st == 'DONE':
        for r in range(1, 32):
            if arf.get(r) != iss.x[r]:
                errs.append(f'ARF    : x{r} expected {iss.x[r]:#010x} got {arf.get(r, -1):#010x}')
        for i in range(64):
            if mem.get(i) != iss.mem[i]:
                errs.append(f'MEMORY : word {i} (addr {4*i:#x}) expected {iss.mem[i]:#010x} got {mem.get(i, -1):#010x}')
    cyc = status.group(2) if status else '?'
    for pc, kind, addr in iss.misaligned:
        print(f'    [SPEC-WARN] pc={pc:#06x} {text[pc//4]}: misaligned {kind} to {addr:#x}. RISC-V requires an '
              f'address-misaligned exception (or HW support); this core silently '
              f'{"drops the store" if kind == "store" else "returns 0xFFFFFFFF"}.')
    if errs:
        print(f'[FAIL] {name}  ({cyc} cycles)')
        for e in errs[:12]: print('   ', e)
        stuck = re.findall(r'STUCK rob=(\d+) pc=(\w+) ready=(\d)', out)
        for r, pc, rdy in stuck[:4]:
            print(f'    stuck: ROB[{r}] pc={int(pc,16):#06x} ({text[int(pc,16)//4]}) ready={rdy}')
        return 1
    ipc = len(exp) / max(1, int(cyc)) if cyc != '?' else 0
    print(f'[PASS] {name}  ({cyc} cycles, {len(got)} commits)')
    return 0

if __name__ == '__main__':
    sys.exit(main())
