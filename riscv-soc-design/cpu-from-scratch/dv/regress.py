#!/usr/bin/env python3
"""regress.py -- build a core, run directed + random tests, compare, collect coverage.

  regress.py single  [--seeds N] [--len L]
  regress.py pipe    [--seeds N] [--len L] [--bug NAME]

For every test: gen.py -> gcc -> hex -> ISS trace + RTL trace -> compare.py.
--bug compiles the pipelined core with one deliberately injected bug
(see rtl/pipe/core_pipe.sv), to show which tests catch it.
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import coverage  # noqa: E402
import iss       # noqa: E402

GCC = 'riscv64-unknown-elf-gcc'
OBJCOPY = 'riscv64-unknown-elf-objcopy'


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)


def build_rtl(core, bug, gparams=''):
    tag = core + (f'_{bug}' if bug else '') + (gparams.replace('-G', '_').replace('=', '').replace(' ', '') if gparams else '')
    mdir = os.path.join(ROOT, 'build', tag)
    os.makedirs(mdir, exist_ok=True)
    srcs = ['rtl/common/generic.sv', 'rtl/common/units.sv']
    srcs += ['rtl/single/core_single.sv'] if core == 'single' else ['rtl/pipe/hazard.sv', 'rtl/pipe/priv.sv', 'rtl/pipe/core_pipe.sv', 'rtl/pipe/dcache.sv', 'rtl/pipe/mmu.sv', 'rtl/pipe/bpred.sv', 'rtl/uncore/uncore.sv']
    defs = '-DPIPELINE' if core == 'pipe' else ''
    if bug: defs += f' -D{bug}'
    defs += ' ' + gparams
    r = sh(f'verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style {defs} --top-module tb '
           f'-Mdir {mdir} -o Vtb {" ".join(srcs)} tb/tb.sv', cwd=ROOT)
    exe = os.path.join(mdir, 'Vtb')
    if not os.path.exists(exe):
        print(r.stdout[-3000:], r.stderr[-3000:])
        sys.exit('RTL build failed')
    return exe


def build_test(src_s, out_dir):
    base = os.path.join(out_dir, os.path.splitext(os.path.basename(src_s))[0])
    r = sh(f'{GCC} -march=rv32i_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles -T {HERE}/link.ld '
           f'-o {base}.elf {src_s} && {OBJCOPY} -O binary {base}.elf {base}.bin')
    if r.returncode:
        sys.exit(f'assembly failed for {src_s}:\n{r.stderr}')
    data = open(f'{base}.bin', 'rb').read()
    data += b'\0' * (-len(data) % 4)
    with open(f'{base}.hex', 'w') as f:
        for i in range(0, len(data), 4):
            f.write(f'{int.from_bytes(data[i:i + 4], "little"):08x}\n')
    return f'{base}.hex'


def run_one(exe, hexfile, out_dir, name):
    ref = os.path.join(out_dir, f'{name}.iss.trace')
    dut = os.path.join(out_dir, f'{name}.dut.trace')
    r = sh(f'{exe} +HEX={hexfile} +TRACE={dut} +MAXCYCLES=200000')
    # the ISS follows the DUT trace only for interrupt timing and mcycle/time/mip reads
    iss.run(hexfile, ref, follow=dut)
    status = next((l for l in r.stdout.splitlines() if l.startswith(('PASS', 'FAIL', 'DONE'))), r.stdout)
    import io, contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = __import__('compare').compare(ref, dut)
    # Both must hold: the DUT agrees with the reference model at every instruction,
    # AND the test itself did not report a failure (a self-checking test that fails
    # identically on DUT and ISS would otherwise "match").
    ok = rc == 0 and not status.startswith('FAIL')
    return ok, status, buf.getvalue().strip(), ref


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('core', choices=['single', 'pipe'])
    ap.add_argument('--seeds', type=int, default=20)
    ap.add_argument('--len', type=int, default=300)
    ap.add_argument('--bug', default='')
    ap.add_argument('--quiet', action='store_true')
    ap.add_argument('--gparams', default='', help="e.g. '-GRAM_WAIT=2' (Lab 6: slow bus RAM)")
    a = ap.parse_args()

    exe = build_rtl(a.core, a.bug, a.gparams)
    out = os.path.join(ROOT, 'build', 'tests')
    os.makedirs(out, exist_ok=True)

    results, traces = [], []
    # 1) the book's directed test (prebuilt hex)
    ok, status, cmp, ref = run_one(exe, os.path.join(ROOT, 'tests/book/riscvtest.hex'), out, 'book')
    results.append(('book riscvtest', ok, status, cmp)); traces.append(ref)
    # 2) our directed tests
    for s in sorted(os.listdir(os.path.join(ROOT, 'tests/directed'))):
        if s.endswith('.S'):
            hx = build_test(os.path.join(ROOT, 'tests/directed', s), out)
            ok, status, cmp, ref = run_one(exe, hx, out, s[:-2])
            results.append((f'directed {s[:-2]}', ok, status, cmp)); traces.append(ref)
    # 2b) privileged directed tests (Lab 5), pipeline only
    if a.core == 'pipe':
        for s in sorted(os.listdir(os.path.join(ROOT, 'tests/priv'))):
            if s.endswith('.S'):
                hx = build_test(os.path.join(ROOT, 'tests/priv', s), out)
                ok, status, cmp, ref = run_one(exe, hx, out, s[:-2])
                results.append((f'priv {s[:-2]}', ok, status, cmp)); traces.append(ref)
    # 2c) bus tests (Lab 6), pipeline only
    if a.core == 'pipe':
        for s in sorted(os.listdir(os.path.join(ROOT, 'tests/bus'))):
            if s.endswith('.S'):
                hx = build_test(os.path.join(ROOT, 'tests/bus', s), out)
                ok, status, cmp, ref = run_one(exe, hx, out, s[:-2])
                results.append((f'bus {s[:-2]}', ok, status, cmp)); traces.append(ref)
    # 2c''') branch predictor (Lab 10): directed + 5 genbp seeds, lock-step AND the ideal predictor model
    if a.core == 'pipe':
        import bphunt, genbp
        g = lambda k, dflt: int((__import__('re').search(k + r'=(\d+)', a.gparams) or [None, dflt])[1])
        bp_tests = [os.path.join(ROOT, 'tests/bp', s) for s in sorted(os.listdir(os.path.join(ROOT, 'tests/bp'))) if s.endswith('.S')]
        for seed in range(1, 6):
            p = os.path.join(out, f'bpr{seed}.S')
            open(p, 'w').write(genbp.gen(seed, 25))
            bp_tests.append(p)
        for src in bp_tests:
            hx = build_test(src, out)
            nm = os.path.basename(src)[:-2]
            d = bphunt.run_all(exe, hx, f'reg_{nm}', g('BTB_BITS', 10))
            if d['lock'] and d['flushes'] >= 0:      # model at this configuration's predictor type and sizes
                import bpsim
                d['model'], _, d['mmsg'] = bpsim.check(os.path.join(ROOT, 'build', 'bp', f'reg_{nm}.iss'), d['flushes'],
                                                      g('BP_TYPE', 4), g('BHT_BITS', 10), g('BTB_BITS', 10), g('RAS_SIZE', 4))
            ok = d['lock'] and d['model'] and not d['status'].startswith('FAIL')
            results.append((f'bp {nm}', ok, d['status'], d['lmsg'] if not d['lock'] else d['mmsg']))
            traces.append(os.path.join(ROOT, 'build', 'bp', f'reg_{nm}.iss'))
    # 2c'') LSU hazard tests (Lab 9), pipeline only
    if a.core == 'pipe':
        for s in sorted(os.listdir(os.path.join(ROOT, 'tests/lsu'))):
            if s.endswith('.S'):
                hx = build_test(os.path.join(ROOT, 'tests/lsu', s), out)
                ok, status, cmp, ref = run_one(exe, hx, out, s[:-2])
                results.append((f'lsu {s[:-2]}', ok, status, cmp)); traces.append(ref)
    # 2c') MMU tests (Lab 8), pipeline only
    if a.core == 'pipe':
        for s in sorted(os.listdir(os.path.join(ROOT, 'tests/mmu'))):
            if s.endswith('.S'):
                hx = build_test(os.path.join(ROOT, 'tests/mmu', s), out)
                ok, status, cmp, ref = run_one(exe, hx, out, s[:-2])
                results.append((f'mmu {s[:-2]}', ok, status, cmp)); traces.append(ref)
        import mmuhunt
        for i, hx in enumerate(mmuhunt.build_random(5, 300)):
            g = lambda k, dflt: int((__import__('re').search(k + r'=(\d+)', a.gparams) or [None, dflt])[1])
            d = mmuhunt.run_all(exe, hx, f'reg_mrand{i + 1}', g('TLB_ENTRIES', 4))
            ok = d['lock'] and d['tlb'] and not d['status'].startswith('FAIL')
            results.append((f'mmu mrand{i + 1}', ok, d['status'], d['lmsg'] if not d['lock'] else d['tmsg']))
            traces.append(os.path.join(ROOT, 'build', 'mmu', f'reg_mrand{i + 1}.iss'))
    # 2d) cache tests (Lab 7), pipeline only: directed + 5 constrained-random seeds, each also
    #     checked by the end-of-test RAM image and the transaction-level cache model
    if a.core == 'pipe':
        import cachehunt, gencache
        cache_tests = [os.path.join(ROOT, 'tests/cache', s) for s in sorted(os.listdir(os.path.join(ROOT, 'tests/cache'))) if s.endswith('.S')]
        for seed in range(1, 6):
            p = os.path.join(out, f'crand{seed}.S')
            open(p, 'w').write(gencache.gen(seed, 300))
            cache_tests.append(p)
        import genlsu                                   # Lab 9: back-to-back loads and stores
        for seed in range(1, 6):
            p = os.path.join(out, f'lrand{seed}.S')
            open(p, 'w').write(genlsu.gen(seed, 300))
            cache_tests.append(p)
        for src in cache_tests:
            hx = build_test(src, out)
            nm = os.path.basename(src)[:-2]
            import re as _re
            g = lambda k, dflt: int((_re.search(k + r'=(\d+)', a.gparams) or [None, dflt])[1])
            d = cachehunt.run_all(exe, hx, f'reg_{nm}', (g('DC_WAYS', 2), g('DC_SETS', 8), g('DC_LINEWORDS', 4)))
            ok = d['lock'] and d['mem'] and d['model'] and not d['status'].startswith('FAIL')
            cmp = d['lmsg'] if not d['lock'] else ('RAM image differs' if not d['mem'] else d['mmsg'])
            results.append((f'cache {nm}', ok, d['status'], cmp)); traces.append(os.path.join(out, f'reg_{nm}.iss'))
    # 3) constrained random
    for seed in range(1, a.seeds + 1):
        src = os.path.join(out, f'rand{seed}.S')
        sh(f'python3 {HERE}/gen.py {seed} {a.len} {src}')
        hx = build_test(src, out)
        ok, status, cmp, ref = run_one(exe, hx, out, f'rand{seed}')
        results.append((f'random seed {seed}', ok, status, cmp)); traces.append(ref)

    nfail = 0
    first_fail_shown = False
    for name, ok, status, cmp in results:
        if not ok: nfail += 1
        if not a.quiet or not ok:
            print(f'{"PASS" if ok else "FAIL"}  {name:22s} {status}')
        if not ok and not first_fail_shown:
            print('      ' + cmp.replace('\n', '\n      '))
            first_fail_shown = True
    print(f'\n{len(results) - nfail}/{len(results)} tests passed'
          f'{" with bug " + a.bug if a.bug else ""}')
    coverage.report(traces)
    return 1 if nfail else 0


if __name__ == '__main__':
    sys.exit(main())
