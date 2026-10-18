// ------------------------------------------------------------------
// Blueprint overrides (test layer) - no change to the base classes
// ------------------------------------------------------------------
// Balanced opcode mix: without 'dist', randomize() is uniform over ALL
// solutions, so J/U-type (many free fields) swamp R/I/S/B.
class yarp_tr_balanced extends yarp_transaction;
  // Portable fix: pick the opcode class FIRST with a weighted randcase,
  // then freeze it so the solver only fills in the fields for that opcode.
  // (Same intent as 'solve opcode before ...'; works on every simulator.)
  function void pre_randomize();
    opcode.rand_mode(1);
    randcase
      20: opcode = R_TYPE;   20: opcode = I_TYPE_1;  15: opcode = I_TYPE_0;
      15: opcode = S_TYPE;   10: opcode = B_TYPE;     5: opcode = U_TYPE_0;
       5: opcode = U_TYPE_1;  5: opcode = J_TYPE;     5: opcode = I_TYPE_2;
    endcase
    opcode.rand_mode(0);
  endfunction
endclass

// Memory-heavy: loads/stores use x0 as base and a 64B window so loads
// actually read back earlier stores (otherwise the read path is never checked)
class yarp_tr_mem extends yarp_tr_balanced;
  constraint c_mem_win { (opcode inside {I_TYPE_0, S_TYPE}) -> (rs1 == 0 && imm12 inside {[0:63]}); }
endclass
