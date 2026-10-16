# Cache Coherence — One-Stop Interview Kit

Everything for cache organization, coherence and memory consistency interviews (Senior CPU/GPU DV), from beginner to senior level.

| What | File | Use it for |
|---|---|---|
| Main notes (Challenge 32) | [`../32-cache-coherence-and-memory-consistency.md`](../32-cache-coherence-and-memory-consistency.md) | Full write-up: concepts, races, litmus tests, verification plan, follow-ups, pitch |
| Cheat sheet | [`CHEATSHEET.md`](CHEATSHEET.md) | 10-minute revision right before the interview |
| Beginner guide (interactive) | [`html/cache-from-zero.html`](html/cache-from-zero.html) | 14 levels with analogies, clickable cache and MSI simulators, self-checks |
| Senior field guide (interactive) | [`html/cache-coherence-field-guide.html`](html/cache-coherence-field-guide.html) | Infographics, MESI simulator, bug catalog, 25 interview Q&A |
| Cache model | [`python/cache_sim.py`](python/cache_sim.py) | Address split, set-associative LRU, write-back vs write-through, 3 C's, AMAT |
| MESI model + mini testbench | [`python/mesi_model.py`](python/mesi_model.py) | SWMR monitor, scoreboard, CoRR, drain compare, coverage table, bug injection |
| Litmus explorer | [`python/litmus.py`](python/litmus.py) | Exhaustive SC vs x86-TSO outcomes for SB, MP, LB, IRIW, CoRR, fences |
| SV scoreboard + coverage | [`sv/coherence_pkg.sv`](sv/coherence_pkg.sv) | Reusable class-based scoreboard (legal-value window, CoRR) and covergroup |
| SVA checkers | [`sv/coherence_assertions.sv`](sv/coherence_assertions.sv) | SWMR / single-owner, legal L1 transitions, miss completion, ack accounting |

## Viewing the HTML guides

Download or clone the repo and open the `.html` files in any browser (GitHub shows HTML as source, not as a page). They are self-contained; fonts load from Google Fonts when online and fall back to system fonts offline.

## Running the code

Python 3.9+ standard library only.

```bash
cd cache-coherence/python

python3 cache_sim.py                    # demos: address split, locality, conflicts, write policy, AMAT
python3 cache_sim.py --selftest         # 60k random ops vs a golden model

python3 litmus.py                       # all litmus tests, SC vs TSO
python3 litmus.py SB MP                 # selected tests

python3 mesi_model.py                   # 4 cores, 4 hot lines, 20 seeds, coverage table
python3 mesi_model.py --msi             # MSI instead of MESI
python3 mesi_model.py --trace 20        # print bus transactions
python3 mesi_model.py --bug upgrade_no_inv   # watch the SWMR monitor fire
python3 mesi_model.py --bug stale_e          # SWMR: E granted while others share
python3 mesi_model.py --bug no_flush         # scoreboard: owner doesn't supply dirty data
python3 mesi_model.py --bug silent_m_evict   # scoreboard: dirty eviction dropped
```

Expected results (verified):

```
cache_sim self-test: PASS
SB r1=0 r2=0      SC forbidden   TSO allowed
mesi_model clean: all seeds PASS, 17/17 legal (state x event) cells covered
--bug upgrade_no_inv -> SWMR violated        --bug stale_e        -> SWMR violated
--bug no_flush       -> Scoreboard mismatch  --bug silent_m_evict -> Scoreboard mismatch
```

SystemVerilog files are syntax- and elaboration-checked with [slang](https://github.com/MikePopoloski/slang) (`pip install pyslang`). They have not been run on a commercial simulator; signal names in the bind example are placeholders for your RTL.

```bash
python3 -c "from pyslang import driver; d=driver.Driver(); d.addStandardArgs(); \
d.parseCommandLine('slang sv/coherence_pkg.sv sv/coherence_assertions.sv'); \
d.processOptions(); d.parseAllSources(); d.reportCompilation(d.createCompilation(), False)"
```

## Suggested study order

1. `html/cache-from-zero.html` (Levels 1–14), running `cache_sim.py` alongside Levels 2–5.
2. `32-cache-coherence-and-memory-consistency.md` sections 3–6.
3. `mesi_model.py` with every `--bug`, then read `sv/` to see the same checkers in SystemVerilog.
4. `litmus.py`, then section 5 of the notes.
5. `html/cache-coherence-field-guide.html` Q&A out loud, then `CHEATSHEET.md` on interview day.

Reference: Nagarajan, Sorin, Hill, Wood, *A Primer on Memory Consistency and Cache Coherence*, 2nd ed., 2020 — [free PDF](https://pages.cs.wisc.edu/~markhill/papers/primer2020_2nd_edition.pdf).
