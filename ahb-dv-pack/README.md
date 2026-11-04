# AMBA AHB DV Interview Pack

One stop for AHB design-verification interview prep: twelve one-page cards (PDF, PNG, HTML) and a searchable text cheatsheet. Each card covers concepts, cycle-by-cycle timing tables, encodings, traps, SVA/coverage snippets and rapid-fire interview Q&A.

Made for the **AMBA AHB PROTOCOL BATCH 2** playlist by ALL ABOUT VLSI (12 videos).

## Start here

| If you have… | Open |
|---|---|
| 2 minutes | The "Remember:" line at the end of each section in [`AHB_CHEATSHEET.md`](AHB_CHEATSHEET.md) |
| 20 minutes | [`ahb-dv-cards.pdf`](ahb-dv-cards.pdf): all 12 cards, one per page |
| A browser | [`cards/index.html`](cards/index.html): the same cards as HTML |
| A phone | [`images/`](images/): PNG of each card (1860 px wide) |
| A whiteboard question | Cards 04 (burst address math) and 05 (HREADY / wait states): the most-asked ones |

## Contents

```
ahb-dv-pack/
├── AHB_CHEATSHEET.md   text version of all 12 cards (searchable on GitHub)
├── ahb-dv-cards.pdf    12 pages
├── cards/              standalone HTML cards + index
└── images/             PNG of each card
```

| # | Card | Must-know |
|---|---|---|
| 01 | [AMBA family & AHB architecture](images/01-amba-ahb-architecture.png) | AMBA timeline, APB vs AHB vs AXI, why muxes not tristates |
| 02 | [AHB signal map](images/02-ahb-signals.png) | Every signal with driver/phase, HSIZE, HPROT, byte lanes, HREADY vs HREADYOUT |
| 03 | [Transfers, pipelining & HTRANS](images/03-transfers-htrans.png) | Address/data overlap, IDLE/BUSY/NONSEQ/SEQ, legal sequences, stability SVA |
| 04 | [Bursts & address calculation](images/04-bursts-address-math.png) | HBURST, INCR vs WRAP math, 1 KB rule, early termination, burst constraints |
| 05 | [Wait states & HREADY](images/05-wait-states-hready.png) | Why slaves qualify with HREADY, what freezes, default slave, no-hang check |
| 06 | [Slave responses: HRESP](images/06-slave-responses-hresp.png) | Two-cycle ERROR/RETRY/SPLIT and why, cancelling the next transfer |
| 07 | [Arbitration & bus handover](images/07-arbitration-handover.png) | HBUSREQ/HGRANT/HMASTER, ownership = HGRANT & HREADY, locked transfers |
| 08 | [SPLIT & RETRY](images/08-split-retry.png) | 8-step SPLIT handshake, HSPLIT, dummy master, RETRY starvation |
| 09 | [Decoder, muxes & multi-layer](images/09-decoder-muxes-multilayer.png) | Live vs HREADY-registered selects, default slave, bus matrix |
| 10 | [AHB-Lite & AHB5](images/10-ahb-lite-ahb5.png) | What Lite removes, what AHB5 adds (HNONSEC, HEXCL/HEXOKAY, 7-bit HPROT) |
| 11 | [AHB-to-APB bridge](images/11-ahb-to-apb-bridge.png) | 8-state reference FSM, posted writes, PREADY/PSLVERR mapping |
| 12 | [Verifying AHB in UVM](images/12-verifying-ahb-uvm.png) | Two-thread pipelined driver, phase-pairing monitor, coverage plan, test list |

## Notes on sources

- YouTube exposed only the playlist's name and video count, not the video titles or what is said in them. The 12 cards follow the usual order for an AHB course and are written from the AMBA AHB specifications (AMBA 2 AHB, AHB-Lite, AHB5). They are **not mapped to the actual videos**; add the video titles to remap them.
- SVA, constraint and driver snippets are reference code, checked by reading only. They have **not been compiled or simulated**.
- Related material in this repo: [17 – Bus protocols](../17-bus-protocols-axi-ahb-pcie.md) (AHB-Lite two-cycle error, HMASTLOCK), [Session 2 – layered AXI/AHB agent](../sv-course-sessions/02-session2-layered-axi-ahb-agent.md), [Session 3 – APB testbench](../sv-course-sessions/03-session3-apb-dual-port-testbench.md).

Source: [AMBA AHB PROTOCOL BATCH 2 playlist](https://www.youtube.com/playlist?list=PLqPfWwayuBvNX_IQPBHGJn8YFkvI86lr9)
