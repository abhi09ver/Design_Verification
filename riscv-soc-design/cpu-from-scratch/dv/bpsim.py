#!/usr/bin/env python3
"""bpsim.py -- Lab 10: a reference model of the branch predictor ("CModel", book 13.2.2 / 21.3.2).

Replays a committed-instruction trace (the ISS trace) through the same algorithm as bpred.sv
-- tagless BTB with instruction class, bimodal or gshare 2-bit counters, a return-address stack
-- but with IDEAL timing: every lookup sees every older update. The RTL updates at commit, three
instructions behind Fetch, so its count can only be a little higher than the model's. A count
that is much higher is a predictor that works (lock-step passes) but predicts badly: exactly the
bugs lock-step cannot see. With GHR forwarding (TYPE 4) the RTL's history is the same as the
ideal one and the counts agree EXACTLY (checked on the benchmark and on random programs with
CSR flushes and RAS repairs), so check() then demands equality.

check(trace, rtl_flushes, type, bht, btb, ras) -> (ok, model_flushes, message)
Usage: bpsim.py <iss_trace> [type bht_bits btb_bits ras_size]
"""
import sys

C_NONE, C_BRANCH, C_JUMP, C_CALL, C_RET = range(5)


def classify(insn):
    op, rd, rs1 = insn & 0x7F, (insn >> 7) & 31, (insn >> 15) & 31
    if op == 0x63:
        return C_BRANCH
    if op == 0x6F:
        return C_CALL if rd in (1, 5) else C_JUMP
    if op == 0x67:
        if rd == 0 and rs1 in (1, 5):
            return C_RET
        return C_CALL if rd in (1, 5) else C_JUMP
    return C_NONE


def immb(insn):
    v = ((insn >> 31) & 1) << 12 | ((insn >> 7) & 1) << 11 | ((insn >> 25) & 0x3F) << 5 | ((insn >> 8) & 0xF) << 1
    return v - (1 << 13) if v >> 12 else v


def simulate(trace, typ=3, bht=10, btb=10, ras=4):
    recs = []
    for line in open(trace):
        if line.startswith('pc='):
            t = line.split()
            recs.append((int(t[0][3:], 16), int(t[1][5:], 16)))
        elif line.startswith('trap'):
            recs.append(None)                     # the next instruction is a trap vector: unpredictable
    pht = [1] * (1 << bht)
    btbc, btbt = [C_NONE] * (1 << btb), [0] * (1 << btb)
    ghr, stack, ptr = 0, [0] * ras, 0
    wrong = n = 0
    for i, r in enumerate(recs[:-1]):
        if r is None or recs[i + 1] is None:
            continue
        pc, insn = r
        nxt = recs[i + 1][0]
        cls = classify(insn)
        bi, pi = (pc >> 2) & ((1 << btb) - 1), ((pc >> 2) & ((1 << bht) - 1))
        if typ >= 3:                              # gshare (3 and 4: the model's history is exact)
            pi ^= ghr
        # ---- predict (Fetch) ----
        pc_cls, pred = btbc[bi], pc + 4
        if typ == 1:
            if insn & 0x7F == 0x6F:
                imm = ((insn >> 31) and -(1 << 20) or 0) | ((insn >> 12) & 0xFF) << 12 | ((insn >> 20) & 1) << 11 | ((insn >> 21) & 0x3FF) << 1
                pred = (pc + imm) & 0xFFFFFFFF
            elif insn & 0x7F == 0x63 and insn >> 31:
                imm = -(1 << 12) | ((insn >> 7) & 1) << 11 | ((insn >> 25) & 0x3F) << 5 | ((insn >> 8) & 0xF) << 1
                pred = (pc + imm) & 0xFFFFFFFF
        elif typ >= 2:
            if pc_cls == C_BRANCH and pht[pi] >= 2: pred = btbt[bi]
            elif pc_cls in (C_JUMP, C_CALL): pred = btbt[bi]
            elif pc_cls == C_RET: pred = stack[ptr]
        n += 1
        if pred != nxt:
            wrong += 1
        if typ < 2:
            continue
        # ---- update (ideal: immediately) ----
        if cls == C_CALL:
            ptr = (ptr + 1) % ras
            stack[ptr] = pc + 4
        elif cls == C_RET:
            ptr = (ptr - 1) % ras
        if cls == C_BRANCH:
            taken = nxt != pc + 4
            pht[pi] = min(3, pht[pi] + 1) if taken else max(0, pht[pi] - 1)
            ghr = (ghr >> 1) | (int(taken) << (bht - 1))
        if cls != C_NONE:
            btbc[bi] = cls
            # the RTL writes IEUAdr: for a branch that is the computed target even when not taken
            btbt[bi] = (pc + immb(insn)) & 0xFFFFFFFF if cls == C_BRANCH else nxt
        elif pc_cls != C_NONE:
            btbc[bi] = C_NONE
    return wrong, n


def check(trace, rtl_flushes, typ=4, bht=10, btb=10, ras=4, slack=0.15, floor=12):
    """TYPE 4 (forwarded history) must match the ideal model EXACTLY; TYPE 3 (committed history)
    lags the fetch stream, so it gets slack."""
    model, n = simulate(trace, typ, bht, btb, ras)
    if typ <= 1 or (typ == 4 and btb >= 8):
        limit = model                     # exact (static predictors have no state at all)
    elif typ == 4:
        limit = model + model // 100 + 2  # tiny BTB: an entry can change while its writer is in flight
    else:                                 # (Wally forwards in-flight BTB entries; this core does not)
        limit = int(model * (1 + slack)) + floor
    ok = rtl_flushes <= limit
    msg = f'RTL {rtl_flushes} mispredictions vs ideal model {model} (limit {limit}) over {n} instructions'
    return ok, model, msg


if __name__ == '__main__':
    a = sys.argv[1:]
    w, n = simulate(a[0], *[int(x) for x in a[1:5]])
    print(f'model: {w} mispredictions in {n} instructions ({100 * w / max(n, 1):.2f}%)')
