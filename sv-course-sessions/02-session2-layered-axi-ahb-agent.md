# Session 2 — Layered UVM Agent for AXI and AHB

Source: `Session2_pdf_UVM_Agent_Deep_dive.pdf`, page 20: *"Can you implement a layered agent for AXI and AHB protocol agent?"*
Code: [`code/session2_layered_uvm_agent/session2_layered_axi_ahb_agent.sv`](code/session2_layered_uvm_agent/session2_layered_axi_ahb_agent.sv)
Output: [`logs/s2_layered_agent_AXI.log`](logs/s2_layered_agent_AXI.log), [`logs/s2_layered_agent_AHB.log`](logs/s2_layered_agent_AHB.log)

## Architecture

```
                       +-------------------------------+
    test / vseq ---->  | upper sequencer  (bus_txn)    |   no driver on this layer
                       +---------------+---------------+
                                       | get_next_item / item_done (pull)
            +--------------------------+---------------------------+
   bus2axi_seq on axi_sequencer                         bus2ahb_seq on ahb_sequencer
   splits at 4KB, sets AWLEN/AWSIZE                     splits at 1KB, INCR4/8/16/SINGLE
            |                                                      |
      axi_driver --> AXI pins                               ahb_driver --> AHB pins
      axi_monitor --> axi2bus ----+                +---- ahb2bus <-- ahb_monitor
                                  v                v
                         bus-level analysis port --> scoreboard / coverage
```

- **Upper layer:** the protocol-independent `bus_txn` (kind, addr, data[]) runs on a sequencer with **no driver**.
- **Downward translation:** a layering sequence runs on the *lower* sequencer. In a loop it:
  1. calls `up_sqr.get_next_item(b)` to pull from the upper layer,
  2. splits `b` into protocol items with `start_item` / `finish_item`,
  3. calls `up_sqr.item_done()`.
- **Upward translation:** `axi2bus` / `ahb2bus` subscribers rebuild `bus_txn` from monitored items, so the scoreboard and coverage stay protocol-independent.
- **Selecting the protocol:** a `config_db` knob (`+PROTO=AXI|AHB`) picks the protocol. The test only ever talks to `env.bus_sqr`.

## What the run shows (same test, two protocols)

| Request: write 20 words at `0xFF8` | AXI | AHB |
|---|---|---|
| Boundary rule | must not cross **4KB** | must not cross **1KB** |
| Bursts produced | `AxLEN=1` @0xFF8, `AxLEN=17` @0x1000 | SINGLE, SINGLE, INCR16 @0x1000, SINGLE, SINGLE |
| Result | PASS: 44 words, 0 UVM errors | PASS: 44 words, 0 UVM errors |

## Interview talking points
- **Why layering?**
  - Write sequences once, and reuse them when a port changes from AHB to AXI.
  - Protocol rules (4K/1K boundaries, burst encoding) live in exactly **one** place.
  - Keeps the stimulus at the transaction level.
- **Order matters:** the upper `item_done()` must come *after* the last lower `finish_item()`. Otherwise the upper sequence runs ahead of what is actually on the bus, and response routing breaks.
- **Alternatives:**
  - A translator `uvm_component` with TLM ports.
  - `uvm_reg` adapters (`reg2bus` / `bus2reg`), the same idea used for register access.
  - Layering through `p_sequencer`.
  - A virtual sequence that just picks a protocol sequence. That is *not* layering, because it has no translation.
- **Responses / reads:** for reads, put the read data into the upper item (or send a response with `put_response`) **before** `item_done`.
- **Merging on the way up:** a real `axi2bus` merges split bursts back into one `bus_txn`, using ID or address continuity. The demo keeps it 1:1 for clarity.
- **AHB specifics:** NONSEQ then SEQ beats, pipelined address and data phases, a fixed INCR4/8/16 must not cross 1KB, and an undefined-length INCR is also legal.
- **AXI specifics:** AxLEN = beats − 1 (up to 256 for INCR in AXI4), AxSIZE = log2(bytes per beat), and a burst must not cross 4KB.

## Running it
Needs Verilator ≥ 5.030 and the Accellera UVM library (`UVM_HOME`). See [`run_all.sh`](run_all.sh). The compile takes ~3–4 minutes because the whole UVM library is built.
