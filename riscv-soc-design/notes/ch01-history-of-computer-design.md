# Ch 1 · A Brief History of Computer Design

Every CPU feature you will verify — pipelines, caches, branch predictors, out-of-order execution, multicore — was invented to spend more transistors on more performance; this chapter is the story of why each arrived when it did, and why that game changed around 2004.

## 1.1 Moore's Law and Dennard scaling

Shrinking a transistor made it faster, lower-power and cheaper all at once, and for about 30 years that single fact paid for every new CPU feature; around 2004 the "lower-power" part stopped working, and CPU design has been different ever since.

### First principles: what a transistor is and why smaller is better

- A **transistor** is an electrically controlled switch: a voltage on its *gate* controls current between two other terminals. Digital logic is built from these switches (invented 1947 at Bell Labs; the integrated circuit, many transistors on one substrate, in 1958).
- Chips are printed by **photolithography**: light through a mask defines transistor and wire shapes on a silicon wafer, which is then diced into chips.
- Make the transistor smaller and three good things happen together:
  - **Faster** — electrons travel a shorter distance.
  - **Lower power** — fewer electrons move per switch.
  - **Cheaper** — more transistors fit on the same wafer.

### Moore's Law (1965)

Gordon Moore observed that transistors per chip grow exponentially. In practice: about **40% per year, doubling roughly every two years, for five decades** — 11 orders of magnitude. The book's example: the 2024 Apple A17 Pro has about 19 billion transistors on 1 cm² for roughly $40, or about **2 nanodollars per transistor**.

But no exponential lasts forever. Leading-edge fabs now cost tens of billions, so manufacturing has consolidated to TSMC, Samsung, UMC, GlobalFoundries, SMIC and Intel — and the cost advantage of each new node is fading:

&#91;embedded content: Book Table 1.1 (Zafar19) · 5 process nodes, 2014–2022\]

### Dennard scaling (1974): why shrinking also cut power

Dennard showed what happens if you shrink dimensions, supply voltage and threshold voltage all by 30% (a factor k = 0.7). Start from dynamic power:

```latex
P_{dynamic} = \alpha \, C \, V_{DD}^{2} \, f
```

| Quantity | Scales by | Why |
| --- | --- | --- |
| Transistor area | 0.7 × 0.7 ≈ 0.5 | Both dimensions shrink → **2× transistors** in the same area |
| Capacitance C | 0.7 | Smaller gates |
| Voltage V | 0.7 → V² ≈ 0.5 | Supply scaled down |
| Frequency f | 1 / 0.7 ≈ 1.4 | Shorter delay |
| Power per transistor | 0.7 × 0.5 × 1.4 ≈ **0.5** | Half the power each… |
| Power per chip area | 2× transistors × 0.5 = **1** | …so power density stays constant |

That is the magic: every node gave **2× transistors at 1.4× speed for the same power per area**. Architects could spend the free transistors on pipelines, caches and predictors *and* raise the clock.

### Why Dennard scaling ended (\~2004)

1. **Threshold voltage couldn't keep falling.** Subthreshold leakage (current through a switch that is supposed to be off) grows *exponentially* as Vt drops. So V stopped scaling — and with V stuck, the V² saving disappears.
2. **Gate oxide hit atomic limits.** Below about 12 Å (about 4 atomic layers) electrons quantum-tunnel through the insulator → unacceptable gate leakage.

With V fixed, doubling transistors and raising f now **raises power density** — the *power wall* (section 1.6). Progress since then comes from device inventions (strained silicon, high-k metal gates, FinFETs, gate-all-around) rather than pure shrinking, and node names (7 nm, 5 nm, 3 nm) no longer match any physical dimension.

&#91;image: Two dies shrink through five generations: with voltage scaling, power density stays 1x and every transistor can switch; with voltage stuck, power density climbs to 35x and only 3% of the die can run at the same power\]

*Animated: the same die through five generations. Left, Dennard scaling keeps power density flat. Right, with voltage stuck, each transistor's power stays about the same (capacitance × 0.7, frequency × 1.43), so twice the transistors means **twice the power density every generation** — 35× after five. To stay within the same cooling, 97% of the die must stay dark. Try it yourself in experiment 1 of the companion page.*

### Why a CPU verification engineer should care

- The power wall is why chips went **multicore** → cache coherence, memory ordering and atomics became central verification problems (Chapter 17).
- Power can't be wasted any more → clock gating, power gating, DVFS and retention states are now features you verify, along with **dark silicon** (section 1.2).
- Rising design cost means fewer, bigger tape-outs — a bug escape costs more than ever.

**Check yourself**

- Using P = αCV²f, show why power per transistor halves under ideal Dennard scaling, and why power density then stays flat.
- Which physical effect stopped voltage scaling, and what did that do to clock frequency?
- "Moore's Law is dead" — argue for and against using Table 1.1.

## 1.2 System-on-Chip

More transistors let one chip hold an entire system — several kinds of processor cores, caches, accelerators and I/O — and designing and verifying such a chip now costs hundreds of millions of dollars, with verification costing more than design itself.

### Architecture vs microarchitecture (the idea the whole book rests on)

- **Architecture (ISA)**: the programmer's view — instructions, registers, memory addressing. Same ISA → the same program runs, so customers can upgrade without rewriting software.
- **Microarchitecture**: the registers, memories and execution units that implement it. Free to change every generation.
- As transistor budgets grew, microarchitectures spent them on, in order:
  - **Wider data**: 8 → 16 → 32 → 64-bit.
  - **More overlap**: microcoded → pipelined → superscalar → out-of-order.
  - **More cores**: single → multicore.

### What an SoC is

- **General-purpose** chips (CPUs, GPUs, FPGAs) vs **ASICs** (Wi-Fi modems, disk controllers, Bitcoin miners) — a line that blurs as ASICs gain programmable parts.
- An **SoC** combines many processors, memories, accelerators and buses. The book's example, the Apple A15: at least 2 high-performance + 4 energy-efficient CPU cores, tens of MB of L2/L3 cache, GPU and neural-engine cores, video and image accelerators, display and DRAM interfaces, all at several GHz doing tens of trillions of operations per second.
- **Dark silicon**: running everything at once would overheat the chip, so only part of it is powered at any moment. This is the power wall from 1.1, seen at chip level.
- **Accelerators are 100–1000× more energy-efficient** than general-purpose cores for their task, so work is offloaded to them whenever possible.
- The system is so complex that a **small management microprocessor** controls power and clocks for everything else — often a RISC-V core.

### Why cost exploded — and why verification is the biggest slice

&#91;embedded content: Values read from book Fig. 1.5 (International Business Strategies, Sept 2024) · 9 nodes\]

- Teams grew from 1–2 people in the 1970s to hundreds across companies, yet transistors per designer still rose \~100,000×. Productivity came from:
  - **HDLs** (Verilog, VHDL) replacing transistor schematics in the 1990s.
  - **EDA synthesis** (e.g. Synopsys Design Compiler) turning HDL into gates.
  - **IP reuse**: processors, memories, peripherals and cell libraries bought or reused — ideally *with their test frameworks*.
- The book is blunt: **verifying correctness now takes more time and money than design**, and the largest cost and source of errors is the **software** running on the SoC.
- Result: only a handful of companies (Intel, Apple, Qualcomm, AMD, NVIDIA, Google and a few others) can afford leading-edge SoCs. That's why open-source hardware and software (Linux, GCC, RISC-V) matter commercially, not just ideologically.

### Why it matters for your career

This is the economic reason CPU DV jobs are senior and well-paid: a design that costs over $500M at 3 nm cannot afford a respin. Your RISC-V subsystem experience is SoC integration verification; a CPU DV role goes one level deeper, into a single IP block that the SoC team then trusts.

**Check yourself**

- Explain dark silicon using the power-density argument from 1.1.
- Why do accelerators beat general-purpose cores on energy, and what do they give up?
- Why does IP reuse lower *verification* cost, not just design cost?

## 1.3 Birth of computing

Early computing was a search for a reliable, fast switch — gears, then relays, then vacuum tubes, then transistors — and for the idea that made computers general: keep the program in memory, as data.

### First principles: what makes something a computer

1. **Binary switches.** Konrad Zuse saw that a switch has two states, so binary is the natural number system. Every later technology is just a better switch.
2. **Programmable.** The same machine runs different procedures (Colossus via plugs and switches; Mark I via paper tape).
3. **General-purpose.** It can compute anything computable, given time and memory (Turing's universal machine).
4. **Stored program.** Instructions live in the same memory as data, so programs can be loaded, changed and even generated by other programs. This is the step that made software possible.

### The switch technology ladder

| Switch | Era | Speed | Problem it solved | Problem it created |
| --- | --- | --- | --- | --- |
| Gears | 1820s–1830s (Babbage) | Hand-cranked | Error-free tables | Too hard to build in his lifetime |
| Relays | 1940s (Z3, Mark I) | Milliseconds | Electrically controlled | Slow, unreliable (and attracted moths) |
| Vacuum tubes | 1940s–1950s (Colossus, ENIAC) | Microseconds | 1000× faster | Hot, power-hungry, burned out (one ENIAC tube every two days) |
| Transistors | 1950s–60s (IBM Stretch) | Nanoseconds | Small, reliable, low power | Wiring thousands of discrete parts |
| Integrated circuits | 1960s → today | Picoseconds | Many transistors per chip | Power density (section 1.1) |

### Milestones (book Fig. 1.6, first half)

| Year | Machine | First at | Why a CPU engineer cares |
| --- | --- | --- | --- |
| 1830–1871 | Analytical Engine (Babbage) | Digital computer design | Had programmable instructions and a 1000-element memory |
| 1941 | Z3 (Zuse) | General-purpose computer | Binary, because a switch has two states |
| 1942 | ABC (Atanasoff, Berry) | Electronic computer | Vacuum tubes for digital logic |
| 1943 | Colossus (Bletchley Park) | Programmable electronic computer | 1,600 tubes; codebreaking |
| 1944 | Harvard Mark I | Separate program and data | Origin of "Harvard architecture" |
| 1945 | ENIAC (U. Penn) | Electronic, general-purpose, programmable | 5 kHz, 30 tons, 174 kW |
| 1948 | Manchester "Baby" | Stored program | Programs become data |
| 1949 | EDSAC (Cambridge) | Practical stored-program machine | First in regular use |
| 1951 | EDVAC (U. Penn) | von Neumann's stored-program design | Origin of "von Neumann architecture" |
| 1961 | IBM 7030 Stretch | Transistor-based computer | Pioneered **pipelining, interrupts, memory protection, multiprogramming** |

### Harvard vs von Neumann, and how modern CPUs use both

|  | Harvard | von Neumann |
| --- | --- | --- |
| Memory | Separate instruction and data memories | One memory holds both |
| Strength | Fetch an instruction and load data in the same cycle | Flexible: programs can load and modify programs |
| Weakness | Can't treat code as data | Instruction fetch and data access compete |
| Where you see it | Our single-cycle and pipelined cores (IROM + DTIM) | Main memory of every PC and phone |

Modern CPUs get both: a **unified main memory** (von Neumann) behind **separate L1 instruction and data caches** (Harvard). The catch for verification: when software writes code as data (JIT compilers, self-modifying code), the instruction cache may hold stale bytes — which is why RISC-V has `fence.i`.

**The first "bug"** (1947): Grace Hopper's team found a moth shorting a relay in the Harvard Mark II and taped it into the logbook.

**Check yourself**

- What exactly does "stored program" add over "programmable"?
- Why does a pipelined core prefer a Harvard-style memory interface?
- Why does a unified memory with split caches need an instruction like `fence.i`?

## 1.4 Mainframes and minicomputers

The IBM System/360 invented the idea you'll spend your career verifying — one ISA, many microarchitectures — and timesharing operating systems forced the hardware features (privilege, protection, interrupts, virtual memory) that make CPUs hard to verify today.

### System/360 (1964): the architecture/microarchitecture split

- IBM bet the company — about $5 billion, half the cost of the Manhattan Project — on a **family** of computers sharing one ISA.
- The range was huge: **Model 30** with 8 KiB of core memory and 34.5 thousand instructions/s, up to **Model 91** with 6 MiB and 16.6 million instructions/s, filling a room and drawing 94 kW. Same software on all of them.
- Compatibility has lasted six decades: the 2022 **z16** (up to 200 cores at 5.2 GHz) still runs System/360 code.
- **The lesson:** an ISA is a long-term promise to software. Microarchitecture can change completely underneath it — which is exactly why the reference model (ISA) and the RTL (microarchitecture) are different things, and why verification compares them.

### Hardware of the era

- **Core memory**: each bit a hand-woven ferrite ring, magnetized one way or the other.
- **Solid Logic Technology**: transistor + diodes + resistors on one substrate, a precursor to ICs.
- **74xx TTL chips** (TI, 1966): a few gates per package; minicomputers were racks of boards full of them.

### Minicomputers and the birth of Unix

- **DEC PDP-11** (1970s): about 600,000 sold from $12,000 — affordable for universities. Its 18-bit address space proved too small, so DEC followed with the 32-bit **VAX** (virtual memory, floating point, vector processing).
- **Multics** (MIT, GE, Bell Labs, 1964) pioneered timesharing, virtual memory and security but was late and expensive.
- Bell Labs engineers (Thompson, Ritchie and others) built a simpler OS, **Unix** (\~1970), then the **C language** (1972–73) to rewrite it portably. Linus Torvalds reimplemented Unix as open-source **Linux** in 1991.

### First principles: why operating systems shaped CPU hardware

Batch processing ran one job at a time. **Timesharing** runs many users' programs on one machine, and that only works if the hardware enforces rules the programs can't break:

| OS need | Hardware feature | Where in the book |
| --- | --- | --- |
| A buggy program must not crash others or the OS | Privilege modes (user vs supervisor vs machine) | Ch 8 |
| The OS must regain control periodically | Timer interrupts, traps | Ch 8, Ch 20 (CLINT) |
| Programs must not read each other's memory | Memory protection (PMP), virtual memory | Ch 11 |
| Each program thinks it owns all of memory | Virtual memory with page tables + TLB | Ch 11 |
| Many users share devices | Interrupt controller | Ch 20 (PLIC) |

Each row is a whole class of corner cases for a verification engineer: a trap arriving mid-instruction, a page fault on a store, an interrupt during a TLB miss.

**Check yourself**

- Why was System/360's compatibility worth $5 billion to IBM's customers?
- Name three hardware features timesharing requires, and the bug class each introduces.
- Why did Unix being written in C matter for hardware vendors?

## 1.5 Microprocessors

Once a whole CPU fit on one chip (Intel 4004, 1971), each new generation spent its extra transistors on one big idea — wider data, memory management, pipelining, caches, superscalar issue, out-of-order execution — and that sequence is the table of contents of a CPU architecture course.

### The first microprocessor

- Intel (founded 1968 by Noyce and Moore) first sold a 64-bit SRAM, the 3101, to replace core memory.
- In 1969 a calculator company, Busicom, asked for a 12-chip calculator chipset. Ted Hoff and Federico Faggin realized a **programmable processor** would be cheaper: the **4004** (1971), 4-bit, **2,300 transistors**, 10 µm pMOS, its layout cut by hand from red rubylith film.
- **First principle:** a general-purpose programmable chip beats a custom one when volume is high and requirements change — the same argument behind every SoC's embedded RISC-V management core.

### How each generation spent its transistors

| Chip (Intel x86) | Year | New idea | What it is | Book chapter |
| --- | --- | --- | --- | --- |
| 8086 / 8088 | 1978 / 1979 | 16-bit ISA (8088: cheap 8-bit bus) | Wider registers and ALU | 2 |
| 80286 | 1982 | 24-bit addresses + MMU | Memory protection for multitasking | 11 |
| 80386 | 1985 | 32-bit ISA | Datapath, bus unit, **microcode PLA**, random logic on one die | 2, 7 |
| 80486 | 1989 | **Pipelining + on-chip cache + FPU** | Overlap instructions; keep data close | 7, 10, 16 |
| Pentium | 1993 | **2-way superscalar** | Issue two instructions per cycle (CPI below 1) | — (beyond Wally) |
| Pentium Pro / II / III / 4 | 1995–2000 | **Out-of-order**, wider issue | Execute instructions when their operands are ready, not in program order | — (covered later in these notes) |

### First principles behind the jargon

- **Microcode vs hardwired control.** Hardwired control is a decoder (like `decoder` in the Labs) that produces control signals directly. Microcode stores a small program per complex instruction in a ROM/PLA; the control unit steps through it. Microcode makes complex instructions easy to add and fix, at the cost of many cycles per instruction.
- **Superscalar.** Fetch, decode and execute two or more instructions per cycle using duplicated hardware. Performance is then measured as **IPC** (instructions per cycle), the inverse of CPI.
- **Out-of-order.** Instructions wait in a buffer until their operands are ready, then execute in any order, but **retire in program order** so exceptions stay precise. This is where reorder buffers and register renaming come from — core topics in NVIDIA, AMD and Intel CPU DV interviews.

### The PC revolution, and why x86 got messy

- The 6502-based **Apple II** ($1,300, 1977) and the 8088-based **IBM PC** ($1,565, 1981) made computers personal. IBM required a second source, so **AMD** began making compatible chips — the origin of today's Intel/AMD rivalry.
- Every generation kept running old software, so x86 accumulated decades of backward-compatible, variable-length instructions — the book calls it a "Frankenstein monster." Decoding x86 is genuinely hard, which matters in 1.6.

**Check yourself**

- Why did Busicom's calculator become a general-purpose processor?
- What is the difference between CPI and IPC, and why does superscalar make IPC the natural metric?
- Out-of-order cores execute out of order but retire in order. Why?

## 1.6 CISC and RISC

RISC won the 1980s–90s debate by attacking the iron law from a different side — more, simpler instructions that each run in about one short cycle — and x86 survived by turning itself into a RISC machine on the inside; then the power wall ended the clock-rate race and pushed everyone to multicore.

### Why CISC made sense in the 1970s

Memory was small and slow, and compilers were weak, so architects packed as much work as possible into each instruction. Example: x86 `REP MOVS` copies a whole string in one instruction; some machines were tuned to run LISP directly.

The costs (Patterson & Ditzel's 1980 RISC manifesto): long design times, many design errors, lots of state to save on a context switch, long clock cycles — and in practice about a quarter of the instructions accounted for 99% of those executed.

### The RISC idea, as an iron-law argument

```latex
T_{CPU} = N_{instructions} \times CPI \times T_c
```

|  | CISC | RISC |
| --- | --- | --- |
| N (instruction count) | Lower: one instruction does a lot | Higher: simple instructions |
| CPI | High: microcoded, many cycles each | \~1: pipelined, one per cycle |
| Tc | Long: complex decode and datapath | Short: simple, regular hardware |
| Memory access | Most instructions may touch memory | Only loads and stores (load/store architecture) |
| Instruction length | Variable (x86: 1 to 15 bytes) | Fixed 32 bits |

RISC bets that the drop in CPI × Tc outweighs the rise in N.

**Illustrative example (not from the book):** copy 100 bytes. CISC: one `REP MOVSB`, say \~4 cycles per byte = 400 cycles at 66 MHz ≈ 6.1 µs. RISC: a 5-instruction loop per byte (`lb`, `sb`, two `addi`, `bne`) = 500 instructions at CPI 1.2 = 600 cycles at 200 MHz ≈ 3.0 µs. Five times the instructions, still twice as fast. The animated companion steps through both.

### The RISC pioneers

- **IBM 801** (1970s, John Cocke): the first RISC.
- **RISC-I** (Berkeley, Patterson, 1982): a 78 × 32-bit register file dominates the die.
- **MIPS-I** (Stanford, Hennessy, 1982–84), **ARM1** (Acorn, Furber and Wilson, 1985), **SPARC** (Sun, from Berkeley RISC).
- Hennessy and Patterson shared the 2017 Turing Award; their *Computer Architecture: A Quantitative Approach* remains the standard text.

### How the debate ended

- 1992: DEC's **Alpha 21064** RISC ran at **200 MHz**; Intel's 1993 CISC **Pentium** ran at **66 MHz**. A 3× clock advantage settled the argument.
- Intel's answer, from the **Pentium Pro** on: decode each x86 instruction into one or more RISC-like **micro-ops** and run those on a fast out-of-order core. **CISC outside, RISC inside** — still true of every Intel and AMD x86 core today.

### The megahertz wars and the power wall

&#91;embedded content: Book Fig. 1.23 (Hennessy & Patterson, 2019) · 8 processors, 1978–2017\]

- Processors were marketed by clock rate. Intel's P6 went from **200 MHz** (Pentium Pro, 1995, 0.35 µm) to **1.13 GHz** (Pentium III, 1999, 0.13 µm); NetBurst (Pentium 4) reached **3.4 GHz** by 2002 in the same process.
- They got there by **superpipelining**: 14 stages in the Pentium III, **20 to 31+** in the Pentium 4. Longer pipelines meant more hazards and bigger branch penalties, so performance rose less than clock rate, sometimes not at all.
- Power passed **100 W**. In 2001 Intel's CTO Pat Gelsinger showed that, on trend, power density would reach a nuclear reactor by 2005, a rocket nozzle by 2010 and the surface of the sun by 2015.
- **2006:** Intel abandoned NetBurst for the **Core** microarchitecture — several power-efficient cores derived from the Pentium Pro. Performance now had to come from **parallelism**, not frequency. Single-thread performance growth fell from about **52%/year** (1986–2003) to just a few percent per year.
- Today's pipeline depths, per the book: about **2 stages** in low-cost microcontrollers, **5–8** in energy-efficient cores, **13–20** in high-performance cores. Wally's 5 stages sit in the efficient class.
- Modern example: Intel's Raptor Lake (13th-gen Core) mixes 8 high-performance and 16 energy-efficient cores at up to 5.7 GHz on one 257 mm² die.

### Where ARM fits

Nearly all phones and tablets use ARM-based cores (also Apple Macs and Raspberry Pi); more than 25 billion ARM processors ship a year. ARM earns money by **licensing** its ISA and cores to Qualcomm, Samsung, MediaTek and Apple — and guards that IP closely, which is part of why RISC-V appeared (1.7).

### Why this matters in a CPU DV interview

- "Why do x86 cores decode into micro-ops?" and "why did clock rates stop rising?" are common warm-up questions at Intel and AMD.
- Micro-op translation adds a verification layer: the x86 instruction must behave as its micro-op sequence, including exceptions mid-sequence.
- Multicore → every shared-memory feature (coherence, atomics, memory ordering) became a verification problem.

**Check yourself**

- Use the iron law to explain why RISC can win with *more* instructions.
- Why did 31-stage pipelines not deliver 31-stage performance?
- What does "CISC outside, RISC inside" mean, and what new verification problem does it create?

## 1.7 RISC-V

RISC-V (2010, Berkeley) is the fifth Berkeley RISC: it keeps what 30 years of RISC experience proved, drops the features that made MIPS and ARM hard to build fast, and — most importantly — is an open standard anyone can implement without a license.

### Why a new ISA at all

- Every major ISA was **proprietary**: x86 (Intel/AMD) and ARM (licensed for royalties, guarded closely — ARM even sued its customer Qualcomm in 2022). Universities and startups couldn't freely build, teach or extend them.
- Krste Asanović, Andrew Waterman, Yunsup Lee, David Patterson and others started RISC-V as a Berkeley summer project in 2010. It is now stewarded by the nonprofit **RISC-V International**.

### What it fixes, and the hardware reason

| Older ISA choice | Why it hurts a fast implementation | RISC-V choice |
| --- | --- | --- |
| ARM: conditional execution on most instructions | Every instruction depends on condition flags → extra dependencies to track and rename | Branches compare two registers directly; no flags register |
| ARM: few registers | More loads/stores to spill values | 32 integer registers |
| ARM: addressing modes with three source registers | Register file needs a third read port → bigger, slower | At most two source registers per integer instruction |
| ARM: optional shift before the ALU | Shifter in series with the ALU lengthens the critical path | Shifts are separate instructions |
| MIPS: branch delay slots (Section 2.6) | Bakes one pipeline's timing into the ISA forever | No delay slots |
| Everyone: monolithic ISA | Every implementation carries every feature | **Small base (RV32I/RV64I) + optional extensions** (M, A, F, D, C, B, V…) |

You've already met the payoff in the Labs: register fields in fixed positions, the sign bit always in bit 31, and a decoder small enough to read in one sitting.

### Adoption (as of the book's writing)

- More than **13 billion RISC-V cores** shipped by 2024 — **over a billion of them inside NVIDIA GPUs** (as embedded controllers).
- The SHD Group (2024) forecast RISC-V revenue growing about 47% a year to **$92 billion by 2030**.
- The book's prediction: x86 keeps laptops and desktops, ARM keeps phones and tablets (with some RISC-V competition), and RISC-V replaces most of the many proprietary ISAs in embedded and data-center roles.

### Your angle in interviews

- At **NVIDIA**, RISC-V is not a side topic: their GPUs embed RISC-V cores by the hundreds of millions. Your RISC-V subsystem experience maps directly.
- At **ARM, Intel, AMD**: frame RISC-V knowledge as ISA fluency — privilege modes, traps, memory ordering, extensions — and show you can map it to AArch64 or x86 (see the translation table in your Interview Prep doc).
- A good one-liner: *"RISC-V's openness means the verification ecosystem is open too — Sail, Spike, riscv-arch-test, riscv-dv, RVVI — so I've worked with the same lock-step methodology commercial teams use."*

**Check yourself**

- Why does removing condition flags make an out-of-order core simpler?
- What's the advantage of a small base ISA plus extensions for a verification team?
- Why would a GPU company put RISC-V cores inside its chips?

## 1.8 Economic and security competition

Leading-edge chip manufacturing now costs so much that only a few companies — concentrated in Taiwan and South Korea — can do it, which has turned semiconductors into a matter of national security.

&#91;embedded content: Book Fig. 1.27 (IDC23) · 2022 market shares\]

### How the industry consolidated

- In the 1970s a few engineers could start a chip company with its own fab. Exponential fab costs forced a shakeout: first small companies, then small countries, "now smaller continents."
- Most designers became **fabless** and use **foundries** (manufacturers that build other companies' chips). TSMC builds for Apple, Qualcomm, AMD, NVIDIA, Broadcom and MediaTek.
- AMD and IBM sold their fabs (2008, 2014), which became GlobalFoundries; Europe's ST stopped at 14 nm FinFET; Japan fell to about 2% of global foundry capacity by 2020; Intel, long a year or two ahead, stumbled at 10 nm and now trails the leading foundries.

### Why it became a security issue

- Computing drives economic growth, and AI may be the next wave: NVIDIA's market value tripled to more than $3 trillion in 2024 on demand for its chips.
- Governments have banned suppliers over espionage concerns (Huawei and ZTE in 2018), imposed export controls on chips and on lithography equipment (2023), and seen retaliation on raw materials such as gallium and germanium.
- The two largest producers sit in geopolitically exposed places, so the US passed the **CHIPS Act** (2022, $280 billion over a decade), and the EU, UK and Japan followed with their own programs.
- An open ISA like RISC-V reduces any single country's or company's control over processor architectures.

For a verification engineer this mostly shows up as context: companies multi-source manufacturing and IP, and an open, well-verified core is strategically valuable.

**Check yourself**

- What is a foundry, and why did most chip companies become fabless?
- Why does an open ISA matter geopolitically, not just commercially?

## Chapter 1 recap and interview drill

**Animated companion:** [Power Wall Lab](https://claude.ai/artifact/7EVEcwNgLwurgdFtpQXdVC) — drag a process slider to watch Dennard scaling and dark silicon, race a CISC and a RISC machine cycle by cycle, and step through the switch-technology eras.

### The chapter in six sentences

1. Transistors are switches; shrinking them made them faster, lower-power and cheaper at once, and Moore's Law delivered that for five decades.
2. Dennard scaling (shrink V with size) kept power density flat, so every generation got 2× transistors at 1.4× speed for free.
3. Around 2004 voltage stopped scaling (leakage, oxide tunneling); power density rose, clocks stalled at \~3–5 GHz, and the industry turned to multicore, accelerators and dark silicon.
4. System/360 separated architecture from microarchitecture; timesharing forced privilege, protection, interrupts and virtual memory into hardware.
5. RISC beat CISC on the iron law (lower CPI × Tc outweighs higher N), and x86 survived by translating to RISC-like micro-ops internally.
6. RISC-V is an open, modular, implementation-friendly ISA; its open verification ecosystem is part of its value.

### Interview questions with model answers

**Q1. Why did single-core clock frequencies stop rising around 2004?**

> Dynamic power is αCV²f. Under Dennard scaling, V dropped with every node, so power per transistor halved while transistor count doubled — power density stayed flat. Around 2004 threshold voltage couldn't drop further without exponential subthreshold leakage, and gate oxide hit tunneling limits, so V stalled near 1 V. With V fixed, doubling transistors and raising f increases power density, and chips hit the cooling limit — the power wall. Performance had to come from parallelism and specialization instead of frequency.

*Follow-up:* "So how do modern chips still get faster?" → more cores, wider and smarter out-of-order cores (higher IPC), bigger caches, accelerators, and running parts of the chip only when needed (DVFS, power gating).

**Q2. RISC vs CISC — which is better, and why do x86 chips still win benchmarks?**

> By the iron law, RISC raises instruction count but lowers CPI and cycle time, and in the early 1990s that won decisively: the 200 MHz Alpha against the 66 MHz Pentium. But ISA is now a small factor. Since the Pentium Pro, x86 decodes into RISC-like micro-ops and runs them on an out-of-order core, so the back end is effectively RISC. The cost of CISC moved to the front end — complex, power-hungry decoders for variable-length instructions — which matters most in low-power designs.

*Follow-up:* "What does micro-op translation mean for verification?" → each x86 instruction must behave exactly like its micro-op sequence, including faults and interrupts in the middle of the sequence; precise exceptions must still be reported at the architectural instruction.

**Q3. What's the difference between architecture and microarchitecture, and why does it matter to a verification engineer?**

> Architecture is the contract software sees — instructions, registers, memory model, privilege. Microarchitecture is how one design implements it. Verification proves the implementation never violates the contract. That's why lock-step compares only architectural state against an ISA-level reference model: a 5-stage pipeline and a 20-stage out-of-order core must produce identical architectural results after every instruction.

**Q4. Why are pipelines in high-performance cores 13–20 stages and not 31 like the Pentium 4?**

> Each stage adds fixed register overhead, so the clock doesn't keep improving; and branch mispredictions and other hazards cost more cycles the deeper the pipeline. The Pentium 4 reached high clocks but not proportional performance, and its power was unsustainable. Designers settled where the CPI penalty and power balance against frequency.

**Q5. What is dark silicon?**

> Because power density rises when voltage can't scale, a modern chip can't run all its transistors at full speed at once without overheating. So parts are powered down at any moment and specialized accelerators — 100–1000× more efficient for their task — are used when needed.

**Q6 (NVIDIA-style). Why would a GPU company put RISC-V cores in its chips?**

> Every big chip needs small control processors — power, security, scheduling, firmware. An open ISA means no license fees, freedom to customize, and an open toolchain and verification ecosystem. The book notes over a billion RISC-V cores already shipped inside NVIDIA GPUs.

### How Chapter 1 connects forward

| Idea from Ch 1 | Where it becomes engineering |
| --- | --- |
| Architecture vs microarchitecture | Ch 2 (RISC-V ISA), Ch 5 (lock-step), Ch 7 (pipelined core) |
| Stretch's pipelining and interrupts | Ch 7 (pipeline), Ch 8 (traps) |
| Timesharing needs protection | Ch 8 (privilege), Ch 11 (MMU, PMP) |
| 486 caches, Pentium superscalar | Ch 10 (caches), Ch 13 (branch prediction) |
| Power wall → multicore | Ch 17 (atomics, coherence, consistency) |
| Accelerators, SoC | Ch 9 (buses), Ch 20 (peripherals) |

## Book coverage check (Ch 1 audit)

I checked this tab against all nine sections of Chapter 1. The tab above already covers the substance. The facts below are the only ones the book has that the tab lacked.

- **The open-source thread (chapter opening).** Hardware's open-source story copies software's:
  - the Automobile Manufacturers Association's open sharing of patents (first half of the 20th century);
  - IBM releasing its OS code (1950s–60s);
  - Stallman founding the Free Software Foundation (1985) and the Open Source Initiative (1998);
  - Linux, TCP/IP, Apache HTTPD and Python. Linux gets more than 4,000 contributors a year, the largest of them for-profit companies (Intel, Red Hat).
  - The book's point: companies open-source for flexibility, interoperability, security and collaboration, not only out of idealism. RISC-V carries the same logic over to ISAs.
- **"Software is harder than hardware"** (1.2). The book states that the largest cost and source of errors in an SoC is now the software running on it. Verification already costs more than design. IP blocks that come with robust test frameworks lower that cost, which is a strong interview line for why reusable UVM environments and verification IP (VIP) matter.
- **Accelerators are 2–3 orders of magnitude more energy-efficient** than general-purpose cores \[Taylor12\]. That is why SoCs offload work to them and accept dark silicon.
- **Exactly why Dennard scaling stopped.** Two causes:
  - Lowering the threshold voltage makes subthreshold leakage rise exponentially.
  - Gate oxide thinner than about 12 Å (4 atomic layers) lets electrons tunnel through the gate.
  - Process names stopped matching any physical feature after FinFETs arrived at 22 nm.
- **Small-scale integration.** TI introduced the SN74xx family in 1966, a few gates per package. Mainframes and minicomputers were racks of boards built from 74xx TTL parts. IBM's SLT modules were the step before integrated circuits.
- **Pipeline-depth ranges to quote** (1.6):

  | Class | Pipeline stages |
  | --- | --- |
  | Low-cost microcontrollers | 2 |
  | Energy-efficient cores | 5–8 |
  | High-performance cores | 13–20 |
  | Pentium III | 14 |
  | Pentium 4 | 20–31+ |
- **Reading list from the margins.** Tracy Kidder's *The Soul of a New Machine* (the Data General Eclipse MV/8000 team) is the classic account of the human side of a CPU project. Hennessy & Patterson's *Computer Architecture: A Quantitative Approach* is a must-read before OoO interviews.
- **Quotes.**
  - Krste Asanović at the 2022 RISC-V Summit: "RISC-V is inevitable."
  - Mark Himelstein at the 2023 RISC-V Summit: "All your core are belong to us" (a play on the Zero Wing meme).
  - Babbage: "I wish to God these calculations had been executed by steam." The first computing was done to eliminate errors in hand-computed tables, which is verification's oldest motive.
