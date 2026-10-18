// ------------------------------------------------------------------
// Test layer: blueprint overrides. The base classes stay untouched.
// ------------------------------------------------------------------
// Loads/stores in a 64-byte window around x0, so loads read back stores.
class yarp_tr_mem extends yarp_transaction;
  function new(); w_ld = 30; w_st = 30; endfunction
  constraint c_win { (opcode inside {I_TYPE_0, S_TYPE}) -> (rs1 == 0 && imm12 inside {[0:63]}); }
endclass

// ALU only (R + I type): checks the datapath at full rate
class yarp_tr_alu extends yarp_transaction;
  function new(); w_ld = 0; w_st = 0; w_br = 0; w_jal = 0; w_jalr = 0; w_lui = 5; w_auipc = 5; endfunction
endclass

// Back-to-back: ready with zero delay. Hits the pipeline-like corner
// where a handshake completes every cycle.
class yarp_tr_b2b extends yarp_tr_mem;
  // same name as the base constraint -> REPLACES it (constraint override)
  constraint legal_delay { instr_mem_ready_delay == 0; data_mem_ready_delay == 0; }
endclass

// Long stalls on both interfaces: checks the payload-stable rules
class yarp_tr_stall extends yarp_tr_mem;
  constraint legal_delay { instr_mem_ready_delay inside {[8:16]}; data_mem_ready_delay inside {[8:16]}; }
endclass
