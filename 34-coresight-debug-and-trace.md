# Challenge 34: CoreSight Debug and Trace — Architecture, Spec and Verification

> **Level:** Fresher → Senior CPU DV interview (NVIDIA / ARM / Qualcomm style)
> **Topics:** debug vs. trace, DAP (DP/AP), programmers' model and ID registers, ROM tables and discovery, topology detection, APB / ATB / event / channel / timestamp interfaces, authentication, trace formatter, cross-triggering (CTI/CTM), power and reset, verification plan, SVA, bug catalog
> **Source:** ARM IHI 0029E, *CoreSight Architecture Specification v3.0* (section refs like `§C5.4`). Items marked **(beyond spec)** come from neighbouring ARM specs (ADI, ETM, CTI, TMC, AMBA ATB).
> **Related:** [08 – SVA](08-sva-assertions.md), [10 – Ready/valid](10-ready-valid-handshake-assertions.md), [13 – SVA beyond happy path](13-sva-beyond-happy-path.md), [15 – RAL](15-uvm-register-model-ral.md), [17 – Bus protocols](17-bus-protocols-axi-ahb-pcie.md), [25 – Debugging failures](25-debugging-intermittent-and-persistent-failures.md)

**Companion material in [`coresight/`](coresight/README.md):**

| File | What it is |
|---|---|
| [`coresight/coresight-from-zero.html`](coresight/coresight-from-zero.html) | Beginner course with analogies, mini games and a quiz (open in a browser) |
| [`coresight/coresight-field-guide.html`](coresight/coresight-field-guide.html) | Senior infographic guide with live decoders (auth, formatter, ROM entry, ID registers) |
| [`coresight/code/coresight_tools.py`](coresight/code/coresight_tools.py) | Python golden models: ID decode, ROM walk, auth equations, formatter encode/decode, self-tests |
| [`coresight/code/coresight_sva.sv`](coresight/code/coresight_sva.sv) | Bind-able SVA checkers: ATB, channel handshake, APB power-down, auth/AUTHSTATUS, CTI |

---

## 1. The 60-second picture

CoreSight is a **plug-together debug and trace fabric**:

- every component exposes the **same 4KB register frame** so tools can **identify** it,
- a **ROM table** lets a debugger **discover** everything from one base pointer,
- **APB** programs components, **ATB** carries trace from **sources → links → sinks**,
- **channels** carry cross-triggers between **CTIs**,
- **authentication signals** gate what is allowed,
- a shared **64-bit timestamp** correlates streams,
- and all of it must keep working while parts of the SoC are **powered off**.

Three layers of the architecture (`§A1.2`):

| Layer | Spec part | Mandatory? | Contents |
|---|---|---|---|
| Visible component | Part B | Yes | Programmers' model (CIDR/PIDR, management regs `0xF00–0xFFC`), topology-detection registers |
| Reusable component | Part C | No (needed for interoperability) | APB, ATB, event, channel, authentication, timestamp interfaces |
| System | Part D | Yes for systems | Clock/power domains, auth control, memory views, connectors, formatter, ROM tables, topology detection, compliance |

---

## 2. Background (fresher level)

| Everyday picture | Real term |
|---|---|
| Pause a worker and look inside | **Debug** — *invasive*: changes defined behaviour (halt, memory write, instruction injection) |
| CCTV recording, worker never stops | **Trace** — *non-invasive*: observes only |
| Front door + receptionist + hallways | Probe on **JTAG/SWD** → **DP** (Debug Port) → **APs** (APB-AP, AXI/AHB-AP, JTAG-AP) = **DAP** |
| Same name badge in every room | **CIDR0–3 / PIDR0–7** at `0xFD0–0xFFC` |
| Building map | **ROM table** |
| Mailboxes over a phone line | **Registers** over the **Debug APB** |
| Cameras / diary | **ETM** (instruction trace), **STM** (software/system trace) |
| Conveyor belt with name tags | **ATB** with `ATVALID/ATREADY` and **ATID** |
| Lane merger / photocopier | **Funnel** / **replicator** |
| Shelf / warehouse / window | **ETB/ETF** / **ETR** (DRAM) / **TPIU** (trace port) |
| Stickers in the stream | **Trace formatter** (16-byte frames) |
| Walkie-talkies | **CTI** + **CTM** + channels |
| Keys | **DBGEN, NIDEN, SPIDEN, SPNIDEN, HIDEN, HNIDEN** |
| Lights off | **Power domains**; "sorry, dark" = **PSLVERR** |

---

## 3. System map

```
 Probe ──JTAG/SWD──► SWJ-DP ─┬─ APB-AP ──► Debug APB ═══╦═══════╦═══════╦══════════╦═══════
                             ├─ AXI-AP ──► system mem   ║       ║       ║          ║
                             └─ JTAG-AP ─► legacy TAPs  ROM   Power   TS gen   Cluster0..N
                                                       table  req.    (64b)   [dbg|CTI|ETM|PMU]
                                                                                 │     │
            Auth ctrl (fuses / challenge-response) ──► *EN to every component    │     │ ATB
                                                                                 │     ▼
                     CTI0 ◄──channels──► CTM ◄──channels──► CTI1 ... CTI(sinks)  │  Funnel ─► ETF ─► Replicator ─┬─► ETR ─► DRAM
                                                                                 │                              └─► TPIU ─► trace port ─► TPA
                                                                  STM ───────────┘ (ATB)
```

Component taxonomy and `DEVTYPE` (`§B2.3.8`):

| Role | Examples | DEVTYPE MAJOR / SUB |
|---|---|---|
| Trace source | ETM, PTM, STM, HTM | `0x3` / `0x1` core, `0x4` bus, `0x6` software |
| Trace link | Funnel, replicator, ATB bridge, ETF | `0x2` / `0x1` funnel, `0x2` filter, `0x3` FIFO |
| Trace sink | TPIU, ETB, TMC/ETR | `0x1` / `0x1` port, `0x2` buffer, `0x3` router |
| Debug control | CTI/CTM, auth module, power requestor | `0x4` / `0x1`, `0x2`, `0x3` |
| Debug logic | PE external debug, bus debug, BIST | `0x5` / `0x1` … `0x5` |
| Performance monitor | PMU, SMMU PMU | `0x6` / `0x1` … `0x5` |

---

## 4. Programmers' model (`§B2`)

Word-aligned, little-endian, 4KB. Top 256 bytes are common to all CoreSight components.

| Offset | Register | Notes |
|---|---|---|
| `0x000 ↑` | Component control regs | Grow upward |
| `… 0xEFC ↓` | Integration regs | Grow downward (recommended) |
| `0xF00` | **ITCTRL** | `IME=1` → integration / topology-detection mode. Reset the system afterwards |
| `0xFA0 / 0xFA4` | **CLAIMSET / CLAIMCLR** | Cooperative ownership tags; CLAIMCLR resets to 0 |
| `0xFA8 / 0xFAC` | **DEVAFF0/1** | Affinity (e.g. MPIDR) — links PE ↔ CTI ↔ ETM without detection |
| `0xFB0 / 0xFB4` | **LAR / LSR** | Software lock, key `0xC5ACCE55`; **deprecated in v3.0** |
| `0xFB8` | **AUTHSTATUS** | What the auth signals currently allow |
| `0xFBC` | **DEVARCH** | ARCHITECT[31:21], PRESENT[20], REVISION[19:16], ARCHID[15:0] |
| `0xFC0–0xFC8` | DEVID2 / DEVID1 / DEVID | Capabilities |
| `0xFCC` | **DEVTYPE** | SUB[7:4], MAJOR[3:0] |
| `0xFD0–0xFEC` | **PIDR4–7, PIDR0–3** | JEP106 designer, PART[11:0], REVISION, REVAND, CMOD |
| `0xFF0–0xFFC` | **CIDR0–3** | Preamble `0x0D, 0x?0, 0x05, 0xB1`; CLASS = CIDR1[7:4] |

- **CLASS:** `0x1` ROM table · `0x9` CoreSight component · `0xF` CoreLink/PrimeCell/system · `0xE` generic IP · `0xB` peripheral test block · `0x0` generic verification component.
- **Unique Component Identifier** (`§B2.1.2`): CLASS + PART + JEP106 + REVISION + REVAND (+ DEVARCH, DEVTYPE for class 0x9). CMOD can no longer distinguish parts. Any change → bump REVISION or REVAND.
- **Reserved space:** unimplemented = **RAZ/WI**; everything unimplemented in `0xF00–0xFFF` reads zero.
- **Multi-4KB components:** 2ⁿ contiguous blocks, max 16,384 (64MB). `PIDR4.SIZE` deprecated (should be 0, tools ignore it).
- ARM's JEP106: continuation `0x4`, ID `0x3B` → `DEVARCH.ARCHITECT = 0x23B`.

### Four mechanisms people confuse

| Mechanism | Protects against | How |
|---|---|---|
| **Authentication** (`§C5`) | Unauthorized people | Pin enables disable **functionality**; registers stay readable |
| **Software lock** (`§B2.3.10`) | Rogue on-chip code | `LAR ← 0xC5ACCE55`; external accesses should bypass it |
| **Claim tags** (`§B2.3.2`) | Two debug agents fighting | Software protocol; protocol 3 adds race back-off |
| **OS lock** (beyond spec) | Debugger vs. OS save/restore across power-down | Needs separate internal/external views (`§D2.3`) |

---

## 5. Discovery: ROM tables and topology (`§D5–D8`)

- Only the **top-level pointer is absolute** (MEM-AP `BASE`, DP `BASEPTR`). Entries are **relative**:
  `component = ROM_base + (OFFSET << 12)`, OFFSET is **signed**.
- ID registers of the component are at `component + 0xFD0`.
- **Rules:** every component appears **once** per visible hierarchy; **no circular** references; `OFFSET ≠ 0` when present.
- Systems with more than one debug component **must** have a ROM table.

| | Class 0x1 | Class 0x9 |
|---|---|---|
| Identified by | CIDR1.CLASS = 0x1 | CLASS = 0x9, DEVARCH.ARCHID = `0x0AF7` |
| Entries | 32-bit, ≤ 960, area to `0xEFC` | 32-bit ×512 or 64-bit ×256 (DEVID.FORMAT), area to `0x7FC` |
| Fields | OFFSET[31:12], POWERID[8:4], POWERIDVALID[2], FORMAT[1]=1, PRESENT[0] | OFFSET[31:12] or [63:12], POWERID[8:4], POWERIDVALID[2], PRESENT[1:0] |
| End | entry == 0 (or entry at 0xEFC) | PRESENT=`0b00` (all zero) |
| Not present, keep going | PRESENT=0, entry ≠ 0 | PRESENT=`0b10` |
| Power / reset | Separate power requestor in the same table | Built in: DBGPCR/DBGPSR, SYSPCR/SYSPSR, PRIDR0, DBGRSTRR/AR, SYSRSTRR/AR |

Worked example (spec Figure D6-1): class 0x1 entry `0x00003017` at ROM base `0x8000_0000` →
PRESENT=1, FORMAT=1, POWERIDVALID=1, POWERID=1, OFFSET=3 → component at `0x8000_3000`, request power domain 1 first.

```python
>>> from coresight_tools import decode_romentry
>>> decode_romentry(0x00003017, 0x8000_0000, rom_class=0x1)
RomEntry(kind='present', address=2147495936, offset_4kb=3, power_id=1, errors=[])
```

### Cold connect (`§A1.4.2`, `§D8.2`)

1. Connect JTAG/SWD; talk to the DP.
2. Request debug + system power-up; check clocks.
3. Read the top-level ROM PIDR; if a **saved description** matches, use it (non-invasive reconnect).
4. Else walk all ROM tables; identify each component (CIDR/PIDR/DEVARCH/DEVTYPE). Unknown parts: report JEP106 + class, ignore.
5. Topology detection with `ITCTRL.IME=1`.
6. **Reset the system** (detection is invasive) and save the description.

```text
// §D8.4 detection algorithm (condensed)
for each component: ITCTRL.IME = 1
for each interface type t:
  master_preamble(all); slave_preamble(all)
  for each master m:
    assert(m)                               // ATB: ATVALID←1   Channel: CHOUT[0]←1
    for each slave s: if check_asserted(s) record(m→s)
    slave_post_assert(all); deassert(m)
    for each slave s: if !check_deasserted(s) error
    slave_post_deassert(all)
for each component: ITCTRL.IME = 0          // then reset the system
```

Why **ATVALID**? A non-programmable bridge passes no control while ATVALID is low (`§C7.3.1`). When DBGACK on the CoreETM interface is not controllable, use **DEVAFF**.

---

## 6. Reusable interfaces (`§C2–C6`)

| Interface | Key rules | Famous corner case |
|---|---|---|
| **Debug APB** | 32-bit, non-pipelined, PREADYDBG stall, PSLVERRDBG error. Off-clamps: PREADY=1, PSLVERR=1, PRDATA=0 | PSLVERR **only** for "component not available" (e.g. powered down). PADDRDBG[31] split deprecated |
| **ATB** | Valid/ready stall, ATBYTES, ATID per beat, flush AFVALID/AFREADY (beyond spec) | IDs 0x7B (flush resp) and 0x7D (trigger) are legal on ATB |
| **Event** | Event = **rising edge**; ≤ 1 per 2 clocks; falling edge = completion | **No back-pressure** → events merge across CDC |
| **Channel** | Bidirectional, ≥ 4 channels, sync (CHCLK) or async 4-phase (CHIN/CHINACK) | Must **not reflect** input to own output; subset rule: contiguous from channel 0 |
| **Timestamp** | TSVALUEB[63:0], same value to all | **0 = UNKNOWN**; resolution ≥ 10% of fastest PE clock |
| **Authentication** | DBGEN, NIDEN, SPIDEN, SPNIDEN, HIDEN, HNIDEN | Non-invasive enable requires importing its invasive pair; effect timing is IMPLEMENTATION DEFINED |

Channel async handshake: `CHIN↑ → CHINACK↑ → CHIN↓ → CHINACK↓`. Not suitable for counting fast events (e.g. instructions); fine for one-shot triggers and handshaked IRQs.

---

## 7. Authentication (`§C5`, `§D2.2`)

CoreSight **disables functionality, not register access** — tools must always discover and read AUTHSTATUS.

```text
NS invasive     = DBGEN
NS non-invasive = DBGEN | NIDEN
S  invasive     = DBGEN & SPIDEN
S  non-invasive = (SPIDEN | SPNIDEN) & (DBGEN | NIDEN)
H  invasive     = DBGEN & HIDEN
H  non-invasive = (HIDEN | HNIDEN) & (DBGEN | NIDEN)
```

Three ideas generate all six: **invasive ⇒ non-invasive**, **Secure needs the Non-secure enable**, **Secure and hypervisor are independent**.

AUTHSTATUS fields (2 bits each, `0b10` supported/disabled, `0b11` supported/enabled, `0b00` not supported):
`HNID[11:10] HID[9:8] SNID[7:6] SID[5:4] NSNID[3:2] NSID[1:0]`.

Not-recommended combinations (rules 4, 7, 8, 9, 12, 15, 16), e.g. NIDEN=0 with DBGEN=1, SPIDEN=1 with DBGEN=0. Deprecated since v2.0: (SPIDEN,DBGEN,SPNIDEN,NIDEN) = 0010, 1010, 1011.

Signal drive options: tied LOW (production), tied HIGH (prototype), **fuse**, or **challenge-response** auth module.

Definitions worth quoting: measuring the duration of a Secure routine is **Non-secure** debug; changing it is **Secure** debug. Changing cycle counts is not invasive unless the cycles are architecturally defined.

---

## 8. Trace formatter (`§D4`)

Merges many ATB sources into one stream when IDs cannot travel on pins. **16-byte frames**:

```
        bits 31..24   23..17 16     15..8   7..1   0
Bytes 3-0   data(B)   ID/data  F    data(A) ID/data F      even bytes: bit0 = F
Bytes 7-4   data      ID/data  F    data    ID/data F        F=1 → bits[7:1] = new ID
Bytes 11-8  data      ID/data  F    data    ID/data F        F=0 → data[7:1], data[0] in aux
Bytes 15-12 aux J..A  ID/data  F    data    ID/data F      byte 15 = aux bits for bytes 0,2,…,14
```

- For an ID byte, the aux bit says whether the **next** byte still belongs to the **old** ID (1) or the **new** ID (0). An ID in byte 14 takes effect from the next frame.
- Special IDs: `0x00` null · `0x01–0x6F` sources · `0x70–0x7A` reserved · `0x7B` flush response · `0x7C` reserved · `0x7D` trigger · `0x7E` reserved · `0x7F` never.
- Sync: full frame `0x7FFFFFFF`; halfword `0x7FFF` (continuous mode only, discarded by TPA).
- Overhead ≈ 6% + 1 byte per ID change; repeat ID ≈ every 10 frames.

| Mode | Formatter | TRACECTL | Use when |
|---|---|---|---|
| Bypass | Off | Required | Single source; no 0x7D trigger; cannot use ID-switch alignment |
| Normal | On | Marks trigger/idle | ETM-era TPAs |
| Continuous | On | Unused | TPA decodes sync/trigger from stream |

End of trace (`§D4.4`): bypass → a single `1` bit then zeros; normal/continuous → complete the frame with null ID `0x00`.

Spec worked example (Table D4-2), decoded by the golden model:

```python
>>> from coresight_tools import decode_frame
>>> f = bytes.fromhex("07 AA A6 A7 2B A8 54 52 52 54 07 CA C6 C7 C8 1C")
>>> pairs, end_id, _ = decode_frame(f)
# ID 0x03: AA A6 A7 A8 CA C6 C7 C8      ID 0x15: 55 52 53 54
```

---

## 9. Cross-triggering (CTI / CTM)

```
PE0 halted ─TRIGIN─► CTI0 [CTIINEN: trig→chan] ─► CTM (ch0 halt, ch1 restart, ch2 trace-stop)
                                                    ├─► CTI1 [CTIOUTEN: chan→trig] ─TRIGOUT─► PE1 halt
                                                    └─► CTI2 ─► ETF/TPIU TRIGIN, FLUSHIN
```

CTI register names (CTIINEN, CTIOUTEN, CTIGATE, CTIAPPPULSE/SET, CTIINTACK) are **beyond spec**.
Compliance (`§D9.2.1`): every event I/O connects to a CTI (unless only one component has events) and all channel interfaces are connected.

Hard parts to verify: **skid** (instructions retired after the halt), **CDC merging**, **level vs. pulse** (output held until CTIINTACK re-halts after restart), **no reflection**.

---

## 10. Power, clocks, reset (`§D2.1`, `§D6.3`, `§D7.3–7.4`)

| Domain | Contains | Rule |
|---|---|---|
| Always-on | DP, power controller | Never off; debugger can connect to a dormant device |
| Debug | ROM tables, CTI/CTM, links, sinks | Can be off; must stay on once Debug Power Up is requested |
| System | PEs, memory, interconnect | Clocks vary/stop; must honour System Power Up |

- Entry with POWERIDVALID=1 → **request power for POWERID before access**.
- Class 0x9 with DEVID.PRR=1: set `DBGPCR<p>.PR`, poll `DBGPSR<p>.PS == 0b11`.
- Debug reset: `DBGRSTRR.DBGRR←1`, wait `DBGRSTAR.DBGRA==1`, `DBGRR←0`, wait `DBGRA==0`.
- Compliance: everything visible with clocks running on Debug Power Up, operational on System Power Up, reset on Debug Reset (except where hidden by security).

---

## 11. Verification plan

Four-beat answer for any "how would you verify X": **spec intent → design hazard → stimulus → checker + coverage**.

| Area | Must hold | Stimulus | Checker | Coverage |
|---|---|---|---|---|
| ID & register frame | Preamble, CLASS, PIDR, DEVARCH, DEVTYPE match IP-XACT; RAZ/WI | Generated reg sequences, read every word `0xF00–0xFFF` | RAL mirror + table generated from design DB | reg × access × security view; formal for RAZ/WI |
| ROM discovery | Each component once; no cycles; OFFSET≠0; end marker; POWERID right | "Debugger-in-a-box" ROM walker (`walk_rom`) | Compare against integration netlist / SoC config | Every config & fuse variant; top-level PIDR changes with config |
| Authentication | Six equations; AUTHSTATUS truthful; clean stop | All 64 combos + toggles mid-trace/halt/world switch | `cs_auth_checker` + scoreboard: no Secure packets when blocked | combos × components; 0→1 / 1→0 per signal |
| Trace path | Lossless (or flagged); ID preserved; per-source order; flush completes | Random ATREADY, many sources, bursty STM, sink stop/start | Per-ATID scoreboard → formatter model → sink memory → decode | overflow, wrap, every funnel port, ID range edges |
| Formatter | Frame rules, aux bits, delayed switch, sync cadence, padding | ID change at every byte 0…14, flush mid-frame | `decode_frame` / `encode_frames` golden model | ID position × aux value; 3 modes × flush |
| Cross-trigger | Mapping, no reflection, bounded latency, ack clears | Random maps, simultaneous triggers, async clocks | Channel model; `cs_channel_checker`, `cs_cti_checker` | trigger × channel × target; gate; target WFI/off |
| Power | Off-domain access errors, never hangs | Power down mid-access/trace/halt | `cs_apb_pwr_checker`, UPF-aware sim | domain × access path |
| Non-invasiveness | Trace/PMU never change architectural results | Run each test trace-off vs. trace-on with max back-pressure | Compare retire log / final state | Suite parity |
| Timestamp | Monotonic, shared, 0=unknown, bounded skew | DVFS, TS gen off/on, reset | Cross-stream correlation | Wrap of implemented subset |

### Key assertions (full file: [`coresight/code/coresight_sva.sv`](coresight/code/coresight_sva.sv))

```systemverilog
// ATB: payload stable while stalled
a_atb_stable: assert property (@(posedge atclk) disable iff (!atresetn)
  atvalid && !atready |=> atvalid && $stable({atid, atdata, atbytes}));

// ATB: legal IDs only
a_atid_legal: assert property (@(posedge atclk) disable iff (!atresetn)
  atvalid |-> (atid inside {[7'h01:7'h6F]} || atid == 7'h7B || atid == 7'h7D));

// Debug APB: powered-down slave answers with PSLVERR, never hangs
a_no_hang:      assert property ($rose(psel && penable) |-> ##[0:MAX_WAIT] pready);
a_err_when_off: assert property (psel && penable && pready && !pwr_on |-> pslverr);

// Auth: Secure non-invasive gating
a_no_s_leak: assert property (!((spiden|spniden) & (dbgen|niden)) [*SYNC_CYC] |-> !secure_trace_active);
```

### Golden models (full file: [`coresight/code/coresight_tools.py`](coresight/code/coresight_tools.py))

```bash
cd coresight/code && python3 coresight_tools.py     # runs self-tests incl. spec Table D4-2
```

```python
from coresight_tools import auth_permissions, encode_frames, decode_stream
auth_permissions(dbgen=1, niden=1, spiden=0, spniden=1)["authstatus"]   # 0xAEF
frames = encode_frames([(0x10, 0xAA), (0x11, 0x55), (0x10, 0xBB)])       # stimulus / prediction
decode_stream(frames)                                                    # {0x10: b'\xaa\xbb', 0x11: b'U'}
```

---

## 12. Bug catalog (bring these as stories)

| Area | Bug | How you catch it |
|---|---|---|
| Power | Debugger hangs reading a sleeping core: off slave not clamped to PREADY=1/PSLVERR=1 | Access every component in every power state; bus-timeout monitor |
| Auth | AUTHSTATUS reports NS-only while the component gates Secure trace | Equation model vs. actual packet emission |
| Formatter | Delayed-ID aux bit inverted → one byte per switch on the wrong source | ID change at each even byte with both aux values |
| Flush | Funnel port starved during AFVALID, or replicator waits on disabled branch | Flush with each port idle/busy/disabled; flush-done bound |
| Trace ID | Two sources share ATID, or 0x00/0x70+ programmed | Unique-ID assertion across enabled sources |
| CDC | Cross-trigger pulse lost crossing into a slow cluster | Random clock ratios, back-to-back triggers |
| CTI | Core re-halts after restart: TRIGOUT level not acknowledged | Restart with and without CTIINTACK |
| ROM | POWERID tie-offs swapped between clusters | Power each domain alone, access every component |
| Timestamp | Reset to 0 mid-run or unsynchronised sampling → cross-core order inverts | Correlation checker with DVFS and TS gating |
| Integration | ITCTRL.IME left set; functional trace dead until reset | Functional run after detection must flag missing reset |

---

## 13. Likely interviewer follow-ups (model answers)

**Q1. Define invasive vs. non-invasive. Is timing a Secure routine Secure debug?**
Invasive changes defined behaviour (halt, memory writes, injecting instructions). Measuring a Secure routine's duration is **Non-secure** (Non-secure software could measure it too); changing it is Secure.

**Q2. Walk through a cold connect.**
DP → power-up requests → BASE/BASEPTR → top-level ROM PIDR lookup → (if unknown) ROM walk, identify parts, topology detection with ITCTRL.IME, reset, save description keyed by ROM PIDR.

**Q3. Why disable functionality instead of blocking registers?**
Tools must always discover and identify parts and read AUTHSTATUS to explain why something is off; the memory map stays identical between development and production parts (`§D2.2`).

**Q4. Software lock vs. authentication vs. claim tags vs. OS lock?**
People / rogue code / cooperating agents / OS save-restore. Claim tags cannot guard the lock because claim access is itself behind the lock.

**Q5. Why is ATVALID the ATB topology-detection signal?**
Intermediate non-programmable bridges pass nothing while ATVALID is low.

**Q6. Why can't the channel interface count instructions?**
Rising-edge events, no back-pressure, merging across CDC.

**Q7. Explain the formatter frame and its overhead.**
7 data bytes + 8 mixed bytes + 1 aux byte; aux restores data bit 0 or times the ID switch. ~6% + 1 byte per ID change; ID repeated ~every 10 frames; sync `0x7FFFFFFF`.

**Q8. When can you bypass the formatter?**
Single source ID, TRACECTL pin supported by TPA. Lose 0x7D trigger and ID-switch alignment; end with `1` then zeros.

**Q9. How does a flush work end to end?**
AFVALID upstream; every link/source drains pre-request data; AFREADY back; 0x7B responses in formatted stream; formatter pads (null ID or `1`+zeros).

**Q10. How would you verify authentication completely?**
Spec intent (6 equations + AUTHSTATUS) → hazards (wrong AND/OR, unsynchronised enables, register vs. function gating, Secure leakage via shared trace) → stimulus (64 combos, toggles mid-activity) → checkers (equation model, no-leak scoreboard, SVA, formal on enable cone) → coverage (combos × components, transitions).

**Q11. How do you prove trace is non-invasive?**
A/B runs: trace off vs. all sources on with max back-pressure; compare retire logs and final state; only cycle differences allowed.

**Q12. Scoreboard for multi-source trace into an ETR?**
Per-ATID expected streams from source monitors → formatter model → read ETR buffer (DAP or backdoor) → de-format with golden decoder → compare per source; handle wrap, overflow, flush padding, lost start.

**Q13. ROM table properties to check?**
Preamble/CLASS, DEVARCH 0x0AF7 for class 0x9, contiguous entries, end marker, not-present skipped, OFFSET≠0, each component once, no cycles, POWERID vs. UPF, top-level PIDR changes when config changes. Generate expectations from the integration DB.

**Q14. Verify cross-trigger across 8 cores?**
Random channel maps, simultaneous/back-to-back triggers, random clock ratios, cores in WFI/off. Channel model, latency bound, skid measurement, no-reflection and 4-phase SVA; coverage trigger × channel × target × gate.

**Q15. Debugger hangs after a cluster enters low power. Debug it.**
Was power requested for its POWERID? Is the off slave clamped (PREADY=1, PSLVERR=1)? Does an AP/bridge wait on a stopped clock? Add timeout monitor and UPF-aware access test.

**Q16. ETR trace decodes to garbage after a few KB.**
Wrap lost the start → hunt frame sync and next ID repeat; check 16-bit sync alignment, aux handling, ETR pointer/wrap flag, duplicate ATIDs, source protocol syncs (ETM A-sync).

**Q17. New ETM revision in a subsystem — which IDs change?**
ETM PIDR2.REVISION or PIDR3.REVAND must change; subsystem ROM revision may not; top-level PIDR must change if the set of components/connections changes.

**Q18. Topology detection ran and now functional trace is broken. Why?**
Integration mode is invasive; the spec requires a system reset after detection even after IME is cleared.

**Q19. What is DEVAFF for?**
Matching unique values (e.g. MPIDR) in PE, CTI and ETM so tools associate them without invasive detection. Test pairs against the integration DB.

**Q20. What does a timestamp of 0 mean?**
UNKNOWN: source disabled or reset. Correlation checkers must not treat it as time zero.

---

## 14. Common mistakes

- Calling PSLVERR a generic error — in CoreSight APB it means "component not available".
- Saying authentication hides registers — it disables functionality.
- Treating ROM offsets as absolute or unsigned.
- Forgetting that an entry marked not-present is **not** the end of the table.
- Using `disable iff (stall)` on ATB checks instead of a stability property (see [08](08-sva-assertions.md), [10](10-ready-valid-handshake-assertions.md)).
- Assuming channels can count fast events.
- Forgetting the system reset after integration mode.
- Quoting `PIDR4.SIZE` for component size — deprecated in v3.0.

---

## 15. 60-second interview pitch

> "CoreSight gives every debug component the same 4KB ID frame so a debugger can discover the whole SoC from one ROM-table pointer. APB programs components, ATB moves trace from sources like the ETM through funnels to sinks like the ETR or TPIU, the formatter keeps source IDs when trace leaves the chip, CTIs and the CTM share halt and trigger events, and DBGEN/NIDEN/SPIDEN/SPNIDEN gate what's allowed without hiding registers. When I verify it I start from the spec rule, look for the hazards — CDC, power-down, arbitration, security leakage — drive constrained-random back-pressure, flushes and auth toggles, and check with golden models: an auth equation model against AUTHSTATUS, a formatter decoder against sink memory, a ROM walker against the integration database, plus an A/B run that proves trace is non-invasive."

---

## 16. Self-check

- [ ] Draw the system map from memory: DAP, Debug APB, ROM, clusters, CTI/CTM, funnel → ETF → replicator → ETR/TPIU.
- [ ] Recite the CIDR preamble and the CLASS values 0x1 / 0x9 / 0xF.
- [ ] Decode ROMENTRY `0x00003017` at base `0x8000_0000`.
- [ ] Write the six authentication equations and compute AUTHSTATUS for DBGEN=1, NIDEN=1, SPNIDEN=1.
- [ ] Decode the spec formatter example by hand; explain the aux bit for an ID byte.
- [ ] List special trace IDs 0x00, 0x7B, 0x7D, 0x7F.
- [ ] Explain why ATVALID is used for topology detection.
- [ ] Explain why PSLVERR must be returned by a powered-down component.
- [ ] Give the four-beat verification answer for cross-triggering.
- [ ] Tell one bug story from Section 12 in STAR format.
