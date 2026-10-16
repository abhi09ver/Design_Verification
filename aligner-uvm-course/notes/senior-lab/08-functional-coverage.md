# Functional coverage

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 8 · proving you tested it

## Functional coverage

Checks find bugs; coverage proves the checks ran on the scenarios that matter. Your env has four coverage collectors. This module measures how honest they are: one double-counts, one can never exceed about 15%, and most of the Module 0 plan has none.

covergroups & crossesignore vs illegal binsreachabilityclosure strategy

### 8.1Coverage map against the verification plan

| Plan item (Module 0) | Collected by | Status |
| --- | --- | --- |
| APB direction, response, wait states, addr/data bits | `cfs_apb_coverage` | covered |
| MD offset × size, length, gaps, data bits | `cfs_md_coverage` (×2) | covered, double-sampled |
| Alignment split cases | `cfs_algn_coverage.cover_split` | ≤ 15.5% reachable |
| Alignment without split (merges) | nothing | gap |
| IRQ events × enables, W1C while condition holds | nothing | gap |
| CNT\_DROP saturation, CLR, CLR-vs-err race | nothing | gap |
| FIFO full / empty, RX back-pressure | nothing | gap |
| Register access type × register (incl. illegal CTRL) | nothing (RAL built with `UVM_NO_COVERAGE`) | gap |
| Reset during traffic | `cover_reset` in APB/MD coverage | covered |

### 8.2Reachability of `cover_split.all`

The cross is ctrl\_offset × ctrl\_size × md\_offset × md\_size × num\_bytes\_needed. After its `ignore_bins`, 7 CTRL settings × 16 (md\_offset, md\_size) pairs × 3 values of `num_bytes_needed` remain: 336 bins. A split needs `num_bytes_needed < md_size`, `num_bytes_needed ≤ ctrl_size` and `md_offset + md_size ≤ 4`. Each cell below shows how many of its 3 bins can pass those necessary conditions.

### 8.3Code walkthrough: two coverage bugs

```systemverilog
// cfs_algn_coverage: only CTRL combos are filtered
all : cross ctrl_offset, ctrl_size, md_offset, md_size, num_bytes_needed {
  ignore_bins ignore_ctrl = (binsof(ctrl_offset) intersect {0} && binsof(ctrl_size) intersect {3}) ||
                            (binsof(ctrl_offset) intersect {1} && binsof(ctrl_size) intersect {2, 3, 4}) ||
                            (binsof(ctrl_offset) intersect {2} && binsof(ctrl_size) intersect {3, 4}) ||
                            (binsof(ctrl_offset) intersect {3} && binsof(ctrl_size) intersect {2, 3, 4});
  //TODO: other combinations should be ignored from this cross
}

// cfs_md_coverage: sampled for EVERY write from the monitor
virtual function void write_item(cfs_md_item_mon item);
  cover_item.sample(item);       // called at START and at END
  // at START: response = default (CFS_MD_OKAY), length = 1
endfunction
```

1. **The TODO is the bug.** Without filtering impossible (md, needed) combinations, the "all" cross can't reach 100%. Engineers then ignore a red number, which hides the real holes inside it.
2. **Double sampling lies.** The monitor writes each transfer twice. At the start write, `response` is still the default `CFS_MD_OKAY` and `length` is 1. So `length_eq_1` and the OKAY bin are hit by *every* transfer, even if no 1-cycle OKAY transfer ever happened.

```systemverilog
// fixes
virtual function void write_item(cfs_md_item_mon item);
  if(item.is_active()) return;   // sample completed transfers only
  cover_item.sample(item);
  ...
endfunction

all : cross ctrl_offset, ctrl_size, md_offset, md_size, num_bytes_needed {
  ignore_bins ignore_ctrl = ...;  // as before
  ignore_bins unreachable = all with (num_bytes_needed >= md_size  ||
                                      num_bytes_needed > ctrl_size ||
                                      md_offset + md_size > 4);
}
```

### 8.4Hidden concepts

illegal\_bins are checkers

Hitting an `illegal_bins` raises a run-time error. Use them only for things the DUT must never do, never for "the TB doesn't generate this". `illegal_bins length_lt_1` in MD coverage is a checker hiding in the coverage model.

ignore\_bins with `with`

Expression filters (`all with (…)`) state the rule once instead of enumerating bins, and they scale with parameters. They're the fix for both the TODO and the hard-coded 32-bit bins.

per\_instance + set\_inst\_name

Two MD agents share one covergroup type. Without `per_instance = 1` the tool merges RX and TX coverage into one number, and you can't tell which side is missing.

Sample the right event

Coverage must be sampled at the moment the behaviour is complete and checked: end of transfer, after compare, after IRQ observed. Sampling at the start covers stimulus *intent*, not verified behaviour.

Transition bins

`(CFS_APB_READ, CFS_APB_WRITE => CFS_APB_READ, CFS_APB_WRITE)` covers all 4 direction sequences. Write-after-read hazards live there, and value bins can't see them.

Closure loop

Run a regression, then merge, then review holes with the plan, then for each hole decide: unreachable (ignore with justification), missing stimulus (constraint or directed sequence) or missing check. Coverage percentage is a conversation, not a target.

### 8.5Interview drill

**Q: Q1 "You have 100% functional and code coverage, and a bug escaped to silicon. How?"**

Coverage proves stimulus reached a state, not that a checker looked at it. Typical escapes: (1) the plan missed the feature, so there's no bin; (2) the bins were sampled at the wrong time or double-counted (your MD coverage); (3) crosses missing the dangerous combination (same-cycle CLR and err); (4) checks disabled or too weak; (5) the bug is in an interaction across features each covered alone. Fix the process: tie each bin to a check, review the plan with designers, and add cross and temporal coverage for interactions.

**Q: Q2 "Code coverage vs functional coverage: which do you sign off on?"**

Both, for different questions. Code coverage asks "did we execute the RTL?" and finds dead code and untested branches, but knows nothing about the spec. Functional coverage asks "did we exercise the spec's scenarios?" but only what you thought to write. A line never hit is a real hole. A functional bin never hit is a hole or a wrong bin. Sign-off needs both reviewed, with documented waivers.

### 8.6Lab

- Apply both fixes, then run 10 seeds of `cfs_algn_test_random` and compare `cover_split.all` before and after (set the coverage report verbosity to see it).
- Write `cover_irq`: event type × IRQEN bit × "cleared while condition persists", sampled from the model.
- Add a CNT\_DROP covergroup with bins 0, [1:254], 255 and a transition 254 => 255. Run your `rx_err` test to hit it.
