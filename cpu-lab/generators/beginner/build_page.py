# -*- coding: utf-8 -*-
# Builds "CPU From Zero" - the beginner ladder page - from the real .sv files and real sim output.
import html, json, os, re, sys
E = html.escape
HERE = os.path.dirname(os.path.abspath(__file__))
R = json.load(open(os.path.join(HERE, 'results.json')))
ADV_URL = "https://claude.ai/artifact/7uWYxRU5pbYHEWq7JPc63b"

def src(fname):
    s = open(os.path.join(HERE, fname)).read()
    i = s.find('\nmodule tb_')
    return s[:i].strip(), s[i:].strip()

# --------------------------------------------------------------------------- pictures
def svg(body, vb, label):
    return f'<svg viewBox="{vb}" class="pic" role="img" aria-label="{label}">{body}</svg>'

ARROW = '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0L10,5L0,10z" class="ah"/></marker></defs>'

def rbox(x, y, w, h, t, sub="", cls="b"):
    o = f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>'
    if sub:
        o += f'<text class="t" x="{x+w/2}" y="{y+h/2-4}" text-anchor="middle">{t}</text><text class="s" x="{x+w/2}" y="{y+h/2+14}" text-anchor="middle">{sub}</text>'
    else:
        o += f'<text class="t" x="{x+w/2}" y="{y+h/2+6}" text-anchor="middle">{t}</text>'
    return o

def ar(x1, y1, x2, y2, cls="l"):
    return f'<line class="{cls}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" marker-end="url(#a)"/>'

def pic_adder():
    o = [ARROW]
    for i, x in enumerate([500, 360, 220, 80]):
        o.append(rbox(x, 60, 110, 70, "full adder", f"bit {i}"))
        o.append(f'<text class="s" x="{x+30}" y="45" text-anchor="middle">a{i}</text><text class="s" x="{x+80}" y="45" text-anchor="middle">b{i}</text>')
        o.append(ar(x+30, 50, x+30, 58)); o.append(ar(x+80, 50, x+80, 58))
        o.append(ar(x+55, 130, x+55, 160)); o.append(f'<text class="s" x="{x+55}" y="178" text-anchor="middle">sum{i}</text>')
        if i < 3: o.append(ar(x, 95, x-28, 95, "l hot"))
    o.append(f'<text class="hotT" x="190" y="88" text-anchor="middle">carry</text>')
    o.append('<text class="s" x="640" y="100">0 in</text>'); o.append(ar(638, 95, 612, 95, "l hot"))
    o.append('<text class="s" x="20" y="220">1 + 1 = 10 in binary: the "1" carries to the next box, exactly like 9 + 1 = 10 carries in school.</text>')
    return svg(''.join(o), "0 0 680 235", "chain of full adders passing a carry")

def pic_clock():
    o = []; y0 = 40; cw = 70
    d = ""
    for c in range(8):
        x = 90 + c*cw; d += f"M{x},{y0+30} L{x},{y0} L{x+cw/2},{y0} L{x+cw/2},{y0+30} L{x+cw},{y0+30} "
    o.append(f'<path class="w" d="{d}"/><text class="t" x="80" y="{y0+22}" text-anchor="end">clock</text>')
    vals = [0, 0, 1, 2, 2, 3, 4, 5]; en = [0, 1, 1, 0, 1, 1, 1, 0]
    for c in range(8):
        x = 90 + c*cw
        o.append(f'<rect class="cellb" x="{x+4}" y="110" width="{cw-8}" height="34" rx="6"/><text class="t" x="{x+cw/2}" y="133" text-anchor="middle">{vals[c]}</text>')
        o.append(f'<text class="s" x="{x+cw/2}" y="172" text-anchor="middle">{"en" if en[c] else "·"}</text>')
        o.append(f'<line class="grid" x1="{x}" y1="30" x2="{x}" y2="150"/>')
    o.append('<text class="t" x="80" y="133" text-anchor="end">count</text><text class="s" x="80" y="172" text-anchor="end">enable</text>')
    o.append('<text class="s" x="90" y="205">The number only changes ON the rising edge (dotted lines), and only if enable was 1 just before it.</text>')
    return svg(''.join(o), "0 0 680 220", "clock waveform and counter value changing on edges")

def pic_alu():
    o = [ARROW, rbox(40, 40, 70, 40, "a"), rbox(40, 120, 70, 40, "b"), rbox(40, 200, 70, 40, "op", "ADD? SUB?…")]
    names = ["a + b", "a − b", "a & b", "a | b", "a ^ b", "a < b ?", "a << b", "…"]
    for i, n in enumerate(names):
        o.append(f'<rect class="cellb" x="200" y="{20+i*30}" width="120" height="24" rx="6"/><text class="m" x="260" y="{37+i*30}" text-anchor="middle">{n}</text>')
    o.append(ar(110, 60, 196, 100)); o.append(ar(110, 140, 196, 140))
    o.append('<path class="b" d="M380,40 L440,80 L440,200 L380,240 Z"/><text class="t" x="410" y="145" text-anchor="middle">pick</text>')
    o.append(ar(320, 140, 376, 140)); o.append(ar(110, 220, 408, 226))
    o.append(ar(440, 140, 520, 140)); o.append(rbox(524, 118, 80, 44, "y"))
    o.append('<text class="s" x="200" y="272">Hardware computes ALL answers at once; "op" just picks which one comes out.</text>')
    return svg(''.join(o), "0 0 640 285", "ALU computing all results and a mux picking one")

def pic_lockers():
    o = []
    for i in range(32):
        r, c = divmod(i, 8); x = 30 + c*72; y = 20 + r*56
        cls = "cellz" if i == 0 else "cellb"
        o.append(f'<rect class="{cls}" x="{x}" y="{y}" width="64" height="48" rx="6"/><text class="t" x="{x+32}" y="{y+22}" text-anchor="middle">x{i}</text>')
        o.append(f'<text class="s" x="{x+32}" y="{y+40}" text-anchor="middle">{"always 0" if i == 0 else "32 bits"}</text>')
    o.append('<text class="s" x="30" y="262">32 lockers. Two can be peeked at every cycle, one can be filled. Locker x0 is glued shut.</text>')
    return svg(''.join(o), "0 0 620 275", "32 registers drawn as lockers, x0 glued shut")

def pic_fifo():
    o = [ARROW, rbox(20, 70, 120, 60, "producer"), rbox(520, 70, 120, 60, "consumer")]
    for i in range(4):
        o.append(f'<rect class="{"cellb" if i < 3 else "celle"}" x="{220+i*60}" y="80" width="52" height="40" rx="6"/>')
        if i < 3: o.append(f'<text class="m" x="{246+i*60}" y="105" text-anchor="middle">#{i+7}</text>')
    o.append(ar(140, 90, 214, 90)); o.append('<text class="s" x="178" y="80" text-anchor="middle">valid →</text>')
    o.append(ar(214, 112, 140, 112, "l hot")); o.append('<text class="hotT" x="178" y="132" text-anchor="middle">← ready</text>')
    o.append(ar(460, 90, 516, 90)); o.append('<text class="s" x="488" y="80" text-anchor="middle">valid →</text>')
    o.append(ar(516, 112, 460, 112, "l hot")); o.append('<text class="hotT" x="488" y="132" text-anchor="middle">← ready</text>')
    o.append('<text class="s" x="20" y="180">A ticket moves only when the giver says "valid" AND the taker says "ready" on the same beat.</text>')
    o.append('<text class="s" x="20" y="200">Full queue → ready goes low → the producer must WAIT and keep holding its ticket.</text>')
    return svg(''.join(o), "0 0 660 215", "FIFO with valid and ready handshakes on both sides")

def pic_cpu():
    o = [ARROW]
    steps = [("1 Fetch", "read instr at PC"), ("2 Decode", "slice the bits"), ("3 Execute", "ALU does math"), ("4 Write back", "result → locker")]
    for i, (a, b) in enumerate(steps):
        o.append(rbox(20 + i*160, 50, 140, 64, a, b))
        if i < 3: o.append(ar(160 + i*160, 82, 178 + i*160, 82))
    o.append('<path class="l" d="M570,114 C570,170 90,170 90,118" marker-end="url(#a)"/>')
    o.append('<text class="t" x="330" y="160" text-anchor="middle">PC = PC + 4   (or jump if a branch is taken)</text>')
    o.append('<text class="s" x="20" y="205">All four steps happen in ONE clock cycle here. Simple, but the clock must be slow enough for the longest path.</text>')
    return svg(''.join(o), "0 0 660 220", "fetch decode execute write back loop with PC")

def pic_scoreboard():
    o = [ARROW]
    items = [("mul x3", "cooking… 5 beats", "b hotbox"), ("add x4 ← x3", "WAITS for x3", "b warnbox"), ("addi x5", "could go… but stuck", "b dim"), ("sub x6", "stuck too", "b dim")]
    for i, (a, b, c) in enumerate(items):
        o.append(rbox(20 + i*160, 60, 140, 64, a, b, c))
    o.append(ar(640, 92, 600, 92))
    o.append('<text class="s" x="20" y="160">In-order = a single-file line. One instruction waiting blocks everyone behind it,</text>')
    o.append('<text class="s" x="20" y="180">even "addi x5" which needs nothing from anyone. Out-of-order CPUs fix exactly this.</text>')
    return svg(''.join(o), "0 0 680 195", "in-order line where a waiting instruction blocks independent ones")

def pic_rename():
    o = []
    o.append('<text class="t" x="20" y="30">Program</text><text class="t" x="330" y="30">Rename table (RAT)</text>')
    rows = [("mul x3, x1, x2", "x3 → ticket 0"), ("add x4, x3, x1", "reads x3 = ticket 0"), ("sub x3, x5, x1", "x3 → ticket 2 (newer!)")]
    for i, (a, b) in enumerate(rows):
        o.append(f'<rect class="cellb" x="20" y="{44+i*44}" width="250" height="34" rx="6"/><text class="m" x="34" y="{66+i*44}">{a}</text>')
        o.append(f'<rect class="{"cellh" if i==2 else "cellb"}" x="330" y="{44+i*44}" width="270" height="34" rx="6"/><text class="m" x="344" y="{66+i*44}">{b}</text>')
    o.append('<text class="s" x="20" y="200">Two orders both want "x3". Giving each a ticket number means they never fight:</text>')
    o.append('<text class="s" x="20" y="220">the add waits for ticket 0, and anyone later who reads x3 waits for ticket 2.</text>')
    return svg(''.join(o), "0 0 640 235", "rename table mapping x3 to ticket numbers")

def pic_rs():
    o = []
    rows = [("T5: add", "x3? wait T2", "x1 ✓", "waiting"), ("T6: sub", "x5 ✓", "x1 ✓", "READY ✋"), ("T7: mul", "x6? wait T5", "x6? wait T5", "waiting")]
    o.append('<text class="t" x="20" y="28">The rail of order tickets</text>')
    for i, (a, b, c, d) in enumerate(rows):
        y = 40 + i*46
        o.append(f'<rect class="{"cellh" if "READY" in d else "cellb"}" x="20" y="{y}" width="460" height="38" rx="6"/>')
        o.append(f'<text class="m" x="34" y="{y+24}">{a}</text><text class="m" x="140" y="{y+24}">{b}</text><text class="m" x="270" y="{y+24}">{c}</text><text class="t" x="380" y="{y+24}">{d}</text>')
    o.append('<circle class="bell" cx="560" cy="90" r="34"/><text class="t" x="560" y="86" text-anchor="middle">CDB</text><text class="s" x="560" y="104" text-anchor="middle">"T2 = 30!"</text>')
    o.append('<text class="s" x="20" y="200">Every ticket listens to the bell. When T2 rings, T5 grabs the value 30 and raises its hand.</text>')
    return svg(''.join(o), "0 0 640 215", "reservation station entries listening to the CDB bell")

def pic_rob():
    o = []
    ent = [("T0", "served ✓", "celld"), ("T1", "cooking…", "cellb"), ("T2", "DONE, waits", "cellh"), ("T3", "DONE, waits", "cellh"), ("T4", "cooking…", "cellb"), ("", "free", "celle"), ("", "free", "celle"), ("", "free", "celle")]
    for i, (a, b, c) in enumerate(ent):
        o.append(f'<rect class="{c}" x="{20+i*76}" y="50" width="68" height="60" rx="6"/><text class="t" x="{54+i*76}" y="76" text-anchor="middle">{a}</text><text class="s" x="{54+i*76}" y="96" text-anchor="middle">{b}</text>')
    o.append('<text class="hotT" x="130" y="36" text-anchor="middle">▼ head: oldest, the only one allowed to leave</text>')
    o.append('<text class="s" x="420" y="134" text-anchor="middle">▲ tail: next new order goes here</text>')
    o.append('<text class="s" x="20" y="170">T2 and T3 are finished, but T1 is older and still cooking, so nobody is served until T1 is.</text>')
    o.append('<text class="s" x="20" y="190">That is why a CPU can stop at any instruction cleanly: everything before it is served, nothing after.</text>')
    return svg(''.join(o), "0 0 640 205", "reorder buffer serving dishes in order from the head")

def pic_gantt(log):
    ev = {}
    names = ["addi x1, x0, 5", "addi x2, x0, 6", "mul  x3, x1, x2", "add  x4, x3, x1", "addi x5, x0, 7", "sub  x6, x5, x1", "mul  x3, x6, x6", "add  x7, x3, x4"]
    for line in log:
        m = re.match(r'cycle\s+(\d+):(.*)', line)
        if not m: continue
        c = int(m[1]); rest = m[2]
        for t in re.findall(r'ticket T(\d)', rest): ev.setdefault(int(t), {})['D'] = c
        for t in re.findall(r'start T(\d)', rest): ev.setdefault(int(t), {})['S'] = c
        for t in re.findall(r'BELL T(\d)', rest): ev.setdefault(int(t), {})['B'] = c
        mm = re.search(r'COMMIT (.+)$', rest)
        if mm: ev.setdefault(names.index(mm[1].strip()), {})['C'] = c
    X0, CW, RH = 170, 30, 30
    o = []
    for c in range(1, 17):
        x = X0 + (c-1)*CW
        o.append(f'<line class="grid" x1="{x}" y1="22" x2="{x}" y2="{30+8*RH}"/><text class="s" x="{x+CW/2}" y="18" text-anchor="middle">{c}</text>')
    for t in range(8):
        y = 28 + t*RH; e = ev[t]
        o.append(f'<text class="m" x="{X0-8}" y="{y+19}" text-anchor="end">T{t} {names[t]}</text>')
        def cx(c): return X0 + (c-1)*CW
        o.append(f'<rect class="gwait" x="{cx(e["D"])+2}" y="{y+6}" width="{cx(e["S"])-cx(e["D"])}" height="16" rx="3"/>')
        o.append(f'<rect class="gcook" x="{cx(e["S"])+2}" y="{y+6}" width="{cx(e["B"])-cx(e["S"])+CW-4}" height="16" rx="3"/>')
        if e["C"] > e["B"] + 1:
            o.append(f'<rect class="gdone" x="{cx(e["B"]+1)}" y="{y+6}" width="{cx(e["C"])-cx(e["B"]+1)}" height="16" rx="3"/>')
        o.append(f'<circle class="gc" cx="{cx(e["C"])+CW/2}" cy="{y+14}" r="7"/>')
    y = 40 + 8*RH
    o.append(f'<rect class="gwait" x="20" y="{y}" width="20" height="12" rx="3"/><text class="s" x="46" y="{y+11}">waiting in the RS</text>')
    o.append(f'<rect class="gcook" x="190" y="{y}" width="20" height="12" rx="3"/><text class="s" x="216" y="{y+11}">executing → bell</text>')
    o.append(f'<rect class="gdone" x="350" y="{y}" width="20" height="12" rx="3"/><text class="s" x="376" y="{y+11}">done, waiting its turn</text>')
    o.append(f'<circle class="gc" cx="556" cy="{y+6}" r="6"/><text class="s" x="568" y="{y+11}">commit (served)</text>')
    return svg(''.join(o), f"0 0 {X0+16*CW+20} {y+28}", "timeline of the tiny out-of-order CPU")

# --------------------------------------------------------------------------- levels
L = [
 dict(n=1, file="L01_adder.sv", title="Wires and gates", sub="build an adder from nothing",
  story="A computer only knows two things: <b>0</b> (off) and <b>1</b> (on), like a light switch. Gates are tiny rules: AND says 'both on?', OR says 'any on?', XOR says 'exactly one on?'. Glue enough rules together and you can add numbers. We build a 1-bit adder, then copy it 32 times.",
  pic=pic_adder, words=[("bit", "one 0-or-1"), ("combinational", "no memory: output follows input instantly"), ("assign", "a permanent wire connection"), ("generate", "copy hardware N times")],
  look="Read <code>full_adder</code>: sum is 1 when an odd number of inputs are 1. The carry goes to the next box, just like carrying in school maths.",
  breakit=("Change the carry to <code>assign cout = (a &amp; b);</code> (forget the carry-in).", "The adder is right only when no carry ever ripples. Random testing finds it immediately: 990 of 1000 checks fail."),
  quiz=[("What is 1 + 1 in binary?", "10: write 0, carry 1."), ("Why test 0xFFFFFFFF + 1 on purpose?", "It makes the carry ripple through all 32 boxes, the longest and riskiest path, and the result wraps to 0 with cout = 1.")],
  big="Your core's ALUs, address adders and the Booth multiplier are all built from this idea."),
 dict(n=2, file="L02_counter.sv", title="The clock and memory", sub="flip-flops remember",
  story="The <b>clock</b> is a drumbeat: tick, tick, tick. A <b>flip-flop</b> is a notebook that may only write on the tick. Between ticks it keeps showing the old number. Everything in a CPU marches to this drum, which is why all parts stay in step.",
  pic=pic_clock, words=[("clock edge", "the instant the drum hits (0→1)"), ("always_ff", "'this block is flip-flops'"), ("<=", "non-blocking: all notebooks write together"), ("reset", "start from a known value")],
  look="<code>count &lt;= count + 1</code> means: at the next tick, the new value is the old value plus 1. Use <code>&lt;=</code> in <code>always_ff</code> and <code>=</code> in <code>always_comb</code>. Mixing them was a real source of races in the big core.",
  breakit=("Delete <code>if (en)</code> so it always counts.", "The testbench keeps its own model counter and compares every tick: 38 mismatches."),
  quiz=[("A 4-bit counter is at 15 and counts once more. What does it show?", "0. It wraps around, because 16 needs 5 bits."), ("Why does the testbench check just AFTER the clock edge?", "The flip-flop changes on the edge. Checking a moment later sees the new value; checking exactly on the edge is a race.")],
  big="Every register in your core (ROB entries, RS entries, the PC) is a bank of these notebooks."),
 dict(n=3, file="L03_alu.sv", title="The ALU", sub="the CPU's calculator",
  story="The ALU (arithmetic logic unit) is a calculator with buttons: ADD, SUB, AND, SHIFT... In hardware all the answers are worked out at the same time, and the button (<code>op</code>) only chooses which answer leaves the box.",
  pic=pic_alu, words=[("case", "pick one of many"), ("$signed", "treat bits as a +/- number"), (">>>", "shift that keeps the sign"), ("enum", "names instead of magic numbers")],
  look="SLT and SRA need <code>$signed</code>. Without it, -1 (0xFFFFFFFF) looks like a huge positive number.",
  breakit=("Write <code>SRA: y = a &gt;&gt;&gt; b[4:0];</code> without <code>$signed</code>.", "<code>&gt;&gt;&gt;</code> on an unsigned value acts like a normal shift, so negative numbers lose their sign: 148 of 3000 random checks fail. Testing corner values (-1, MIN, MAX) on purpose helps."),
  quiz=[("Why does the ALU have a <code>default</code> branch?", "So an unknown op can never silently 'do nothing'. In your big core, missing ops (andi, ori…) did exactly that and the instruction vanished (bug B03)."), ("Is 0x80000000 bigger than 1?", "Unsigned: yes (2147483648). Signed: no (it is -2147483648). The same bits, two meanings.")],
  big="Your core has 3 of these ALUs working in parallel."),
 dict(n=4, file="L04_regfile.sv", title="The register file", sub="32 lockers, one glued shut",
  story="Registers are the CPU's pockets: tiny, very fast storage for numbers it is working on. RISC-V has 32 of them, x0 to x31. Each cycle you can peek into two lockers and put something into one. Locker <b>x0</b> is glued shut: it always reads 0, and anything you put in it disappears.",
  pic=pic_lockers, words=[("read port", "a window to peek in"), ("write port", "a slot to put in"), ("x0", "always zero"), ("write enable", "'actually write this cycle'")],
  look="Two guards protect x0: one on the write side (<code>wa != 0</code>) and one on the read side. Reads are combinational (instant); writes wait for the clock.",
  breakit=("Remove both x0 guards.", "Now x0 can hold junk, and any instruction that reads x0 gets a wrong value: 6 read mismatches."),
  quiz=[("Why have a zero register at all?", "It gives free constants and tricks: <code>addi x5, x0, 7</code> means 'x5 = 7', <code>add x5, x6, x0</code> means 'copy x6'."), ("You write x7 and read x7 in the same cycle. Which value do you get?", "In this design, the OLD one, because the write lands at the clock edge. Real pipelines add a bypass so you get the new one.")],
  big="Your core calls this the ARF (architectural register file). Renaming (Level 8) is about NOT waiting for it."),
 dict(n=5, file="L05_fifo.sv", title="Queues and handshakes", sub="valid + ready",
  story="Think of a queue at a ticket counter. The person giving tickets raises a flag saying 'I have one' (<b>valid</b>). The counter raises a flag saying 'I have room' (<b>ready</b>). A ticket moves only when both flags are up on the same beat. If the counter is full, the giver must wait <i>and keep holding the same ticket</i>.",
  pic=pic_fifo, words=[("FIFO", "first in, first out"), ("valid", "'I have data'"), ("ready", "'I can take it'"), ("back-pressure", "ready=0 makes the sender wait")],
  look="<code>count</code> has one extra bit so it can say 'completely full'. Push and pop in the same cycle leave the count unchanged.",
  breakit=("Set <code>in_ready = 1</code> always (ignore 'full').", "New tickets overwrite old ones that were never read: 88 scoreboard errors. My own first testbench also had a bug here: it checked the handshake <i>after</i> the clock edge, when everything had already moved. Always sample just <i>before</i> the edge."),
  quiz=[("The giver has valid=1 but ready=0 for 3 beats. What must the giver do?", "Keep the same data and keep valid=1 until ready=1. Changing the data or dropping it loses a ticket."), ("What did your big core's frontend get wrong here?", "Its PC kept moving while the queue said 'not ready', so whole bundles of instructions were skipped (bug B09).")],
  big="Your core's 16-entry instruction queue and the fetch→decode path are exactly this."),
 dict(n=6, file="L06_tiny_cpu.sv", title="A whole tiny CPU", sub="fetch → decode → execute → write back",
  story="Now we have a calculator (ALU), pockets (registers) and memory, and we can build a CPU! A program is a list of instructions. The <b>PC</b> (program counter) is a bookmark pointing at the current line. Every cycle the CPU reads that line, works out what it means, does it, saves the answer, and moves the bookmark. A <b>branch</b> moves the bookmark somewhere else, which is how loops work.",
  pic=pic_cpu, words=[("PC", "bookmark: address of the current instruction"), ("opcode", "which kind of instruction"), ("immediate", "a number written inside the instruction"), ("branch", "jump if a condition holds")],
  look="The test program adds 1+2+…+10 with a loop, stores 55 to memory, loads it back, and checks that <code>addi x5, x0, -1</code> gives 0xFFFFFFFF. Immediates are <b>always sign-extended</b> from bit 31. <code>funct7</code> means something only for R-type instructions. Your big core broke both rules (bugs B01 and B02).",
  breakit=("Zero-extend the immediate: <code>{20'b0, instr[31:20]}</code>.", "The loop still works (all its numbers are small and positive), but <code>addi x5, x0, -1</code> gives 0x00000FFF. Tests with only small positive numbers would never notice. That is exactly how your big core's original test passed."),
  quiz=[("How does the CPU make a loop?", "A branch at the bottom compares two registers and, if the condition holds, sets PC = PC + offset (negative offset = jump back)."), ("Why is a single-cycle CPU slow?", "The clock must wait for the longest path (fetch + decode + register read + ALU + memory + write) every single cycle, even for simple instructions.")],
  big="Your core does these same four jobs, but split into many stages and for 3 instructions at a time."),
 dict(n=7, file="L07_scoreboard.sv", title="Why simple CPUs wait", sub="dependencies and the scoreboard",
  story="Faster CPUs work like an assembly line: a new instruction starts every cycle while older ones are still finishing. Problem: if <code>add x4, x3</code> needs x3 and <code>mul x3</code> hasn't finished, the add must wait. In a single-file line, <b>everyone behind it waits too</b>, even instructions that need nothing. A scoreboard keeps one 'busy' flag per register to know who must wait.",
  pic=pic_scoreboard, words=[("RAW", "read-after-write: a true need"), ("WAW", "write-after-write: two writers"), ("stall", "wait a cycle"), ("busy bit", "'this register is being computed'")],
  look="The flag is set when an instruction starts and cleared when its result comes back. <code>stall</code> checks both sources and the destination.",
  breakit=("Only check the destination (remove the RAW check).", "The add starts before the mul finishes and would use a stale x3: the testbench catches it."),
  quiz=[("<code>addi x5, x0, 7</code> sits behind a stalled instruction. Does it need to wait?", "Logically no, it depends on nothing. An in-order CPU makes it wait anyway. Out-of-order CPUs let it go ahead (Levels 8–11)."), ("Which hazards are 'fake'?", "WAR and WAW. They only exist because there are few register names. Renaming (Level 8) removes them; only RAW is real.")],
  big="This is the problem your whole out-of-order core exists to solve."),
 dict(n=8, file="L08_rename.sv", title="Renaming", sub="ticket numbers instead of names",
  story="In a restaurant two customers might both order 'pizza'. The kitchen doesn't track 'pizza'; it tracks <b>ticket numbers</b>. The CPU does the same: every result gets a fresh ticket (a tag). The rename table (RAT) remembers, for each register, which ticket will produce its newest value. If there is no ticket, the value is already sitting in the register file.",
  pic=pic_rename, words=[("tag / ticket", "the name of a future value"), ("RAT", "register → newest ticket"), ("valid bit", "'a ticket exists'"), ("commit", "ticket finished, value saved")],
  look="Two rules. (1) A <b>separate valid bit</b>: ticket 0 is a real ticket, never 'no ticket'. (2) When a ticket finishes, clear the entry <b>only if it still points to that ticket</b>; a newer ticket may have replaced it.",
  breakit=("Clear the RAT entry on any finish, without checking the ticket number.", "When old ticket 0 finishes, it wipes the mapping that belongs to newer ticket 1. Later readers would read a stale register."),
  quiz=[("<code>mul x3…</code> gets ticket 0, then <code>sub x3…</code> gets ticket 2. Who reads which?", "Instructions between them read ticket 0. Instructions after the sub read ticket 2. Both writers can run at the same time without clashing."), ("Why is 'tag 0 means none' dangerous?", "Ticket 0 is handed out like any other number. Your big core made this mistake and every instruction waiting on ticket 0 waited forever (bug B04).")],
  big="Your core's RAT has 32 entries, and its tickets are the 48 ROB slots."),
 dict(n=9, file="L09_rs_cdb.sv", title="Waiting room and the bell", sub="reservation station + CDB",
  story="Order tickets wait on a rail (the <b>reservation station</b>) until all their ingredients are ready. When a cook finishes, they ring the bell and shout 'ticket 2 is ready, it's 30!'. That bell is the <b>common data bus (CDB)</b>. Every waiting ticket listens: anyone who needs ticket 2 grabs the 30. As soon as a ticket has everything, it raises its hand, and the oldest raised hand goes to a cook. A younger, ready instruction can go before an older, waiting one. <b>That is out-of-order execution.</b>",
  pic=pic_rs, words=[("RS", "where instructions wait for operands"), ("wakeup", "matching your tag on the bell"), ("select", "pick one ready instruction"), ("CDB", "the shared result bell")],
  look="Two subtle cases are handled: tag 0 is a real tag (only the ready bit matters), and an instruction inserted on the <b>same cycle</b> the bell rings must catch it too, or it waits forever.",
  breakit=("Add <code>&amp;&amp; e[i].a_tag != 0</code> to the wakeup.", "The test makes instruction A wait for ticket 0. It never wakes up and the testbench fails. This is your core's bug B04, rebuilt small."),
  quiz=[("Instruction B is younger than A but ready first. Who goes?", "B. Waiting A doesn't block it, which is the whole point."), ("Why one bell for everyone instead of private messages?", "The producer doesn't know who needs its result. Broadcasting the ticket number lets any number of waiters match it in the same cycle.")],
  big="Your core has 12 ALU + 4 MUL/DIV + 16 load/store RS entries and a 3-lane CDB."),
 dict(n=10, file="L10_rob.sv", title="Serve in order", sub="the reorder buffer",
  story="Dishes get cooked in any order, but customers must be served in the order they ordered. The <b>reorder buffer (ROB)</b> is a line of slots: new instructions join at the tail, finished ones are marked done, and only the one at the head (the oldest) may leave and update the real registers. This keeps the CPU's official state tidy at every moment.",
  pic=pic_rob, words=[("ROB", "the in-order line"), ("head", "oldest: commits"), ("tail", "next free slot"), ("commit / retire", "make a result official")],
  look="It's a circular FIFO (Level 5 again!) plus a 'done' flag per slot. <code>commit_valid = valid[head] &amp;&amp; done[head]</code>.",
  breakit=("Retire without waiting for <code>done</code>.", "My first testbench MISSED this: it only checked the <i>order</i> of retirement, not the values. A weak checker passes a broken design. After adding a value check, the testbench catches it. Always ask: what could be wrong that my checker can't see?"),
  quiz=[("Finish order is 2, 4, 0, 3, 1. What is the retire order?", "0, 1, 2, 3, 4, always program order."), ("Why bother? Just write results when they finish.", "If something goes wrong (a wrong-guess branch, an exception) we must undo everything after a point. With in-order retirement nothing after that point has touched the real registers yet.")],
  big="Your core's ROB has 48 slots and retires up to 3 per cycle."),
 dict(n=11, file="L11_tiny_ooo.sv", title="The whole restaurant", sub="a tiny out-of-order CPU",
  story="Now glue Levels 8, 9 and 10 together. Orders come in one per cycle (dispatch). Each gets a ticket and a ROB slot, waits on the rail for ingredients, gets cooked when ready (ALU: 1 beat, MUL: 3 beats), rings the bell, and is served in order. Below is the <b>real timeline</b> from simulating it: instructions finish out of order and retire perfectly in order.",
  pic=None, words=[("dispatch", "rename + ROB slot + RS slot"), ("issue", "start cooking"), ("structural hazard", "two results want the single bell"), ("WAW", "two writers to x3: newest wins at commit")],
  look="Look at T4 (<code>addi x5</code>): it is ordered after the slow <code>mul</code> (T2) and the <code>add</code> that waits for it (T3), yet it finishes in cycle 7, before both. Then it waits, done, until cycle 12 to be served. x3 is written by two muls; the ARF ends with the second one's value (4), because commit is in order.",
  breakit=("In <code>lookup()</code>, ignore finished-but-not-committed ROB values (<code>if (1'b0)</code>).", "An instruction whose producer already rang the bell waits for a bell that will never ring again: a missed wakeup, so the CPU stalls forever and the final registers are wrong (x4 = 0, x7 = 0)."),
  quiz=[("Why can't an ALU op start in the cycle a MUL is 2 stages along?", "Both results would reach the single bell (CDB) in the same cycle. That is a structural hazard: not enough of a resource. Your big core uses 3 CDB lanes plus a completion buffer instead."), ("Name the three places a source value can come from at dispatch.", "The register file (no ticket), the ROB (ticket finished but not yet served), or the CDB right now. Otherwise, wait for the bell.")],
  big="This is your 3-wide core in miniature. Next step: the advanced course."),
]

CSS = r'''
/* layout: a learning path — a numbered map of 11 stops (a real sequence), then one card per level */
:root{
  --bg:#F5F7FA; --card:#FFFFFF; --ink:#18212B; --ink2:#3C4856; --muted:#667385; --line:#D9E0E8;
  --teal:#0E7C7B; --teal-soft:#DDF1EF; --sun:#E8A317; --sun-soft:#FCF0D2; --coral:#D2553F; --coral-soft:#FBE3DE;
  --leaf:#3C8D47; --leaf-soft:#E0F1E2; --code:#EDF1F5;
  --f-display:"Fredoka", "Trebuchet MS", system-ui, sans-serif;
  --f-body:"Nunito Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
  --f-mono:"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace;
}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){
  --bg:#11161C; --card:#18202A; --ink:#E6ECF2; --ink2:#C2CCD7; --muted:#8F9CAB; --line:#2A3542;
  --teal:#4CC3BF; --teal-soft:#16302F; --sun:#F2C04E; --sun-soft:#3A3016; --coral:#F07A64; --coral-soft:#3B211C;
  --leaf:#6CC57A; --leaf-soft:#1A3220; --code:#1F2933; color-scheme:dark;}}
:root[data-theme="dark"]{
  --bg:#11161C; --card:#18202A; --ink:#E6ECF2; --ink2:#C2CCD7; --muted:#8F9CAB; --line:#2A3542;
  --teal:#4CC3BF; --teal-soft:#16302F; --sun:#F2C04E; --sun-soft:#3A3016; --coral:#F07A64; --coral-soft:#3B211C;
  --leaf:#6CC57A; --leaf-soft:#1A3220; --code:#1F2933; color-scheme:dark;}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--ink);font-family:var(--f-body);font-size:17px;line-height:1.65;
  padding-left:max(16px, env(safe-area-inset-left, 0px));padding-right:max(16px, env(safe-area-inset-right, 0px))}
.wrap{max-width:980px;margin:0 auto;padding-block:30px 90px}
a{color:var(--teal)}
code{font-family:var(--f-mono);font-size:.84em;background:var(--code);padding:.1em .35em;border-radius:5px}
h1{font-family:var(--f-display);font-weight:600;font-size:clamp(42px,7vw,72px);line-height:1;margin:.1em 0 .2em;letter-spacing:-.01em;text-wrap:balance}
h2{font-family:var(--f-display);font-weight:600;font-size:32px;line-height:1.1;margin:0;text-wrap:balance}
h3{font-family:var(--f-display);font-weight:500;font-size:20px;margin:22px 0 8px}
p,li{max-width:68ch}
.kicker{font-family:var(--f-mono);font-size:12px;letter-spacing:.1em;text-transform:uppercase;color:var(--teal);margin:0}
.lede{font-size:20px;color:var(--ink2);margin:0 0 18px}
.promise{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin:18px 0 8px}
.promise div{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 16px;min-width:0}
.promise b{display:block;font-family:var(--f-display);font-weight:500;font-size:18px}
.promise span{font-size:15px;color:var(--ink2)}
/* map */
.map{margin:30px 0 10px;background:var(--card);border:1px solid var(--line);border-radius:18px;padding:18px}
.map ol{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.map a{display:flex;gap:10px;align-items:center;text-decoration:none;color:var(--ink);padding:8px 10px;border-radius:12px;border:1px solid var(--line);background:var(--bg)}
.map a:hover{border-color:var(--teal)}
.dot{flex:none;width:32px;height:32px;border-radius:50%;display:grid;place-items:center;font-family:var(--f-display);font-weight:600;background:var(--teal-soft);color:var(--teal)}
.map a.ok .dot{background:var(--leaf);color:var(--card)}
.map small{display:block;font-size:12px;color:var(--muted);line-height:1.2}
.map .stage{grid-column:1/-1;font-family:var(--f-mono);font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-top:6px}
.progress{font-size:14px;color:var(--muted);margin:10px 2px 0}
/* level */
section.lvl{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:26px 28px;margin-top:28px;scroll-margin-top:14px}
.lvhead{display:flex;gap:16px;align-items:center;flex-wrap:wrap}
.big{flex:none;width:58px;height:58px;border-radius:16px;display:grid;place-items:center;font-family:var(--f-display);font-size:28px;font-weight:600;background:var(--teal);color:var(--card)}
.lvhead .tt{flex:1 1 260px;min-width:0}
.lvhead p{margin:0;color:var(--muted)}
label.done{font-size:14px;display:flex;gap:6px;align-items:center;border:1px solid var(--line);padding:6px 12px;border-radius:20px;cursor:pointer;color:var(--ink2);white-space:nowrap}
label.done:has(input:checked){border-color:var(--leaf);color:var(--leaf);background:var(--leaf-soft)}
.story{font-size:18px;background:var(--sun-soft);border-radius:14px;padding:14px 18px;margin:18px 0}
.story::before{content:"The idea";display:block;font-family:var(--f-mono);font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--ink2);margin-bottom:4px}
.picbox{overflow-x:auto;margin:14px 0}
.picbox>div{min-width:560px}
svg.pic{width:100%;height:auto;display:block;font-family:var(--f-body)}
.pic .b{fill:var(--card);stroke:var(--ink2);stroke-width:1.5}
.pic .b.hotbox{fill:var(--sun-soft);stroke:var(--sun)} .pic .b.warnbox{fill:var(--coral-soft);stroke:var(--coral)} .pic .b.dim{fill:var(--bg);stroke:var(--line)}
.pic .cellb{fill:var(--bg);stroke:var(--line)} .pic .celle{fill:none;stroke:var(--line);stroke-dasharray:4 3}
.pic .cellz{fill:var(--coral-soft);stroke:var(--coral)} .pic .cellh{fill:var(--leaf-soft);stroke:var(--leaf)} .pic .celld{fill:var(--teal-soft);stroke:var(--teal)}
.pic .bell{fill:var(--sun-soft);stroke:var(--sun);stroke-width:2}
.pic .l{stroke:var(--muted);stroke-width:1.6;fill:none} .pic .l.hot{stroke:var(--coral)} .pic .ah{fill:var(--muted)}
.pic .w{fill:none;stroke:var(--teal);stroke-width:2} .pic .grid{stroke:var(--line);stroke-dasharray:3 3}
.pic text{fill:var(--ink)} .pic .t{font-size:15px;font-weight:700} .pic .s{font-size:13px;fill:var(--muted)}
.pic .m{font-size:13px;font-family:var(--f-mono)} .pic .hotT{font-size:13px;fill:var(--coral)}
.pic .gwait{fill:var(--sun-soft);stroke:var(--sun)} .pic .gcook{fill:var(--teal)} .pic .gdone{fill:var(--leaf-soft);stroke:var(--leaf)} .pic .gc{fill:var(--ink)}
.words{display:flex;flex-wrap:wrap;gap:8px;margin:10px 0}
.word{border:1px solid var(--line);border-radius:10px;padding:4px 10px;font-size:14px;background:var(--bg)}
.word b{font-family:var(--f-mono);font-size:13px;color:var(--teal);margin-right:6px}
pre.code{background:var(--code);border-radius:12px;padding:14px 16px;overflow-x:auto;font-size:13px;line-height:1.55;margin:8px 0;max-height:520px}
pre.code code{background:none;padding:0;font-size:inherit}
details{margin:8px 0}
details>summary{cursor:pointer;font-weight:700;color:var(--teal)}
summary:focus-visible,a:focus-visible,input:focus-visible{outline:2px solid var(--sun);outline-offset:2px}
.run{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:12px;margin:12px 0}
.panel{border-radius:14px;padding:12px 14px;min-width:0}
.panel.ok{background:var(--leaf-soft)} .panel.bad{background:var(--coral-soft)}
.panel h4{margin:0 0 6px;font-family:var(--f-display);font-weight:500;font-size:17px}
.panel p{margin:6px 0;font-size:15px}
.out{font-family:var(--f-mono);font-size:12.5px;background:var(--card);border-radius:8px;padding:6px 8px;overflow-x:auto;white-space:pre}
.quiz details{background:var(--bg);border:1px solid var(--line);border-radius:12px;padding:8px 14px}
.quiz details p{margin:6px 0 2px}
.bigcore{border-left:4px solid var(--teal);padding:4px 12px;color:var(--ink2);margin-top:14px}
pre.term{background:var(--ink);color:var(--bg);border-radius:12px;padding:14px 16px;overflow-x:auto;font-family:var(--f-mono);font-size:13px}
.next{background:var(--teal);color:var(--card);border-radius:20px;padding:24px 28px;margin-top:28px}
.next h2{color:var(--card)} .next p{color:var(--card)} .next a{color:var(--card);font-weight:700}
@media (max-width:700px){
  section.lvl{padding:20px 16px}
  .promise,.run{grid-template-columns:minmax(0,1fr)}
  h2{font-size:27px}
}
@media (prefers-reduced-motion: reduce){*{transition:none!important}}
'''

def level(d):
    k = f"L{d['n']:02d}"; res = R[k]
    mod, tb = src(d['file'])
    o = [f'<section class="lvl" id="lv{d["n"]}">',
         f'<div class="lvhead"><div class="big">{d["n"]}</div><div class="tt"><h2>{d["title"]}</h2><p>{d["sub"]} · <code>{d["file"]}</code></p></div>'
         f'<label class="done"><input type="checkbox" id="done-{d["n"]}" data-n="{d["n"]}"> I got this</label></div>',
         f'<p class="story">{d["story"]}</p>']
    if d['pic']:
        o.append(f'<div class="picbox"><div>{d["pic"]()}</div></div>')
    else:
        o.append(f'<div class="picbox"><div style="min-width:700px">{pic_gantt(res["log"])}</div></div>')
    o.append('<div class="words">' + ''.join(f'<span class="word"><b>{a}</b>{b}</span>' for a, b in d['words']) + '</div>')
    o.append(f'<h3>Read the code</h3><p>{d["look"]}</p>')
    o.append(f'<pre class="code"><code>{E(mod)}</code></pre>')
    o.append(f'<details><summary>Show the self-checking testbench</summary><pre class="code"><code>{E(tb)}</code></pre></details>')
    mut = res['mut'].split('CAUGHT: ')[-1]
    o.append(f'<h3>Run it, then break it</h3><div class="run">'
             f'<div class="panel ok"><h4>Run it</h4><p><code>./run_all.sh {d["n"]}</code></p><div class="out">{E(res["pass"])}</div></div>'
             f'<div class="panel bad"><h4>Break it on purpose</h4><p>{d["breakit"][0]}</p><div class="out">{E(mut)}</div><p>{d["breakit"][1]}</p></div></div>')
    if d['n'] == 11:
        o.append('<details><summary>Show the full event log</summary><pre class="code"><code>' + E('\n'.join(res['log'])) + '</code></pre></details>')
    o.append('<h3>Check yourself</h3><div class="quiz">' + ''.join(f'<details><summary>{q}</summary><p>{a}</p></details>' for q, a in d['quiz']) + '</div>')
    o.append(f'<p class="bigcore"><b>In your big core:</b> {d["big"]}</p></section>')
    return ''.join(o)

JS = r'''
(function(){
  const st = { get(k){ try{return localStorage.getItem(k);}catch(e){return null;} }, set(k,v){ try{localStorage.setItem(k,v);}catch(e){} } };
  const boxes = [...document.querySelectorAll('input[data-n]')];
  function upd(){ let n=0; boxes.forEach(b=>{ const a=document.querySelector('.map a[href="#lv'+b.dataset.n+'"]'); if(a) a.classList.toggle('ok', b.checked); if(b.checked) n++; });
    document.getElementById('prog').textContent = n + ' of ' + boxes.length + ' levels done' + (n===boxes.length ? ' - you built an out-of-order CPU.' : ''); }
  boxes.forEach(b=>{ b.checked = st.get('lvl-'+b.dataset.n)==='1'; b.addEventListener('change',()=>{ st.set('lvl-'+b.dataset.n, b.checked?'1':'0'); upd(); }); });
  upd();
})();
'''

STAGES = {1: "Part 1 · Building blocks", 6: "Part 2 · A first CPU", 7: "Part 3 · Going out of order"}

def page():
    P = ['<title>CPU From Zero</title><meta name="claude:viewport-fit-sides" content="cover">',
         '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>',
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&family=JetBrains+Mono:wght@400;600&family=Nunito+Sans:ital,wght@0,400;0,700;1,400&display=swap">',
         f'<style>{CSS}</style><div class="wrap">',
         '<header><p class="kicker">Beginner track · 11 levels · SystemVerilog</p><h1>CPU From Zero</h1>'
         '<p class="lede">Start with a single wire and finish with a working out-of-order CPU. Every level is small enough to type in one sitting, comes with a story, a picture, and a test that tells you if you got it right.</p>'
         '<div class="promise"><div><b>No background needed</b><span>If you know what 1 + 1 is, you can start. Each level uses only what came before.</span></div>'
         '<div><b>Everything really runs</b><span>All 11 designs were simulated. The outputs on this page are real, not made up.</span></div>'
         '<div><b>Break things on purpose</b><span>Each level shows one classic mistake and how the test catches it. That is how verification engineers think.</span></div></div></header>']
    P.append('<nav class="map" aria-label="Levels"><ol>')
    for d in L:
        if d['n'] in STAGES: P.append(f'<li class="stage">{STAGES[d["n"]]}</li>')
        P.append(f'<li><a href="#lv{d["n"]}"><span class="dot">{d["n"]}</span><span>{d["title"]}<small>{d["sub"]}</small></span></a></li>')
    P.append('</ol><p class="progress" id="prog">0 levels done</p></nav>')
    P.append('''<section class="lvl" id="setup"><div class="lvhead"><div class="big">0</div><div class="tt"><h2>Get ready</h2><p>10 minutes, once</p></div></div>
<p class="story">You need one free tool: <b>Verilator</b>, a simulator. It turns your hardware description into a program that pretends to be the chip, so you can watch it work without building anything.</p>
<pre class="term">pip install verilator            # or: sudo apt install verilator  (needs version 5.026 or newer)
cd beginner
./run_all.sh                     # builds and tests all 11 levels
./run_all.sh 6                   # just one level</pre>
<p>Every testbench prints one line ending in <b>PASS</b> or <b>FAIL</b>. The files are in the <code>beginner/</code> folder of the lab kit. The best way to learn: open the level's file, <b>delete the module body, and type it again yourself</b> from the explanation. Then run the test.</p>
<h3>How to read SystemVerilog in 60 seconds</h3>
<pre class="code"><code>module name (input logic a, output logic y);   // a box with pins
  logic [31:0] x;          // 32 wires bundled together, bit 31 on the left
  assign y = a &amp; b;        // permanent wiring (combinational)
  always_comb  begin ... end   // logic that recomputes instantly
  always_ff @(posedge clk) begin q &lt;= d; end   // memory that updates on the clock tick
endmodule</code></pre></section>''')
    for d in L:
        P.append(level(d))
    P.append(f'''<section class="next"><h2>You built an out-of-order CPU. Now meet the real one.</h2>
<p>Your 3-wide core is Level 11 made wider and faster: 3 instructions per cycle, 48 ROB tickets, 32 RS entries, a 3-lane bell, and loads/stores with their own ordering puzzles. The advanced course takes it apart module by module, with 15 real bugs, many of which you have now met in miniature (sign extension, tag 0, valid/ready, retire-before-done).</p>
<p><a href="{ADV_URL}">Open the Tomasulo Core Lab →</a></p></section>''')
    P.append(f'</div><script>{JS}</script>')
    return '\n'.join(P)

out = sys.argv[1]
open(out, 'w').write(page())
print('wrote', out, os.path.getsize(out))
