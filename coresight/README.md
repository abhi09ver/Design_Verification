# CoreSight Debug & Trace: one-stop interview kit

Everything for ARM CoreSight (debug and trace) prep in one folder, from "what is a chip" to senior CPU DV interview answers.
Source spec: **ARM IHI 0029E, CoreSight Architecture Specification v3.0** (not included here; download it from ARM's developer site).

## Study order

| Step | File | Time | Use it for |
|---|---|---|---|
| 1 | [`coresight-from-zero.html`](coresight-from-zero.html) | 60–90 min | Beginner course: 16 lessons with everyday analogies, 4 mini games (ROM map, ATB belt, freeze game, auth keys), 10-question quiz |
| 2 | [`coresight-field-guide.html`](coresight-field-guide.html) | 2–3 h | Senior infographic guide: system map, register frame, ROM rules, interfaces, auth simulator, formatter frame decoder, CTI, power, verification plan, bug catalog, 20 Q&A |
| 3 | [`../34-coresight-debug-and-trace.md`](../34-coresight-debug-and-trace.md) | 1–2 h | Full written notes in this repo's challenge format (renders on GitHub), with follow-up questions and the 60-second pitch |
| 4 | [`code/coresight_tools.py`](code/coresight_tools.py) | 30 min | Python golden models: ID decode, ROM entry decode and walk, auth equations + AUTHSTATUS, formatter decode/encode |
| 5 | [`code/coresight_sva.sv`](code/coresight_sva.sv) | 30 min | Bind-able SVA checkers: ATB, async channel handshake, APB power-down, auth/AUTHSTATUS, CTI no-reflection |
| 6 | [`CHEATSHEET.md`](CHEATSHEET.md) | 10 min | One page for the last hour before the interview |

## Opening the HTML guides

GitHub shows `.html` files as source, not as pages. To view them:

```bash
git clone -b coresight-debug-trace-prep https://github.com/abhi09ver/Design_Verification.git
cd Design_Verification/coresight
# open in your browser
xdg-open coresight-from-zero.html      # Linux
open coresight-from-zero.html          # macOS
start coresight-from-zero.html         # Windows
```

Both pages are single self-contained files (no build step). They load Google Fonts when online and fall back to system fonts offline. The beginner page links to the field guide by relative path, so keep them in the same folder.

Live hosted copies (private to the repo owner's Claude account):
[CoreSight from Zero](https://claude.ai/artifact/PzpoaWSWBcDPdxuBmuThLT) · [CoreSight Field Guide](https://claude.ai/artifact/D3Jp8Z5nrShrrnk4DHGmkt)

## Running the code

```bash
# Python 3.8+, no dependencies. Runs all self-tests, including spec Table D4-2.
python3 code/coresight_tools.py
```

```python
from coresight_tools import decode_frame, auth_permissions, decode_romentry

decode_frame(bytes.fromhex("07AAA6A72BA854525254 07CAC6C7C81C".replace(" ", "")))
auth_permissions(dbgen=1, niden=1, spiden=0, spniden=1)   # permissions + AUTHSTATUS
decode_romentry(0x00003017, rom_base=0x8000_0000, rom_class=0x1)
```

`code/coresight_sva.sv` contains standalone modules meant to be attached with `bind` (example binds at the bottom of the file). It elaborates cleanly in slang with no diagnostics; adapt signal names and the `MAX_*` latency parameters to your RTL.

## What's spec, what's not

Section references like `§C5.4` point into IHI 0029E. Items tagged **beyond spec** (ATB flush signals, CTI register names, TMC ETF/ETR modes, ADI power signals) come from neighbouring ARM specifications; confirm them against your IP's TRM.
