# -*- coding: utf-8 -*-
# Inline SVG diagrams for the course. All colours come from CSS tokens via classes.
import math

def wrap(svg, cap, minw=720, fig=""):
    return (f'<figure class="fig"><div class="figscroll"><div style="min-width:{minw}px">{svg}</div></div>'
            f'<figcaption><span class="fignum">{fig}</span>{cap}</figcaption></figure>')

def box(x, y, w, h, title, sub="", cls="bx", tcls="t", subcls="ts"):
    s = f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="3"/>'
    if sub:
        s += f'<text class="{tcls}" x="{x+w/2}" y="{y+h/2-3}" text-anchor="middle">{title}</text>'
        s += f'<text class="{subcls}" x="{x+w/2}" y="{y+h/2+13}" text-anchor="middle">{sub}</text>'
    else:
        s += f'<text class="{tcls}" x="{x+w/2}" y="{y+h/2+5}" text-anchor="middle">{title}</text>'
    return s

def arrow(x1, y1, x2, y2, cls="ln"):
    return f'<line class="{cls}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" marker-end="url(#ah)"/>'

def path(d, cls="ln"):
    return f'<path class="{cls}" d="{d}" marker-end="url(#ah)"/>'

DEFS = ('<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        '<path d="M0,0 L10,5 L0,10 z" class="ahd"/></marker>'
        '<marker id="ahs" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        '<path d="M0,0 L10,5 L0,10 z" class="ahs"/></marker></defs>')

def machine():
    s = [f'<svg viewBox="0 0 1000 600" class="dg" role="img" aria-label="Block diagram of the 3-wide Tomasulo core">', DEFS]
    for x, lab in [(20, "FRONTEND"), (232, "DECODE"), (380, "RENAME · DISPATCH"), (594, "RESERVATION STATIONS"), (800, "EXECUTE")]:
        s.append(f'<text class="lab" x="{x}" y="22">{lab}</text>')
    # frontend
    s.append(box(20, 40, 170, 44, "Instruction memory", "64 words · 3 instr/cycle"))
    s.append(box(20, 104, 170, 40, "Fetch register ×3"))
    s.append(box(20, 164, 170, 44, "Instruction queue", "16 entries"))
    s.append(box(20, 228, 170, 40, "Fetch→decode latch"))
    s.append(box(20, 312, 170, 80, "Branch predictor", "BTB 64×4 · gshare 1K", cls="bx dim"))
    s.append('<text class="ts" x="105" y="378" text-anchor="middle">RAS 16 · BPQ 16</text>')
    s.append(arrow(105, 84, 105, 102)); s.append(arrow(105, 144, 105, 162)); s.append(arrow(105, 208, 105, 226))
    s.append(path("M190,124 C214,124 214,330 192,330", "ln dash"))
    s.append('<text class="ts" x="186" y="300" text-anchor="end">predecode</text>')
    # decode
    s.append(box(232, 196, 120, 104, "Decode ×3", "op key · imm · type"))
    s.append(arrow(190, 248, 230, 248))
    # rename
    s.append(box(380, 60, 180, 50, "RAT", "32 regs → ROB tag"))
    s.append(box(380, 130, 180, 200, "", cls="bx acc"))
    s.append('<text class="t" x="470" y="160" text-anchor="middle">Reorder buffer</text>')
    s.append('<text class="ts" x="470" y="178" text-anchor="middle">48 entries · holds results</text>')
    for i in range(8):
        y = 194 + i * 15
        s.append(f'<rect class="cell{" on" if i in (2,3,4,5) else ""}" x="394" y="{y}" width="110" height="12" rx="1"/>')
    s.append('<text class="ts" x="508" y="233">◂ commit</text>')
    s.append('<text class="ts" x="508" y="278">◂ alloc</text>')
    s.append(box(232, 340, 120, 50, "Arch. RF", "32 × 32 bit"))
    s.append(arrow(352, 248, 378, 248))
    s.append(path("M380,310 C366,310 366,365 354,365"))
    s.append('<text class="ts" x="292" y="410" text-anchor="middle">commit ×3, in order</text>')
    # RS group + dispatch trunk
    s.append('<rect class="bx ghost" x="584" y="50" width="180" height="210" rx="4" style="stroke:var(--signal)"/>')
    s.append(box(594, 60, 160, 50, "ALU RS", "12 entries"))
    s.append(box(594, 130, 160, 50, "MUL/DIV RS", "4 entries"))
    s.append(box(594, 200, 160, 50, "Load/store buffer", "16 entries"))
    s.append('<line class="ln" x1="560" y1="230" x2="574" y2="230"/><line class="ln" x1="574" y1="85" x2="574" y2="230"/>')
    s.append(arrow(574, 85, 592, 85)); s.append(arrow(574, 155, 592, 155)); s.append(arrow(574, 225, 592, 225))
    # FUs
    s.append(box(800, 46, 180, 30, "ALU ×3 · 1 cycle"))
    s.append(box(800, 84, 180, 30, "ALU", cls="bx ghost", tcls="tm"))
    s.append(box(800, 124, 180, 46, "MUL ×2 · DIV ×2", "Booth 3 st · radix-8 11 st"))
    s.append(box(800, 190, 180, 100, "", cls="bx"))
    s.append('<text class="t" x="890" y="214" text-anchor="middle">Memory unit</text>')
    s.append('<text class="ts" x="890" y="232" text-anchor="middle">LQ 8 · SQ 8</text>')
    s.append('<text class="ts" x="890" y="248" text-anchor="middle">2 load ports · 1 store port</text>')
    s.append('<text class="ts" x="890" y="264" text-anchor="middle">data memory 1024 words</text>')
    s.append('<text class="ts" x="890" y="280" text-anchor="middle">drains senior stores</text>')
    s.append(arrow(754, 85, 798, 61)); s.append(arrow(754, 155, 798, 147)); s.append(arrow(754, 225, 798, 237))
    # completion buffer + CDB
    s.append(box(800, 330, 180, 50, "Completion buffer", "48 entries · 9 inputs", cls="bx acc"))
    s.append(path("M980,61 C996,61 996,340 982,345")); s.append(path("M980,147 C992,147 992,345 982,350")); s.append(path("M980,240 C988,240 988,350 982,355"))
    s.append('<rect class="bus" x="440" y="430" width="540" height="14" rx="2"/>')
    s.append('<text class="tb" x="710" y="466" text-anchor="middle">CDB · 3 results per cycle (tag + value)</text>')
    s.append(arrow(890, 380, 890, 428, "ln sig"))
    s.append(path("M674,430 L674,262", "ln sig")); s.append('<text class="tsig" x="682" y="300">wakeup: every waiting</text><text class="tsig" x="682" y="316">operand in every RS</text>')
    s.append(path("M470,430 L470,332", "ln sig")); s.append('<text class="tsig" x="478" y="400">writeback</text>')
    # flush (not implemented)
    s.append(path("M400,330 L400,560 L30,560 L30,394", "ln dash"))
    s.append('<text class="ts" x="215" y="580" text-anchor="middle">branch resolution / flush: NOT IMPLEMENTED (capstone)</text>')
    s.append('</svg>')
    return wrap(''.join(s), "The core as built: every number is a real parameter from <code>design.sv</code> / <code>tomasulo_pkg.sv</code>. Blue paths are the CDB: one broadcast writes the ROB and wakes up every waiting operand.", 820, "Fig 0.1")

def fetch():
    s = [f'<svg viewBox="0 0 900 210" class="dg" role="img" aria-label="Fetch pipeline with back-pressure">', DEFS]
    xs = [(20, "PC register", "fetch_pc_mux_d"), (190, "Instr memory", "→ fetch_reg ×3"), (360, "Instruction queue", "16 entries"), (530, "Fetch→decode latch", "fec_dec_latch"), (700, "Decode → alloc", "alloc_rdy")]
    for x, a, b in xs:
        s.append(box(x, 50, 150, 54, a, b))
    for i in range(4):
        x = xs[i][0] + 150
        s.append(arrow(x, 77, x + 18, 77))
    # ready path
    s.append(path("M775,104 C775,150 455,150 435,108", "ln bad"))
    s.append('<text class="tbad" x="600" y="146" text-anchor="middle">ready (alloc_stall) — back-pressure</text>')
    s.append(path("M435,104 C435,175 265,175 265,108", "ln bad"))
    s.append('<text class="tbad" x="350" y="190" text-anchor="middle">IQ full → imem_stall</text>')
    s.append('<rect class="callout" x="20" y="120" width="150" height="62" rx="3"/>')
    s.append('<text class="tbad" x="95" y="142" text-anchor="middle">bug B09: PC never</text>')
    s.append('<text class="tbad" x="95" y="158" text-anchor="middle">sees the stall → it</text>')
    s.append('<text class="tbad" x="95" y="174" text-anchor="middle">skips whole bundles</text>')
    s.append('</svg>')
    return wrap(''.join(s), "Two back-pressure paths. Each stage must hold its data <i>and</i> its state when the next stage says no. The original PC register ignored both.", 760, "Fig 1.1")

def formats():
    W = 24; X0 = 110
    rows = [("R", [(31, 25, "funct7", "k"), (24, 20, "rs2", ""), (19, 15, "rs1", ""), (14, 12, "f3", ""), (11, 7, "rd", ""), (6, 0, "opcode", "")]),
            ("I", [(31, 20, "imm[11:0]", "x"), (19, 15, "rs1", ""), (14, 12, "f3", ""), (11, 7, "rd", ""), (6, 0, "opcode", "")]),
            ("S", [(31, 25, "imm[11:5]", "x"), (24, 20, "rs2", ""), (19, 15, "rs1", ""), (14, 12, "f3", ""), (11, 7, "imm[4:0]", ""), (6, 0, "opcode", "")]),
            ("B", [(31, 25, "imm[12|10:5]", "x"), (24, 20, "rs2", ""), (19, 15, "rs1", ""), (14, 12, "f3", ""), (11, 7, "imm[4:1|11]", ""), (6, 0, "opcode", "")])]
    s = [f'<svg viewBox="0 0 {X0 + 32*W + 20} 300" class="dg" role="img" aria-label="RISC-V instruction formats">', DEFS]
    xb = X0 + (31 - 31) * W
    s.append(f'<rect class="hl" x="{xb-3}" y="34" width="{7*W+6}" height="{4*44+8}" rx="3"/>')
    for b in (31, 25, 24, 20, 19, 15, 14, 12, 11, 7, 6, 0):
        s.append(f'<text class="ts" x="{X0 + (31-b)*W + W/2}" y="26" text-anchor="middle">{b}</text>')
    for r, (name, fields) in enumerate(rows):
        y = 40 + r * 44
        s.append(f'<text class="t" x="{X0-16}" y="{y+24}" text-anchor="end">{name}-type</text>')
        for hi, lo, lab, kind in fields:
            x = X0 + (31 - hi) * W; w = (hi - lo + 1) * W
            cls = "bx" + (" key" if kind == "k" else " imm" if kind == "x" else "")
            s.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="34" rx="2"/>')
            s.append(f'<text class="tm2" x="{x + w/2}" y="{y+22}" text-anchor="middle">{lab}</text>')
    s.append(f'<text class="tbad" x="{X0}" y="{40+4*44+28}">op key = {{instr[31:25], funct3, opcode}} → bits 31:25 are funct7 only in R-type.</text>')
    s.append(f'<text class="tbad" x="{X0}" y="{40+4*44+46}">addi x1,x0,100 puts imm bits there → key 0x00c13 → "OTHER" → no RS → deadlock (B01).</text>')
    s.append('</svg>')
    return wrap(''.join(s), "Same bit positions, different meaning per format. The highlighted column is what the original decoder fed into the operation key for every instruction.", 760, "Fig 2.1")

def rob():
    cx, cy, R1, R2 = 210, 200, 150, 110
    tail, head = 40, 6
    s = [f'<svg viewBox="0 0 900 400" class="dg" role="img" aria-label="Circular reorder buffer with commit and allocation pointers">', DEFS]
    for i in range(48):
        a0 = -math.pi/2 + 2*math.pi*i/48; a1 = -math.pi/2 + 2*math.pi*(i+1)/48 - 0.012
        p = lambda r, a: (cx + r*math.cos(a), cy + r*math.sin(a))
        x1, y1 = p(R1, a0); x2, y2 = p(R1, a1); x3, y3 = p(R2, a1); x4, y4 = p(R2, a0)
        live = (i - tail) % 48 < (head - tail) % 48
        s.append(f'<path class="seg{" on" if live else ""}" d="M{x1:.1f},{y1:.1f} A{R1},{R1} 0 0 1 {x2:.1f},{y2:.1f} L{x3:.1f},{y3:.1f} A{R2},{R2} 0 0 0 {x4:.1f},{y4:.1f} Z"/>')
        if i % 6 == 0 or i in (tail, head, 3, 44):
            lx, ly = p(R1 + 16, (a0+a1)/2)
            s.append(f'<text class="ts" x="{lx:.1f}" y="{ly+4:.1f}" text-anchor="middle">{i}</text>')
    def ptr(i, lab, cls):
        a = -math.pi/2 + 2*math.pi*(i+0.5)/48
        x1, y1 = cx + (R2-48)*math.cos(a), cy + (R2-48)*math.sin(a)
        x2, y2 = cx + (R2-4)*math.cos(a), cy + (R2-4)*math.sin(a)
        return f'<line class="{cls}" x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" marker-end="url(#ah)"/>' + \
               f'<text class="t" x="{x1 - 6*math.cos(a):.1f}" y="{y1 - 8*math.sin(a)+4:.1f}" text-anchor="middle">{lab}</text>'
    s.append(ptr(tail, "commit", "ln acc")); s.append(ptr(head, "alloc", "ln sig"))
    s.append(f'<text class="tm" x="{cx}" y="{cy+4}" text-anchor="middle">48 entries</text>')
    tx = 420
    lines = [("t", "Live window: tail = 40 → head = 6 (wrapped)"),
             ("ts", "ROB_tail is the commit pointer, ROB_head the allocation pointer"),
             ("ts", "(this code swaps the usual names)."),
             ("t", ""),
             ("t", "Which is older, tag 44 or tag 3?"),
             ("tbad", "raw compare:  3 < 44  →  'tag 3 is older'   ✗"),
             ("tok", "age(t) = (t − tail) mod 48"),
             ("tok", "age(44) = 4,  age(3) = 11  →  tag 44 is older   ✓"),
             ("t", ""),
             ("ts", "Bugs B07 and B13 used raw compares. Raw compares in"),
             ("ts", "alu_top / mul_div_top select only affect fairness here.")]
    for k, (c, txt) in enumerate(lines):
        s.append(f'<text class="{c}" x="{tx}" y="{80 + k*24}">{txt}</text>')
    s.append('</svg>')
    return wrap(''.join(s), "The ROB is circular, so a tag is a <i>name</i>, not an age. Age is always the distance from the commit pointer.", 760, "Fig 3.1")

def wave(rows, ncyc, title_x=150, cw=56, y0=40, rh=36):
    out = []
    for c in range(ncyc + 1):
        x = title_x + c * cw
        out.append(f'<line class="grid" x1="{x}" y1="{y0-10}" x2="{x}" y2="{y0 + len(rows)*rh}"/>')
        if c < ncyc:
            out.append(f'<text class="ts" x="{x + cw/2}" y="{y0-14}" text-anchor="middle">{c}</text>')
    for r, (name, kind, vals) in enumerate(rows):
        y = y0 + r * rh
        out.append(f'<text class="t" x="{title_x-10}" y="{y+18}" text-anchor="end">{name}</text>')
        if kind == "clk":
            d = ""
            for c in range(ncyc):
                x = title_x + c*cw
                d += f"M{x},{y+26} L{x},{y+6} L{x+cw/2},{y+6} L{x+cw/2},{y+26} L{x+cw},{y+26} "
            out.append(f'<path class="wv" d="{d}"/>')
        elif kind == "bit":
            d = f"M{title_x},{y+26 if not vals[0] else y+6}"
            for c, v in enumerate(vals):
                x = title_x + c*cw; yy = y+6 if v else y+26
                d += f" L{x},{yy} L{x+cw},{yy}"
            out.append(f'<path class="wv" d="{d}"/>')
        else:  # bus with labels
            for c, v in enumerate(vals):
                x = title_x + c*cw
                if v:
                    out.append(f'<path class="wvbus" d="M{x+4},{y+16} L{x+10},{y+6} L{x+cw-10},{y+6} L{x+cw-4},{y+16} L{x+cw-10},{y+26} L{x+10},{y+26} Z"/>')
                    out.append(f'<text class="tm2" x="{x+cw/2}" y="{y+20}" text-anchor="middle">{v}</text>')
                else:
                    out.append(f'<line class="wv" x1="{x}" y1="{y+16}" x2="{x+cw}" y2="{y+16}"/>')
    return ''.join(out)

def wakeup():
    s = [f'<svg viewBox="0 0 860 440" class="dg" role="img" aria-label="Wakeup and select timing, this design vs ideal">', DEFS]
    s.append('<text class="lab" x="20" y="22">THIS DESIGN — 2 CYCLES PER DEPENDENT ADD</text>')
    s.append(wave([("clk", "clk", None),
                   ("CDB tag", "bus", ["", "ROB1", "", "ROB2", "", "ROB3"]),
                   ("ROB2 src_valid", "bit", [0, 0, 1, 1, 1, 1]),
                   ("ROB2 ready", "bit", [0, 0, 0, 1, 0, 0]),
                   ("issue (select)", "bus", ["", "", "", "ROB2", "", "ROB3"])], 6, y0=50))
    s.append('<text class="lab" x="20" y="262">IDEAL — WAKEUP AND SELECT IN THE SAME CYCLE</text>')
    s.append(wave([("clk", "clk", None),
                   ("CDB tag", "bus", ["", "ROB1", "ROB2", "ROB3", "ROB4", ""]),
                   ("issue (select)", "bus", ["", "ROB2", "ROB3", "ROB4", "ROB5", ""])], 6, y0=290))
    s.append('<text class="ts" x="500" y="420">ready = src_valid_reg | (src_tag == cdb_tag)   — combinational into select</text>')
    s.append('</svg>')
    return wrap(''.join(s), "Measured on <code>b12_raw_chain</code>: dependent results reach the CDB at cycles 9, 11, 13, 15. The extra cycle is the registered <code>ready</code> bit (alloc_reorder_retire.sv:1186). Exercise E4 removes it.", 760, "Fig 4.1")

def lsq():
    s = [f'<svg viewBox="0 0 900 380" class="dg" role="img" aria-label="Load issue decision tree">', DEFS]
    s.append(box(330, 20, 240, 46, "Load in LQ, address known", "can it issue this cycle?", cls="bx acc"))
    s.append(box(330, 100, 240, 46, "Any OLDER store still in LSB?", "(address or data unknown)"))
    s.append(box(640, 100, 220, 46, "WAIT", "store may alias", cls="bx warn", tcls="t"))
    s.append(box(330, 180, 240, 52, "Youngest older overlapping", "SQ store not yet in memory?"))
    s.append(box(40, 180, 220, 52, "READ MEMORY", "no older store in the way", cls="bx ok"))
    s.append(box(330, 270, 240, 52, "Same address and", "store size ≥ load size?"))
    s.append(box(640, 270, 220, 52, "FORWARD", "byte-select + sign/zero extend", cls="bx ok"))
    s.append(box(40, 270, 220, 52, "WAIT", "partial overlap → let it drain", cls="bx warn"))
    s.append(arrow(450, 66, 450, 98))
    s.append(arrow(570, 123, 638, 123)); s.append('<text class="ts" x="604" y="116" text-anchor="middle">yes</text>')
    s.append(arrow(450, 146, 450, 178)); s.append('<text class="ts" x="462" y="168">no</text>')
    s.append(arrow(330, 206, 262, 206)); s.append('<text class="ts" x="296" y="199" text-anchor="middle">none</text>')
    s.append(arrow(450, 232, 450, 268)); s.append('<text class="ts" x="462" y="256">found</text>')
    s.append(arrow(570, 296, 638, 296)); s.append('<text class="ts" x="604" y="289" text-anchor="middle">yes</text>')
    s.append(arrow(330, 296, 262, 296)); s.append('<text class="ts" x="296" y="289" text-anchor="middle">no</text>')
    s.append('<text class="ts" x="40" y="360">"Older" = smaller age (tag − commit ptr) mod 48. A senior store (retired, not yet written) is older than every load (bug B13c).</text>')
    s.append('</svg>')
    return wrap(''.join(s), "The conservative load-issue policy in <code>solutions/memory_management_unit.sv</code>. The original had none of the left-hand checks.", 760, "Fig 8.1")

def vflow():
    s = [f'<svg viewBox="0 0 900 250" class="dg" role="img" aria-label="Verification flow">', DEFS]
    s.append(box(20, 30, 170, 44, "Directed tests", "tests/b01…b19.s"))
    s.append(box(20, 94, 170, 44, "Random generator", "tools/gen_random.py"))
    s.append(box(240, 62, 140, 44, "Assembler", "tools/rv.py"))
    s.append(box(430, 30, 200, 120, "", cls="bx acc"))
    s.append('<text class="t" x="530" y="58" text-anchor="middle">DUT: top_module</text>')
    s.append('<rect class="bx dim" x="450" y="72" width="160" height="30" rx="2"/><text class="ts" x="530" y="92" text-anchor="middle">SVA via bind (A1–A7)</text>')
    s.append('<rect class="bx dim" x="450" y="108" width="160" height="30" rx="2"/><text class="ts" x="530" y="128" text-anchor="middle">commit monitor</text>')
    s.append(box(240, 180, 140, 44, "Golden ISS", "tools/rv.py"))
    s.append(box(680, 100, 200, 60, "Scoreboard", "order · value · ARF · mem · hang"))
    s.append(arrow(190, 52, 238, 80)); s.append(arrow(190, 116, 238, 90))
    s.append(arrow(380, 84, 428, 84)); s.append('<text class="ts" x="404" y="76" text-anchor="middle">hex</text>')
    s.append(path("M310,106 L310,178"))
    s.append(arrow(630, 123, 678, 123)); s.append('<text class="ts" x="654" y="116" text-anchor="middle">trace</text>')
    s.append(path("M380,202 C560,202 700,202 760,162"))
    s.append('<text class="ts" x="560" y="196" text-anchor="middle">expected commit stream</text>')
    s.append('</svg>')
    return wrap(''.join(s), "The lab flow. The contract checked is the one an ISA promises: the committed stream and memory equal a sequential machine's.", 760, "Fig 9.1")

def bars(stages):
    s = [f'<svg viewBox="0 0 640 260" class="dg" role="img" aria-label="Random programs passing per fix stage">', DEFS]
    X0, Y0, H, BW = 70, 30, 170, 90
    for v in (0, 30, 60, 90, 120):
        y = Y0 + H - v/120*H
        s.append(f'<line class="grid" x1="{X0}" y1="{y}" x2="620" y2="{y}"/><text class="ts" x="{X0-8}" y="{y+4}" text-anchor="end">{v}</text>')
    for i, (lab, v) in enumerate(stages):
        x = X0 + 20 + i * 135; h = v/120*H
        s.append(f'<rect class="bar{" full" if v == 120 else ""}" x="{x}" y="{Y0+H-h}" width="{BW}" height="{max(h,1.5)}" rx="2"/>')
        s.append(f'<text class="t" x="{x+BW/2}" y="{Y0+H-h-8}" text-anchor="middle">{v}</text>')
        s.append(f'<text class="ts" x="{x+BW/2}" y="{Y0+H+20}" text-anchor="middle">{lab}</text>')
    s.append(f'<text class="ts" x="{X0}" y="{Y0-12}">random programs passing (of 120; the final core also passes 720/720)</text>')
    s.append('</svg>')
    return wrap(''.join(s), "After every directed test passed, 79 of 120 random programs still failed. The last four bugs were found only by random stimulus.", 560, "Fig 9.2")
