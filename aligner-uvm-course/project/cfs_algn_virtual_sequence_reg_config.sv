///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_virtual_sequence_reg_config.sv
// Author:      Cristian Florin Slav
// Date:        2025-02-04
// Description: Virtual sequence which writes random value in configuration 
//              registers.
///////////////////////////////////////////////////////////////////////////////

`ifndef CFS_ALGN_VIRTUAL_SEQUENCE_REG_CONFIG_SV
  `define CFS_ALGN_VIRTUAL_SEQUENCE_REG_CONFIG_SV
  
  class cfs_algn_virtual_sequence_reg_config extends cfs_algn_virtual_sequence_base;
    
    `uvm_object_utils(cfs_algn_virtual_sequence_reg_config)
    
    function new(string name = "");
      super.new(name);
    endfunction
    
    virtual task body();
      uvm_reg registers[$];
      uvm_status_e status;
      
      p_sequencer.model.reg_block.get_registers(registers);
      
      for(int reg_idx = registers.size() - 1; reg_idx >= 0; reg_idx--) begin
        if(!(registers[reg_idx].get_rights() inside {"RW", "WO"})) begin
          registers.delete(reg_idx);
        end
      end
      
      registers.shuffle();
      
      foreach(registers[reg_idx]) begin
        void'(registers[reg_idx].randomize());
        
        registers[reg_idx].update(status);
      end 
    endtask
    
  endclass

`endif