# Interview gauntlet

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 11 · the interview

## Interview gauntlet

Fourteen senior-level questions across the seven domains your prep framework scores. Answer out loud first, then open the model answer and the cross-questions. Rate yourself honestly. Your scores stay in this browser only.

UVM & SVRTLC/C++coveragedebugmethodologyadvanced

### 11.1How answers are judged

| Score | What it sounds like |
| --- | --- |
| 3–4 | Correct definitions. "A scoreboard compares expected and actual." No trade-offs, no example. |
| 6–7 | Correct, with a concrete example from your own work and one trade-off. Handles the first cross-question. |
| 9–10 | Starts from the spec and the risk, names the failure mode, gives numbers ("255 errors and a 50% enable bit"), and volunteers what they'd do differently. Survives three cross-questions. |

### 11.3Your readiness

**Ready for the live version?**Say `mock interview` in chat. I'll run your interview-prep framework: a short level check, then 12–15 questions across all seven domains with cross-questions on every answer, and a scored report per domain.

### 11.2 Fourteen questions

#### [UVM & SystemVerilog] Explain the factory. Name three ways an override silently doesn't apply.

**Model answer:** The factory maps a requested type (or instance path) to the type actually constructed, as long as objects are made with type_id::create. Silent failures: (1) the object is built with new(), bypassing the factory; (2) the override is registered after the create() it should affect (e.g. in build_phase after super.build_phase created the child); (3) the override targets a different specialization of a parameterized class, or uses by-name overrides on a param class, which registers without a name. Debug with factory.print() and print_topology().

**Cross-questions:**

- Type vs instance override precedence?
- Why do your agents use instance overrides in the constructor?

#### [UVM & SystemVerilog] Two sequences run on one sequencer. How is the order decided, and how do you make a 3-item register update atomic?

**Model answer:** The sequencer arbitrates per item using its arbitration mode (default FIFO by request time; also weighted, random, strict-priority). Items from both sequences interleave. For atomic multi-item operations, lock() (waits its turn, then exclusive) or grab() (jumps the queue). Release with unlock/ungrab. In test_reg_access, the random and unmapped register sequences interleave on the APB sequencer exactly like this.

**Cross-questions:**

- What happens to a locked sequencer if the sequence is killed at reset?
- Priority on start_item vs sequence priority?

#### [RTL design] cfs_rx_ctrl drives md_rx_ready = (push_valid & push_ready) | md_rx_err. What does that imply, and how would you test it?

**Model answer:** Illegal transfers are accepted immediately even when the RX FIFO is full: errors bypass back-pressure, so CNT_DROP can increment while ready would otherwise be low. That's reasonable (nothing is stored) but worth confirming with the designer. Test: fill the RX FIFO with a stalled TX side, then send illegal items, and check they complete in one cycle with err while legal ones stall. Cover 'err while FIFO full'.

**Cross-questions:**

- Is ready combinationally dependent on valid here? Why does that matter for the master?
- What if a master waits for ready before asserting valid?

#### [RTL design] This core has md_rx_clk, pclk and md_tx_clk. What would you verify and why does the current TB miss it?

**Model answer:** Every crossing: async FIFOs (Gray pointers, full/empty in the right domain), single-bit syncs (2 flops), multi-bit values (CNT_DROP goes through a single-flop cfs_synch, not safe), and reset/clear crossing domains (clr_cnt_dop as async reset). The TB ties all clocks to one clk, so metastability and ratio effects never happen. Add independent clocks with random ratios and jitter, run a CDC lint tool, and assert gray-code properties on pointers.

**Cross-questions:**

- Why is a multi-bit counter unsafe through 2-flop syncs?
- How do you model metastability in simulation?

#### [C/C++ infrastructure] How would you replace the SV alignment algorithm with a C++ golden model?

**Model answer:** Write the algorithm as a pure C++ function (bytes in, CTRL in, TX words out) and unit-test it with GoogleTest on host. Export it via a thin C wrapper and import it with import "DPI-C" function. Pass open arrays (byte unsigned data[]) and use svSize/svGetArrElemPtr. Keep the SV threads for timing; call DPI only for the data transform. Keep it 'pure' (no static state) where possible for safety; if it must keep state, key it by instance handle. Build it into the sim's shared library in the Makefile.

**Cross-questions:**

- What does 'context' on a DPI import allow, and what does it cost?
- Who owns memory returned from C?

#### [C/C++ infrastructure] Write the legality rule in C++ and describe a self-check for it.

**Model answer:** bool legal(unsigned W, unsigned off, unsigned size){ unsigned B = W/8; return size != 0 && (B+off) % size == 0 && off+size <= B; }  Self-check: loop over all W in {8,16,32,64}, every off < B and size ≤ 2B−1, and compare against a table derived by hand from the spec. Also compare against the SV model through DPI for the same inputs. Exhaustive is cheap because the space is tiny, so prefer it over random.

**Cross-questions:**

- Where would you put this so SV constraints, model and coverage all use one definition?

#### [Coverage] 100% functional and code coverage, yet a bug escaped. Give three concrete reasons from this testbench.

**Model answer:** (1) Bins sampled at the wrong time: MD coverage samples the transfer at start, so the OKAY/length=1 bins fill even with no such transfer. (2) The plan had no bin: nothing covers IRQ source × enable, so MAX_DROP-to-pin was never required. (3) Stimulus guards: test_random never reconfigures under traffic, and the unmapped test never uses paddr[1:0]≠0. Coverage proves reached states, not checked behaviour.

**Cross-questions:**

- How would you tie each covergroup bin to a check?
- What would you put in a coverage review with designers?

#### [Coverage] illegal_bins vs ignore_bins vs an assertion: when do you use each?

**Model answer:** ignore_bins: unreachable or out-of-scope combinations, documented. illegal_bins: values the DUT must never produce. They error at runtime, so they're effectively checkers and belong only where the coverage sample is DUT output. Assertions: temporal protocol rules, checked every cycle, also usable in formal. Don't use illegal_bins on stimulus you chose not to generate: that encodes TB assumptions as DUT rules.

**Cross-questions:**

- How do you justify an ignore bin in sign-off?

#### [Debug] Nightly regression: 2% of 5000 seeds fail. Walk me through triage.

**Model answer:** Bucket by first-error signature (ID + message stripped of numbers). Biggest bucket first. Reproduce one seed with waves and higher verbosity. Classify: DUT_ERROR vs ALGORITHM_ISSUE vs SVA. Check the spec to decide who's wrong. Correlate failing seeds with config (e.g. IRQEN.MAX_DROP in this TB). Shrink to a minimal directed test, file the bug, then add the test and a covergroup so it can't regress. Track the fail rate per bucket to confirm the fix.

**Cross-questions:**

- Two buckets share a root cause. How would you notice?
- A failure won't reproduce with the same seed. Why?

#### [Debug] Scoreboard says TX data mismatch: expected {11,22} got {22,11}. Where do you look, in order?

**Model answer:** Is CTRL.SIZE > 1 (byte order only matters then)? Check the mirror's CTRL vs the DUT at that time (a predictor or callback bug would make the model align differently). Find the RX items that fed this TX word in the model log. Check the monitor's byte extraction (shift by (offset+i)*8). Then the waveform: md_rx_data lanes vs md_tx_data lanes at those times. Decide with the datasheet figure which order is correct.

**Cross-questions:**

- How would you prove it's not the monitor?

#### [Methodology] How do you decide verification of this block is done?

**Model answer:** Every vplan row has a check and a coverage item that's been hit (or a reviewed waiver). Code coverage reviewed: no unexplained holes. Regression stable over N nights with seed variety, bug-discovery rate flattened. Assertions all have covers hit. Spec ambiguities closed with designers. Known-escape analysis done (what classes of bug could this TB never see? e.g. CDC here). Sign-off is a review, not a number.

**Cross-questions:**

- Which of those does this TB fail today?

#### [Methodology] Simulation or formal for this aligner? Split the work.

**Model answer:** Formal: legality → md_rx_err, APB error rules, protocol stability, IRQ edge/W1C logic, CNT_DROP saturation. Small state spaces, so exhaustive proofs beat random. Simulation: the data path through FIFOs and the alignment transform (deep state, long sequences), end-to-end with a model. Use formal cover to show reachability of corner cases like 'FIFO full and illegal item same cycle'.

**Cross-questions:**

- What assumptions would your formal setup need on the MD RX interface?

#### [Advanced scenarios] Reuse this env at SoC level with four aligner instances behind an interconnect.

**Model answer:** Make the env instantiable per aligner (config object per instance, unique vif names via config_db paths or a vif array). APB agents go passive (the CPU drives), the predictor keeps working off monitors, and the reg block becomes a sub-block of the SoC block with an offset per instance. MD agents become passive monitors on internal interfaces, hooked up via bind. White-box probes (algn_if) must move to bind as well. The model and scoreboard reuse unchanged. Add an SoC-level vseq that coordinates instances.

**Cross-questions:**

- What breaks first if you just copy-paste the env four times?

#### [Advanced scenarios] Regression takes 10 hours. Cut it to 2 without losing quality.

**Model answer:** Measure first: per-test sim time and coverage contribution. Drop or shorten tests with no unique coverage (coverage-driven test ranking). Turn off waves and high verbosity by default. Reduce UVM_INFO string formatting in hot paths (the monitors log every item at UVM_LOW). Compile once and run many (separate compile and elaborate). Parallelize across a farm. Use coverage-guided seed selection. Move exhaustive small spaces (legality, APB errors) to formal.

**Cross-questions:**

- How do you prove the shorter regression didn't lose bug-finding power?

