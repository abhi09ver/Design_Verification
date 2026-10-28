# Chapter 3 · RISC-V Software Tool Flow

## At a glance

Chapter 2 was the hardware's view of RISC-V. Chapter 3 is the software's view: how a test program goes from text to bits in memory, and how you run it on models that are not your RTL. **Every test that ever touches Wally follows this one path:** riscv-arch-test, your random tests, CoreMark, even Linux. When a test fails at 2 a.m., the skills in this chapter tell you whether the bug is in the RTL, the test, the toolchain flags, or the linker script.

&#91;embedded content: RISC-V tool flow · build once, run on every model (book Fig. 3.1, extended)\]

The chapter's core vocabulary is the difference between three kinds of simulator. Interviewers ask this in some form almost every time.

| Kind | Examples | What it models | Cycle-accurate? | Speed (book's numbers) | What it is for |
| --- | --- | --- | --- | --- | --- |
| Instruction set simulator (ISS) | Spike, Sail | How each instruction changes registers, CSRs and memory. No peripherals. | No | Sail about 300,000 instructions/s; Spike faster | Reference model, expected signatures, trace logs |
| Emulator | QEMU | An ISS plus peripherals (timer, UART), via just-in-time translation to the host's instructions | No | On the order of 1 billion instructions/s | Booting an OS, GDB debugging |
| Logic (cycle-accurate) simulator | Verilator, Questa, VCS | The SystemVerilog itself, clock by clock | Yes: hazards, cache misses, mispredictions | Orders of magnitude slower than Spike or QEMU | Verifying the hardware |

**First principle:** only the RTL simulator tells you what the chip does; only the ISS tells you what it *should* do. Verification is the comparison between the two, so the same ELF must run on both.

## 3.1–3.3.1 The tools, and a first program

### What Wally's flow uses

Required and free: **GCC** (compile and assemble), **Spike** (ISS), **Sail** (ISS and formal model), **QEMU** (emulator) and **Verilator** (logic simulator and lint). Optional and mostly licensed: Questa or VCS (logic simulation), Design Compiler (ASIC synthesis), ImperasDV (lock-step reference, Chapter 5) and Vivado (FPGA).

Three ways to set up: a personal Linux machine (you install everything), a shared server (an admin installs tools in `/opt/riscv`, each user clones `cvw`), or a Docker container. Two environment variables tie it together: `RISCV` points at the tools and `WALLY` at your `cvw` clone; `setup.sh` sets both. The smoke test after setup is `regression-wally`, which should end with "SUCCESS! All tests ran without failures."

### Reading the tool name

`riscv64-unknown-elf-gcc` follows the GNU target triplet, cpu-vendor-OS/ABI:

- **riscv64**: the target CPU family. With multilib the same compiler also emits RV32 code when you pass `-march=rv32i`.
- **unknown**: no specific vendor.
- **elf**: bare metal, no OS, linked against the small **newlib** C library. The Linux-targeting toolchain is `riscv64-unknown-linux-gnu-gcc`, which uses glibc instead.

It is a **cross-compiler**: it runs on an x86 or ARM host and produces RISC-V code.

### The smallest useful program (Code Example 3.1)

```asm
.section .text.init
.globl rvtest_entry_point        # visible to the linker
rvtest_entry_point:              # the linker script's ENTRY symbol
    li a0, 42                    # a0 = 42
self_loop:
    j self_loop                  # park here forever
```

Build, then disassemble:

```bash
riscv64-unknown-elf-gcc -o example -march=rv32i -mabi=ilp32 -nostartfiles \
    -mcmodel=medany -T../../link/link.ld example.S
riscv64-unknown-elf-objdump -D example
```

```text
80000000 <rvtest_entry_point>:
80000000:  02a00513   li  a0,42
80000004 <self_loop>:
80000004:  0000006f   j   80000004 <self_loop>
```

I rebuilt this with GCC 13.2 and got the same two words. Decode them with Chapter 2's formats:

| Word | Fields | Real instruction | Pseudoinstruction |
| --- | --- | --- | --- |
| 0x02A00513 | imm = 0x02A (42), rs1 = x0, funct3 = 0, rd = x10 (a0), opcode 0x13 | addi a0, zero, 42 | li a0, 42 |
| 0x0000006F | J-type, offset 0, rd = x0, opcode 0x6F | jal zero, 0 | j . (jump to itself) |

### Running it on Spike

```text
$ spike --isa=rv32i -d example
warning: tohost and fromhost symbols not in ELF; can't communicate with target
core 0: 0x00001000 (0x00000297) auipc t0, 0x0
core 0: 0x00001004 (0x02028593) addi  a1, t0, 32
core 0: 0x00001008 (0xf1402573) csrr  a0, mhartid
core 0: 0x0000100c (0x0182a283) lw    t0, 24(t0)
core 0: 0x00001010 (0x00028067) jr    t0
core 0: 0x80000000 (0x02a00513) li    a0, 42
: reg 0 a0
0x0000002a
```

What to notice:

- **Spike does not start at your code.** A five-instruction boot ROM at 0x1000 puts the hart ID in a0, a pointer to the device tree in a1, loads the ELF entry point from a table, and jumps to it. QEMU's `virt` machine and Sail do the same thing. This is why a reset-PC mismatch is a classic first bug when you bring up a lock-step compare: the RTL may reset straight to 0x80000000 while the model starts at 0x1000.
- **The warning matters.** Without a `tohost` symbol the program has no way to tell the simulator it finished, so Spike runs the self-loop forever. Section 3.3.8 fixes this.

## 3.3.2 Linking and ELF

### What the linker does

The assembler works on one file at a time. It cannot know where its code will end up in memory, or the address of a label defined in another file. So each object file is built as if it started at address 0, and every reference it cannot finish is left as a placeholder plus a **relocation record** ("patch this instruction once you know where `sum` is"). The linker then:

1. **Collects** the object files, any library code that is actually used, and startup code.
2. **Places** each section at an address, following the linker script.
3. **Resolves** every symbol to its final address.
4. **Patches** each relocation with real offsets, and writes one executable.

&#91;image: The linker at work: two object files placed by link.ld, then relocations patched\]

The numbers in the animation come from building the book's `sumtest` with GCC 13.2 against the `link.ld` in today's cvw repo. Before linking, `jal sum` in `sumtest.o` is `0xfe9ff0ef`, a jump to itself carrying an `R_RISCV_JAL` relocation. After linking it is `0x02c000ef`: sum sits 0x2C bytes past the jal. `la t0, N` becomes an auipc/addi pair, and the linker splits the PC-relative offset 0x3FF8 into a high and a low part:

- hi = (0x3FF8 + 0x800) >> 12 = 0x4, so the instruction becomes `auipc t0, 0x4`
- lo = 0x3FF8 − 0x4000 = −8, so it becomes `addi t0, t0, -8`

The **+0x800** is there because addi sign-extends its 12-bit immediate. Whenever the low 12 bits look negative, the high part must round up by one to compensate. This rounding is a favourite interview puzzle, and the companion page has a calculator for it.

### Inside an ELF file

ELF (Executable and Linkable Format) is used for both object files and executables.

| Part | What it holds | example (RV32) | sumtest (RV64) |
| --- | --- | --- | --- |
| ELF header (52 bytes for ELF32, 64 for ELF64) | Magic `7F 45 4C 46` ("\\x7FELF"), 32/64-bit class, endianness, machine = RISC-V, **entry point**, where the two tables live | ELF32, little endian, entry 0x80000000 | ELF64, flags `RVC, double-float ABI` |
| Program headers (segments) | What a loader copies into memory, and with which permissions | one LOAD, R E | LOAD R E at 0x80000000; LOAD RW at the data address |
| Section headers | The linker's view: .text, .data, .bss, .symtab, .strtab, .riscv.attributes, debug info | 6 sections | 15 sections (with -g) |
| .symtab | Every label and its address | self\_loop = 0x80000004 | sum = 0x80000044, topofstack, tohost, begin\_signature |
| .riscv.attributes | The ISA the code was built for | `rv32i2p1` | `rv64i2p1_m2p0_a2p1_f2p2_d2p2_c2p0` |

**Sections versus segments** is a common interview question. Sections are the linker's fine-grained units, by content type. Segments are the loader's coarse units, by permissions. Several sections fold into one segment: in sumtest, .data and .bss share the RW segment. That segment has a file size of 0x18 bytes (N plus the signature) but a memory size of 0x1200, because .bss is NOBITS. It takes up address space but no bytes in the file, and the loader fills it with zeros.

### The linker script

The `link.ld` in today's cvw repo:

```text
OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)        /* becomes the ELF entry point */
SECTIONS
{
  . = 0x80000000;                /* "." is the location counter: start of RAM */
  .text : { *(.text.init) *(.text) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x4000);
  .data : { *(.data) }
  .data.string : { *(.data.string)}
  . = ALIGN(0x1000);
  .bss : { *(.bss) }
  . = ALIGN(0x1000);
  .text : { *(.text.main) }
  _end = .;
}
```

The book prints an older version that aligns .data to 0x1000, so its objdump shows `N` at 0x80002000. Its Sail trace, from the newer script, shows `begin_signature` at 0x80004008. My build matches the Sail trace. Expected addresses depend on the linker script, so a signature extractor that hard-codes addresses breaks when the script changes. Real flows look up `begin_signature` and `end_signature` in the symbol table instead.

Why start at 0x80000000? It is the start of RAM in Wally's memory map (Chapter 2) and on Spike, QEMU `virt` and Sail, so the same ELF runs everywhere. If you leave out `-T`, GCC's default script starts the program near 0x10000 (the book shows 0x10078). That layout suits a program loaded by an OS or by Spike's proxy kernel (pk), but on bare-metal Wally it would fetch from an address with no memory behind it.

**DV checklist when a test misbehaves:** `objdump -D` (did the code you meant actually get built?), `readelf -S` (are the sections where the testbench loads them?), `nm` (where are tohost and the signature?).

## 3.3.3–3.3.5 ABI, SBI and machine architecture

### ABI versus API

An **API** is a source-level contract: which functions and variables a library exposes. An **ABI** is a binary-level contract, the rules compiled code must follow so separately compiled pieces work together:

- the object and executable format (ELF)
- which ISA is assumed
- the size, layout and alignment of data types
- the calling convention (how arguments and results move between functions)
- how programs call the OS
- the code model (how instructions reach a label)

### Data-type ABIs (Table 3.1)

The name spells out the widths: **i**nt, **l**ong, **p**ointer.

| Type | ilp32 | ilp32f | ilp32d | lp64 | lp64d |
| --- | --- | --- | --- | --- | --- |
| int | 32 | 32 | 32 | 32 | 32 |
| long, pointer | 32 | 32 | 32 | 64 | 64 |
| char / short | 8 / 16 | 8 / 16 | 8 / 16 | 8 / 16 | 8 / 16 |
| float passed in FP registers | no | yes | yes | no | yes |
| double passed in FP registers | no | no | yes | no | yes |

Data is aligned to its own size: address 0x3002 is fine for a char or short but not for an int or long. With an ABI that has no floating-point registers (ilp32, lp64), float and double values are passed in integer registers instead.

### The calling convention

| Register | ABI name | Role | Who saves it |
| --- | --- | --- | --- |
| x1 | ra | Return address | Caller |
| x2 | sp | Stack pointer | Callee (must restore it) |
| x3 | gp | Global pointer, for fast access to globals | Not allocated |
| x4 | tp | Thread pointer | Not allocated |
| x10–x17 | a0–a7 | Up to 8 arguments; result in a0 (a1 too if it is 2×XLEN wide) | Caller |
| x8–x9, x18–x27 | s0–s11 | Saved registers for long-lived values; s0 may be the frame pointer | Callee |
| x5–x7, x28–x31 | t0–t6 | Temporaries | Caller |

Arguments beyond eight go on the stack. The FP ABIs pass float and double arguments in fa0–fa7.

**System calls** reuse the convention: the syscall number goes in a7, arguments in a0–a5, then `ecall` traps to S-mode. The kernel puts the result in a0 and returns with `sret`. For example, `open(path, flags)` takes the path and flags in a0 and a1 and returns a file descriptor in a0.

**The ISA does not enforce the ABI.** Hardware must not assume, for example, that a return address is always in x1. A return-address-stack predictor (Chapter 13) may use x1 as a hint, but the result must still be correct when software breaks the convention. Random instruction generators break it on purpose, which is one reason they find bugs that compiled code never does.

### Code models: how an instruction reaches a global

&#91;embedded content: Two ways to reach b\[1000\] at 0x14978 (book Fig. 3.2 and Code Example 3.2, RV64 -O3)\]

The example program is `long a; long b[2000]; return a + b[1000];`. `a` is close to gp, so one gp-relative load reaches it (0x131A0 − 0x7E0 = 0x129C0). `b[1000]` is too far for a 12-bit offset, so the compiler needs two instructions. With **medlow**, `lui` builds an absolute address. With **medany**, `auipc` adds an offset to the PC. On RV64, `lui` sign-extends, so medlow can only reach addresses within ±2 GiB of 0. Wally's RAM starts at 0x80000000, just out of that range, which is why the cvw Makefiles (45 of them; only the code-model demo uses medlow) pass `-mcmodel=medany`.

### SBI: the OS calling the firmware

The ABI covers user code calling the OS. The **SBI** covers the OS calling M-mode firmware (OpenSBI on a Linux system) for platform-specific jobs: setting the timer, sending inter-processor interrupts, remote fences, starting and stopping harts, rebooting, reading performance counters. The mechanism has the same shape one level up:

|  | ABI system call | SBI call |
| --- | --- | --- |
| Caller | U-mode program | S-mode kernel |
| Call ID | a7 = syscall number | a7 = extension ID (EID), a6 = function ID (FID) |
| Arguments | a0–a5 | a0–a5 |
| Trap goes to | S-mode (kernel) | M-mode (firmware) |
| Returns | a0 = result, `sret` | a0 = error code, a1 = value, `mret` |
| Example | open: a0 = path, a1 = flags | sbi\_set\_timer: EID 0x54494D45 (ASCII "TIME"), FID 0, a0 = new time |

This is why Chapter 2's three-layer picture (user, OS, firmware) works: each layer only knows the interface below it.

### -march and -mabi (Table 3.2)

`-march` tells GCC which instructions it may emit (lowercase): rv32i, rv32im, rv32imac, rv32gc (= rv32imafdc), rv64gc, or longer strings joined by underscores such as `rv64gc_zba_zbb_svpbmt`. `-mabi` must match the floating-point registers the architecture has:

| -march | -mabi |
| --- | --- |
| rv32e | ilp32e |
| rv32i, rv32im, rv32iac, rv32imac | ilp32 |
| rv32imafc | ilp32f |
| rv32imafdc (rv32gc) | ilp32d |
| rv64i, rv64im, rv64ic, rv64iac, rv64imac | lp64 |
| rv64imafdc (rv64gc) | lp64d |

What changes with -march: with rv32imac, `a = b * c;` compiles to a single `mul`. With rv32i it becomes a call to a library routine built from shifts and adds, and a hand-written `mul` fails to assemble.

**DV angle:** the test's `-march` must match the DUT configuration. If it is wider than the hardware, a test that passes on the ISS hits an illegal-instruction trap on the RTL. That is a test-configuration bug, not an RTL bug. The `Tag_RISCV_arch` attribute that readelf prints is a quick way to check what a binary assumes.

## 3.3.6–3.3.7 Driving GCC and assembler directives

### One command, four steps

`riscv64-unknown-elf-gcc` is a driver. Under the hood it runs four tools in order:

| Step | What happens | Intermediate file (keep it with `--save-temps`) |
| --- | --- | --- |
| Preprocess | Expand `#include` and `#define` | .i |
| Compile | C to assembly | .s |
| Assemble | Assembly to an ELF object | .o |
| Link | Join objects, place sections, resolve references | the executable |

Capital **.S** files go through the preprocessor first and lowercase **.s** files do not. That is why test suites use .S: `arch_test.h` macros and `#define TOHOST` work. One trap I hit while writing the labs: in a .S file, a comment line starting `# if ...` is read as a C `#if` directive and fails with "missing binary operator". Most other `#` comment lines pass through silently, so the bug looks random. Using `//` for full-line comments in .S files avoids it.

### The flags you will see in every Makefile (Table 3.3 and Section 3.4)

| Flag | Meaning |
| --- | --- |
| `-o example` | Output file name |
| `-march=rv32i` | Which instructions the compiler may emit |
| `-mabi=ilp32` | Data-type sizes and calling convention, matching -march |
| `-mcmodel=medany` | PC-relative addressing (medlow = absolute) |
| `-nostartfiles` | Do not link the default startup code (crt0) |
| `-nostdlib` | No startup code **and** no standard library (a superset of -nostartfiles) |
| `-T link.ld` | Use this linker script |
| `-g` | Keep debug information, so objdump -S and GDB can show source lines |
| `-static` | Link libraries into the binary instead of loading them at run time |
| `-O`, `-O2`, `-O3` | Optimize: basic, everything that doesn't grow code, everything |

Without `-march` the default is usually rv64gc, so compressed instructions appear. Without `-T` the program lands at GCC's default address instead of 0x80000000. Both cause classic "test hangs on the RTL" bugs.

### Makefiles

A Makefile records the exact command, so nobody has to remember the flags, and it rebuilds only what changed. `example.objdump: example` means the objdump depends on the executable, which in turn depends on `example.S`. The `make sim` target in sumtest uses a neat idiom:

```bash
diff --ignore-case sumtest.signature.output sumtest.reference_output || exit
echo "Signature matches! Success!"
```

`||` only runs its right side when the left side fails, so a mismatch exits before the success message prints. A regression script judges pass or fail from the exit code in exactly the same way.

### Assembler directives (Table 3.4)

An assembly file holds four kinds of things: instructions, comments (`#` or `//`, and `/* */`), labels (ending in `:`, giving an address a name) and **directives** (starting with `.`, telling the assembler what to emit or where).

| Group | Directive | Meaning |
| --- | --- | --- |
| Sections | `.text` | Code |
|  | `.data` | Initialized variables, e.g. `int salary = 110000;` |
|  | `.rodata` | Read-only constants |
|  | `.bss` | Uninitialized variables, e.g. `double matrix[3][3];` (no bytes in the file; zeroed at start-up) |
|  | `.section name` | A custom section, e.g. `.text.init` or `.tohost` |
| Data | `.byte`, `.half`, `.word`, `.dword` | 8, 16, 32 or 64-bit values |
|  | `.string "str"` | Null-terminated string |
|  | `.space n` | Reserve n bytes |
|  | `.fill num, size, value` | num copies of a size-byte value |
| Other | `.align n` | Align to a power of two |
|  | `.globl sym` | Make a label visible to the linker |
|  | `.equ name, value` | Define a constant |
|  | `.macro` … `.endm` | Define a macro |

The directives that matter most for verification: `.section .tohost` and `tohost:` (how the test ends), `.fill …, 0xdeadbeef` (pre-filling the signature so an unwritten word stands out), and `.globl rvtest_entry_point` (where execution starts).

## 3.3.8–3.3.10 Spike, performance counters, and sumtest

### Spike as a debugger (Table 3.5)

Spike was the original golden model. Sail has since taken over that role, but Spike is still the easier one to use. Both are ISSs: they compute what each instruction does and ignore timing. Start it with `spike --isa=rv32gc -d prog`. All values are in hex.

| Command | Does |
| --- | --- |
| Enter | Step one instruction |
| `reg 0 t0` / `reg 0 mstatus` | Show a register or CSR on hart 0 |
| `mem 80000004` | Show physical memory |
| `until pc 0 80000004` | Run until hart 0 reaches that PC |
| `until reg 0 a0 2a` / `until mem 0 80000020 1` | Run until a register or memory value matches |
| `while …` | Run while a condition holds |
| `run` / `rs` | Run with a trace / run silently |
| Ctrl-C, `q` | Pause, quit |

### How a test tells the simulator it is done: HTIF

A bare-metal test ends in an infinite loop, so something has to stop the simulator. Spike's **host-target interface** watches a symbol named `tohost` in the ELF. The address doesn't matter, because Spike finds it in the symbol table.

| Value written to tohost | Spike's reaction |
| --- | --- |
| 1 | Exit with code 0: pass |
| 3 | Print `*** FAILED ***` and exit with code 1 |
| Any odd value v | Exit with code v >> 1 |
| An even value | A system call: the value is a pointer to a block holding the call number and arguments, e.g. 64 = sys\_write(fd, buf, len) |

This is how `printf` works on bare metal: newlib's syscalls write to tohost, and Spike prints the text on the host. Sail uses the same convention, and Wally's testbench watches for the same write, so one test binary ends cleanly on every model.

### Signatures

A signature is a block of memory that the test fills with results. It is bounded by the labels `begin_signature` and `end_signature`. At the end of the run the simulator dumps the block to a file:

```bash
spike +signature=sumtest.signature.output +signature-granularity=8 sumtest
```

The test passes if that file matches a reference output. The block is pre-filled with 0xdeadbeef, so a result that was never written stands out. This is the comparison method riscv-arch-test uses (Section 3.7).

### Performance counters (3.3.9)

`instret` counts instructions retired and `cycle` counts clock cycles. Read them with `csrr rd, instret` (objdump shows it as `rdinstret`). On Spike they are equal, because it models one instruction per cycle. On real hardware cycle / instret is the CPI, which is how you measure a pipeline. Implementation-specific event counters (cache misses, mispredictions) come in Section 8.4.3.1.

### Putting it together: sumtest (Code Examples 3.5–3.8)

Two RV64 files. `sumtest.S` sets up the stack, loads N = 4, reads instret, calls `sum`, reads instret again, and stores the result and the instruction count into the signature. Then it writes 1 to tohost. `sum.S` is the ABI-following callee:

```asm
sum:  addi sp, sp, -16     # make room
      sd   s0, 0(sp)       # s0, s1 are callee-saved: save them
      sd   s1, 8(sp)
      li   s0, 0           # result = 0
      li   s1, 1           # i = 1
for:  bgt  s1, a0, done    # exit when i > N  (assembles as blt a0, s1)
      add  s0, s0, s1
      addi s1, s1, 1
      j    for
done: mv   a0, s0          # return value in a0
      ld   s0, 0(sp)       # restore
      ld   s1, 8(sp)
      addi sp, sp, 16
      ret
```

**Counting the instructions** (the book says the call costs 13 + 4N instructions):

| Part | Instructions |
| --- | --- |
| `rdinstret s8` itself, plus `jal sum` | 2 |
| Prologue: addi, sd, sd, li, li | 5 |
| Loop body: blt, add, addi, j, executed N times | 4N |
| Final blt that exits | 1 |
| Epilogue: mv, ld, ld, addi, ret | 5 |
| **Total** | **13 + 4N** = 29 = 0x1D for N = 4 |

The expected signature is therefore `000000000000000A` (1+2+3+4 = 10) and `000000000000001D`. The book's Sail trace confirms it: instret reads 0x0A before the call and 0x27 after, a difference of 0x1D.

A detail for sharp readers: the book's printed objdump (Code Example 3.9) leaves out the `addi sp, sp, 16` at 0x8000005E and shows `ret` there. The book's own Sail trace, and my rebuild, both have `c.addi sp, 16` at 0x8000005E and `ret` at 0x80000060. The 13 + 4N count only works with the addi included.

The build also shows things you only see in a disassembly:

- with rv64gc, most of `sum` assembles to 16-bit compressed instructions (`1141` is `c.addi sp, -16`), so the PC advances by 2 as well as 4
- `la` becomes auipc + addi (Section 3.3.2)
- `bgt` is a pseudoinstruction: the assembler swaps the operands and emits `blt`

## 3.4 The C compiler

### A first C program on bare metal (Code Examples 3.11–3.12)

`sum.c` computes sum(4), prints `s = 10`, and checks the answer with `verify()`. It is built with:

```bash
riscv64-unknown-elf-gcc -o sum -g -O -march=rv64gc -mabi=lp64d -mcmodel=medany \
  -nostdlib -static -lm -fno-tree-loop-distribute-patterns \
  -T../common/test.ld -I../common sum.c ../common/crt.S ../common/syscalls.c
```

The flags that are new in this section:

- `-nostdlib`: there is no OS, so leave out the normal startup code and libc and supply our own, `crt.S` and `syscalls.c`.
- `-fno-tree-loop-distribute-patterns`: stop GCC from replacing a loop with a call to `memcpy` or `memset`, which would not exist here.
- `-lm`: link the math library.

**What `crt.S` does before `main`** (bare-metal startup, a sequence you will see in every SoC bring-up):

1. Zero all registers.
2. Turn on the FPU.
3. Point `mtvec` at a trap handler that exits with an error.
4. Set gp, tp and sp to RAM above the program.
5. Call `_init`, which calls `main` on hart 0, then `exit` with main's return code.

The resulting memory map (book Fig. 3.3), from the bottom up:

| Address | Section | Contents |
| --- | --- | --- |
| 0x80000000 | .text.init | crt.S startup code |
| 0x80001000 | .tohost | HTIF mailbox |
| 0x80002000 | .text | sum, main, syscalls |
| 0x80002748 / 0x80002794 | .rodata.str1.8 / .rodata | String constants / other constants |
| 0x800028F0 | .bss | Uninitialized data |
| 0x80002940 | .tbss | Thread data (tp points here) |
| 0x800030EC up | heap, then stack | gp near the heap; sp starts at 0x80022890 and grows down |

### What the optimizer does to sum

&#91;embedded content: sum's stack frame with optimization off\]

| Level | Code for sum | Instructions to run sum(4) |
| --- | --- | --- |
| None | 48-byte frame; every use of result, i and N is a load or store (Code Example 3.13) | 62 |
| `-O` | No stack. a4 = N+1, a5 = i, a0 = result; loop `add; addi; bne` (Code Example 3.14) | 21 |
| `-O2` / `-O3` | The compiler works out sum(4) = 10 at compile time and emits `li a1, 10`. The verify call disappears too, because the compiler can prove it returns 0. | 1 |

&#91;embedded content: Instructions to run sum(4) at each optimization level\]

The measured counters (book Table 3.6) were 115 / 31 / 11 for mcycle and 132 / 38 / 16 for minstret. They are higher than the true counts because `setStats()` itself takes instructions to read the counters. Counters are only meaningful for code much longer than the measurement overhead.

**The DV lesson: the optimizer can delete your test.** At -O2 the loop you meant to run on the hardware no longer exists. Directed tests written in C need `volatile`, inline assembly, or `-O0`, and someone has to read the objdump to confirm the instructions you wanted are actually there.

### Inline assembly (Code Examples 3.16–3.17)

C has no way to say "read a CSR", so you embed one instruction:

```c
long cycles;
asm volatile("csrr %0, 0xB00" : "=r"(cycles));   // 0xB00 = mcycle
```

- `%0` is replaced by the register the compiler picks for operand 0.
- `"=r"(cycles)` says operand 0 is an output (`=`) in a general register (`r`), bound to `cycles`. Here the compiler picked a1, so the instruction became `csrr a1, mcycle`.
- `volatile` stops the optimizer from deleting or moving the statement, which matters because its result changes every time it runs.

### Mixing C and assembly files (Code Example 3.18)

For more than a line or two, keep the assembly in its own file and let the ABI join them. The C file declares `extern int sum(int);`, the .S file declares `.global sum`, and the linker connects them. N arrives in a0 and the result goes back in a0. The assembly must save any s registers it uses: the C caller assumes they survive the call, and the compiler does not check hand-written assembly.

### Standard libraries and startup code (3.4.4)

- **libc** (stdio, string, time…) is linked automatically unless you pass `-nostdlib`.
- **libm** (math) is linked only with `-lm`, a historical split from when math libraries were large.
- **Static** linking copies the code into the binary: `libc.a`, `libm.a`. Embedded systems use this.
- **Dynamic** linking shares one copy loaded at run time: `libc.so`. It needs OS support, so Linux uses it.
- **glibc** is the Linux C library. **newlib** has a more permissive license and is the usual choice for embedded and bare-metal systems.
- **Multilib**: newlib is precompiled once per -march/-mabi combination in Table 3.2. GCC links the matching one, so `sqrt()` uses `fsqrt.d` on rv64gc but a long integer routine on rv32i.

### Compiler Explorer (3.4.5)

godbolt.org shows C and the generated RISC-V assembly side by side for any GCC version and flag. The book's example is a recursive factorial: with -O it stays recursive, and with -O2 the recursion becomes a loop. It is the fastest way to check what instructions a construct will produce before you write a directed test around it.

## 3.5–3.6 Sail, QEMU and GDB

### Sail: the specification you can run

Sail is a language for describing ISAs, and the **official formal specification of RISC-V is written in it**. Where the English specification is ambiguous or disagrees with Sail, Sail wins. One description serves three purposes:

1. Precise, readable documentation of every instruction.
2. An automatically generated simulator, `sail_riscv_sim`, that matches the specification by construction.
3. Definitions for theorem provers, so properties of the ISA can be proved.

The ADDI/SLTI/ANDI family, as Sail states it (Code Example 3.19):

```text
function clause execute (ITYPE (imm, rs1, rd, op)) = {
  let immext : xlenbits = sign_extend(imm);
  X(rd) = match op {
    RISCV_ADDI  => X(rs1) + immext,
    RISCV_SLTI  => zero_extend(bool_to_bits(X(rs1) <_s immext)),
    RISCV_SLTIU => zero_extend(bool_to_bits(X(rs1) <_u immext)),
    RISCV_ANDI  => X(rs1) & immext,
    RISCV_ORI   => X(rs1) | immext,
    RISCV_XORI  => X(rs1) ^ immext
  };
  RETIRE_SUCCESS
}
```

Notice `sltiu`: the immediate is sign-extended first and then compared as unsigned. So `sltiu rd, rs1, -1` compares against 0xFFFF…FF and is true for every value except all ones. A careless RTL or reference model zero-extends it, and that is exactly the kind of corner the formal spec settles.

Running `sail_riscv_sim sumtest --test-signature sumtest.sig --trace-all` prints, for every instruction, the instruction number, privilege mode, PC, the encoding and assembly, and every register, CSR or memory location it changed:

```text
[10] [M]: 0x0000000080000014 (0xC0202C73) csrrs x24, instret, x0
CSR instret (0xC02) -> 0x000000000000000A
x24 <- 0x000000000000000A
[13] [M]: 0x0000000080000046 (0xE022) c.sdsp x8, 0x0(x2)
mem[W,0x00000000800051F0] <- 0x0000000000000000
```

That per-instruction record of state changes is exactly what a lock-step or trace-compare testbench checks the RTL against (Chapter 5). Sail is configured with a JSON file that lists the extensions and implementation choices. It runs at about **300,000 instructions per second**, slower for floating point, which makes it the bottleneck when RISCOF generates reference signatures.

### QEMU: fast enough to boot an OS

QEMU translates RISC-V instructions into host instructions just in time, reaching around a billion instructions per second, an order of magnitude faster than Spike. It also models peripherals, which booting Linux needs. It is not a golden model, though no discrepancies are known.

```bash
qemu-system-riscv64 -S -M virt -nographic -bios none -kernel sumtest
```

| Option | Meaning |
| --- | --- |
| `-S` | Start paused |
| `-M virt` | Generic RISC-V virtual board |
| `-nographic` | Serial console in the terminal |
| `-bios none` | Skip OpenSBI; run bare metal |
| `-kernel sumtest` | Load the ELF |
| `-icount 0` | Deterministic virtual instruction counter |
| `-gdb tcp::1234` | Accept a GDB connection |

Press Ctrl-A then C to reach the monitor. `info registers` shows the PC at 0x1000 (a boot ROM again), `x /2xg 0x80002008` dumps the signature, `c` continues and `q` quits.

**The lesson in this section:** QEMU got the sum right (0x0A) but reported **0x48470** instructions instead of 0x1D, because by default its counters follow the host's timing. With `-icount 0` it reports 0x1D, matching Spike. An emulator is functionally right and has no idea of timing, so never use it as a reference for counters or cycles.

### GDB over QEMU

Start QEMU with `-S -gdb tcp::1234`, then in a second terminal run `riscv64-unknown-elf-gdb -ex "target remote :1234" -iex "file sumtest"`. GDB reads the symbols from the ELF, so you can use names: `b sum`, `x/2xg &begin_signature`.

| Command | Does |
| --- | --- |
| `info all-reg` | All registers |
| `x <addr>` / `x <symbol>` | Memory |
| `stepi` (Enter repeats) | One instruction |
| `b <function>` / `b *<addr>` | Breakpoint |
| `c`, Ctrl-C | Continue, pause |
| `set $pc=0x1000` | Restart from the boot ROM |
| `display /i $pc` | Show the next instruction after each step |

For C, build with `-gdwarf-2` and use `s` / `n` / `p var` at source level. Two quirks from the book's transcript: a variable can print as `<optimized out>`, and `printf` hangs under QEMU in a loop polling `fromhost`, because QEMU's `virt` board doesn't answer Spike's HTIF.

**Which tool when (a common interview question):**

| Need | Tool |
| --- | --- |
| What should this instruction do, exactly? | Sail (or Spike, which is quicker to use) |
| Expected signature or trace for compliance | Sail via RISCOF |
| Step through a C program with source lines | QEMU + GDB |
| Boot Linux to check the software stack | QEMU |
| What does *my* hardware do, cycle by cycle? | RTL simulation (Verilator, Questa) |

## 3.7 Test suites

Wally uses three families of tests: the official **riscv-arch-test**, its own **wally-riscv-arch-test**, and **TestFloat** for floating point. `make --jobs` at the top of cvw builds them all in parallel. Section 5.11.1 runs them against the RTL.

### riscv-arch-test: the compliance suite

RISC-V International's Architecture Test SIG maintains it, and it covers RV32I, RV64I and the ratified extensions (C, M, F, D, Zb\*, Zk\*), plus basic privileged tests (ebreak, ecall, misaligned accesses). **Passing it is required to use the RISC-V trademark, but it does not prove a core correct.** Remember that sentence: it is the core of a very common interview question.

The test pool is laid out by base ISA and extension, for example `rv32i_m/I/src/add-01.S`, `rv64i_m/M/...`, `rv32i_m/privilege/...`. The `_m` means the tests run in machine mode.

### Inside one test (add-01.S, Code Example 3.20)

```asm
RVTEST_ISA("RV32I")                     // which configs may run it
rvtest_entry_point:                     // fill registers with known junk (0xfeedbead...)
RVMODEL_BOOT                            // model-specific setup hook
RVTEST_CODE_BEGIN
RVTEST_SIGBASE(x3, signature_x3_1)      // gp = where results go
inst_0:  // add x24, x4, x24 with x4 = 0x7fffffff, x24 = 1  -> signed overflow
TEST_RR_OP(add, x24, x4, x24, 0x80000000, 0x7fffffff, 0x1, x3, 0, x18)
         //  lui tp,0x80000; addi tp,tp,-1; li s8,1; add s8,tp,s8; sw s8,0(gp)
inst_1:  // add x28, x10, x10 with x10 = 0x20000  -> rs1 == rs2
TEST_RR_OP(add, x28, x10, x10, 0x40000, 0x20000, 0x20000, x3, 4, x18)
RVTEST_CODE_END
RVMODEL_HALT                            // write 1 to tohost
RVMODEL_DATA_BEGIN
signature_x3_1: .fill 17*(XLEN/32),4,0xdeadbeef
RVMODEL_DATA_END
```

The comment above each case lists the **coverpoints** it was generated to hit: `rs2 == rd != rs1`, `rs1_val == 2**(xlen-1)-1`, `rs2_val == 1`. That is functional coverage written into the test. The tests were produced by a coverage-driven generator, which is the same idea as Chapter 5's coverage-driven verification.

The expected signature for these two cases is `80000000`, then `00040000`. To write your own test, replace the code between `RVTEST_SIGBASE` and `RVTEST_CODE_END`, and enlarge the `.fill` if you store more results.

### RISCOF: running the suite

&#91;embedded content: RISCOF flow for riscv-arch-test, as Wally runs it\]

RISCOF (written in Python by IIT Madras and InCore, now part of the official flow):

1. Reads an ISA YAML, for example `spike_rv32gc_isa.yaml` with `ISA: RV32IMAFDCZicsr_Zicond_…` and `misa reset-val: 0x4000112D`.
2. Keeps the tests whose `RVTEST_ISA` the config supports.
3. Compiles them.
4. Runs each on a DUT model and on Sail, and diffs the two signatures.

The arch32 run in the book compiles and passes **387 tests**. It can take more than an hour, mostly waiting for Sail, and RISCOF reruns everything even if nothing changed. It also calls `elf2hex` to produce memory files the SystemVerilog testbench can load, plus .objdump, .addr and .lab files for debugging.

| Suite | Config | Source | What it covers |
| --- | --- | --- | --- |
| arch32 / arch64 | config32.ini / config64.ini | riscv-arch-test | Standard compatibility tests |
| arch32e | config32e.ini | riscv-arch-test | RV32E |
| wally32 / wally64 | config32.ini / config64.ini | wally-riscv-arch-test | Privileged and peripheral tests |

### wally-riscv-arch-test, and the gap it exposes

These are tests the authors wrote for traps, CSRs, the MMU and peripherals. Sail does not model the peripherals that raise interrupts, so it cannot produce expected values for them. Instead, **a human-written `reference_output` is copied in.** The developer predicts the answer, and no reference model checks the prediction. If the prediction is wrong, the RTL is "fixed" to match it, and the bug ships with a passing test.

**The interview-grade summary of signature testing:**

| Strength | Weakness |
| --- | --- |
| Simple, portable: any model that can dump memory can be checked | Checks only the final contents of the signature region, not every instruction |
| The same test runs on Spike, Sail, QEMU and RTL | A wrong intermediate value that is later overwritten, a wrong CSR side effect, or a stray write outside the region all go unnoticed |
| Required for the trademark | Covers the specification, not your microarchitecture: no hazards, cache or timing corners |

That gap is why Chapter 5 adds **lock-step comparison** against a reference model at every retired instruction, plus coverage of the microarchitecture itself.

## Chapter 3 recap and interview drill

### The chapter in six sentences

1. A RISC-V program goes source → gcc (preprocess, compile, assemble) → relocatable object → linker + linker script → ELF executable. The same ELF then runs on objdump, Spike, Sail, QEMU and the RTL.
2. The linker places sections at the addresses the script gives (0x80000000 for Wally), resolves symbols and patches relocations. The ELF's program headers tell a loader what to copy into memory, and its section headers and symbol table tell you where everything is.
3. The ABI fixes data-type sizes (ilp32, lp64d…), register roles (a0–a7 arguments, s registers callee-saved, t registers caller-saved) and code models. Wally needs medany because RAM sits at 0x80000000.
4. -march and -mabi must match the hardware being tested. The optimizer can remove code a test depends on, so read the objdump.
5. Spike and Sail are untimed ISSs (Sail is the official executable specification). QEMU is a fast emulator with devices but no timing. Only the RTL simulator is cycle-accurate.
6. Tests end by writing tohost and are checked through a signature. riscv-arch-test with RISCOF compares DUT and Sail signatures: required for the trademark, not proof of correctness.

### Interview questions with model answers

**Q1. Walk me through what happens from a .c file to instructions executing on your DUT.** The driver preprocesses, compiles to assembly and assembles to a relocatable ELF object whose sections start at 0, with relocation records for unresolved symbols. The linker combines the objects with startup code and libraries, places sections according to the linker script (text at 0x80000000 for Wally), resolves symbols and patches the relocations. The testbench converts the ELF to a memory image (elf2hex), loads it, and resets the core to the entry point. Startup code sets up sp, gp, mtvec and calls main, and the test ends by writing tohost. In parallel the same ELF runs on the reference model so results can be compared.

**Q2. What is the difference between an ISS, an emulator and an RTL simulator?** An ISS such as Spike or Sail models only architectural state changes, one instruction at a time, with no timing. An emulator such as QEMU adds peripherals and uses just-in-time translation for speed (around 10^9 instructions per second), enough to boot Linux, but is not cycle-accurate. Its instret was wildly wrong without -icount. An RTL simulator runs the actual SystemVerilog clock by clock, including hazards and cache misses, and is orders of magnitude slower. The ISS is the oracle, the RTL is what you are checking.

**Q3. Explain sections versus segments, and why .bss takes no space in the file.** Sections are the linker's units by content (.text, .data, .bss, .symtab). Segments, described by program headers, are the loader's units by permission, and several sections can share one: .data and .bss form one RW segment in sumtest. .bss is NOBITS: it has an address and a size but no bytes in the file, since it only has to be zero at start-up, so the segment's memory size (0x1200) exceeds its file size (0x18).

**Q4. `la t0, N` assembled to `auipc t0, 0x4; addi t0, t0, -8`. Why the negative number?** The offset from the auipc's PC to N is 0x3FF8. addi sign-extends its 12-bit immediate, so 0xFF8 would mean −8. The linker therefore computes hi = (offset + 0x800) >> 12 = 4 and lo = offset − 0x4000 = −8. The +0x800 rounds hi up whenever the low part reads as negative. Getting this wrong in a linker, assembler or ISS gives addresses that are off by exactly 4 KiB.

**Q5. Why does Wally compile with -mcmodel=medany?** medlow builds absolute addresses with lui, which on RV64 sign-extends, so it only reaches addresses within ±2 GiB of zero. Wally's RAM starts at 0x80000000, just outside that range. medany uses auipc, so it reaches anything within ±2 GiB of the PC and is position independent.

**Q6. What are the caller-saved and callee-saved registers, and how could an ABI violation show up in a verification environment?** a0–a7, t0–t6 and ra are caller-saved; s0–s11 and sp are callee-saved. Hand-written assembly that clobbers an s register corrupts the C caller, and that looks like a hardware bug until you read the trace. The reverse matters too: hardware must not assume the ABI (for example that returns always use x1), because random generators break those conventions deliberately.

**Q7. Your C directed test passes at -O0 but at -O2 it doesn't exercise anything. What happened?** The compiler proved the result at compile time and removed the code. In the book, sum(4) became a single `li a1, 10` and even the verify call disappeared. Use volatile, inline assembly, or -O0 for hardware-targeting code, and always check the objdump for the instructions you meant to test.

**Q8. Passing riscv-arch-test: what does it prove and what doesn't it?** It proves that, for the configured ISA, each instruction produces the specified results for the generated coverpoints, compared with Sail through signatures. It is required for the trademark. It does not prove the microarchitecture correct. It runs short, mostly hazard-free sequences, checks only final signature memory, does not cover your pipeline, caches or interrupt timing, and the privileged and peripheral coverage is thin. Wally's own peripheral tests even rely on hand-written expected outputs. That is why we add random tests with lock-step comparison and coverage of microarchitectural events.

**Q9. A test passes on Spike but hangs on the RTL. Where do you look first?** In order:

1. The reset PC and boot path: models start at a 0x1000 boot ROM, and the RTL may not.
2. Whether the RTL detects the store to the `tohost` address taken from the symbol table.
3. -march: compressed or other extensions the DUT lacks raise illegal-instruction traps, and mtvec may point at nothing.
4. The linker script and memory map: sections outside the RTL's memory.
5. The trace, to find where the PC stops advancing or loops in a trap handler.

**Q10. Why pre-fill the signature with 0xdeadbeef and the registers with junk?** So a result that is never written, or a register that isn't really restored, cannot pass by accident. In the companion page, a load bug in sum's epilogue passes both checks when s0 and s1 start at 0. With junk initial values, lock-step catches it but the signature still passes, because those registers never reach the signature.

### Try it

The [Toolchain Bench](https://claude.ai/artifact/3bJdYUUAukoTe1UVjwxTt3) runs the real sumtest build on a small ISS. Inject one of four hardware bugs and see which ones a signature check catches, which ones lock-step catches, and which ones neither catches. A second instrument is a calculator for the linker's hi/lo split.

| Bug in the companion | Signature | Lock-step | What it teaches |
| --- | --- | --- | --- |
| instret skips compressed instructions | Fails | Fails at the second rdinstret | Counters need checking too |
| c.add writes rs2 instead of rd + rs2 | Fails | Fails at the first c.add | Lock-step pinpoints the instruction |
| blt compares unsigned | Passes | Passes | No test, no coverage: N is never negative |
| c.ldsp returns 0 | Passes | Passes with zeroed registers, fails with junk | Initial state can mask bugs |

### How Chapter 3 connects forward

| Ch 3 idea | Where it comes back |
| --- | --- |
| Toolchain, Makefiles, regression-wally | Ch 4 (HDL practices) and Ch 5 (regressions) |
| Sail and Spike as references; signatures; RISCOF | Ch 5 (signature and lock-step verification) |
| Traps, CSRs, mtvec in crt.S, SBI | Ch 8 (privileged operations) |
| Code models, virtual addresses | Ch 11 (MMU) |
| instret, cycle, performance counters | Ch 8.4.3 and Ch 21 (benchmarking) |
| QEMU, OpenSBI, booting Linux | Ch 22 |
| elf2hex memory images | Ch 23 (FPGA) and the testbench |

## Book coverage check (Ch 3 audit)

I compared this tab with every Chapter 3 section from 3.1 to 3.8, including the full Sail, QEMU and GDB transcripts and the RISCOF log. The tab already covers the chapter closely. These are the remaining book details, mostly from 3.7. Interviewers ask about them when you claim compliance-test experience.

### The arch-test pool, file by file (Fig. 3.6)

- The `env/` directory holds `arch_test.h` (the RVTEST\_\* macros), `encoding.h` (CSR numbers and opcodes) and `test_macros.h` (TEST\_RR\_OP and its relatives). The macro language is specified in `riscv-arch-test/spec/TestFormatSpec.adoc`.
- Suites: `rv32i_m`, `rv64i_m` and `rv32e_m`. Extension folders include A, B, C, CMO, D, D\_Zfa, F, F\_Zfa, I, K, M, Zfh, Zicond, Zifencei and P\_unratified, plus `privilege` (ebreak, ecall, and misaligned loads, stores, branches and jumps). F tests are split by operand class, for example `fadd_b1-01.S`, `fadd_b10-01.S` and `fadd_b11-01.S`.
- The signature region starts with a **canary** (`sig_begin_canary: CANARY`). Each slot is pre-filled with 0xdeadbeef by `.fill N*(XLEN/32),4,0xdeadbeef`.
  - A slot still holding deadbeef means the test never wrote it.
  - A damaged canary means something wrote outside the region.
  - Both are cheap checks for silent failures.
- `rvtest_data` holds `.word 0xbabecafe`, initialized data for load and store tests.
- Under `RVTEST_CASE(0, "//check ISA:=regex(.*32.*);check ISA:=regex(.*I.*);def TEST_CASE_1=True;", add)`, RISCOF filters each test against the DUT's ISA string by **regular expression**. Example 3.21 shows Sail's reference signature for add-01: `80000000`, `00040000`.

### RISCOF configuration: WARL is declared, not assumed (Code Example 3.22)

```
hart_ids: [0]
hart0:
  ISA: RV32IMAFDCZicsr_Zicond_Zifencei_Zfa_Zfh_Zca_Zcb_Zba_Zbb_Zbc_Zbkb_Zbkc_Zbkx_Zbs_Zknd_Zkne_Zknh
  physical_addr_sz: 32
  User_Spec_Version: '2.3'
  supported_xlen: [32]
  misa:
    reset-val: 0x4000112D      # MXL=1 (RV32), bits A C D F I M
    rv32:
      accessible: true
      mxl:
        implemented: true
        type:
          warl:
            dependency_fields: []
            legal: [ "mxl[1:0] in [0x1]" ]
            wr_illegal: [ Unchanged ]   # an illegal write leaves the field as it was
```

This is the **riscv-config** schema (`schema_isa.yaml`, `schema_platform.yaml`). Every WARL field states its legal values and what happens on an illegal write. RISCOF validates the YAML ("Initiating WARL legality checks", "Performing Checks on PMP CSRs") and writes `*_checked.yaml` files into `riscof_work/`.

The tools in the log are RISCOF 1.25.2, **riscv\_isac** 0.11.0 and riscv\_config 3.5.0. riscv\_isac is the ISA *coverage* tool: it reads execution logs, measures the coverpoints you see in the test comments, and its companion generator, riscv-ctg, writes the tests from the same coverpoint definitions (this last point is general knowledge, not from the book).

**Interview line:** "Our reference model and our RTL must agree on every WARL choice. RISCOF makes you write those choices down in YAML. I'd do the same in the DV plan: one table of every WARL field, its legal set and its illegal-write behaviour, shared by the RTL team and the reference-model configuration."

### What RISCOF leaves on disk (Fig. 3.8)

The work directory is `tests/riscof/work/riscv-arch-test/rv32i_m/I/src/add-01.S/`:

| File | Purpose |
| --- | --- |
| `dut/DUT-spike.signature`, `dut/my.elf` | Spike run (the "device under test" inside RISCOF) |
| `ref/ref.elf`, `ref/add-01.log` | Sail build and log |
| `ref/Reference-sail_c_simulator.signature` | Expected signature |
| `ref/ref.elf.memfile` | elf2hex output loaded by the SystemVerilog testbench |
| `ref/ref.elf.objdump`, `.objdump.addr`, `.objdump.lab` | Disassembly, plus label addresses and names for the testbench and for debug |

RISCOF is run with `make` in `$WALLY/tests/riscof` (also called from `$WALLY` and `$WALLY/sim`). It generates `config32.ini`, `config64.ini` and `config32e.ini` by sed-substituting `config.ini`.

### Adding your own test to wally-riscv-arch-test (book's procedure)

1. Copy the form of an existing .S file and keep the arch-test macros. Set `RVTEST_ISA`/`RVTEST_CASE` to the extensions you need, for example `RV64I_Zicsr`.
2. Add the test to a suite in `tests.vh`. If the suite is new, also add it to the testbench and to the regression.
3. If Sail can model the test (no interrupts or peripherals), run `make` in `sim` and RISCOF produces the reference signature.
4. Otherwise put `NO_SAIL=True` in `RVTEST_CASE`, write the expected values by hand in `references/<test>.reference_output`, and run `make` (it compiles without Sail).
5. Run `regression-wally`, then inspect the objdump and signature under `tests/riscof/work/wally-riscv-arch-test`.

Step 4 is the weakness to raise yourself in an interview, as the tab above notes: the human-predicted reference has no reference model behind it.

### Small facts from 3.1–3.6

- The tool list in 3.1 includes **ImperasDV** (now Synopsys), the lock-step RISC-V reference used in Chapter 5, and VCS alongside Questa and Verilator.
  - Questa and Design Compiler licences are sold only to companies and universities, not to individuals.
  - Vivado has a limited free version.
- Three ways to install: a personal Linux machine; a shared server where an admin installs the tools and each user clones `cvw`; or the **Docker** image (`docs/docker.md`). `$RISCV` points to the tools (/opt/riscv or \~/riscv) and `$WALLY` to the cvw clone. `setup.sh` sets both. After `make`, success is `regression-wally` printing "SUCCESS! All tests ran without failures."
- Sail is written in a functional language from the ML family; the book calls it OCaml. Sail models also exist for MIPS, ARM and IBM Power. The "holy grail" is proving an HDL implementation correct against Sail, which still can't be automated for complex cores. Run it with `sail_riscv_sim --config $WALLY/tests/riscof/sail_cSim/rv64gc.json …`; `--print-default-config` shows the defaults (RV64, chosen to match Spike).
- QEMU monitor: QEMU appears to hang until you press Ctrl-a c. If it really locks up, use `killall qemu-system-riscv64`. Even under GDB without `-icount`, the second signature word is garbage (0x17658e47a8), which is the same counter lesson as the tab's 0x48470.
- The authoritative GDB reference is Stallman's GDB manual, freely available.
