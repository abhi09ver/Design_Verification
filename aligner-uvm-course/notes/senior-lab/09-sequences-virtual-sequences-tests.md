# Sequences, virtual sequences & tests

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 9 · driving the scenario

## Sequences, virtual sequences & tests

Tests choose *what* happens; sequences decide *how*. Your test tree is shallow on purpose. The interesting parts are the virtual sequences that coordinate APB, MD RX and MD TX, and the habits around randomization and objections.

layeringvirtual sequencer handlesfactory overridesrandomize() hygieneobjections & drain

### 9.1Test tree and sequence layering

*[Diagram: Test inheritance and sequence layering. Open the HTML page to see it.]*

### 9.2Code walkthrough: coordinating RX and TX

```systemverilog
// cfs_algn_virtual_sequence_slow_pace::body
fork
  begin // RX: a legal item at least CTRL.SIZE bytes long
    int unsigned ctrl_size = p_sequencer.model.reg_block.CTRL.SIZE.get_mirrored_value();
    `uvm_do_on_with(rx_sequence, p_sequencer.md_rx_sequencer, {
      ((algn_data_width / 8) + item.offset) % item.data.size() == 0;
      (item.data.size() + item.offset) <= (algn_data_width / 8);
      item.data.size() >= ctrl_size;
    })
  end
  begin // TX: answer each chunk; ERR on the last one
    do begin
      cfs_md_item_mon item_mon;
      p_sequencer.md_tx_sequencer.pending_items.get(item_mon);
      num_tx_items = rx_sequence.item.data.size() / CTRL.SIZE;
      `uvm_do_on_with(tx_sequence, p_sequencer.md_tx_sequencer, {
        num_tx_items == 1 -> item.response == CFS_MD_OKAY;
        num_tx_items > 1 && tx_item_idx <  num_tx_items-1 -> item.response == CFS_MD_OKAY;
        num_tx_items > 1 && tx_item_idx == num_tx_items-1 -> item.response == CFS_MD_ERR;
      })
      tx_item_idx++;
    end while(tx_item_idx < num_tx_items);
  end
join
```

1. **Constraints read the mirror.** The stimulus depends on current DUT config (CTRL.SIZE), via the model handle on the virtual sequencer. The mirror is shared state between checking and stimulus.
2. **Parallel branches on different sequencers.** RX and TX run concurrently; the TX branch blocks on the same `pending_items` FIFO the forever responder uses. Running both would race, so this vseq must replace the default responder, not run beside it.
3. **Implication constraints** (`->`) give one randomize call per-position behaviour. They're cleaner than branching around three different `uvm_do` calls.

### 9.3Hidden concepts and findings

Finding · void'(randomize()) everywhere

Every test and vseq ignores the randomize result. Your `rx_err` constraint is unsatisfiable at `ALGN_DATA_WIDTH = 8`: with 1 byte, size 1 at offset 0 is the only possible item, and it's legal. Randomize fails silently, the item keeps its constructor defaults (empty data, so size 0), and the run reports `SIZE_EQ_0_A`, a misleading error far from the cause. Always `` if(!x.randomize()) `uvm_fatal(…) ``.

Objections: one owner

Only the test raises and drops, around the whole scenario. The `#(500ns)` before the drop is a hand-made drain time. `phase.phase_done.set_drain_time(this, 500ns)` says the same thing in a way reviewers recognise.

Reconfig guarded by is\_empty()

`if(env.model.is_empty())` skips CTRL changes while data is in flight. It keeps tests passing, and it also means "reconfigure under traffic" is never tested. Know which of your guards are hiding scenarios.

Soft defaults, hard limits

Items use `soft` for preferences (delays ≤5, size 1) and the sequence turns some off with `constraint_mode(0)` in its constructor. Hard constraints encode physics (fits on the bus). Tests override soft ones freely with inline `with`.

Two sequences, one sequencer

`test_reg_access` forks the random-register and unmapped-address vseqs on the same APB sequencer. The default FIFO arbitration interleaves them per item. Use `lock()`/`grab()` when a multi-item operation must not be interrupted.

Unmapped test skips misaligned mapped addresses

`get_reg_addresses()` excludes all 4 byte addresses of each register (0x01, 0x02, 0x03…). The register test uses aligned ones. So the datasheet's "paddr[1:0] ignored" rule is never exercised: a guaranteed escape (Module 10, bug 8).

### 9.4Interview drill

**Q: Q1 "Virtual sequence vs virtual sequencer: do you need the sequencer?"**

A virtual sequence only needs handles to the real sequencers. It can get them from a virtual sequencer (`p_sequencer`, as here), from fields set by the test, or from config\_db. The virtual sequencer is convenient and lets vseqs nest, but it's an extra component. Some teams pass handles directly and start vseqs with `start(null)`. Either is fine; consistency matters.

Cross-questions

- `p_sequencer` vs `m_sequencer`? (`m_sequencer` is the base handle that's always set. `` `uvm_declare_p_sequencer `` adds a typed, cast copy for access to custom fields.)
- How do you stop a forever sequence at end of test? (Let the phase end kill it, or `sequencer.stop_sequences()`; never hold an objection inside it.)

**Q: Q2 "How would you write a test that reconfigures CTRL while traffic is in flight?"**

First get the spec to define it: does a new CTRL apply to bytes already in the buffer? Then the model must snapshot CTRL per TX word (or per RX item, as the spec says). The test forks MD traffic and a delayed CTRL write without the `is_empty()` guard, and coverage records "CTRL changed with N bytes buffered". Without the spec decision this test can only find disagreements, not bugs.

### 9.5Lab

- Replace every `void'(seq.randomize())` in your tests with a checked version. Rebuild with `` `define CFS_ALGN_TEST_ALGN_DATA_WIDTH 8 `` and run `rx_err` to see the clean fatal.
- Write `cfs_algn_test_backpressure`: the slow responder from Module 4 plus 200 RX items. Read STATUS often and look for RX\_LVL = 8.
- Replace `#(500ns)` with `set_drain_time` and confirm the same behaviour.
