#!/usr/bin/env python3
"""run_yarp.py <prog.s> : assemble -> golden ISS -> RTL sim -> compare commit-by-commit."""
import os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv32i import assemble, ISS

def main():
    src = sys.argv[1]
    sim = os.environ.get('SIM_BIN', 'obj/sim'); extra = os.environ.get('SIM_ARGS', '').split()
    name = os.path.splitext(os.path.basename(src))[0]
    os.makedirs('build', exist_ok=True)
    words, text = assemble(open(src).read().splitlines())
    hexf = os.path.abspath(f'build/{name}.hex')
    open(hexf, 'w').write('\n'.join(f'{w:08x}' for w in words) + '\n')
    iss = ISS(); exp = iss.run(words)
    out = subprocess.run([sim, f'+PROG={hexf}'] + extra, capture_output=True, text=True, timeout=300).stdout
    open(f'build/{name}.log', 'w').write(out)
    got = [(int(a, 16), int(b), int(c, 16)) for a, b, c in re.findall(r'COMMIT pc=(\w+) rd=(\d+) val=(\w+)', out)]
    st = re.search(r'STATUS (\w+)', out)
    errs = [f'CHECK  {m}' for m in re.findall(r'\[CHECK\][^\n]*', out)[:2]]
    if not st or st[1] != 'DONE': errs.append(f'did not reach halt ({st[1] if st else "no status"})')
    for k, (e, g) in enumerate(zip(exp, got)):
        if e[0] != g[0]:
            errs.append(f'ORDER  commit #{k}: expected pc={e[0]:#x} ({text[e[0]//4]}) got pc={g[0]:#x}'); break
        if e[1:] != g[1:]:
            errs.append(f'VALUE  pc={e[0]:#x} {text[e[0]//4]:<24} expected x{e[1]}={e[2]:#x} got x{g[1]}={g[2]:#x}')
    if st and st[1] == 'DONE':
        if len(got) != len(exp): errs.append(f'COUNT  expected {len(exp)} retired, got {len(got)}')
        arf = {int(r): int(v, 16) for r, v in re.findall(r'ARF x(\d+)=(\w+)', out)}
        mem = {int(i): int(v, 16) for i, v in re.findall(r'MEM (\d+)=(\w+)', out)}
        errs += [f'ARF    x{r} expected {iss.x[r]:#x} got {arf[r]:#x}' for r in range(32) if arf.get(r) != iss.x[r]]
        errs += [f'MEMORY word {i} expected {iss.mem[i]:#x} got {mem[i]:#x}' for i in range(64) if mem.get(i) != iss.mem[i]]
    if errs:
        print(f'[FAIL] {name}'); [print('   ', e) for e in errs[:10]]; return 1
    print(f'[PASS] {name:<18} {len(got):5d} instructions')
    return 0

if __name__ == '__main__':
    sys.exit(main())
