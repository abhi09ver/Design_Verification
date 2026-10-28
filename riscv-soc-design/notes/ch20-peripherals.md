# Chapter 20 · Peripherals

## At a glance

This chapter (Chapter 20) is online-only: it is not in the print book, but it is on the companion site and in the full PDF. It covers the **uncore**: the hardware outside the core that a real system needs before it can boot Linux or blink an LED. There are five blocks, and each is a de facto standard, so operating systems already have drivers for them.

| Block | What it does | Standard it copies | Wally base |
| --- | --- | --- | --- |
| **CLINT** | 64-bit `mtime`, per-hart `mtimecmp` (timer interrupt) and `msip` (software interrupt) | SiFive FE310 | 0x0200\_0000 |
| **PLIC** | Collects external interrupts, prioritises them, routes them to each hart's M- and S-mode | RISC-V PLIC spec | 0x0C00\_0000 |
| **UART** | Asynchronous serial port (console) | TI/National PC16550D | 0x1000\_0000 |
| **SPI** | Synchronous serial port (SD card, flash, ADCs) | SiFive FU540 | 0x1004\_0000 |
| **GPIO** | 32 pins: input, output, interrupts on high/low/rise/fall | SiFive FE310 | 0x1006\_0000 |

&#91;embedded content: Wally's uncore · five peripherals behind one APB bridge\]

The three ideas to keep from this chapter:

1. **A peripheral is a register file with side effects.** The core talks to it only with loads and stores (memory-mapped I/O). The interesting part is what a read or write *does*: a read pops a FIFO, a write of 1 clears a bit, a write to the same address means something else when DLAB = 1.
2. **Interrupts take two paths.** Timer and software interrupts come straight from the CLINT to each hart. Everything else (UART, SPI, GPIO and any other device) goes through the PLIC, which picks one source and raises MExtInt or SExtInt.
3. **Testing a peripheral is mostly loopback plus register checks.** Wally's tests connect outputs back to inputs (`GPIO_LOOPBACK_TEST`, `SPI_LOOPBACK_TEST`, the UART's MCR.LOOP bit) and check the MIP bits instead of taking interrupts. Lab 11 shows what loopback alone cannot see.

**The Wally config knobs** (config.vh):

- `*_SUPPORTED`, `*_BASE` and `*_RANGE` for each peripheral;
- `GPIO_LOOPBACK_TEST` and `SPI_LOOPBACK_TEST`;
- `UART_PRESCALE`, which divides HCLK by 2^UART\_PRESCALE before the baud divisor;
- `PLIC_NUM_SRC`, `PLIC_GPIO_ID`, `PLIC_UART_ID`, `PLIC_SPI_ID` and `PLIC_SDC_ID`.

The RTL is in `src/uncore` (`gpio_apb.sv`, `clint_apb.sv`, `plic_apb.sv`, `uartPC16550D.sv`, `spi_apb.sv`, `spi_controller.sv`). The tests are assembly programs in `tests/wally-riscv-arch-test` (for example `rv64i/privilege/src/WALLY-spi-01.S` with its `.reference_output`). They are written with the same WALLY-TEST-LIB as Chapter 8, so each test is a list of memory-mapped reads and writes whose results go to the signature.

## First principles: memory-mapped I/O

### Why loads and stores are enough

RISC-V has no `in`/`out` instructions. The PMA checker decides that an address belongs to a device, not memory, and the EBU drives the matching HSEL. Wally's AHB-to-APB bridge then turns the access into a two-phase APB transfer:

- **Setup:** PSEL is high.
- **Access:** PENABLE is also high, and the transfer finishes when PREADY is high.

A few PADDR bits select the register. In the **Access** phase a write stores PWDATA, or a read returns PRDATA. So a peripheral is just a register file with an address decoder, plus whatever hardware the registers control. These registers are usually grouped as **control** (configuration), **status** (read-only flags) and **data** (FIFO windows).

Three properties make device registers different from memory, and every bug in this chapter's lab comes from one of them.

**1. Reads and writes can have side effects.** The 16550's RBR at offset 0 *pops* the receive FIFO, so two reads return two different characters. Reading the IIR clears a THRE interrupt. Reading the LSR clears the overrun flag. Reading the PLIC's claim register clears a pending bit. Writing 1 to a GPIO `*_ip` bit clears it. Consequences:

- the core must perform the access **exactly once**: no speculative or replayed reads to I/O, which is why Chapter 12's LSU marks I/O as uncacheable and non-idempotent;
- C code must declare the pointer `volatile`, or the compiler may cache the value in a register or delete a "redundant" read;
- a verification register model must know each field's **access policy**.

| Policy | Meaning | Example in this chapter |
| --- | --- | --- |
| RW | read what you wrote | GPIO `output_en`, PLIC priority, UART SCR |
| RO | hardware sets it; writes ignored | GPIO `input_val`, PLIC pending, UART LSR |
| W1C | write 1 clears that bit, 0 leaves it | GPIO `rise_ip`, `fall_ip`, `high_ip`, `low_ip` |
| RC (read clears) | the read itself clears it | UART LSR.OE, IIR's THRE source |
| read pops / write pushes | a FIFO window, not a register | UART RBR/THR, SPI `rxdata`/`txdata` |
| banked | the same address means two registers | UART offsets 0 and 1 with LCR.DLAB = 1 are DLL/DLM |
| read-modify | the read returns a value and changes state | PLIC claim/complete |

**2. Values change without the core writing them.** Input pins, `mtime` and FIFO levels move on their own. Software must poll or take interrupts. A test cannot predict "the value" unless it models the hardware cycle by cycle, or waits until the value is stable.

**3. Inputs from outside are asynchronous.** A GPIO pin can change at any moment relative to PCLK. Sampled by one flop, it can go **metastable**: it sits between 0 and 1 for an unbounded time. Wally passes each input through a **2-flop synchronizer**: the second flop gives the first a full cycle to resolve, which makes the probability of failure extremely small (MTBF grows exponentially with the resolution time). One more register after it gives the previous value for rise/fall detection.

The cost is **2 cycles of latency**, and a simulation cannot see the problem at all: RTL simulation has no metastability. A missing synchronizer is found by CDC lint and structural checks, or by a cycle-exact model that notices the latency is wrong (Lab 11's `BUG_GPIO_NO_SYNC`).

### Sticky bits and the set-vs-clear race

An interrupt pending bit must not be lost because software was slow. So `*_ip` is **sticky**: the condition sets it, and it stays set after the condition goes away until software writes a 1 to clear it (Fig. 20.5).

A real design must also decide what happens when the condition and the clearing write arrive in **the same cycle**. The safe answer is that the set wins, so the new event is not lost. Lab 11 hit exactly this in its own UART: an overrun that landed in the same cycle as the polling read of LSR (which clears OE) was lost, until the set was given priority.

### Loopback testing

Connecting a peripheral's outputs to its own inputs lets a self-checking program test the whole path with no external device:

- **GPIO:** `GPIO_LOOPBACK_TEST` makes each input see its output when that output is enabled.
- **SPI:** `SPI_LOOPBACK_TEST` connects SDO to SDI.
- **UART:** MCR bit 4 (LOOP) connects the transmitter to the receiver inside the chip.

Loopback is cheap and catches most wiring and FIFO bugs. Its blind spot: **the transmitter and the receiver come from the same designer's reading of the spec.** If both sides get the parity polarity or the SPI clock phase wrong, they still agree with each other and the test passes. Only an independent model of the far end, or real hardware, catches that. This is the main finding of Lab 11.

## GPIO: 32 pins, four interrupt kinds

The GPIO block (SiFive FE310 layout) gives software individual control of up to 32 pins. Every register is 32 bits wide, with one bit per pin, even on RV64. Reset clears them all, so after reset **every pin is an input with nothing enabled**.

| Offset | Register | Policy | What it does |
| --- | --- | --- | --- |
| 0x00 | input\_val | RO | synchronized pin value (0 where input\_en = 0) |
| 0x04 | input\_en | RW | enable the input path |
| 0x08 | output\_en | RW | enable the tristate driver (the pin is an output) |
| 0x0C | output\_val | RW | value to drive |
| 0x10, 0x14 | pue, ds | RW | pullup, drive strength (not in Wally) |
| 0x18 / 0x1C | rise\_ie / rise\_ip | RW / W1C | interrupt on a 0-to-1 edge |
| 0x20 / 0x24 | fall\_ie / fall\_ip | RW / W1C | interrupt on a 1-to-0 edge |
| 0x28 / 0x2C | high\_ie / high\_ip | RW / W1C | interrupt while the pin is 1 |
| 0x30 / 0x34 | low\_ie / low\_ip | RW / W1C | interrupt while the pin is 0 |
| 0x38, 0x3C | iof\_en, iof\_sel | RW | hand the pin to another peripheral (pin multiplexing) |
| 0x40 | out\_xor | RW | invert the output |

&#91;embedded content: GPIO input path · synchronizer, edge detect, sticky pending, enable\]

**How an interrupt is born.** The pin passes through input\_en and the 2-flop synchronizer, and one more register keeps the previous value. Rise is `cur & ~prev`, fall is `~cur & prev`, high is `cur` and low is `~cur`. Each condition sets its `*_ip` bit, which stays set (sticky). GPIOIntr is the OR over all pins of `rise_ip & rise_ie | fall_ip & fall_ie | high_ip & high_ie | low_ip & low_ie`, and it goes to PLIC source 3.

Two consequences matter for drivers and tests:

- **Level interrupts re-arm themselves.** If the pin is still high when software clears `high_ip`, the bit is set again on the next cycle. The handler must first remove the cause (disable high\_ie, or wait for the pin to drop) and only then clear the bit.
- **Writing 1 to clear is a feature.** It lets a handler clear exactly the bit it serviced, without a read-modify-write that could wipe a bit set in between.

Read literally, Fig. 20.5 selects `ip & ~PWDATA` during a write and ignores `cond`, so an event in the clearing cycle would be lost. Lab 11's RTL ORs the condition in after the clear: the set wins.

### Example 20.1: two switches and an LED

The book's program: switches on pins 0 and 1 (with pulldowns), an LED on pin 2 through a current-limiting resistor. It sets `input_en = 3` and `output_en = 4`, then loops: read `input_val`, and write 4 to `output_val` if any switch is pressed, else turn the LED off.

```
        la   t0, 0x10060000   # GPIO base
        li   t1, 3
        sw   t1, 4(t0)        # input_en: pins 0, 1
        li   t1, 4
        sw   t1, 8(t0)        # output_en: pin 2
loop:   lw   t2, 0(t0)        # input_val
        beq  t2, zero, led_off
        sw   t1, 0xC(t0)      # LED on
        j    loop
led_off:
        sw   t0, 0xC(t0)      # book: stores t0 = 0x10060000, not 0
        j    loop
```

**Spot the bug** (the book warns that none of the Chapter 20 code examples were tested): `led_off` writes the *base address* to `output_val`. It works only because bit 2 of 0x10060000 happens to be 0. Bits 17, 18 and 28 are set too, which is harmless only because those pins are not outputs. The fix is `sw zero, 0xC(t0)`; the C version is right.

Lab 11 found a second, quieter assumption: the program relies on `out_xor` still being 0. After the random phase of the test left `out_xor` random, the book's program lit the LED backwards. Directed tests that rely on reset state should say so, or set it themselves.

### Wally implementation and test plan

`gpio_apb` holds a 14 x 32-bit register file decoded from `PADDR[7:2]`, with PREADY always 1. `input_val` is the synchronizer output, and `pue`/`ds` are not built. RV64 adds a mux that picks the upper or lower 32 bits of PRDATA and PWDATA.

The book's test plan: check reset values, drive outputs and read them back in loopback, and exercise every interrupt enable and pending bit.

What a subsystem DV plan should add:

- **W1C semantics per bit:** write a random mask and check that only those bits clear.
- **Sticky behaviour:** a short pulse on the pin must leave `rise_ip` and `fall_ip` set.
- **Set-wins-over-clear** in the same cycle.
- **Exact synchronizer latency:** a pin change must appear in `input_val` 2 cycles later, not 0 and not 3.
- **input\_en gating** of both `input_val` and the interrupts.
- **out\_xor**, and pins that are outputs and inputs at once (loopback).
- **Reset:** every pin is an input after reset, so nothing is driven.
- **A CDC check** on the 32 asynchronous inputs, which simulation alone cannot provide.

## CLINT and PLIC: where interrupts come from

Chapter 8 handled interrupts from the hart's side: `mip`, `mie`, `mstatus.MIE`, priority and vectoring. This section covers the devices that drive the three interrupt inputs of each privilege mode: software, timer and external.

### CLINT: time, timer interrupt, software interrupt

| Offset | Register | Width | Notes |
| --- | --- | --- | --- |
| 0x0000 + 4i | msip (hart i) | 1 bit | MSwInt = msip; one hart interrupts another by writing here |
| 0x4000 + 8i | mtimecmp (hart i) | 64 | MTimerInt = (mtime >= mtimecmp) |
| 0xBFF8 | mtime | 64 | shared; counts at a constant rate; reset to 0 |

- **mtime is the system's single sense of time.** It keeps counting at a fixed frequency even when the cores' clocks are slowed or stopped. If it runs from a different clock than PCLK, reading it needs a clock-domain crossing (usually Gray-coded or handshaked). The `time` CSR that U-mode reads (Chapter 8) is a shadow of this register.
- **Timer interrupt = a level, not an event.** MTimerInt stays high as long as `mtime >= mtimecmp`. The handler acknowledges it by writing a *later* `mtimecmp`, not by clearing a bit. The OS scheduler does exactly this for each time slice.
- **RV32 needs care with 64-bit registers.** Two hazards follow from the counter being 64 bits wide on a 32-bit bus:
  - **Torn reads.** `mtime` is read as two 32-bit loads. If the low word wraps between them, the result is off by 2^32. The safe read is *hi, lo, hi again, retry if the two hi values differ*. The book's `delay()` in Example 20.2 dereferences a `uint64_t*`, which the RV32 compiler turns into two separate loads.
  - **Spurious timer interrupts.** Writing `mtimecmp` low then high can briefly make it smaller than `mtime`. The privileged spec's sequence writes all-ones to the low word first, then the high word, then the low word.
- **Spot the bug in Example 20.2:** the text gives the CLINT base as 0x0200\_0000, but the code uses 0x2000\_0000, 0x2000\_4000 and 0x2000\_BFF8 (one digit shifted). On Wally those addresses are not the CLINT.

**Wally implementation** (Fig. 20.7): a 64-bit `mtime` counter that increments every cycle unless it is being written, a 64-bit `mtimecmp`, a 1-bit `msip`, a `>=` comparator and a read mux. **Test plan:** toggle `msip` and check `mip.MSIP`; set `mtimecmp` around `mtime` and check that `mip.MTIP` follows. Lab 11 adds the boundary cases the plan leaves implicit:

- `mtime == mtimecmp` must interrupt (`>=`, not `>`);
- the carry from the low word into the high word, by writing `mtime` just below 2^32;
- the hi-lo-hi read sequence.

### PLIC: one interrupt line, many devices

&#91;embedded content: PLIC · gateway, arbiter, threshold, and the claim/complete handshake\]

The PLIC spec allows up to 1,023 sources (source 0 does not exist) and 15,872 **hart contexts**. A context is one privilege mode of one hart: a 4-core system with 2 threads per core and M and S modes has 16 contexts. Wally has 2 contexts (M and S of its one hart) and, like the SiFive FE310, up to 53 sources (ids 1 to 53) with 3-bit priorities (1 to 7). `PLIC_NUM_SRC` sets how many sources are built.

| Offset | Register | Notes |
| --- | --- | --- |
| 0x000000 + 4i | priority of source i | 0 = never interrupt |
| 0x001000, 0x001004 | pending bits | read-only; one bit per source |
| 0x002000 + 0x80c | enable bits for context c | one bit per source |
| 0x200000 + 0x1000c | threshold of context c | interrupt only if priority > threshold |
| 0x200004 + 0x1000c | claim/complete of context c | read = claim, write = complete |

The rules, all of which Lab 11 checks cycle by cycle:

1. **Arbitration.** Among sources that are pending, enabled for this context and have priority above 0, the highest priority wins. **A tie goes to the lowest id.** That is why GPIO (id 3) beats the UART (id 10) when both have the same priority.
2. **Threshold.** The context's interrupt line goes high only if the winner's priority is **strictly greater** than the threshold. Equal is masked, so a threshold of 7 masks everything.
3. **Claim.** Reading claim/complete returns the winning id (0 if none) and clears that source's pending bit. If two harts are interrupted for the same source, one claims it and the other reads 0. Handlers must accept a 0.
4. **Gateway.** A claimed source is *in progress*. While it is in progress its request is ignored, so a level request that stays high cannot become pending again. **Complete** (writing the id back) ends that state. A completion with an id that is not enabled for that context is ignored.

**Example 20.3** sets `priority[3] = 5` (GPIO), `priority[10] = 4` (UART), enables both for context 0 and sets threshold 2. The handler claims, services the device, then completes.

**Spot the bugs** in the book's code:

- the pointers are declared `uint32_t*` but cast from `(uint8_t*)`;
- `uint32_t *source = *PLIC_CLAIMCOMPLETE0;` declares a *pointer* and assigns it the claimed id. It should be `uint32_t source`.

The ordering is right: service the device first, then complete. If you complete first, a level source that is still high is pending again at once.

**Wally implementation** (`plic_apb.sv`): for each context and each priority level 1 to 7, find which requests are pending and enabled at that level; pick the highest non-empty level; within it, pick the lowest id; compare with the threshold. **Test plan:** permutations of UART and GPIO interrupts with different priorities, enables and contexts.

A DV engineer should also cover these cases explicitly:

- ties broken by id;
- priority equal to the threshold;
- priority 0;
- a claim with nothing pending;
- a source still high while in progress;
- a completion of an id that is not enabled or not in progress;
- both contexts seeing the same source;
- a request that drops before it is claimed. A pending bit stays set once it is captured, so this is a stale interrupt the handler must tolerate.

## UART and SPI: two serial ports

&#91;embedded content: UART framing and 16x sampling · SPI clock modes\]

### UART (PC16550D)

**Asynchronous** means no clock wire. The two ends agree in advance on the baud rate, the number of data bits (5 to 8), parity (none, odd, even or stick) and stop bits (1 or 2).

On the line:

- The line idles high. A falling edge marks the **start bit**.
- The data bits follow, **LSB first**, then the optional parity bit, then one or two high **stop bits**.

Inside the receiver:

- It oversamples the line at 16 times the baud rate.
- It confirms the start bit at its middle, 8 ticks after the edge, then samples every 16 ticks. Every bit is read near its centre, and the receiver resynchronises on each start bit.

This gives a budget: the two ends' clocks may differ by about 4.6% in total. That budget is why a cheap RC oscillator is not good enough, and why a test should run with the far end deliberately fast and slow.

| Offset | Read | Write | Notes |
| --- | --- | --- | --- |
| 0 | RBR (pops RX) | THR (pushes TX) | DLL when LCR.DLAB = 1 |
| 1 | IER | IER | DLM when DLAB = 1; ERBFI, ETBEI, ELSI, EDSSI |
| 2 | IIR | FCR | IIR: highest pending source; FCR: FIFO enable, resets, RX trigger 1/4/8/14 |
| 3 | LCR | LCR | word length, stop bits, parity enable/even/stick, break, DLAB |
| 4 | MCR | MCR | DTR, RTS, OUT1, OUT2, **LOOP** |
| 5 | LSR | - | DR, OE, PE, FE, BI, THRE, TEMT, RXFE; reading clears OE and the error bits |
| 6 | MSR | - | modem status: CTS, DSR, RI, DCD and their deltas |
| 7 | SCR | SCR | scratch |

**Interrupt identification (IIR) has a priority order:**

1. receiver line status (an error);
2. received data available (the FIFO reached its trigger level) or a character timeout;
3. THR empty;
4. modem status.

The THRE interrupt is cleared by **reading the IIR while it reports THRE**, or by writing the THR. So even an innocent read of the IIR is a state change.

**Overrun:** a character that arrives when the 16-byte RX FIFO is full is lost, and LSR.OE is set until the LSR is read. The book's history note: the 8250 had a single-byte buffer and lost characters above 9600 baud, which is why the 16550 added FIFOs and kept the register map.

**Example 20.4** (9600 baud, 8N1, divisor 65):

- `uartInit()` writes `LCR = 0b1000011` (DLAB, 8 bits), then `DLL = 65`, then `LCR = 0b0000011`;
- `uartSend()` waits for LSR.THRE (bit 5), then writes THR;
- `uartReceive()` waits for LSR.DR (bit 0), then reads RBR.

Two things in it are worth saying in an interview. DLM is never written, so the code relies on the reset value 0. And FCR is never written, so the FIFOs stay off and each THRE wait is per character.

**Wally** has a 16550-compatible UART (`uartPC16550D.sv`), with `UART_PRESCALE` dividing PCLK by 2^n before the divisor. **Book test plan:** loopback under every LCR configuration; interrupts from the line status, modem control and FIFO; RX FIFO trigger levels and overflow.

### SPI (SiFive FU540 subset)

**Synchronous** means the controller drives SCK, so there is no baud agreement and it can run much faster. SDO and SDI shift on opposite clock edges, so every frame sent is also a frame received (full duplex). An active-low chip select chooses one of up to 4 peripherals, and each peripheral tristates its SDO while not selected.

| Offset | Register | Notes |
| --- | --- | --- |
| 0x00 | sckdiv | f\_SCK = f\_PCLK / (2 (sckdiv\[11:0\] + 1)) |
| 0x04 | sckmode | bit 0 phase (CPHA), bit 1 polarity (CPOL) |
| 0x10 / 0x14 / 0x18 | csid / csdef / csmode | which CS, its idle value, AUTO (per frame), HOLD or OFF |
| 0x28 / 0x2C | delay0 / delay1 | CS-to-SCK and inter-frame delays |
| 0x40 | fmt | protocol (1/2/4 lanes), endianness, direction, bits per frame (1 to 8) |
| 0x48 | txdata | write pushes; bit 31 = FIFO full |
| 0x4C | rxdata | read pops; bit 31 = FIFO empty |
| 0x50 / 0x54 | txmark / rxmark | watermarks |
| 0x70 / 0x74 | ie / ip | tx watermark pending when tx count < txmark; rx when rx count > rxmark |

Wally builds two of these: a generic SPI (`SPI_SUPPORTED`, base 0x1004\_0000, PLIC id 6) and one dedicated to the SD card (`SDC_SUPPORTED`). It has a clock divider, configurable phase and polarity, 4 chip selects with adjustable delays, 1 to 8-bit frames in either bit order, and 8-entry FIFOs with watermark interrupts. It does not build the FU540's memory-mapped flash mode or the 2- and 4-lane modes.

**Example 20.5** reads an MCP3002 ADC: `sckdiv = 49` (200 MHz to 2 MHz), send 0x60 to start a conversion and discard the byte that comes back, then send 0x00 and the byte returned is the sample.

**Spot the bugs** in the book's code:

- `*SPI_TX_DATA = send` uses an undeclared name (`SPI_TXDATA`);
- `if (!(rxdata >> 31)` is missing a parenthesis;
- the text says "waits until the receive FIFO is not full", where it means not *empty*;
- Table 20.4 describes `sckmode` as "Pin input enable", a copy-paste slip.

The test with external peripherals is honest about its limits: "The SPI has not yet been tested with external peripherals." The cvw test `WALLY-spi-01.S` runs entirely in loopback (`SPI_LOOPBACK_TEST`): it checks reset values, writes each configuration register while sending single bytes and 4-byte bursts, and checks the watermark interrupts through the PLIC.

## How to verify peripherals

Wally verifies each peripheral with a directed assembly program, run on the full core. Each program does a sequence of memory-mapped reads and writes, logs every read to a signature, compares the signature with a reference output, and checks interrupts through the `mip` bits. That is a good **integration** test: it proves that the core, the PMA, the bridge and the device agree on addresses and widths. As a **block** test it has three blind spots, and each one maps onto a standard subsystem-DV component.

| Blind spot of a directed, loopback, signature test | What closes it | UVM name for the same idea |
| --- | --- | --- |
| Only the values the test author thought of are checked | a **register model** that knows every field's reset value, width and access policy, and a **reference model** that predicts every read | uvm\_reg / RAL with prediction; scoreboard |
| Timing is checked only where the test waits | cycle-by-cycle checks of every output pin (interrupt lines, pads) against the model | monitors plus a scoreboard, or SVA assertions |
| Transmitter and receiver share one person's understanding of the spec | an **independent agent** for the far end: a UART that decodes the pin with its own timing, an SPI peripheral for each mode | UVM agents (driver, monitor, sequencer) per interface, often a purchased VIP |
| "Did we try 7-bit odd parity with 2 stop bits?" | functional coverage with crosses, closed by directed or weighted randomness | covergroups, coverage-driven verification |

### The register model, done properly

- **Reset test:** read every register after reset and compare with the documented value, including read-only status (LSR = 0x60 means the transmitter is empty, IIR = 0x01 means no interrupt) and FIFO windows (SPI `rxdata` reads with the empty flag set).
- **Bit-bash:** for every RW field write ones, zeros and random values and read back through the field mask. **Exclude** fields with side effects: W1C, read-to-clear, FIFO windows, claim/complete, and anything that starts hardware (a write to THR transmits). UVM's `uvm_reg_bit_bash_seq` needs the `NO_REG_TESTS` or `NO_REG_BIT_BASH_TEST` attribute on exactly these. Forgetting it is a classic way to get false failures, or worse, to fire a peripheral in the middle of a register test.
- **Banked registers** (DLAB) need their own sequence: set the bank, check, restore.
- **Volatile fields** (`mtime`, `input_val`, pending bits) must be marked volatile so the model *predicts* them instead of mirroring the last write.

### Reference models: exact or tolerant?

An **exact** model (cycle-accurate synchronizer, gateway, `>=` compare) catches latency and boundary bugs, but it must be updated whenever the design's timing legitimately changes. A **tolerant** model ("eventually equal", or "read after settling") is robust but blind to timing. A good split, the one Lab 11 uses:

- **Exact** where the spec defines the timing: the GPIO synchronizer depth, the PLIC rules, the CLINT compare.
- **Transaction-level** where it does not: UART and SPI are checked frame by frame on the pins, by agents that keep their own timing.

### Coverage that matters for these blocks

- **UART:** word length x parity x stop bits (24 formats); each trigger level reached; PE, FE and OE detected; far-end baud error in both directions; THRE raised and cleared both ways.
- **SPI:** 4 modes x 2 bit orders; short frames; csmode AUTO and HOLD; each chip select; full TX FIFO; watermark interrupts.
- **GPIO:** each interrupt kind per pin; W1C with random masks; clear and set in the same cycle; loopback and external pins.
- **CLINT:** `mtime == mtimecmp`; carry across 2^32; a torn read retried.
- **PLIC:** ties; priority equal to the threshold; priority 0; both contexts; a claim with nothing pending; a source still high while in progress; stray completions.

### The book's own code is untested

The chapter states it outright: "None of the code examples in this chapter are tested. Caveat emptor." Reviewing them is a good interview warm-up, because each bug is a classic of embedded code:

- **Example 20.1:** stores the wrong register (the base address) to output\_val.
- **Example 20.2:** the CLINT base address is off by a digit, and a 64-bit read on RV32 can tear.
- **Example 20.3:** pointer and value are confused in `uint32_t *source = *...`.
- **Example 20.5:** an undeclared name, a missing parenthesis, and "not full" where it means "not empty".

None of these would survive an RTL-plus-firmware co-simulation, which is what a real SoC team runs before tape-out.

## Lab 11: build the five peripherals, then verify them two ways

Code in `cpu-from-scratch`. Run `make periph`, then `make periphhunt`, then `make periphdemo`.

**RTL** (`rtl/uncore/periph.sv`, one APB port, Wally's base addresses and PLIC ids):

- **GPIO:** the FE310 map, input\_en gating, a 2-flop synchronizer plus an edge register, sticky W1C pending bits where the set wins, out\_xor.
- **CLINT:** 64-bit `mtime` and `mtimecmp` as two words each, `msip`, `MTimerInt = mtime >= mtimecmp`.
- **PLIC:** 31 sources and 2 contexts. A gateway with an in-progress bit; the highest priority wins with ties to the lowest id; a strict `>` threshold; claim and complete.
- **UART:** a PC16550D subset with DLAB banking, 16-deep FIFOs with trigger levels, 16x oversampling, 5 to 8 bits, parity, 1 or 2 stops, LSR/IIR priorities, THRE cleared by an IIR read, overrun and MCR loopback.
- **SPI:** an FU540 subset with sckdiv, all four modes, both bit orders, 1 to 8-bit frames, CS AUTO/HOLD/OFF and watermark interrupts.

**Testbench** (`tb/tb_periph.sv`, plain SystemVerilog on Verilator, the same structure a UVM bench would have):

- **Driver:** an APB driver with random idle gaps.
- **Register model:** reset values, write masks and DLAB banking.
- **Cycle-exact reference models** for GPIO, CLINT and PLIC. They check GPIOIntr, the pads, MTimerInt, MSwInt, MExtInt and SExtInt every cycle, and every register read.
- **A UART agent** that shares no code with the RTL. A monitor decodes TX frames on the pin with its own timing and checks parity and stop bits. A driver sends RX frames with baud error (±2%, and 3% slow), with injected parity and framing errors.
- **An SPI peripheral model** for all four modes and both bit orders. It also checks that only the selected CS is active and that SCK idles at CPOL.
- **81 coverage bins**, including the full 24-format UART cross, all 8 SPI mode/order combinations and the PLIC corner cases. All 81 are hit over 5 seeds.
- `+BOOKPLAN` checks the way the book's test plan does: UART and SPI only in internal loopback, GPIO read only after the inputs settled.

### What it looks like in simulation

One UART character (0x5A, 8E1) through the 16x receiver, then book Example 20.3 on the PLIC. Every waveform in the GIF is printed from the RTL by `tb/tb_periph_demo.sv`.

&#91;image: Lab 11 simulation: UART frame sampling and PLIC claim/complete\]

### The bug hunt: 14 injected bugs, two verification styles

| Injected bug | Full bench | Book-style plan | First failure |
| --- | --- | --- | --- |
| GPIO\_NOT\_STICKY (ip follows the condition) | 5/5 | 5/5 | low\_ip read 0x63e4b503, model 0xffffffff |
| GPIO\_W1C\_ALL (any write clears every bit) | 5/5 | 5/5 | rise\_ip read differs in the cleared bits |
| GPIO\_NO\_SYNC (no synchronizer) | 5/5 | 4/5 | fall\_ip differs: the event landed 2 cycles early, before a W1C write instead of after |
| CLINT\_GT (`>` instead of `>=`) | 5/5 | 5/5 | MTimerInt = 0 at mtime = mtimecmp = 87 |
| CLINT\_NO\_CARRY (two 32-bit counters) | 5/5 | 5/5 | mtime high word 2, model 3 |
| PLIC\_TIE\_HIGH\_ID | 5/5 | 5/5 | claim returned 15, model 12 |
| PLIC\_THRESH\_GE (`>=` threshold) | 5/5 | 5/5 | MExtInt with priority 7 = threshold 7 |
| PLIC\_NO\_GATEWAY (re-pends while in progress) | 5/5 | 5/5 | pending read after a claim shows the claimed bit again |
| **UART\_PARITY\_INV** (odd and even swapped, TX and RX alike) | 5/5 | **0/5** | TX monitor: wrong odd parity bit for data 0x1f |
| **UART\_SAMPLE\_EARLY** (sample at 1/16 of the bit) | 5/5 | **0/5** | RX read 0x4c, sent 0x2c (remote 3% slow) |
| UART\_NO\_OVERRUN | 5/5 | 5/5 | LSR.OE not set after 17 characters |
| **SPI\_IGNORE\_PHASE** (CPHA ignored, both directions) | 5/5 | **0/5** | mode 1: received 0xc2, expected 0x84 |
| **SPI\_IGNORE\_ENDIAN** (always MSB first) | 5/5 | **0/5** | mode 1 LSB-first: received 0xc2, expected 0x43 |
| SPI\_TXWM\_LE (`<=` instead of `<`) | 5/5 | 5/5 | reset value of ip: 1, expected 0 |

What the table teaches:

1. **Loopback is self-consistent.** The four bugs it misses are each a wrong reading of a standard, made identically in the transmitter and the receiver. Parity polarity, sample point, clock phase and bit order all talk to themselves perfectly. Only an independent model of the far end catches them. This is also why SoC teams buy VIP and why the book says "The SPI has not yet been tested with external peripherals."
2. **A missing synchronizer is not a functional bug in RTL simulation.** The cycle-exact model saw the 2-cycle latency disappear. The settled check still caught it 4 times in 5, but only through a race between an edge and a W1C write, which is luck rather than design. The real check is CDC lint.
3. **Boundary values need explicit coverage:** `mtime == mtimecmp`, priority == threshold, ties, a carry across 2^32, txcount == txmark. Each one-character bug (`>` vs `>=`) lives exactly there.

### Three things the lab found that were not planted

- **An RTL race.** In the loopback overflow test, OE was "never set". The overrun arrived in the same cycle as the polling read of LSR, which clears OE, and the clear was written last in the RTL, so it won. The fix: the set wins over clear-on-read (the same rule as GPIO's W1C). The full bench, which reads LSR at other times, had not hit it.
- **A testbench mistake of the same kind.** The first version polled LSR until TEMT and then read LSR again to check OE. The polling reads had already consumed OE. Read side effects bite testbenches too.
- **A directed test that relied on reset state.** The book's Example 20.1, run after the random GPIO phase, lit the LED backwards because `out_xor` was no longer 0.

## Recap, interview drill, companion

**Companion page:** [Peripherals Lab](https://claude.ai/artifact/EhkqpxZMbH5n2KnXoaUMeD). Click a GPIO pin through the synchronizer into a sticky interrupt (and lose an event with clear-wins), run the PLIC by hand, drift a UART receiver's clock until it misreads, and mismatch SPI modes while loopback stays green.

### Recap in ten lines

1. Peripherals are register files reached by loads and stores (memory-mapped I/O) through the AHB-to-APB bridge. What a read or write *does* is the whole design.
2. Access policies: RW, RO, W1C, read-to-clear, FIFO windows, banked (DLAB), claim/complete. A register model must know each one.
3. GPIO: input\_en, a 2-flop synchronizer, edge and level conditions, sticky W1C pending bits, an OR of pending AND enable into PLIC source 3. Level conditions re-arm while they last.
4. CLINT: 64-bit `mtime` (constant rate, its own clock domain if needed), per-hart `mtimecmp` with `MTimerInt = mtime >= mtimecmp`, `msip` for software interrupts. RV32 reads hi-lo-hi.
5. PLIC: a gateway per source, a priority per source, and per context the enables, a strict threshold and claim/complete. Ties go to the lowest id. Service the device before completing.
6. UART: async frames (start, 5 to 8 data bits LSB first, parity, 1 or 2 stops), 16x oversampling with mid-bit samples, about 4.6% total clock budget, divisor = f / (2^prescale x 16 x baud).
7. 16550 traps: DLAB banks offsets 0 and 1; reading IIR clears THRE; reading LSR clears OE; RBR pops.
8. SPI: synchronous, full duplex, CPOL/CPHA/bit order/frame length must match the device, `f_SCK = f_PCLK / (2 (sckdiv + 1))`, FIFOs with watermarks.
9. Wally tests each peripheral with directed loopback programs that check signatures and `mip` bits. That is good integration coverage and blind to errors that both ends share.
10. Lab 11: the full bench catches all 14 injected bugs; the book-style plan misses 4 (parity polarity, sample point, CPHA, bit order). It also found a real set-vs-clear race in the RTL.

### Ten questions with model answers

**Q1. Walk me through verifying a GPIO block.** Start with the register model: reset (every pin an input), RW masks, W1C per bit with random masks. Then:

- an exact model of the input path (2 synchronizer cycles, then edge detection) and every interrupt kind per pin;
- sticky behaviour with one-cycle pulses;
- a clearing write in the same cycle as a new event, where the set must win;
- input\_en gating, out\_xor, outputs in loopback, and `iof` pin multiplexing if present;
- GPIOIntr checked every cycle;
- a CDC run on the 32 asynchronous inputs, because simulation cannot show metastability.

**Q2. What is a W1C register and why use it?** Write 1 to clear, write 0 to leave alone. A handler can clear exactly the bits it serviced without a read-modify-write, which could erase a bit that was set between the read and the write. Testing it means: random masks, a write of 0 changes nothing, and same-cycle set versus clear. Bit-bash sequences must exclude W1C fields.

**Q3. Why does the PLIC need claim/complete instead of just a pending bit?** Two reasons:

- **Arbitration among harts.** Exactly one claimant gets each interrupt; the others read 0.
- **Level requests.** Without the in-progress state, a source that is still high would re-trigger during its own handler.

Complete tells the gateway that the handler is done, so the source may become pending again. If you complete before servicing, you get a spurious interrupt. If you never complete, the source is silent forever.

**Q4. Equal priorities and priority equal to the threshold: what happens?** The lowest id wins a tie. Priority equal to the threshold does not interrupt, because the priority must be strictly greater. A threshold of 7 masks everything, and priority 0 means never. These are the one-character bugs (`>=` versus `>`), so they need explicit coverage bins. Lab 11's PLIC\_TIE\_HIGH\_ID and PLIC\_THRESH\_GE were caught by a cycle-exact model.

**Q5. How do you read `mtime` on RV32, and how do you set `mtimecmp` without a spurious interrupt?** Read hi, lo, hi again, and retry if the two hi values differ. For `mtimecmp`: write the low word to all ones, then the high word, then the low word, so that the 64-bit value is never briefly smaller than `mtime`. The timer interrupt is a level: it is acknowledged by moving `mtimecmp` forward.

**Q6. What baud-rate error can a UART tolerate, and how would you verify it?** Samples are taken mid-bit after one start-edge resynchronisation. The last sample is about 9.5 bits later, so the total error between the two ends must stay under roughly (0.5 - 1/16) / 9.5, about 4.6%, minus synchronizer jitter. Verify it with an independent remote-UART agent sweeping the far end fast and slow (Lab 11 used ±2% and 3% slow). The sample-point bug passed loopback and failed at 3% slow.

**Q7. Why is loopback testing not enough, and what do you add?** Loopback checks the datapath and FIFOs, but transmitter and receiver share the designer's interpretation of the protocol. A swapped parity polarity, CPHA or bit order still round-trips correctly. Add independent protocol agents or VIP for the far end, test against real device models (an SD card, an ADC), and use protocol assertions on the pins. Lab 11: 4 of 14 bugs were invisible to loopback.

**Q8. Explain the 16550's side-effect registers a test can trip over.**

- Offsets 0 and 1 are banked by LCR.DLAB.
- Reading RBR pops the RX FIFO.
- Reading LSR clears OE and the error bits.
- Reading IIR clears a pending THRE interrupt.

Lab 11's first overflow test polled LSR and so consumed OE before checking it. A register model must mark these fields volatile or read-clear, and exclude them from bit-bash.

**Q9. CPOL and CPHA: what goes wrong when the controller and the device disagree?** Different CPHA: one side samples on the edge where the other changes data, so the data is shifted or corrupted. Different CPOL with the same CPHA: each side calls the other's leading edge trailing, so they sample on the change edge with zero hold time. That may even work on the bench and fail with temperature. Different bit order: the byte is reversed. Nothing on the wires reveals any of it, which is why the device datasheet's mode is part of the test plan.

**Q10. You own subsystem DV for this uncore. What is your plan, in one minute?** I would run three layers, each catching what the others cannot:

1. **Block level (UVM).** A RAL model with correct access policies; reference models with exact timing where the spec defines it (synchronizer depth, PLIC rules, timer compare); independent agents or VIP for UART and SPI with error injection and baud sweeps; and functional coverage on the format and corner crosses.
2. **Formal and static.** CDC on every asynchronous input, plus assertions on APB protocol, interrupt stability and FIFO invariants.
3. **SoC level.** C or assembly tests on the real core (the Wally-style signature tests) for address map, widths and interrupt routing to `mip`, and boot-firmware co-simulation, which would have caught every bug in the book's own example code.

### The 60-second story to tell

"I built a GPIO, CLINT, PLIC, UART and SPI to the SiFive and 16550 register maps, and verified them two ways: the way the reference design's test plan does it, with loopback and signatures, and with a proper block-level bench. The block-level bench had a register model, cycle-exact models and independent UART and SPI agents with baud-error and error injection. I injected 14 bugs. The full bench caught all of them. The loopback plan missed four, every one a misreading of the protocol shared by transmitter and receiver, such as parity polarity or SPI clock phase. Along the way the bench also found a real race in my own RTL: an overrun arriving in the same cycle as the status read that clears it was lost, until I gave the set priority over the clear."
