# Chapter 9 · Bus Interface

@Abhishek

## At a glance

Until now our core read instructions and data from memories *inside* the core that answer in the same cycle. Real chips put RAM, boot ROM, timers, UARTs and GPIO *outside* the core, in the **uncore**, and reach them over a standard **bus**. Chapter 9 is about that wire bundle: what signals it carries, how a slow device makes the core wait, how several devices share one bus, and what this does to the pipeline.

&#91;embedded content: Wally's bus system (after book Figs. 9.1 and 9.20)\]

| Idea | One-line version | Why an interviewer cares |
| --- | --- | --- |
| Controller / peripheral | Controller sends address (+ write data); peripheral returns read data and *ready* | Every bus is this, plus handshakes |
| Handshake | Peripheral holds READY low to add wait states | Stall logic and timeouts live here |
| Decoder + mux | Address picks one peripheral (HSEL); a mux returns its data/ready | Default subordinate keeps an unmapped access from hanging the bus |
| Arbiter | Picks one of several controllers (fixed priority, round robin, TDMA) | Starvation and deadlock questions |
| APB | Setup then Access, one transfer at a time; for slow peripherals | Simplest protocol to write a checker for |
| AHB | Address and Data phases overlap: up to one transfer per cycle | HREADY vs HREADYOUT, HSELD, write data one cycle late |
| AXI | Five independent VALID/READY channels, IDs, out-of-order, bursts | The protocol at NVIDIA/AMD/ARM-class SoCs |
| Wally | LSU and IFU each get an AHB FSM (Adr, Data, Mem3); the EBU arbitrates, LSU first | A bus access stalls the whole pipeline and delays interrupts |

## 9.1 Principles

### What a bus is

A bus connects **controllers** (they start transfers: a CPU, a DMA engine) to **peripherals** (they answer: SRAM, DRAM, ROM, timer, interrupt controller, GPIO, UART). The book uses *controller/peripheral*; ARM's AHB/AXI documents say *manager/subordinate*, APB says *requester/completer*, older documents *master/slave*. Know all four pairs; interviewers mix them.

The book builds a bus up in three steps (Fig. 9.2):

1. **Asynchronous read-only.** Address in, data out after some delay. Like our IROM.
2. **Synchronous read-only.** The address must be set up before the clock edge; data comes back after it. Almost every real memory is synchronous because timing is easy to close.
3. **Synchronous read/write.** Add write data (WD) and write enable (WE). The write happens on the edge.

### Unidirectional, point-to-point

Old boards shared one bidirectional data bus with tristate drivers to save pins. On chip, wires are cheap, long wires need repeaters (which only drive one way), and tristates are hard to time and verify. So **on-chip buses always use separate read and write data and point-to-point wires with a read mux.** Off chip, the trend is the same: a few fast unidirectional serial lanes beat a wide shared bus.

### Handshaking

- **REQ** (request): the controller says "the address on the bus is valid now". It saves power when idle.
- **RDY / ACK** (ready): the peripheral says "done". A slow device (DRAM to a new row, a flash, a bridge) keeps it low for **wait states**.

That pair is the seed of every protocol below: APB's PSEL/PENABLE/PREADY, AHB's HTRANS/HREADY, AXI's VALID/READY.

### Many peripherals: address decoder and read mux

SoCs use **memory-mapped I/O**: each device owns an address range in the **memory map**. An **address decoder** turns the address into one-hot select signals, and a **read mux** returns RD and RDY from the selected device (Fig. 9.5b). In RISC-V the decoder grows into the **PMA checker** (physical memory attributes, Ch 11): it also knows whether a range is cacheable, which sizes are legal, and whether reads have side effects.

### Many controllers: arbitration

With several controllers, an **arbiter** grants the bus to one at a time and a grant mux forwards its signals (Fig. 9.6).

| Policy | How it works | Weakness |
| --- | --- | --- |
| Static (fixed) priority | Highest-priority requester always wins | Starves low priority under constant traffic |
| Round robin | Rotate the winner | Fair, but a critical request can wait a full round |
| TDMA | Fixed time slots sized by bandwidth | Wastes idle slots |
| Dynamic priority | Priorities change at run time (age, QoS) | More logic, harder to verify |

Two more multi-controller ideas. **Locking** (HMASTLOCK, AXI exclusive access) lets one controller finish a read-modify-write atomically (Ch 17). **DMA** lets a device read or write memory without the CPU. That creates a **coherence** problem: a cache may hold a stale copy of what DMA just wrote. It is solved with cache-management instructions (Ch 19) or coherent buses (ACE, CHI, TileLink-C).

### Other features

- **Byte enables / size**: write only some bytes (HWSTRB, PSTRB, WSTRB).
- **Bursts**: several beats to consecutive addresses, so DRAM can stream from an open row.
- **Split / out-of-order transfers**: tag a slow request with an ID and free the bus meanwhile.
- **Bridges**: translate one protocol to another (AHB-to-APB, AXI-to-AHB).
- **Network on chip (NoC)**: crossbars, meshes or rings when one shared bus is not enough bandwidth.

### High-speed off-chip links (context only)

USB-C 40 Gb/s, dual-channel DDR5-6400 about 400 Gb/s, PCIe 5.0 x16 about 1 Tb/s (2025 figures in the book). Two clocking styles:

- **Source-synchronous** (DDR): send a clock alongside the data and use both edges. It is limited by skew between bits.
- **Serial with clock/data recovery** (PCIe, USB, Ethernet): encode so the stream toggles often (8b/10b, 64b/66b, 128b/130b), and a PLL recovers the sampling clock.

These are bought as IP (controller + PHY) and attached to the SoC over AXI.

## 9.2 AMBA buses: APB, AHB, AXI

ARM's AMBA family (since 1996) is the de facto on-chip standard. Fig. 9.7 is the classic layout: CPU and memories on fast **AHB**, slow peripherals on **APB** behind a bridge.

&#91;embedded content: APB vs AHB phases for a write, a read, and a read with one wait state\]

### APB: the simple one

Signals: PSEL, PENABLE, PADDR, PWRITE, PWDATA, PSTRB from the controller (usually the bridge); PRDATA, PREADY, PSLVERR from the peripheral.

1. **Setup** (1 cycle): PSEL = 1, PENABLE = 0, address, direction and write data valid.
2. **Access** (1 or more cycles): PENABLE = 1, everything held steady. The transfer completes on the edge where **PREADY = 1**. A peripheral that never waits ties PREADY high.

If no peripheral is selected, the APB mux must still return PREADY = 1, or the bus hangs.

**Example 9.1, GPIO on APB** (close to your GPIO pinmux work). Three registers: GPIOOUT at 00, GPIOEN at 01 and read-only GPIOIN at 10. A write happens when PSEL & PENABLE & PWRITE. A 2:3 decoder on PADDR\[1:0\] picks the register; a read mux returns it. PREADY = 1 always. GPIOEN drives the pad tristate enables.

### AHB: pipelined

AHB (the book means AHB5 / AHB-Lite: one manager per layer) keeps the two phases but **overlaps** them: while transfer *n* is in its **Data** phase, transfer *n+1* is already in its **Address** phase. That roughly doubles throughput.

| Signal | Phase | Meaning |
| --- | --- | --- |
| HADDR, HWRITE, HSIZE, HBURST, HPROT, HMASTLOCK | Address | where, what, how big |
| HTRANS | Address | 00 IDLE, 01 BUSY, 10 NONSEQ (single or first beat), 11 SEQ (later beats) |
| HWDATA, HWSTRB | Data | write data and byte strobes, **one cycle after** their address |
| HRDATA, HRESP | Data | read data, status (OKAY / ERROR) |
| HREADYOUT | Data | from each subordinate: "my Data phase is done" |
| HREADY | both | the muxed HREADYOUT, broadcast to the manager **and every subordinate** |

The details that make AHB tricky, and where bugs live:

- **HREADY vs HREADYOUT.** Each subordinate drives HREADYOUT. The interconnect muxes it into HREADY and sends HREADY back to all of them. A subordinate samples a new address only when HSEL & HTRANS\[1\] & **HREADY**: the previous transfer, possibly to a *different* device, has finished. The book's `initTrans` signal is exactly that AND.
- **HSELD.** The read mux must select by the device in the **Data** phase, so it uses HSEL delayed by one accepted transfer (HSELD), not the current HSEL. Fig. 9.29 shows a ROM read with 2 wait states followed by a RAM read: during the ROM's waits HSEL already points at the RAM, but HREADY must come from the ROM.
- **Default subordinate.** If HADDR matches nothing, a default responder must still give HREADY = 1 (and ideally HRESP = ERROR). Without it, a stray access hangs the SoC. At reset HSEL\[0\] and HSELD\[0\] start at 1 for the same reason.
- **Write retiming.** HWDATA arrives in the Data phase, so a subordinate registers HADDR and HWRITE at the end of the Address phase and writes one cycle later.
- **Single-port SRAM on AHB (Fig. 9.13).** Reads use the live HADDR; writes use the delayed HADDRD. A **write followed immediately by a read** needs both addresses in the same cycle, so the interface inserts **one wait state** for that case only.
- **Sub-word writes (Table 9.6).** To write 0x42 to byte 0x1002 on a 32-bit bus, either send a word transfer with HADDR = 0x1000, HSIZE = 2, HWSTRB = 0100 and HWDATA = 0x00420000, or a byte transfer with HADDR = 0x1002 and HSIZE = 0. Watch the byte lane in the second option. The book's table shows HWDATA = 0x00000042 with HWSTRB = 0001, but the AMBA AHB spec puts a narrow transfer on the lane its address selects (little-endian: HADDR\[1:0\] = 10 → bits 23:16), so a spec-compliant subordinate expects 0x00420000 and strobe 0100 either way. Lane placement for narrow transfers is a classic bus-checker rule and interview question.
- **AHB-to-APB bridge (Figs. 9.14 and 9.15).** It is an AHB subordinate on one side and an APB requester on the other. On writes it must delay PSEL/PADDR/PWRITE by a cycle to line up with HWDATA, and it holds HREADYOUT low until PREADY.
- **Bursts (Fig. 9.16).** HTRANS = NONSEQ then SEQ, and HBURST = INCR, INCR4, WRAP4 and so on. Simple subordinates ignore the hints and use HADDR.
- **Multilayer AHB (Fig. 9.17).** Each manager gets its own layer; an interconnect matrix has a decoder per layer and an arbiter per subordinate.

### AXI: decoupled channels

AHB still assumes the address phase is one cycle and transfers finish in order. Big SoCs need multi-cycle wires, many managers, DRAM with many requests in flight, and coherence. AXI4 gives **five independent channels**, each a VALID/READY handshake:

| Channel | Direction | Key signals |
| --- | --- | --- |
| AR read address | manager → subordinate | ARID, ARADDR, ARLEN (beats − 1), ARSIZE, ARBURST |
| R read data | subordinate → manager | RID, RDATA, RRESP, RLAST |
| AW write address | manager → subordinate | AWID, AWADDR, AWLEN, AWSIZE, AWBURST |
| W write data | manager → subordinate | WDATA, WSTRB, WLAST |
| B write response | subordinate → manager | BID, BRESP |

The handshake rules you will be asked to write assertions for:

- A transfer happens on the clock edge where **VALID and READY are both 1**.
- The **source must not wait for READY before asserting VALID**. That would deadlock against a destination that waits for VALID.
- The destination **may** wait for VALID before asserting READY.
- **Once VALID is asserted, it stays high and the payload stays stable until the handshake.**
- Write data may arrive before, with or after its address. BVALID only comes after both the address and the last data beat (WLAST) are accepted.
- **IDs**: responses with the same ID return in order; different IDs may come back out of order.

AXI4-Lite drops bursts and IDs (single beats, in order). ACE adds coherence, and CHI is the scalable, packetized successor. The cost is size: a 32-bit AXI5 port is about 224 wires, which is overkill for a microcontroller.

## 9.3 Other SoC buses

- **Wishbone**: open (OpenCores), AHB-like but without the one-cycle-late write data.
- **OBI**: used by OpenHW's CORE-V cores; like a simplified AXI with a request and a response channel.
- **CoreConnect**: IBM's PLB + OPB pair; Xilinx used it before moving to AXI.
- **TileLink**: SiFive's open, point-to-point, coherence-capable bus. Customers still mostly ask for AHB or AXI.

## 9.4 Test plan, and what a senior DV engineer would add

The book is candid: Wally's AHB has mostly been tested *by normal use* plus the `ahb64_ram_{0/1/2}_{0/1}_rv64gc` tests. Those run `fadd_b11-01` with 0, 1 or 2 extra RAM wait states and burst line fills off or on, so cache misses generate bus traffic. It says "a more comprehensive test plan would be beneficial". Here is one, structured the way you would present it in an interview.

| Layer | What | How |
| --- | --- | --- |
| Protocol | Every rule of the spec, on every interface, in every test | Assertions bound to the bus (SVA) or a protocol checker VIP |
| Data integrity | Every read returns what the model says | Scoreboard against a reference model, in order (AHB) or by ID (AXI) |
| Subordinates alone | Pipelined back-to-back traffic, all sizes and lanes, unmapped addresses, wait states | Block-level constrained-random manager (Lab 6 `tb_ahb.sv`) |
| Managers alone | busfsm/EBU under random HREADY and arbitration conflicts | Random subordinate that inserts waits; IFU and LSU requests in the same cycle |
| System | CPU + uncore together: interrupts during transfers, traps in Adr, side-effect devices | Directed tests + lock-step vs ISS with device models |
| Performance | Stall cycles per access, arbitration fairness | Counters + bounds (e.g. a bus load costs exactly 2 + waits) |

**Assertions worth knowing by heart** (AHB-Lite, SVA):

```systemverilog
// manager holds the Address phase while the bus is stalled
a_hold: assert property (@(posedge HCLK) disable iff (!HRESETn)
          HTRANS[1] && !HREADY |=> $stable({HADDR, HWRITE, HSIZE, HBURST}) && HTRANS == $past(HTRANS));
// write data stable while the Data phase is stretched
a_wdata: assert property (@(posedge HCLK) disable iff (!HRESETn)
          data_phase_write && !HREADY |=> $stable({HWDATA, HWSTRB}));
// natural alignment for narrow transfers
a_align: assert property (@(posedge HCLK) HTRANS[1] |-> (HSIZE == 1 -> !HADDR[0]) && (HSIZE == 2 -> HADDR[1:0] == 0));
// strobes only on lanes the address and size select
a_strb:  assert property (@(posedge HCLK) data_phase_write |-> (HWSTRB & ~lanes(addr_d, size_d)) == 0);
// liveness: no subordinate stalls forever (pick a bound from the spec of the slowest device)
a_live:  assert property (@(posedge HCLK) disable iff (!HRESETn) !HREADY |-> ##[1:32] HREADY);
// default subordinate: an unmapped NONSEQ completes (OKAY or a two-cycle ERROR)
a_dflt:  assert property (@(posedge HCLK) HTRANS[1] && HREADY && hsel_none |=> ##[0:1] HREADY);
```

**Coverage that matters** (all measured in Lab 6): device × read/write × size × lane; back-to-back transfers; write followed directly by a read to the same RAM; wait states; a wait while the *next* Address phase targets a *different* device (the HSELD case); unmapped accesses; an interrupt pending while a transfer is committed; a trap in the Adr phase of a bus access.

## 9.5 Wally's bus: LSU, IFU, EBU, uncore

### The pieces

With `BUS_SUPPORTED = 1`, the top level becomes `wallypipelinedsoc` = `wallypipelinedcore` + `uncore` (Fig. 9.20).

| Config parameter | Device | Address |
| --- | --- | --- |
| UNCORE\_RAM\_SUPPORTED | RAM in the uncore (ram\_ahb) | 0x8000\_0000 |
| BOOTROM\_SUPPORTED | Boot ROM (rom\_ahb) | 0x1000 |
| EXT\_MEM\_SUPPORTED | AHB port to off-chip memory (e.g. a DDR controller on an FPGA) | 0x8000\_0000 |

Behind `ahbapbbridge` sit CLINT, PLIC, GPIO, UART and SPI (Ch 20). HADDR is a *physical* address, PA\_BITS wide: 34 bits for RV32 and 56 for RV64 (Ch 11).

### 9.5.1 The LSU and IFU bus interfaces

The LSU loses its DTIM (or keeps it next to the bus, 9.5.4) and gains an `ahbinterface`:

- a **write buffer** that drives HWDATA/HWSTRB in the Data phase;
- a **fetch buffer** that captures HRDATA;
- the **busfsm** (below), which sequences the phases.

HADDR is simply IEUAdrM: the access starts in the Memory stage.

&#91;embedded content: busfsm (book Fig. 9.23); Stall = StallW for the LSU, StallD for the IFU\]

| Step | Read | Write |
| --- | --- | --- |
| Execute | IEUAdrE = base + offset | same |
| Mem1 = AHB Adr | HADDR = IEUAdrM, HTRANS = NONSEQ, wait for HREADY | same, plus sub-word write muxing |
| Mem2 = AHB Data | device reads (more cycles if HREADY is low) | HWDATA driven, device writes |
| Mem3 | fetch buffer → sub-word and endian mux → ReadDataM | (nothing) |
| Writeback | ReadDataW → register file | (nothing) |

So **a bus load costs 2 extra cycles even with a zero-wait-state device** (book Fig. 9.22, and Lab 6 below measures exactly 2). Why not overlap the phases like AHB allows? You would need the address one cycle earlier (longer IEUAdrE path) or the data one cycle later (a bigger load-use penalty). With a cache or TIM in front, bus accesses are rare, so **Amdahl's law says keep the cycle time and accept the latency**. That trade-off is a good interview answer.

The IFU's interface is the same idea but read-only, 32-bit, little-endian (HSIZE = 010). Its busfsm uses StallD instead of StallW.

### 9.5.2 External bus unit (EBU): two managers, one bus

The IFU and LSU both want the one AHB. The EBU is a tiny multilayer-AHB arbiter (Figs. 9.25 and 9.26):

- **The LSU always wins.** The instruction in Memory is older; making it wait for a fetch of a younger instruction could deadlock the pipeline.
- `ebufsmarb` has two states, Idle and Arbitrate (a Mealy machine). If both request in Idle, it grants the LSU and goes to Arbitrate.
- The subtle part is the **save and replay**. The IFU also saw HREADY = 1, so it believes its Address phase was accepted and moves to its Data phase. The EBU must therefore **save the IFU's Address-phase signals** (`controllerinput`, IFUSave) and **replay** them (IFURestore) when the LSU is done, holding IFUHREADY low meanwhile. Data-phase signals need no saving.
- Fig. 9.27: cycle 0 both request (LA1 and IA1), the LSU is granted; cycle 1 LSU data returns and the saved IA1 goes on the bus; cycle 2 IFU data returns, back to Idle.

### 9.5.3 Uncore: decoder and mux

`adrdecs` compares HADDR with each device's `<DEVICE>_BASE`/`_RANGE` and produces a one-hot HSEL, with **HSEL\[0\] = no match**. HSELD is HSEL registered **when HREADY is high**, so it names the device that owns the current Data phase. The HREADY and HRDATA muxes use HSELD. Example 9.2 (Fig. 9.29) is the one to be able to draw: a ROM read with 2 wait states, then a RAM read with 1. HSEL moves to the RAM while HSELD stays on the ROM until the ROM's HREADYOUT rises.

### 9.5.4 TIMs and a bus together

An embedded configuration (Wally rv32imc) keeps an IROM and DTIM in the core *and* a bus for peripherals. The **PMA checker** decodes the address into SelDTIM/SelIROM, which steers each access to the TIM (same-cycle) or the busfsm (multi-cycle). Lab 6 builds exactly this.

### 9.5.5 Bus hazards

- **Stall everything.** BusStall from either unit raises **StallW**, and since a stage stalls whenever a later one does, the whole pipeline freezes. The book's equation is `StallWCause = (IFUStallF & ~FlushDCause | LSUStallM) & ~FlushWCause`: a flush beats a bus stall.
- **Why not stall only Decode for an IFU miss?** An exception could then fire in Memory while a fetch is mid-transfer, and caches make that worse. Stalling everything keeps it simple.
- **Wait in Mem3.** If the LSU finishes first while the IFU is still busy, StallW stays high, so the LSU's busfsm parks in Mem3. Otherwise it would re-issue the same request.
- **BusCommitted delays interrupts.** It is 0 only in Adr. From the Data phase on, a transfer must complete, so the trap unit uses `Committed = CommittedM | CommittedF` to hold pending interrupts (Fig. 9.35). A trap in the Adr phase **cancels** the transfer by driving HTRANS = IDLE.
- **Why it matters: non-idempotent reads.** Reading a 16550 UART's receive buffer register *removes* the byte. If an interrupt flushed that load after the read happened, the load would re-execute after mret and a byte would be lost. Stores are similar: once they start they must commit. Fig. 9.34 traces a fetch, and the GIF in Lab 6 traces a real load on our core.

## Lab 6: put a bus on cpu-from-scratch, then hunt bus bugs

**Goal.** Give our 5-stage core what Wally's rv32imc configuration has (book 9.5.4): IROM/DTIM inside the core, plus an AHB port from the LSU to an uncore with RAM and APB peripherals. Then ask the senior-DV question: *which kind of test finds which kind of bus bug?*

### What was built

| File | What it is | Wally counterpart |
| --- | --- | --- |
| `rtl/pipe/core_pipe.sv` | LSU gets a PMA (`SelBusM`: 0x1xxx\_xxxx and 0x9xxx\_xxxx go to the bus), a write buffer, a fetch buffer and `busfsm` (Adr, Data, Mem3). The E, M and W registers gain stall enables. | `lsu.sv`, `ahbinterface.sv`, `busfsm.sv` |
| `rtl/pipe/hazard.sv` | `StallW = LSUStallM & ~FlushWCause`, propagated to every earlier stage; the bubble goes into the first *unstalled* stage | `hazard.sv` (Fig. 9.33) |
| `rtl/pipe/priv.sv` | interrupts gated by `~Committed`; minstret and CSR updates wait while M is stalled | `trap.sv` (Fig. 9.35) |
| `rtl/uncore/uncore.sv` | decoder (HSEL, HSEL\[0\] = none), HSELD, HREADY/HRDATA mux, default subordinate, single-port SRAM with the write-then-read wait state, AHB-to-APB bridge, GPIO (Example 9.1), CLINT, and a UART-like **RXFIFO whose reads pop** | `uncore.sv`, `ram_ahb.sv`, `ahbapbbridge.sv`, `gpio_apb.sv`, `clint_apb.sv` |
| `dv/iss.py` | device models for RAM, GPIO, RXFIFO, CLINT, so lock-step covers bus loads too | ImperasDV with a platform model |
| `tb/tb_ahb.sv` | **block-level** bench: constrained-random pipelined AHB manager, in-order scoreboard, liveness check, coverage counters, no CPU | an AHB VIP |
| `tests/bus/*.S`, `dv/bushunt.py`, `dv/busperf.py` | 3 directed system tests, the bug-hunt matrix, the cost-of-a-bus measurement | — |

Memory map of the bus: RAM `0x9000_0000`, RXFIFO `0x1000_0000`, GPIO `0x1006_0000` (Wally's GPIO base), CLINT `0x1020_0000`; anything else in those regions goes to the default subordinate.

### Results

- **No regressions.** All earlier tests pass with the bus in the design: 60/60 (book test, directed, priv, bus, 50 random seeds), 100% of the Ch 5 coverage bins. They pass again with `-GRAM_WAIT=2`. The Ch 5 and Ch 8 bug hunts give the same answers as before.
- **Block-level bench, clean design:** 5 seeds × 20,000 cycles, 0 errors. Per seed about 5,700 RAM transfers, 9,000 back-to-back transfers, 550 write→read pairs on the RAM, 3,800 wait cycles where the next Address phase targets a different device, and 1,300 unmapped transfers.

**What a bus access costs** (`dv/busperf.py`: write 64 words, then sum them):

| Memory | RAM wait states | Instructions | Cycles | CPI | Bus stall cycles |
| --- | --- | --- | --- | --- | --- |
| DTIM (in core) | – | 588 | 846 | 1.44 | 0 |
| bus RAM | 0 | 588 | 1,102 | 1.87 | 256 |
| bus RAM | 1 | 588 | 1,230 | 2.09 | 384 |
| bus RAM | 2 | 588 | 1,358 | 2.31 | 512 |
| bus RAM | 4 | 588 | 1,614 | 2.74 | 768 |

That is 128 accesses × exactly 2 stall cycles (Adr + Data) with a zero-wait RAM, plus 128 cycles per extra wait state, as in book Fig. 9.22. An APB access costs more: Adr, bridge Setup, Access with the FIFO's wait state, then Mem3. This is why real cores put caches or TIMs in front of the bus (Ch 12–13).

**Interrupts really are deferred.** In `bus_irq.S`, 40 timer interrupts hit a loop of 400 RXFIFO reads, and an enabled interrupt had to wait for a committed transfer in 38 cycles. The animation is that simulation, cycle by cycle:

&#91;image: Lab 6 waveform: a timer interrupt waits while a load from the RXFIFO is committed on the bus, then is taken on the next instruction\]

### Bug hunt: which check finds which bug

Each cell under a system test is *self-check / lock-step vs ISS*. The block-level column is 5 random seeds × 20,000 cycles of `tb_ahb.sv`.

| Injected bug | Where | bus\_basic | bus\_irq | bus\_unmapped | Block-level random |
| --- | --- | --- | --- | --- | --- |
| (none) | – | pass / match | pass / match | pass / match | 0/5 fail |
| `BUG_NO_COMMIT`: interrupt mid-transfer | core | pass / match | **FAIL / MISMATCH** | pass / match | n/a (no CPU) |
| `BUG_BUS_NO_CANCEL`: trapping store still issued | core | **FAIL / MISMATCH** | pass / match | pass / match | n/a (no CPU) |
| `BUG_HSEL_NOT_DELAYED`: mux by HSEL, not HSELD | uncore | pass / match | pass / match | pass / match | **5/5 fail** |
| `BUG_RAM_NO_RAW_WAIT`: no wait for write→read | uncore | pass / match | pass / match | pass / match | **5/5 fail** |
| `BUG_DEFAULT_HANG`: unmapped access never completes | uncore | pass / match | pass / match | **HANG** | **5/5 fail** |
| `BUG_APB_EARLY_WDATA`: bridge takes write data from the Address phase | uncore | **FAIL / MISMATCH** | pass / match | pass / match | **5/5 fail** |

How each one showed up (first failure, verbatim):

- **BUG\_NO\_COMMIT**: `ref x6=00000107, dut x6=00000108` at the first FIFO load after an interrupt. The flushed load had already popped 0x107; after mret it ran again and got 0x108. One UART byte was lost. This is exactly book 9.5.5.
- **BUG\_BUS\_NO\_CANCEL**: the misaligned `sh` to GPIO trapped correctly, but its bus write went out anyway. GPIO OUT read back `99347777`, not `99345678`. Lesson: "the trap was taken" does not mean "nothing happened".
- **BUG\_HSEL\_NOT\_DELAYED**: block-level only, at cycle 22: `read 90000004 got 00000000 expected 80560000`. While the RAM's Data phase was finishing, the next Address phase pointed at another device, so the mux returned that device's data.
- **BUG\_RAM\_NO\_RAW\_WAIT**: block-level only, at cycle 84. A read right after a write got the SRAM port's write address.
- **BUG\_DEFAULT\_HANG**: missed by the first two system tests because **they never touched unmapped space**. That is a coverage hole, not a passing design. `bus_unmapped.S` was written after the hunt showed the hole, and its 3 lines catch it (the testbench reports `AHB hang`, not just a timeout).
- **BUG\_APB\_EARLY\_WDATA**: caught by both. GPIO read back `40401f1f` because the bridge latched the *previous* write's data. The core's write buffer only drives HWDATA in the Data phase, so a write to EN followed by a write to OUT exposes it.

### What to say in an interview

1. **A polite manager hides subordinate bugs.** Our LSU issues one transfer at a time and holds the address through the Data phase, so HSEL always equals HSELD and a write is never directly followed by a read. Two real uncore bugs are **invisible from the CPU**. That is the case for block-level verification with a protocol-legal but *aggressive* random manager: back-to-back, mixed devices, garbage HWDATA outside the Data phase.
2. **Core-side bus bugs need the CPU and a reference model.** Committed and trap-cancel are about how the pipeline and the bus interact. No bus VIP sees them. Lock-step with device models does, provided the model knows about **side effects** (the FIFO pop).
3. **Every bug was found by something, but no single bench found all six.** Plan the layers (protocol, block, system, performance) and make coverage say which scenarios each layer actually reached.
4. **A pass with zero coverage of a feature is not a pass.** BUG\_DEFAULT\_HANG hid until one directed test touched unmapped space.

## Recap

- **Every bus is a controller sending an address (and write data) and a peripheral answering with read data and *ready*.** On chip, the wiring is unidirectional and point-to-point, with an address decoder and a read mux.
- **APB** is Setup then Access, one transfer at a time, PREADY for waits. **AHB** overlaps Address and Data phases, so write data trails its address by a cycle. HREADY is shared, and the mux must follow **HSELD**. **AXI** splits everything into five VALID/READY channels with IDs, bursts and out-of-order responses.
- **The interconnect is where protocol bugs hide:** HSEL vs HSELD, the default subordinate, single-port SRAM write→read collisions, bridge phase alignment, byte lanes for narrow transfers.
- **In Wally, a bus access stalls the whole pipeline** for Adr + Data (2 cycles + waits). The EBU gives the LSU priority and saves/replays the IFU request. **BusCommitted** blocks interrupts once a transfer has started, because devices can have side effects.
- **Verification needs layers.** Lab 6: a polite CPU hid two of four uncore bugs; a block-level random manager found all four. Two core-side bugs needed the CPU plus lock-step with device models. One bug hid until a test touched unmapped space.

## Interview drill

**1. Explain the AHB pipeline in one minute.** Two phases per transfer. In the Address phase the manager drives HADDR, HWRITE, HSIZE and HTRANS; in the Data phase HWDATA goes out or HRDATA comes back. Transfer *n*'s Data phase overlaps transfer *n+1*'s Address phase, so a zero-wait subordinate sustains one transfer per cycle, about twice APB. A subordinate stretches its Data phase by holding HREADYOUT low. The muxed HREADY then freezes both the current Data phase and the waiting Address phase.

**2. HREADY vs HREADYOUT?** HREADYOUT is each subordinate's own "I'm done". HREADY is the interconnect's mux of the HREADYOUT of whoever owns the Data phase, broadcast to the manager *and all subordinates*. A subordinate may start a new transfer only when HSEL & HTRANS\[1\] & **HREADY**, because the previous Data phase may belong to another device.

**3. What is HSELD and what breaks without it?** HSEL registered whenever HREADY is high: the owner of the current Data phase. Muxing by HSEL means a ROM read with wait states, followed by a RAM access, would take HREADY and HRDATA from the RAM. The ROM transfer ends early with the wrong data. In Lab 6 this was invisible from the CPU (one transfer at a time) and found by a random pipelined manager in 22 cycles.

**4. How do you verify an AHB interconnect?** Bind a protocol checker on every port: stability while HREADY is low, alignment, strobe lanes, liveness, and default-subordinate completion. Drive it with a constrained-random manager that issues back-to-back transfers to mixed devices with random sizes and IDLEs, and with garbage on HWDATA outside the Data phase. Check every read with an in-order scoreboard against a device model. Inject waits from the subordinates. Cover device × direction × size × lane × back-to-back × wait × cross-device, plus unmapped space and reset in mid-transfer.

**5. State the AXI handshake rules and write one assertion.** A beat transfers on an edge where VALID & READY. VALID must not wait for READY; READY may wait for VALID. Once VALID is high, VALID and the payload stay stable until the handshake. `assert property (@(posedge ACLK) disable iff (!ARESETn) ARVALID && !ARREADY |=> ARVALID && $stable({ARADDR, ARLEN, ARSIZE, ARBURST, ARID}));` Same IDs return in order; different IDs may come back out of order.

**6. Why does Wally give the LSU priority over the IFU, and what does the EBU save?** The LSU's instruction is older. Making it wait for a younger instruction's fetch could deadlock, because the pipeline is stalled behind it. On a collision the IFU had already seen HREADY = 1 and moved into its Data phase, so the EBU saves the IFU's Address-phase signals and replays them when the LSU is done, holding IFUHREADY low. A typical bug: the replay is lost or issued twice. Check that every IFU address appears on the bus exactly once.

**7. An interrupt arrives while a load is waiting on a UART. What must the core do?** If the transfer is still in its Address phase, the trap may cancel it (HTRANS = IDLE) and the load re-runs after mret, which is harmless. Once the Data phase has started, the device may have acted (the receive buffer popped), so the core must let the transfer finish and take the interrupt on a later instruction. That is Wally's BusCommitted. My Lab 6 bug showed exactly this: one byte lost, caught by lock-step with a FIFO-aware device model.

**8. A bus load costs 2 extra cycles in Wally even with a zero-wait RAM. Why not overlap the AHB phases?** You would need the address a cycle earlier (a longer address-generation path in Execute) or the data a cycle later (a bigger load-use hazard). With a cache or TIM in front, bus accesses are rare, so the cycle time matters more. Lab 6: 128 accesses cost exactly 256 stall cycles; each extra wait state adds 128.

**9. What does an AHB-to-APB bridge have to get right?** Act as an AHB subordinate: sample on initTrans and hold HREADYOUT low through APB Setup and Access until PREADY. Act as an APB requester: PSEL and PADDR stable from Setup, PENABLE only in Access, and **write data from the AHB Data phase**, not the Address phase. Also an APB default response when no peripheral is selected, and strobes passed through. Lab 6's early-write-data bug wrote the previous transfer's data into GPIO.

**10. Your SoC tests all pass. What would make you nervous about the bus?** Coverage, not results. Did any test touch unmapped space, have two managers collide, follow a write immediately with a read, wait on one device while the next transfer targets another, or take an interrupt mid-transfer? In Lab 6, BUG\_DEFAULT\_HANG passed two full system tests because nothing ever addressed unmapped space.

## Companion

Open the **[Bus Protocol Lab](https://claude.ai/artifact/WR95WbVphTVQbgAfYZ8mQJ)**:

- step AHB transfers cycle by cycle (book Fig. 9.10, Example 9.2, SRAM write→read, APB, unmapped) and switch on the HSELD, SRAM and default-subordinate bugs to watch the scoreboard fail;
- draw AXI VALID/READY traces and see the rule checker flag violations;
- watch the EBU save and replay an IFU fetch;
- price a bus access in CPI;
- finish with an 8-question self-check.

## Book coverage check (Ch 9 audit)

This tab was checked against all 19 sections of Chapter 9 and Tables 9.1–9.9. The protocol behaviour, Wally's design and the bug hunt were already covered. What was missing is the signal-level reference material from the book. Bus-VIP interviews ask for it directly.

### AHB signal reference (Tables 9.2–9.5, with the AMBA encodings)

**Terminology.** APB has Setup and Access phases; AHB calls them Address and Data. ARM's own documents use the two sets of names inconsistently. AHB was first defined (AMBA 2) with multiple managers and split transactions. AHB-Lite removed both. AHB5, the version the book means by "AHB", is AHB-Lite plus optional security and exclusive-access signals.

| Signal | Phase | Encoding / meaning |
| --- | --- | --- |
| HTRANS\[1:0\] | Adr | 00 IDLE · 01 BUSY (idle in the middle of a burst) · 10 NONSEQ · 11 SEQ |
| HSIZE\[2:0\] | Adr | Bytes = 2^HSIZE: 000 byte, 001 half, 010 word, 011 dword … up to 111 (128 bytes). Must not exceed the bus width. |
| HBURST\[2:0\] | Adr | 000 SINGLE, 001 INCR (undefined length), 010/011 WRAP4/INCR4, 100/101 WRAP8/INCR8, 110/111 WRAP16/INCR16 *(AMBA spec)* |
| HPROT | Adr | Protection/attribute hints (data or opcode, privileged, bufferable, cacheable) |
| HMASTLOCK | Adr | Locked sequence (read-modify-write) |
| HEXCL / HEXOKAY | Adr / Data | AHB5 exclusive access, and the subordinate's "exclusive succeeded" (the bus-level side of LR/SC) |
| HMASTER | Adr | Manager ID, needed so exclusive monitors know who is asking |
| HNONSEC | Adr | AHB5 security: a non-secure transfer |
| HWSTRB | **Data** | Byte strobes. The only manager-driven control signal in the Data phase. |
| HRESP | Data | The book quotes the old AMBA 2 two-bit code: 00 OKAY, 01 ERROR, 10 RETRY, 11 SPLIT. **In AHB-Lite/AHB5 HRESP is one bit** (0 OKAY, 1 ERROR), and an ERROR takes two cycles: HREADY low, then high. RETRY and SPLIT left with multi-manager AHB. |

The width of HADDR in Wally is PA\_BITS: 34 bits on RV32 (Sv32 physical addresses) and 56 bits on RV64. HRDATA and HWDATA are typically 32, 64, 128 or 256 bits wide.

### AXI4 channel signals (Table 9.7)

- Field widths:
  - xLEN = beats − 1 (1–256 beats for INCR, at most 16 for WRAP; the AXI4 limits).
  - xSIZE: bytes per beat = 2^xSIZE, so 1–128 bytes.
  - xBURST: 00 FIXED, **01 INCR (the one the book uses)**, 10 WRAP.
  - xRESP: 00 OKAY, 01 EXOKAY, 10 SLVERR, 11 DECERR.
  - IDs are ILEN bits wide and addresses ALEN bits; data buses are 8–1024 bits.
- Optional sideband groups: atomics, coherence, security (AxPROT), QoS, regions and USER signals. AXI5 adds options such as loopback signalling and data poisoning.
- **Rules to state in an interview**, from Fig. 9.19 (double-headed arrows mean "must come after"):
  - RVALID only after the AR handshake.
  - BVALID only after **both** AW and the WLAST beat have been accepted for that ID.
  - The W beats can arrive before AW, because of different register stages through the interconnect.
- **Not in the book's table, but always asked:** a burst must not cross a 4 KB boundary, and a WRAP burst's start address must be aligned to its size.

**Why AXI needs buffering.** On a multicycle (pipelined) channel the source only sees READY drop after a delay. The destination must either buffer the transfers already in flight, or hold READY low until VALID arrives, which leaves the bus idle most of the time. Real interconnects therefore use skid buffers. The DV check that follows: no transfer is lost or duplicated when READY drops.

**AXI4-Lite**: single-beat transfers of 32 or 64 bits, in order. A simple bridge connects it to full AXI. **ACE** adds coherence support. **CHI** extends that to scalable networks with directory-based coherence.

### Wally details the tab skipped

- The book suggests Mem2 and Mem3 *could* be merged, saving a cycle per bus load, at the risk of a longer cycle time. With a cache or TIM in front, the authors keep the faster clock.
- `pmachecker` (Fig. 11.16) is the Fig. 9.11 address decoder extended to check access type and size. The decoder you verify in Chapter 9 becomes the PMA checker you verify in Chapter 11.
- **Naming note (margin of 9.1.1).** Old documents say master/slave. ARM moved to manager/subordinate and requester/completer in 2021. SCSI uses initiator/target. The book uses controller/peripheral. Use the customer's terms in an interview; for ARM and NVIDIA, that is manager/subordinate.
