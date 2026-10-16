# Code: SMMU teaching model, tests and SystemVerilog

Everything here runs on free tools. Nothing needs a commercial simulator except the UVM package (and even that was checked with the open-source `slang` compiler).

```
code/
├── smmu_model/            Python reference model (no dependencies)
│   ├── addressing.py      VA slicing per granule, block sizes, nested walk cost
│   ├── pagetable.py       4KB/48-bit VMSAv8-64 table builder + walker, faults as values
│   ├── tlb.py             Tagged LRU TLB (StreamWorld, VMID, ASID) + TLBI scopes
│   ├── queue.py           Circular queue with wrap bit and overflow flag
│   └── smmu.py            STE/CD lookup, config caches, S1/S2/nested, stall/terminate,
│                          command queue (CFGI/TLBI/SYNC/RESUME), event queue, GBPA
├── tests/test_smmu_model.py   24 self-checking interview scenarios (stdlib unittest)
├── demo.py                Guided tour with printed output
└── sv/
    ├── smmu_queue_ptr.sv      Queue pointer RTL + SVA (+ injectable bug)
    ├── tb_smmu_queue_ptr.sv   Random test with reference model (Verilator)
    └── smmu_dv_pkg.sv         UVM: txn, invalidation-aware scoreboard, coverage
```

## Run

```bash
cd 26-mmu-smmu/code

# Python model: tests and demo (Python 3.8+)
python3 -m unittest discover -s tests -v
python3 demo.py

# SystemVerilog queue + SVA on Verilator 5.x
verilator --binary --assert --timing -Wno-fatal \
  --top-module tb_smmu_queue_ptr sv/tb_smmu_queue_ptr.sv sv/smmu_queue_ptr.sv
./obj_dir/Vtb_smmu_queue_ptr                       # → TEST PASSED

# Prove the checker can fail: inject the "no wrap bit" bug
verilator --binary --assert --timing -Wno-fatal +define+BUG_NO_WRAP_BIT \
  --top-module tb_smmu_queue_ptr sv/tb_smmu_queue_ptr.sv sv/smmu_queue_ptr.sv
./obj_dir/Vtb_smmu_queue_ptr                       # → assertion failure

# UVM package: compile with your simulator, e.g.
#   vcs -sverilog -ntb_opts uvm sv/smmu_dv_pkg.sv
#   xrun -uvm sv/smmu_dv_pkg.sv
```

## What each test proves (interview question → test)

| Question | Test |
|---|---|
| Which VA bits index each level? | `test_4k_48bit_slices`, `test_64k_48bit_has_three_levels` |
| Cost of a cold nested walk? | `test_nested_walk_cost`, `test_nested_walk` (counts 24 real reads) |
| Fault types and where they come from | `test_faults`, `test_external_abort_on_walk` |
| Queue full vs empty with a wrap bit | `test_wrap_bit_full_empty`, `test_overflow_flag_episode` |
| ASID / StreamWorld isolation in the TLB | `test_asid_isolation_and_global` |
| STE.Config modes, bad SID/STE | `test_config_modes` |
| SSID range, S1DSS, missing CD | `test_substreams` |
| Why CFGI + SYNC after editing STE / CD | `test_ste_change_needs_cfgi`, `test_cd_change_needs_cfgi_cd` |
| Stale TLB after unmap; TLBI + SYNC fixes it | `test_tlb_hit_and_stale_entry` |
| TLB hit must still check permissions | `test_tlb_hit_checks_all_permissions` |
| S2 fault while fetching an S1 table | `test_s2_fault_on_s1_table_fetch` |
| VMID-wide invalidation | `test_s2_only_vmid_invalidate` |
| Stall → RESUME | `test_stall_then_resume` |
| CD.R=0 hides terminated faults | `test_terminate_record_bit` |
| Event queue overflow | `test_event_queue_overflow` |
| Illegal command stops the queue | `test_illegal_command_stops_queue` |
| SMMUEN=0 and GBPA | `test_smmuen_off_gbpa` |

## Model limits (say these if asked)

* Encodings are names, not bit-accurate STE/CD/command formats.
* Only the 4KB granule, 48-bit table format is walked; other granules are covered by `addressing.py`.
* Sequential model: every command completes immediately, so `CMD_SYNC` is trivially satisfied. Real hardware overlaps walks and invalidations; that is what `smmu_scoreboard` in `smmu_dv_pkg.sv` handles.
* No ATS/PRI, Secure/Realm, GPC or attribute transformation.
