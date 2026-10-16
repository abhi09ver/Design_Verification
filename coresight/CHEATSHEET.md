# CoreSight last-hour cheat sheet

One page. Spec: ARM IHI 0029E (CoreSight v3.0). Full notes: [`../26-coresight-debug-and-trace.md`](../26-coresight-debug-and-trace.md).

## The pitch (say it in 60 s)

Same **4KB ID frame** in every component → tools **identify** it. **ROM table** → debugger **discovers** everything from one base pointer. **APB** programs. **ATB** carries trace **source → link → sink**. **Channels** carry cross-triggers between **CTIs** via the **CTM**. **Auth signals** gate functionality (not register visibility). One **64-bit timestamp** correlates streams. All of it works while SoC regions are **powered off**.

Three layers: **Visible** (Part B, mandatory: programmers' model) · **Reusable** (Part C, optional: APB/ATB/event/channel/auth/timestamp wires) · **System** (Part D: domains, ROM, formatter, connectors, compliance).

## Magic numbers

| Value | Meaning |
|---|---|
| `0xC5ACCE55` | LAR key (software lock, deprecated in v3.0; external debugger bypasses it) |
| CIDR0–3 = `0x0D, 0x?0, 0x05, 0xB1` | Preamble; `?` = CLASS |
| CLASS `0x1` / `0x9` / `0xF` | ROM table / CoreSight component / CoreLink-PrimeCell |
| JEP106 ARM = cont `0x4`, id `0x3B` | DEVARCH.ARCHITECT = `0x23B` |
| ARCHID `0x0AF7` · `0x1A14` · `0x4A13` · `0x0A63` | ROM table · CTI · ETM · STM |
| `0xF00–0xFFC` | Management registers (ITCTRL, CLAIM, DEVAFF, LAR/LSR, AUTHSTATUS, DEVARCH, DEVID, DEVTYPE, PIDR, CIDR) |
| 4KB, 2ⁿ blocks, max 64MB | Component size rules; `PIDR4.SIZE` deprecated |
| 960 / 512 / 256 | Max ROM entries: class 0x1 / 0x9 32-bit / 0x9 64-bit |
| `addr = ROM_base + (OFFSET << 12)` | OFFSET signed; OFFSET=0 with PRESENT set is illegal |
| Trace IDs `0x01–0x6F` | Usable. `0x00` null · `0x7B` flush resp · `0x7D` trigger · `0x7F` never · rest reserved |
| `0x7FFFFFFF` / `0x7FFF` | Full frame sync / halfword sync (continuous mode only) |
| 16-byte frame, ~6% overhead | Repeat source ID about every 10 frames |
| ≥ 4 channels | Recommended per channel interface |
| `TSVALUEB[63:0]`, 0 = UNKNOWN | Timestamp; resolution ≥ 10% of fastest PE clock |
| POWERID[8:4] | 32 power domains per ROM table |

## Authentication equations

```
NS invasive     = DBGEN
NS non-invasive = DBGEN | NIDEN
S  invasive     = DBGEN & SPIDEN
S  non-invasive = (SPIDEN | SPNIDEN) & (DBGEN | NIDEN)
H  invasive     = DBGEN & HIDEN
H  non-invasive = (HIDEN | HNIDEN) & (DBGEN | NIDEN)
```
Generators: invasive ⇒ non-invasive; Secure needs its Non-secure pair; Secure and hypervisor are independent.
AUTHSTATUS fields (2 bits each, `0b10` disabled / `0b11` enabled): HNID[11:10] HID[9:8] SNID[7:6] SID[5:4] NSNID[3:2] NSID[1:0].
Measuring a Secure routine's time = **Non-secure** debug; changing it = Secure debug.

## Formatter frame

Even bytes 0,2,…,14: bit0 = F. F=1 → bits[7:1] = new ID; F=0 → data with bit0 stored in aux. Odd bytes: data. Byte 15 = aux bits for bytes 0,2,…,14.
For an ID byte, aux=0 → next byte uses new ID; aux=1 → next byte still old ID. ID in byte 14 → takes effect next frame.
Modes: **bypass** (one source, needs TRACECTL, no 0x7D) · **normal** (TRACECTL marks trigger/idle) · **continuous** (no TRACECTL, halfword syncs).
End of trace: bypass = one `1` bit then zeros; normal/continuous = finish frame with ID `0x00`.

## ROM tables

| | Class 0x1 | Class 0x9 |
|---|---|---|
| Entry | OFFSET[31:12] · POWERID[8:4] · PIDVALID[2] · FORMAT[1]=1 · PRESENT[0] | same, PRESENT[1:0], optional 64-bit |
| End | entry `0x0`, or slot at 0xEFC | PRESENT=`00`, or slot at 0x7FC |
| Skip, keep scanning | PRESENT=0, entry ≠ 0 | PRESENT=`10` |
| Power/reset | separate power requestor | DBGPCR/PSR, SYSPCR/PSR, DBGRSTRR/AR, SYSRSTRR/AR |

Forbidden: duplicate references, cycles, pointing back up. Top-level PIDR identifies the SoC; it must change when the component set changes.

## Interfaces in one line each

- **APB:** PSLVERRDBG only means "not available" (powered down). Clamps when off: PREADY=1, PSLVERR=1, PRDATA=0 → error, never hang.
- **ATB:** VALID/READY, ATBYTES, ATID; payload stable while stalled; flush AFVALID/AFREADY *(beyond spec)*.
- **Event:** rising edge, at most one per 2 clocks, no back-pressure → events merge across CDC.
- **Channel:** bidirectional; async uses 4-phase ACK; never reflect input to own output; subset connects from channel 0.
- **Topology detection:** ITCTRL.IME=1, drive master (ATVALID / CHOUT[0]), check slaves, clear IME, then **reset the system**.

## Four-beat answer to "how would you verify X"

1. **Spec intent:** quote the rule.
2. **Design hazard:** CDC, power, arbitration, reset, security.
3. **Stimulus:** constrained random + directed corners.
4. **Checker + coverage:** reference model, SVA, formal; what closes the loop.

## Must-have checks

ID frame and RAZ/WI · ROM walk vs integration database · all 64 auth combos and toggling mid-trace · trace scoreboard per ATID through formatter and back · flush completion with idle/busy/disabled ports · CTI mapping, skid, no reflection, ack · access to every power domain while off → error, no hang · trace on vs off gives identical architectural results · timestamp monotonic with bounded skew.

## Bugs to tell as stories

APB hang on a powered-down slave · AUTHSTATUS disagrees with gating · aux-bit off-by-one at an ID switch · flush deadlock in funnel/replicator · duplicate ATID · trigger lost crossing into a slow DVFS clock · core re-halts after restart (no CTIINTACK) · POWERID swapped between clusters · timestamp reset mid-run · integration mode left on.
