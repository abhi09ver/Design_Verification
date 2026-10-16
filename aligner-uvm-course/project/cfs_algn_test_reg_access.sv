///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_test_reg_access.sv
// Author:      Cristian Florin Slav
// Date:        2023-06-27
// Description: Register access test. It targets APB accesses to the registers
//              of the Aligner module.
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_ALGN_TEST_REG_ACCESS_SV
  `define CFS_ALGN_TEST_REG_ACCESS_SV

  class cfs_algn_test_reg_access extends cfs_algn_test_base;
    
    //Number of register accesses
    protected int unsigned num_reg_accesses;

    //Number of unmapped accesses
    protected int unsigned num_unmapped_accesses;

    `uvm_component_utils(cfs_algn_test_reg_access)
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      num_reg_accesses      = 100;
      num_unmapped_accesses = 100;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
      
      phase.raise_objection(this, "TEST_DONE");
      
      #(100ns);
      
      fork
        begin
          cfs_algn_virtual_sequence_reg_access_random seq = cfs_algn_virtual_sequence_reg_access_random::type_id::create("seq");
          
          void'(seq.randomize() with {
            num_accesses == num_reg_accesses;
          });
          
          seq.start(env.virtual_sequencer);
        end
        begin
          cfs_algn_virtual_sequence_reg_access_unmapped seq = cfs_algn_virtual_sequence_reg_access_unmapped::type_id::create("seq");
          
          void'(seq.randomize() with {
            num_accesses == num_unmapped_accesses;
          });
          
          seq.start(env.virtual_sequencer);
        end
      join
      
      #(100ns);
      
      phase.drop_objection(this, "TEST_DONE"); 
    endtask
    
  endclass

`endif