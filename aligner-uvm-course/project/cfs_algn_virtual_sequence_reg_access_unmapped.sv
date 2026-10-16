///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_virtual_sequence_reg_access_unmapped.sv
// Author:      Cristian Florin Slav
// Date:        2025-01-29
// Description: Virtual sequence to access the unmapped locations randomly.
///////////////////////////////////////////////////////////////////////////////

`ifndef CFS_ALGN_VIRTUAL_SEQUENCE_REG_ACCESS_UNMAPPED_SV
  `define CFS_ALGN_VIRTUAL_SEQUENCE_REG_ACCESS_UNMAPPED_SV
 
  class cfs_algn_virtual_sequence_reg_access_unmapped extends cfs_algn_virtual_sequence_base;

    //Number of accesses
    rand int unsigned num_accesses;
    
    constraint num_accesses_default {
      soft num_accesses inside {[150:200]};
    }
    
    `uvm_object_utils(cfs_algn_virtual_sequence_reg_access_unmapped)
    
    function new(string name = "");
      super.new(name);
    endfunction
    
    virtual task body();
      uvm_reg_addr_t addresses[$];
      
      get_reg_addresses(addresses);
      
      for(int unsigned access_idx = 0; access_idx < num_accesses; access_idx++) begin
        cfs_apb_sequence_simple seq;
        
        `uvm_do_on_with(seq, p_sequencer.apb_sequencer, {
          !(item.addr inside {addresses});
        });
        
        wait_random_time();
      end
      
    endtask
    
    //Function to get the addresses of all the registers
    protected virtual function void get_reg_addresses(ref uvm_reg_addr_t addresses[$]);
      uvm_reg registers[$];
      p_sequencer.model.reg_block.get_registers(registers);
      
      foreach(registers[reg_idx]) begin
        for(int byte_idx = 0; byte_idx < registers[reg_idx].get_n_bits() / 8; byte_idx++) begin
          addresses.push_back(registers[reg_idx].get_address() + byte_idx);
        end
      end
    endfunction
    
    //Task to wait some random number of clock cycles
    protected virtual task wait_random_time();
      cfs_algn_vif vif = p_sequencer.model.env_config.get_vif();
      int unsigned delay = $urandom_range(20, 0);
      
      repeat(delay) begin
        @(posedge vif.clk);
      end
    endtask
    
  endclass

`endif