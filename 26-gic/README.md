# 26-gic · Arm GIC study kit

Everything for GICv3 / GICv4 interview prep in one place. Start with the cheat sheet: [`../26-gic-interrupt-controller.md`](../26-gic-interrupt-controller.md).

```
26-gic/
├── pages/
│   ├── gic-from-zero.html      # beginner: stories, diagrams, quizzes, "be the CPU" simulator
│   └── gic-field-guide.html    # senior: architecture, ITS, v4, DV strategy, bug list, Q&A
└── code/
    ├── python/
    │   ├── gic_ref_model.py         # readable GICv3 reference model
    │   └── test_gic_ref_model.py    # 21 tests = 21 interview corner cases
    └── sv/
        ├── gic_cpu_if_sva.sv        # bindable SVA checker + cover properties
        └── gic_scoreboard_pkg.sv    # UVM scoreboard that accepts the set of legal IAR answers
```

## Suggested order

1. `pages/gic-from-zero.html` if any basics feel shaky (≈45 min).
2. `../26-gic-interrupt-controller.md` for a fast revision pass (≈15 min).
3. `pages/gic-field-guide.html` for depth and the Q&A (≈1–2 h).
4. Read `code/python/test_gic_ref_model.py`: each test is a corner case you can talk through.
5. Skim `code/sv/` so you can describe concrete assertions and a scoreboard strategy.

## Running the code

```bash
# Python reference model (Python 3.8+, no dependencies)
cd 26-gic/code/python
python3 -m unittest -v

# SystemVerilog: checked to elaborate cleanly with slang. Compile with your simulator, e.g.
#   vcs -sverilog -ntb_opts uvm gic_scoreboard_pkg.sv gic_cpu_if_sva.sv
#   xrun -uvm gic_scoreboard_pkg.sv gic_cpu_if_sva.sv
```

The Python model applies every change instantly, so it predicts one legal outcome; the SV scoreboard shows how to widen that into the set the spec allows. Signal names in the SV checker are generic; map them to your RTL in the `bind`.

Source: Arm IHI 0069H.b, *GIC Architecture Specification* (GICv3.3 / GICv4.2). Check exact field encodings in Chapter 12 before quoting bit positions.
