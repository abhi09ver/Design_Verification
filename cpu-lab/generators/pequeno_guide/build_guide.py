# -*- coding: utf-8 -*-
# "Pequeno Study Guide" - companion to Chipmunk Logic's Pequeno RISC-V series (parts 1-6),
# continued to a complete, verified 5-stage CPU (pq5). All numbers/pictures come from real sims.
import html, os, re, sys
E = html.escape
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = lambda *p: os.path.join(ROOT, *p)
RTL = open(B('rtl', 'pq5.sv')).read()
BEGINNER_URL = "https://claude.ai/artifact/8kK4bF4PwfrWMHBTA6bfpQ"
ADV_URL = "https://claude.ai/artifact/7uWYxRU5pbYHEWq7JPc63b"
SRC = "https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-"
POSTS = {1: SRC + "part-1-getting-hold-of-the-isa/", 2: SRC + "part-2-specifications-and-architecture/",
         3: SRC + "part-3-dealing-with-pipeline-hazards/", 4: SRC + "part-4-fetch-unit/",
         5: SRC + "part-5-decode-unit/", 6: SRC + "part-6-register-file/"}

def module(name):
    m = re.search(rf'(// =+\n// PART[^\n]*\n(?:// [^\n]*\n)*// =+\n)?(module {name}\b.*?endmodule)', RTL, re.S)
    return m.group(2)

REG = [l for l in open(B('build', 'regress.txt')).read().splitlines() if l.startswith('[PASS]')]
MUT = open(B('build', 'mutation.txt')).read().splitlines()

def pipe_rows(fname, first=None, last=None):
    rows = []
    for l in open(B('build', fname)).read().splitlines():
        m = re.match(r'PIPE\s+(\d+) \| IF (\w+) \| ID (.+?) \| EX (.+?) \| MEM (.+?) \| WB (.+?) \|(.*)', l)
        if m: rows.append((int(m[1]), [m[2].strip(), m[3].strip(), m[4].strip(), m[5].strip(), m[6].strip()], m[7].strip()))
    if first: rows = [r for r in rows if first <= r[0] <= last]
    return rows

def pipe_svg(fname, names, first=None, last=None, label=""):
    rows = pipe_rows(fname, first, last)
    CW, RH, X0 = 54, 30, 70
    stages = ["IF", "ID", "EX", "MEM", "WB"]
    o = [f'<svg viewBox="0 0 {X0 + len(rows)*CW + 10} {40 + 5*RH + 40}" class="pic" role="img" aria-label="{E(label)}">']
    for i, (c, st, ev) in enumerate(rows):
        x = X0 + i*CW
        o.append(f'<text class="s" x="{x+CW/2}" y="18" text-anchor="middle">c{c}</text>')
        for k, v in enumerate(st):
            y = 26 + k*RH
            if v in ('-', ''):
                o.append(f'<rect class="bub" x="{x+2}" y="{y}" width="{CW-4}" height="{RH-4}" rx="5"/><text class="s" x="{x+CW/2}" y="{y+18}" text-anchor="middle">bubble</text>')
            else:
                pc = int(v, 16); nm = names.get(pc, f'{pc:x}'); nm = nm if len(nm) <= 8 else nm[:7] + '…'
                o.append(f'<rect class="ins i{(pc//4) % 6}" x="{x+2}" y="{y}" width="{CW-4}" height="{RH-4}" rx="5"/><text class="m" x="{x+CW/2}" y="{y+18}" text-anchor="middle">{E(nm)}</text>')
        if ev:
            cls = 'evs' if 'STALL' in ev else 'evf'
            o.append(f'<text class="{cls}" x="{x+CW/2}" y="{26+5*RH+16}" text-anchor="middle">{"STALL" if "STALL" in ev else "FLUSH"}</text>')
    for k, s in enumerate(stages):
        o.append(f'<text class="t" x="{X0-10}" y="{26+k*RH+18}" text-anchor="end">{s}</text>')
    o.append('</svg>')
    return f'<div class="picbox"><div style="min-width:{X0 + len(rows)*CW}px">{"".join(o)}</div></div>'

def names_of(prog):
    sys.path.insert(0, B('tools')); from rv32i import parse
    p, _ = parse(open(B('tests', prog)).read().splitlines())
    return {pc: s.split()[0] + ('' if len(s.split()) == 1 else ' ' + s.split()[1].rstrip(',')) for pc, _, _, s in p}

# ----------------------------------------------------------------------------------- pictures
ARROW = '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0L10,5L0,10z" class="ah"/></marker></defs>'
def rb(x, y, w, h, t, s="", c="b"):
    o = f'<rect class="{c}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>'
    if s: return o + f'<text class="t" x="{x+w/2}" y="{y+h/2-3}" text-anchor="middle">{t}</text><text class="s" x="{x+w/2}" y="{y+h/2+15}" text-anchor="middle">{s}</text>'
    return o + f'<text class="t" x="{x+w/2}" y="{y+h/2+5}" text-anchor="middle">{t}</text>'
def ar(x1, y1, x2, y2, c="l"): return f'<line class="{c}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" marker-end="url(#a)"/>'
def pth(d, c="l"): return f'<path class="{c}" d="{d}" marker-end="url(#a)"/>'
def wrapsvg(body, vb, minw, label): return f'<div class="picbox"><div style="min-width:{minw}px"><svg viewBox="{vb}" class="pic" role="img" aria-label="{label}">{ARROW}{body}</svg></div></div>'

def pic_formats():
    W, X0 = 22, 90
    rows = [("R", [(31,25,"funct7",""),(24,20,"rs2",""),(19,15,"rs1",""),(14,12,"f3",""),(11,7,"rd",""),(6,0,"opcode","")]),
            ("I", [(31,20,"imm[11:0]","i"),(19,15,"rs1",""),(14,12,"f3",""),(11,7,"rd",""),(6,0,"opcode","")]),
            ("S", [(31,25,"imm[11:5]","i"),(24,20,"rs2",""),(19,15,"rs1",""),(14,12,"f3",""),(11,7,"imm[4:0]","i"),(6,0,"opcode","")]),
            ("B", [(31,31,"12","i"),(30,25,"imm[10:5]","i"),(24,20,"rs2",""),(19,15,"rs1",""),(14,12,"f3",""),(11,8,"[4:1]","i"),(7,7,"11","i"),(6,0,"opcode","")]),
            ("U", [(31,12,"imm[31:12]","i"),(11,7,"rd",""),(6,0,"opcode","")]),
            ("J", [(31,31,"20","i"),(30,21,"imm[10:1]","i"),(20,20,"11","i"),(19,12,"imm[19:12]","i"),(11,7,"rd",""),(6,0,"opcode","")])]
    o = []
    for b in (31, 25, 20, 15, 12, 7, 0):
        o.append(f'<text class="s" x="{X0+(31-b)*W+W/2}" y="16" text-anchor="middle">{b}</text>')
    for r, (n, f) in enumerate(rows):
        y = 24 + r*40
        o.append(f'<text class="t" x="{X0-12}" y="{y+21}" text-anchor="end">{n}-type</text>')
        for hi, lo, lab, k in f:
            x = X0+(31-hi)*W; w = (hi-lo+1)*W
            o.append(f'<rect class="{"imm" if k else "fld"}" x="{x}" y="{y}" width="{w}" height="30" rx="4"/><text class="m" x="{x+w/2}" y="{y+20}" text-anchor="middle">{lab}</text>')
    o.append(f'<text class="s" x="{X0}" y="{24+6*40+14}">Pink = immediate bits. rs1, rs2, rd and opcode never move. Bit 31 is always the sign of the immediate.</text>')
    return wrapsvg(''.join(o), f"0 0 {X0+32*W+10} {24+6*40+26}", 760, "RISC-V instruction formats R I S B U J")

def pic_pipeline():
    o = []
    st = [("IF", "fetch", "PC → instruction"), ("ID", "decode", "fields + regs"), ("EX", "execute", "ALU · branch"), ("MEM", "memory", "load / store"), ("WB", "writeback", "→ register")]
    for i, (a, b, c) in enumerate(st):
        x = 20 + i*150
        o.append(rb(x, 70, 120, 64, a + " · " + b, c, "b"))
        if i < 4: o.append(f'<rect class="preg" x="{x+124}" y="60" width="18" height="84" rx="3"/>')
        if i < 4: o.append(ar(x+120, 102, x+122, 102))
    for i, n in enumerate(["IF/ID", "ID/EX", "EX/MEM", "MEM/WB"]):
        o.append(f'<text class="s" x="{20+i*150+133}" y="54" text-anchor="middle">{n}</text>')
    o.append(pth("M440,134 C440,190 650,190 650,134", "l fw")); o.append(pth("M440,134 C440,215 800,215 800,134", "l fw"))
    o.append('<text class="fwT" x="560" y="232" text-anchor="middle">forwarding: newest value back into EX</text>')
    o.append(pth("M320,60 C320,22 120,22 80,66", "l st")); o.append('<text class="stT" x="210" y="22" text-anchor="middle">stall (load-use)</text>')
    o.append(pth("M380,60 C380,8 60,8 50,66", "l fl")); o.append('<text class="flT" x="470" y="20">flush + new PC (wrong guess)</text>')
    o.append(pth("M800,70 C800,40 300,40 270,66", "l")); o.append('<text class="s" x="560" y="50" text-anchor="middle">register write</text>')
    return wrapsvg(''.join(o), "0 0 780 245", 760, "five-stage pipeline with forwarding, stall and flush")

def pic_bytes():
    o = []
    vals = ["7F", "01", "FF", "80"]
    for i in range(4):
        o.append(f'<rect class="fld" x="{240-i*70}" y="40" width="64" height="44" rx="6"/><text class="t" x="{272-i*70}" y="68" text-anchor="middle">{vals[i]}</text><text class="s" x="{272-i*70}" y="102" text-anchor="middle">addr {16+i}</text>')
    o.append('<text class="s" x="30" y="30">word at address 16 = 0x80FF017F  (little-endian: the LOW byte lives at the LOW address)</text>')
    rows = [("lb  addr 18", "FF → 0xFFFFFFFF (-1)"), ("lbu addr 18", "FF → 0x000000FF (255)"), ("lh  addr 18", "80FF → 0xFFFF80FF"), ("lhu addr 18", "80FF → 0x000080FF")]
    for i, (a, b) in enumerate(rows):
        o.append(f'<text class="m" x="360" y="{46+i*22}">{a}</text><text class="m" x="470" y="{46+i*22}">{b}</text>')
    return wrapsvg(''.join(o), "0 0 720 120", 640, "little-endian bytes with signed and unsigned loads")

# ----------------------------------------------------------------------------------- content
def regtable():
    rows = []
    for l in REG:
        m = re.match(r'\[PASS\] (\S+)\s+(\d+) instr\s+(\d+) cycles\s+CPI\s+([\d.]+)\s+\(load-use stalls (\d+), flushes (\d+)\)', l)
        n, i, c, cpi, s, f = m.groups(); i, c, s, f = int(i), int(c), int(s), int(f)
        rows.append(f'<tr><td><code>{n}</code></td><td>{i}</td><td>{s}</td><td>{f}</td><td>4 + {i} + {s} + 2×{f} = <b>{4+i+s+2*f}</b></td><td>{c}</td><td>{cpi}</td></tr>')
    return ('<div class="tablewrap"><table class="tt"><thead><tr><th>program</th><th>instructions N</th><th>load-use stalls</th><th>flushes</th><th>predicted cycles</th><th>measured</th><th>CPI</th></tr></thead><tbody>'
            + ''.join(rows) + '</tbody></table></div>')

def muttable():
    rows = []
    for l in MUT:
        m = re.match(r'(.+?)\s+directed fails:\s+(\d+)/10 (\S*)\s+random fails:\s+(\d+)/100(.*)', l)
        name, d, which, r, extra = m.groups()
        verdict = ('<span class="pill ok">only slower</span>' if name.startswith('PERF') else
                   '<span class="pill warn">survives</span>' if d == '0' and r == '0' else '<span class="pill bad">caught</span>')
        rows.append(f'<tr><td>{E(name.replace("PERF: ",""))}</td><td>{d}/10</td><td>{r}/100</td><td>{verdict}{E(extra.strip())}</td></tr>')
    return ('<div class="tablewrap"><table class="tt"><thead><tr><th>remove this from the RTL…</th><th>directed tests failing</th><th>random programs failing</th><th>result</th></tr></thead><tbody>'
            + ''.join(rows) + '</tbody></table></div>')

PARTS = [
 dict(n=1, title="Getting hold of the ISA", tag="RV32I · formats · the assembler",
  summary="Picks RISC-V's base integer ISA (RV32I: 37 instructions, 32 registers, x0 = 0), explains why a standard ISA beats inventing one, groups instructions into six formats (R, I, S, B, U, J), and introduces the author's own assembler.",
  kid="An ISA is the <b>menu</b> a CPU promises to understand. Every dish (instruction) is written on a 32-box order slip in one of six layouts. The kitchen only has to learn those six layouts. The cleverness: the boxes that say <i>which</i> registers (rs1, rs2, rd) are in the same place on every slip, so the kitchen can start fetching ingredients before it has finished reading the order.",
  pic=pic_formats,
  ours="<code>tools/rv32i.py</code> is a ~200-line assembler with <b>labels</b> (so you can write <code>bne x1, x0, loop</code>) plus a golden instruction-set simulator for all 37 instructions. <code>halt</code> is <code>jal x0, 0</code> (jump to yourself), the usual bare-metal \"stop here\". The encoder was checked against known encodings before any program was written.",
  hidden=[("Why are B and J immediates scrambled?", "So that every immediate bit sits in the same instruction bit across formats as often as possible (bit 31 is always the sign). The hardware then needs fewer multiplexers. Software (the assembler) pays the cost of shuffling once."),
          ("No multiply in RV32I", "MUL/DIV live in the M extension. On RV32I you multiply with shift-and-add, as <code>p09_multiply.s</code> does."),
          ("Pseudo-instructions", "<code>nop</code> = <code>addi x0,x0,0</code>, <code>mv</code> = <code>addi rd,rs,0</code>, <code>j</code> = <code>jal x0,…</code>, <code>ret</code> = <code>jalr x0,0(ra)</code>. They cost no hardware.")],
  quiz=[("Where is rs1 in an S-type instruction?", "Bits 19:15, the same as in every other format that has rs1."), ("What does <code>addi x5, x0, -1</code> put in x5?", "0xFFFFFFFF. The 12-bit -1 is sign-extended to 32 bits."), ("Which instruction is a 'free' NOP?", "<code>addi x0, x0, 0</code>. The write to x0 is thrown away.")],
  iq=[("Why is RISC-V popular for teaching and for industry?", "Open and royalty-free, small clean base ISA with optional extensions, fixed 32-bit encoding with register fields in fixed positions (simple decoders), and a big open tool and RTL ecosystem.")]),
 dict(n=2, title="Specifications and architecture", tag="5 stages · valid / stall / flush",
  summary="Sets the spec: 32-bit, RV32I, single-issue, strictly in-order 5-stage pipeline (fetch, decode, execute, memory access, writeback), separate instruction and data memory interfaces, bare-metal (no CSRs, interrupts or exceptions). Each stage hands a packet to the next with a valid bit; stall goes backwards, flush kills older-stage packets.",
  kid="A sandwich shop with one worker does everything for customer 1, then everything for customer 2. Slow. Five workers in a row (take order, read order, make, wrap, hand over) each do one step and pass the tray on. Each customer still takes 5 steps, but a finished sandwich comes out <b>every step</b>. That is pipelining: same latency, 5× the throughput.",
  pic=pic_pipeline,
  ours="pq5 follows the same spec and stage split: one module per stage, a pipeline register between stages, a <code>valid</code> bit in every packet (valid = 0 is a bubble), <code>stall</code> from decode back to fetch, and <code>flush</code> + <code>redirect_pc</code> from execute. Simplifications to stay small: memories are plain arrays (no bus handshake), and fetch has one buffer instead of two.",
  hidden=[("Δ + N − 1", "With Δ = 5 stages and no hazards, N instructions finish in 5 + N − 1 cycles. pq5 measures exactly that: <code>p01_alu</code> has 23 instructions and takes 27 cycles."),
          ("Why not single-cycle?", "The clock must wait for the slowest instruction's whole path (memory + decode + ALU + memory + write). Pipelining cuts that path into 5 short pieces, so the clock can be much faster."),
          ("A stall in one stage stalls everything older", "In-order means nobody may overtake. The instructions <i>behind</i> a stalled one must also hold; the ones ahead keep going, and a bubble appears between them.")],
  quiz=[("A program has 100 instructions and no hazards. How many cycles on a 5-stage pipeline?", "5 + 100 − 1 = 104."), ("What is a bubble?", "A pipeline slot carrying nothing (valid = 0). It moves through the stages like an instruction but changes no state.")],
  iq=[("Throughput vs latency for a pipeline?", "Latency per instruction stays about the same (or grows slightly because of pipeline registers). Throughput approaches 1 instruction per cycle at a higher clock frequency. The cost is area, power and hazards.")]),
 dict(n=3, title="Dealing with pipeline hazards", tag="structural · data · control",
  summary="Classifies hazards. Structural ones are removed by design (split instruction and data memories, a 2-read/1-write register file, local adders). WAR and WAW cannot happen in an in-order pipeline that writes back last. RAW is handled by forwarding, except a load followed immediately by a user, which needs a one-cycle interlock. Control hazards are handled by prediction in fetch plus a flush when execute finds the guess was wrong.",
  kid="<b>RAW</b>: worker 3 needs the sauce worker 4 is still finishing. Instead of waiting for it to be put on the shelf (the register file), worker 4 passes it straight back over the counter: <b>forwarding</b>. <b>Load-use</b>: the sauce comes from the store-room (memory), one step later; no amount of passing helps, so worker 3 waits one beat. <b>Branch</b>: the customer might change their order. We guess and keep working. If the guess was wrong, we throw away the 2 sandwiches started since and start the right one: a <b>flush</b>.",
  pic=None,
  ours="",
  hidden=[("Forwarding only goes forward in time", "A value can be handed to a later instruction if it already exists. A load's value exists only after MEM, one cycle after its neighbour needs it in EX, hence the single bubble."),
          ("Penalty depends on where branches resolve", "pq5 resolves branches in EX, so a wrong guess costs 2 bubbles (the instructions in IF/ID and ID). Resolving in ID would cost 1 but needs a comparator and forwarding into decode."),
          ("CPI = 1 + stall cycles per instruction", "In pq5: cycles = 4 + N + load-use stalls + 2 × flushes. That predicts every measured run exactly (table above).")],
  quiz=[("Why can't WAW happen in an in-order 5-stage pipeline?", "All writes happen in the same stage (WB) in program order, so the later write always lands last."), ("<code>lw x2,0(x0)</code> then <code>add x3,x2,x2</code>. How many bubbles?", "One. With one independent instruction in between: zero."), ("A loop runs 100 times. The backward branch is predicted taken. How many flushes?", "One, on the final exit, when the branch falls through. <code>p04_loop_sum</code> shows exactly 1.")],
  iq=[("Explain forwarding, and where the muxes go.", "Muxes at the ALU inputs in EX choose between the register value read in decode, the result in EX/MEM (distance 1), or the value in MEM/WB (distance 2). The nearest producer wins. Distance 3 is covered by the register file writing before (or through to) the read. Loads in EX/MEM are not forwardable, so an interlock inserts a bubble."),
      ("What happens to CPI with 20% branches, 30% mispredicted, 2-cycle penalty?", "1 + 0.2 × 0.3 × 2 = 1.12, ignoring other stalls.")]),
 dict(n=4, title="Fetch unit", tag="PC · instruction memory · static prediction",
  summary="Fetch sends the PC to instruction memory with a valid/ready-style request, gets {instruction, PC} back, and keeps two buffers. A static predictor looks at buffered instructions: jumps taken, backward branches taken (loops), forward branches not taken. Stall comes only from decode; flush and the correct PC come only from execute. Every stage generates its own stall/flush logic.",
  kid="Fetch is the worker reading the recipe book. It keeps a bookmark (the PC) and normally turns one page. If the recipe says 'go back to step 3' it can turn back right away (a guess). If someone later shouts 'wrong page!', it jumps to the page they name and throws away what it had just read.",
  pic=None, code="pq5_fetch",
  ours="pq5 predicts straight from the instruction memory output in the same cycle: <code>jal</code> taken, backward branch taken, everything else (and <code>jalr</code>) not taken. Flush beats stall. Pequeno puts its predictor behind an extra buffer instead, so the prediction logic is not on the memory-to-PC path. It costs one cycle of startup latency and buys a shorter critical path. pq5 chose simple; a real chip would choose Pequeno's way.",
  hidden=[("The stall must freeze the PC too", "If the PC kept moving while IF/ID was frozen, an instruction would be skipped. This is exactly bug B09 in your out-of-order core. pq5 has an assertion that IF/ID never changes during a stall."),
          ("Why carry the predicted next PC?", "Execute compares the real next PC with what fetch guessed. If they differ, it flushes. That one compare covers wrong direction, wrong target and unpredicted jalr.")],
  quiz=[("Why is a backward branch predicted taken?", "Backward branches usually close loops, and loops usually go round again."), ("Which instruction can't a static predictor guess the target of, and why?", "<code>jalr</code>. Its target is in a register, which fetch doesn't have yet.")],
  iq=[("Static vs dynamic branch prediction?", "Static: a fixed rule from the instruction itself (backward taken), no state, ~60-70% accurate. Dynamic: learns from history (2-bit counters, gshare, TAGE), 90%+, needs tables, update logic and recovery of speculative history.")]),
 dict(n=5, title="Decode unit", tag="fields · immediates · control",
  summary="Decode slices fixed fields (opcode, rs1, rs2, rd, funct3, funct7), builds a type flag per format, an ALU opcode, and the immediate for each format. Source register addresses go to the register file combinationally so the register data and the decoded packet arrive at execute in the same cycle. Only execute can stall or flush decode.",
  kid="Decode is the worker who reads the order slip and writes it out neatly for the cook: which ingredients (registers), how much (immediate), which recipe (ALU operation). It also asks the pantry (register file) for the ingredients right away, so they arrive at the cook together with the instructions.",
  pic=None, code="pq5_decode",
  ours="pq5's decode also hosts the <b>load-use interlock</b>: if the instruction in EX is a load whose destination this instruction reads, decode stalls fetch and sends a bubble forward. Unknown opcodes (fence, ecall) decode to harmless no-ops; <code>rd = x0</code> turns off the write.",
  hidden=[("funct7 is not always funct7", "For OP-IMM, bits 31:25 are immediate bits, except for the shift-immediates, where bit 30 picks srai. Your OOO core put immediate bits into its opcode key (bug B01)."),
          ("'Uses rs2?' matters", "An <code>addi</code> has bits in the rs2 position, but they are immediate bits. Stalling on them would be a false dependency: slow, not wrong. pq5 computes <code>use1</code>/<code>use2</code> per format.")],
  quiz=[("Which formats have no rs1?", "U (lui, auipc) and J (jal)."), ("Why does a store need rs2?", "rs2 holds the data being stored; rs1 holds the base address.")],
  iq=[("Where would you put the load-use detection and why?", "In decode, because the dependent instruction is there when the load is in EX, the last moment you can hold it back cheaply, and holding decode + fetch is simple.")]),
 dict(n=6, title="Register file", tag="2 read · 1 write · x0",
  summary="32 × 32-bit registers, two independent read ports (for rs1 and rs2) used by decode, one write port used by writeback, x0 hard-wired to zero. Reads take one cycle and are registered so the data lines up with decode's packet; during a stall the read enable is turned off so the output holds.",
  kid="32 lockers. Two windows to peek in, one slot to drop things in. Locker 0 is glued shut.",
  pic=None, code="pq5_regfile",
  ours="pq5 reads combinationally in decode, and the values are captured in ID/EX together with the instruction, so a stall simply re-reads next cycle. It adds <b>write-through</b>: if writeback writes the register decode is reading in the same cycle, decode gets the new value.",
  hidden=[("The same-cycle read/write question", "Instruction A in WB writes x5 while instruction D (3 behind) reads x5 in decode. Without write-through or a write-before-read register file, D reads the stale value. Removing write-through from pq5 breaks 7 of 10 directed programs."),
          ("Why stall the register file with decode?", "In Pequeno the read data is registered. If decode freezes but the register file output moves on, the data no longer matches the frozen instruction. pq5 avoids the issue by not registering inside the register file.")],
  quiz=[("How many read ports does a 2-wide superscalar CPU need?", "Four (two sources each). Port count is a big area cost of wide CPUs."), ("Name two ways to make x0 read as zero.", "Guard the read (<code>ra == 0 ? 0 : r[ra]</code>), or guard the write so r[0] is never written (and reset it to 0). pq5 does both.")],
  iq=[("Write-first vs read-first register file?", "Write-first returns the value being written in the same cycle (no extra forwarding path needed for distance 3). Read-first returns the old value, so the pipeline must forward from WB. FPGA block RAMs can be configured either way.")]),
]

EXTRA = [
 dict(n=7, title="Execute unit", tag="beyond Part 6 · forwarding · ALU · branches", code="pq5_execute",
  kid="The cook. Before cooking it checks: is a fresher ingredient being handed back from the next workers? Then it cooks (ALU). For a branch it checks whether fetch's guess was right; if not, it shouts 'wrong page!' (flush) with the right page number.",
  text="Forwarding is two priority checks per operand: the instruction one ahead (EX/MEM) wins over the one two ahead (MEM/WB). The branch unit compares registers, computes the target (<code>pc + imm</code>, or <code>(rs1 + imm) &amp; ~1</code> for jalr), and flushes if the real next PC differs from the predicted one. jal/jalr write the link address pc + 4.",
  hidden=[("Priority order matters", "If two earlier instructions write the same register, the nearer one is newer. Reversing the priority fails only 2 of 10 directed tests and 5 of 100 random programs, an easy bug to miss without targeted tests (p02_forwarding writes x5 three times in a row on purpose)."),
          ("jalr clears bit 0", "The spec says the target is (rs1 + imm) with the lowest bit cleared.")]),
 dict(n=8, title="Memory access and writeback", tag="beyond Part 6 · bytes · little-endian", code="pq5_mem",
  kid="Wrapping and handing over. A load reads from the store-room; a store puts something in it. Some orders want only one byte or half a word, so the worker picks the right part of the box and fills the rest with the sign (lb, lh) or with zeros (lbu, lhu).",
  text="Data memory is word-addressed internally. The byte offset <code>addr[1:0]</code> shifts the wanted byte or half down to bit 0 for loads, and selects the byte lanes for stores. Writeback is just the register file's write port fed from MEM/WB.",
  hidden=[("Stores write in MEM, not WB", "pq5 has no exceptions, so a store in MEM is certain to complete. In a CPU with precise exceptions, a store must not write memory before every older instruction is known to be safe. That is why your OOO core keeps stores in a store queue until commit.")]),
]

CSS = r'''
/* layout: study guide — a numbered part index (it IS a sequence), then one card per part.
   Same family as the beginner track (CPU From Zero), with a slate-blue accent for this series. */
:root{
  --bg:#F4F6F9; --card:#FFFFFF; --ink:#17202B; --ink2:#3A4655; --muted:#647184; --line:#D8DEE6;
  --acc:#2F5DA8; --acc-soft:#E2EAF7; --sun:#D99A12; --sun-soft:#FBEFD0; --coral:#C9503C; --coral-soft:#F9E1DC;
  --leaf:#3B8A46; --leaf-soft:#DFF0E2; --code:#ECF0F5;
  --i0:#DCE8F8; --i1:#E3F2E1; --i2:#FBEFD0; --i3:#F3E2F2; --i4:#DDF1F0; --i5:#F9E1DC;
  --f-display:"Fredoka", "Trebuchet MS", system-ui, sans-serif;
  --f-body:"Nunito Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
  --f-mono:"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace;
}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){
  --bg:#10151C; --card:#18202A; --ink:#E5EBF2; --ink2:#C1CBD7; --muted:#8E9BAB; --line:#2A3542;
  --acc:#7FA7EC; --acc-soft:#1B2840; --sun:#F0BE4C; --sun-soft:#3A3016; --coral:#EE7B65; --coral-soft:#3B211C;
  --leaf:#6CC57A; --leaf-soft:#1A3220; --code:#1F2933;
  --i0:#1D2C44; --i1:#1D3322; --i2:#3A3016; --i3:#36203A; --i4:#173332; --i5:#3B211C; color-scheme:dark;}}
:root[data-theme="dark"]{
  --bg:#10151C; --card:#18202A; --ink:#E5EBF2; --ink2:#C1CBD7; --muted:#8E9BAB; --line:#2A3542;
  --acc:#7FA7EC; --acc-soft:#1B2840; --sun:#F0BE4C; --sun-soft:#3A3016; --coral:#EE7B65; --coral-soft:#3B211C;
  --leaf:#6CC57A; --leaf-soft:#1A3220; --code:#1F2933;
  --i0:#1D2C44; --i1:#1D3322; --i2:#3A3016; --i3:#36203A; --i4:#173332; --i5:#3B211C; color-scheme:dark;}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--ink);font-family:var(--f-body);font-size:17px;line-height:1.65;
  padding-left:max(16px, env(safe-area-inset-left, 0px));padding-right:max(16px, env(safe-area-inset-right, 0px))}
.wrap{max-width:1000px;margin:0 auto;padding-block:30px 90px}
a{color:var(--acc)}
code{font-family:var(--f-mono);font-size:.84em;background:var(--code);padding:.1em .35em;border-radius:5px}
h1{font-family:var(--f-display);font-weight:600;font-size:clamp(40px,7vw,68px);line-height:1;margin:.1em 0 .2em;text-wrap:balance}
h2{font-family:var(--f-display);font-weight:600;font-size:30px;line-height:1.12;margin:0;text-wrap:balance}
h3{font-family:var(--f-display);font-weight:500;font-size:20px;margin:22px 0 8px}
p,li{max-width:70ch}
.kicker{font-family:var(--f-mono);font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:var(--acc);margin:0}
.lede{font-size:20px;color:var(--ink2);margin:0 0 16px}
.credit{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 16px;font-size:15px;color:var(--ink2)}
.index{margin:24px 0 8px;background:var(--card);border:1px solid var(--line);border-radius:18px;padding:16px}
.index ol{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(205px,1fr));gap:10px}
.index a{display:flex;gap:10px;align-items:center;text-decoration:none;color:var(--ink);padding:8px 10px;border-radius:12px;border:1px solid var(--line);background:var(--bg);height:100%}
.index a:hover{border-color:var(--acc)}
.index a.ok .dot{background:var(--leaf);color:var(--card)}
.dot{flex:none;width:32px;height:32px;border-radius:50%;display:grid;place-items:center;font-family:var(--f-display);font-weight:600;background:var(--acc-soft);color:var(--acc)}
.index small{display:block;font-size:12px;color:var(--muted);line-height:1.25}
.index .grp{grid-column:1/-1;font-family:var(--f-mono);font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-top:4px}
.progress{font-size:14px;color:var(--muted);margin:10px 2px 0}
section.part{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:26px 28px;margin-top:28px;scroll-margin-top:14px}
.phead{display:flex;gap:16px;align-items:center;flex-wrap:wrap}
.big{flex:none;width:58px;height:58px;border-radius:16px;display:grid;place-items:center;font-family:var(--f-display);font-size:28px;font-weight:600;background:var(--acc);color:var(--card)}
.big.ext{background:var(--leaf)}
.phead .tt{flex:1 1 260px;min-width:0}
.phead p{margin:0;color:var(--muted)}
label.done{font-size:14px;display:flex;gap:6px;align-items:center;border:1px solid var(--line);padding:6px 12px;border-radius:20px;cursor:pointer;color:var(--ink2);white-space:nowrap}
label.done:has(input:checked){border-color:var(--leaf);color:var(--leaf);background:var(--leaf-soft)}
.post{border-left:4px solid var(--acc);background:var(--acc-soft);border-radius:0 12px 12px 0;padding:10px 14px;margin:16px 0}
.post b{font-family:var(--f-mono);font-size:11px;letter-spacing:.08em;text-transform:uppercase;display:block;color:var(--acc)}
.kid{font-size:18px;background:var(--sun-soft);border-radius:14px;padding:14px 18px;margin:14px 0}
.kid::before{content:"Like you're 10";display:block;font-family:var(--f-mono);font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--ink2);margin-bottom:4px}
.ours{border:1px dashed var(--line);border-radius:12px;padding:10px 14px}
.ours::before{content:"In our pq5";display:block;font-family:var(--f-mono);font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--leaf);margin-bottom:2px}
.grid2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}
.hid{border-top:2px solid var(--acc);padding-top:8px;min-width:0}
.hid h4{margin:0 0 4px;font-family:var(--f-display);font-weight:500;font-size:17px}
.hid p{margin:0;font-size:15px;color:var(--ink2)}
.picbox{overflow-x:auto;margin:14px 0;background:var(--bg);border-radius:14px;padding:10px}
svg.pic{width:100%;height:auto;display:block;font-family:var(--f-body)}
.pic text{fill:var(--ink)} .pic .t{font-size:14px;font-weight:700} .pic .s{font-size:12px;fill:var(--muted)} .pic .m{font-size:11px;font-family:var(--f-mono)}
.pic .b{fill:var(--card);stroke:var(--ink2);stroke-width:1.5} .pic .preg{fill:var(--acc-soft);stroke:var(--acc)}
.pic .fld{fill:var(--card);stroke:var(--ink2)} .pic .imm{fill:var(--coral-soft);stroke:var(--coral)}
.pic .l{stroke:var(--muted);stroke-width:1.6;fill:none} .pic .ah{fill:var(--muted)}
.pic .l.fw{stroke:var(--leaf)} .pic .l.st{stroke:var(--sun)} .pic .l.fl{stroke:var(--coral)}
.pic .fwT{font-size:13px;fill:var(--leaf)} .pic .stT{font-size:13px;fill:var(--sun)} .pic .flT{font-size:13px;fill:var(--coral)}
.pic .bub{fill:none;stroke:var(--line);stroke-dasharray:4 3}
.pic .ins{stroke:var(--line)} .pic .i0{fill:var(--i0)} .pic .i1{fill:var(--i1)} .pic .i2{fill:var(--i2)} .pic .i3{fill:var(--i3)} .pic .i4{fill:var(--i4)} .pic .i5{fill:var(--i5)}
.pic .evs{font-size:11px;font-weight:700;fill:var(--sun)} .pic .evf{font-size:11px;font-weight:700;fill:var(--coral)}
pre.code{background:var(--code);border-radius:12px;padding:14px 16px;overflow-x:auto;font-size:12.5px;line-height:1.55;margin:8px 0;max-height:560px}
pre.code code{background:none;padding:0;font-size:inherit}
details{margin:8px 0}
details>summary{cursor:pointer;font-weight:700;color:var(--acc)}
summary:focus-visible,a:focus-visible,input:focus-visible{outline:2px solid var(--sun);outline-offset:2px}
.quiz details, .iq details{background:var(--bg);border:1px solid var(--line);border-radius:12px;padding:8px 14px}
.quiz details p,.iq details p{margin:6px 0 2px;max-width:none}
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:var(--card);margin:12px 0}
table.tt{border-collapse:collapse;width:100%;font-size:14px;font-variant-numeric:tabular-nums;min-width:640px}
table.tt th,table.tt td{padding:7px 10px;border-bottom:1px solid var(--line);text-align:left}
table.tt th{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}
.pill{display:inline-block;font-family:var(--f-mono);font-size:11px;padding:1px 8px;border-radius:9px;margin-right:6px}
.pill.bad{background:var(--coral-soft);color:var(--coral)} .pill.ok{background:var(--leaf-soft);color:var(--leaf)} .pill.warn{background:var(--sun-soft);color:var(--ink2)}
pre.term{background:var(--ink);color:var(--bg);border-radius:12px;padding:14px 16px;overflow-x:auto;font-family:var(--f-mono);font-size:13px}
.next{background:var(--acc);color:var(--card);border-radius:20px;padding:24px 28px;margin-top:28px}
.next h2,.next p{color:var(--card)} .next a{color:var(--card);font-weight:700}
@media (max-width:720px){ section.part{padding:20px 16px} .grid2{grid-template-columns:minmax(0,1fr)} h2{font-size:26px} }
@media (prefers-reduced-motion: reduce){*{transition:none!important}}
'''

def qa(items, cls):
    return f'<div class="{cls}">' + ''.join(f'<details><summary>{q}</summary><p>{a}</p></details>' for q, a in items) + '</div>'

def part(p):
    o = [f'<section class="part" id="p{p["n"]}"><div class="phead"><div class="big">{p["n"]}</div><div class="tt"><h2>{p["title"]}</h2><p>{p["tag"]}</p></div>'
         f'<label class="done"><input type="checkbox" data-n="{p["n"]}"> Done</label></div>',
         f'<div class="post"><b>What Part {p["n"]} covers</b>{p["summary"]} <a href="{POSTS[p["n"]]}" target="_blank" rel="noopener">Read the original post</a>.</div>',
         f'<p class="kid">{p["kid"]}</p>']
    if p.get('pic'): o.append(p['pic']())
    if p['n'] == 3:
        nm3 = names_of('p03_load_use.s'); nm5 = names_of('p05_if_else.s'); nm4 = names_of('p04_loop_sum.s')
        o.append('<h3>See it: a load-use stall (real simulation)</h3><p>Each column is one clock cycle, each row a stage. <code>lw x2</code> is in EX in cycle 5 while <code>addi x3, x2, 1</code> waits in decode: one bubble enters EX, and the add continues a cycle later with the value forwarded from WB.</p>')
        o.append(pipe_svg('pipe_loaduse.txt', nm3, 1, 12, "load-use stall"))
        o.append('<h3>See it: a wrong guess (flush)</h3><p><code>blt x1, x2, x1_small</code> jumps <i>forward</i>, so fetch guessed "not taken". In cycle 5 execute finds it IS taken: the two instructions behind it become bubbles and fetch restarts at the right place. Cost: 2 cycles.</p>')
        o.append(pipe_svg('pipe_ifelse.txt', nm5, 1, 12, "branch flush"))
        o.append('<h3>See it: a loop the predictor gets right</h3><p>The backward <code>bne</code> is guessed taken, so the loop streams with no bubbles, until the very last iteration (cycle 305) where it falls through: one flush in 100 iterations.</p>')
        o.append(pipe_svg('pipe_loop.txt', nm4, 298, 311, "loop with prediction"))
        o.append('<h3>The cost formula, checked</h3><p>pq5 counts its own stalls and flushes. With 4 cycles to fill the pipe, every run obeys <b>cycles = 4 + N + stalls + 2 × flushes</b>:</p>' + regtable())
        o.append('<h3>Remove one mechanism, see what breaks</h3><p>Each row is a real RTL change, rebuilt and run against all 10 directed programs and 100 random programs. Every correctness mechanism is caught. Prediction only changes speed. One mutant survives, and that is a lesson too (see Part 9).</p>' + muttable())
    if p.get('code'):
        o.append(f'<div class="ours">{p["ours"]}</div><h3>The code</h3><pre class="code"><code>{E(module(p["code"]))}</code></pre>')
    elif p['ours']:
        o.append(f'<div class="ours">{p["ours"]}</div>')
    o.append('<h3>Hidden concepts</h3><div class="grid2">' + ''.join(f'<div class="hid"><h4>{a}</h4><p>{b}</p></div>' for a, b in p['hidden']) + '</div>')
    o.append('<h3>Check yourself</h3>' + qa(p['quiz'], 'quiz'))
    o.append('<h3>Interview question</h3>' + qa(p['iq'], 'iq') + '</section>')
    return ''.join(o)

def extra(p):
    o = [f'<section class="part" id="p{p["n"]}"><div class="phead"><div class="big ext">{p["n"]}</div><div class="tt"><h2>{p["title"]}</h2><p>{p["tag"]}</p></div>'
         f'<label class="done"><input type="checkbox" data-n="{p["n"]}"> Done</label></div>',
         f'<p class="kid">{p["kid"]}</p>', f'<p>{p["text"]}</p>']
    if p['n'] == 8: o.append(pic_bytes())
    o.append(f'<h3>The code</h3><pre class="code"><code>{E(module(p["code"]))}</code></pre>')
    o.append('<h3>Hidden concepts</h3><div class="grid2">' + ''.join(f'<div class="hid"><h4>{a}</h4><p>{b}</p></div>' for a, b in p['hidden']) + '</div></section>')
    return ''.join(o)

JS = r'''(function(){
 const st={get(k){try{return localStorage.getItem(k);}catch(e){return null;}},set(k,v){try{localStorage.setItem(k,v);}catch(e){}}};
 const bx=[...document.querySelectorAll('input[data-n]')];
 function upd(){let n=0;bx.forEach(b=>{const a=document.querySelector('.index a[href="#p'+b.dataset.n+'"]');if(a)a.classList.toggle('ok',b.checked);if(b.checked)n++;});
  document.getElementById('prog').textContent=n+' of '+bx.length+' parts done';}
 bx.forEach(b=>{b.checked=st.get('pq-'+b.dataset.n)==='1';b.addEventListener('change',()=>{st.set('pq-'+b.dataset.n,b.checked?'1':'0');upd();});});
 upd();})();'''

def page():
    P = ['<title>Pequeno Study Guide</title><meta name="claude:viewport-fit-sides" content="cover">',
         '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>',
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&family=JetBrains+Mono:wght@400;600&family=Nunito+Sans:ital,wght@0,400;0,700;1,400&display=swap">',
         f'<style>{CSS}</style><div class="wrap"><header><p class="kicker">Study guide · RV32I · 5-stage in-order pipeline</p><h1>Pequeno Study Guide</h1>'
         '<p class="lede">A beginner-friendly companion to the "Designing Pequeno RISC-V CPU from scratch" series, Parts 1 to 6, continued until the CPU is finished, running real programs and checked instruction by instruction against a reference model.</p>'
         '<p class="credit">The Pequeno series is written by Mitu Raj at Chipmunk Logic. This guide explains its ideas in my own words and links to every original post. The CPU here, <b>pq5</b>, is new code that follows the same architecture so you can run, break and extend it. It is not the series\' RTL.</p></header>',
         '<nav class="index" aria-label="Parts"><ol><li class="grp">The six posts</li>']
    for p in PARTS: P.append(f'<li><a href="#p{p["n"]}"><span class="dot">{p["n"]}</span><span>{p["title"]}<small>{p["tag"]}</small></span></a></li>')
    P.append('<li class="grp">Finishing the CPU</li>')
    for p, t in [(7, "Execute"), (8, "Memory + writeback"), (9, "Verify the whole CPU")]:
        P.append(f'<li><a href="#p{p}"><span class="dot">{p}</span><span>{t}<small>beyond the six posts</small></span></a></li>')
    P.append('</ol><p class="progress" id="prog">0 parts done</p></nav>')
    P.append(f'''<section class="part" id="p0"><div class="phead"><div class="big">0</div><div class="tt"><h2>Where this fits</h2><p>read once</p></div></div>
<p>In the beginner track, <a href="{BEGINNER_URL}">CPU From Zero</a>, Level 6 is a single-cycle CPU and Level 7 explains why simple CPUs wait. This series is the missing step between them: a <b>pipelined, in-order</b> CPU, the design interviewers ask about most. After it, your out-of-order core in the <a href="{ADV_URL}">Tomasulo Core Lab</a> is "the same pipeline, but instructions may overtake each other".</p>
<pre class="term">cd pq5
make obj/sim                         # Verilator 5.026+  (VERILATOR=/path/to/verilator if needed)
make regress                         # 10 programs, each checked against the ISS, with CPI
make pipe T=tests/p03_load_use.s     # cycle-by-cycle picture of the pipeline
python3 tools/gen_rand.py 7 r7.s && python3 tools/run_pq5.py r7.s</pre></section>''')
    for p in PARTS: P.append(part(p))
    for p in EXTRA: P.append(extra(p))
    P.append(f'''<section class="part" id="p9"><div class="phead"><div class="big ext">9</div><div class="tt"><h2>Verify the whole CPU</h2><p>beyond Part 6 · ISS · random · assertions · mutations</p></div>
<label class="done"><input type="checkbox" data-n="9"> Done</label></div>
<p class="kid">How do you know the sandwich shop works? You don't taste one sandwich. You compare every order handed out with what a very slow, very careful single worker (the golden model) would have made from the same orders, and you send in a thousand random customers.</p>
<div class="grid2">
<div class="hid"><h4>Golden model</h4><p><code>tools/rv32i.py</code> runs the program one instruction at a time. <code>run_pq5.py</code> compares every retired instruction (PC, register, value), the final registers and memory.</p></div>
<div class="hid"><h4>Directed programs</h4><p>10 small real programs: every ALU op, forwarding distances 1-3, load-use, loop sum 1..100 (5050), if/else, nested function calls with a stack, bubble sort, byte/half access, shift-and-add multiply (123×45, 6!), Fibonacci. All pass.</p></div>
<div class="hid"><h4>Constrained random</h4><p><code>gen_rand.py</code> builds hazard-dense programs (6 registers, 8 memory words, loops, forward branches, jalr) that always reach <code>halt</code>. 500 of 500 pass.</p></div>
<div class="hid"><h4>Assertions</h4><p>x0 is never written; IF/ID never changes during a stall; stall and flush never coincide; a load's result is never needed one stage too early.</p></div></div>
<h3>Two things the mutation table taught me</h3>
<div class="grid2">
<div class="hid"><h4>A surviving mutant is a question</h4><p>Letting forwarding pass a load's <i>address</i> as if it were data changes nothing in 110 tests. Not a test hole: the load-use interlock guarantees no instruction ever needs a load's result one stage later, so that guard is redundant. I proved it with an assertion (<code>a_loaduse</code>) instead of assuming.</p></div>
<div class="hid"><h4>Random has blind spots</h4><p>The first random generator never used x0 as a destination, so "x0 can be written" escaped all 100 random programs (directed tests caught it). After adding x0 destinations, random catches it in 54 of 100. Always ask what your stimulus can't produce.</p></div></div>
<h3>Build it yourself next</h3><ol>
<li>Move branch resolution to decode (compare + forwarding into ID). Re-measure: the flush penalty should drop from 2 to 1.</li>
<li>Add a 2-bit dynamic predictor (a small table indexed by PC). Compare CPI on <code>p07_bubble_sort</code> and <code>p09_multiply</code>.</li>
<li>Make memory slower: give instruction memory a 1-cycle latency with a valid/ready handshake, like Pequeno's fetch interface. What has to change in fetch?</li>
<li>Add the M extension (mul) as a multi-cycle unit. What does the pipeline do while it waits? This is where out-of-order execution starts to pay off.</li></ol>
<h3>Interview questions</h3>''' + qa([
 ("Design a hazard unit for a 5-stage pipeline. What inputs does it need?", "Source registers and 'uses' flags of the instruction in ID; destination, write-enable and 'is load' of the instructions in EX and MEM; the branch outcome from EX. Outputs: stall IF+ID with a bubble into EX on load-use; flush IF/ID+ID/EX on mispredict; forwarding selects for each ALU operand."),
 ("How would you verify forwarding completely?", "Enumerate the producer kinds (ALU, load, jal link, lui) × distance (1, 2, 3, 4+) × operand (rs1, rs2, store data, branch compare, jalr base) × same-register-twice priority. Write directed tests for each cell, measure functional coverage of that matrix in random runs, and keep a golden-model comparison at commit."),
 ("Why is the load-use penalty 1 cycle and not 2?", "The load's data exists at the end of MEM, and the dependent instruction needs it at the start of its EX. One bubble lines those up, and the value is forwarded from MEM/WB."),
], 'iq') + '</section>')
    P.append(f'''<section class="next"><h2>Next: let instructions overtake</h2><p>pq5 waits whenever an instruction can't go. An out-of-order CPU lets independent instructions go ahead and puts the results back in order at the end. Levels 7 to 11 of <a href="{BEGINNER_URL}">CPU From Zero</a> build that step by step, and the <a href="{ADV_URL}">Tomasulo Core Lab</a> takes your 3-wide core apart.</p></section>''')
    P.append(f'</div><script>{JS}</script>')
    return '\n'.join(P)

out = sys.argv[1]
open(out, 'w').write(page()); print('wrote', out, os.path.getsize(out))
