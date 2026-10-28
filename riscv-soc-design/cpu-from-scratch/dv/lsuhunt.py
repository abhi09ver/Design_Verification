#!/usr/bin/env python3
"""lsuhunt.py -- Lab 9: inject bugs into the D-cache's synchronous read path; see which test finds them.

Per bug: the directed tests/lsu/lsu_hazards.S (self-check + lock-step), then two random suites
with the Lab 7 checks (lock-step, RAM image, cache model):
  gencache : Lab 7's generator, addresses built with li + add (never two memory ops in a row)
  genlsu   : Lab 9's generator, base + immediate, runs of back-to-back loads and stores
and the total cycles / re-read cycles over the genlsu seeds (performance).
Usage: lsuhunt.py [--seeds N] [--ops N]
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import cachehunt  # noqa: E402
import gencache   # noqa: E402
import genlsu     # noqa: E402
import regress    # noqa: E402

BUGS = ['BUG_NO_REREAD', 'BUG_REREAD_SET_ONLY', 'BUG_FILL_NO_INVAL', 'BUG_SELADR_ON_HIT']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=10)
    ap.add_argument('--ops', type=int, default=300)
    a = ap.parse_args()
    out = os.path.join(ROOT, 'build', 'tests')
    os.makedirs(out, exist_ok=True)
    basic = regress.build_test(os.path.join(ROOT, 'tests/lsu/lsu_hazards.S'), out)
    suites = {'gencache': [], 'genlsu': []}
    for s in range(1, a.seeds + 1):
        for name, g in (('gencache', gencache), ('genlsu', genlsu)):
            p = os.path.join(out, f'{name}{s}.S')
            open(p, 'w').write(g.gen(s, a.ops))
            suites[name].append(regress.build_test(p, out))
    print(f'{"Injected bug":22s} {"lsu_hazards self/lock":>22s} {"gencache: lock mem model":>26s} {"genlsu: lock mem model":>24s} {"genlsu cycles (rereads)":>24s}')
    firsts = []
    for bug, gp in [('', ''), ('', '-GDC_SYNC=0')] + [(b, '') for b in BUGS]:
        label = bug or ('(none)' if not gp else '(Lab 7: comb. read)')
        exe = regress.build_rtl('pipe', bug, gp)
        tag = bug or ('base' if not gp else 'comb')
        d = cachehunt.run_all(exe, basic, f'lh_{tag}')
        mk = lambda ok: 'ok' if ok else 'FAIL'
        cells, cyc, rr = [], 0, 0
        for name, hexes in suites.items():
            f = {'lock': 0, 'mem': 0, 'model': 0}
            for i, h in enumerate(hexes):
                r = cachehunt.run_all(exe, h, f'{name}{i + 1}_{tag}')
                for k in f:
                    f[k] += 0 if r[k] else 1
                if name == 'genlsu':
                    cyc += int(re.search(r'(\d+) cycles', r['cyc'] or r['status']).group(1)) if 'cycles' in (r['cyc'] or r['status']) else 0
                    m = re.search(r'rereads=(\d+)', r['stats'])
                    rr += int(m.group(1)) if m else 0
                if bug and not r['lock'] and not any(x[0] == bug and x[1] == name for x in firsts):
                    firsts.append((bug, name, i + 1, r['lmsg']))
            cells.append(f'{f["lock"]:>3d}/{a.seeds} {f["mem"]:>3d}/{a.seeds} {f["model"]:>3d}/{a.seeds}')
        if bug and not d['lock']:
            firsts.insert(0, (bug, 'lsu_hazards', 0, d['lmsg']))
        print(f'{label:22s} {mk(d["self"]) + " / " + mk(d["lock"]):>22s} {cells[0]:>26s} {cells[1]:>24s} {f"{cyc} ({rr})":>24s}')
    print()
    seen = set()
    for bug, where, seed, msg in firsts:
        if (bug, where) in seen:
            continue
        seen.add((bug, where))
        print(f'--- {bug}: first lock-step failure in {where}{f" seed {seed}" if seed else ""} ---\n{msg[:600]}\n')


if __name__ == '__main__':
    main()
