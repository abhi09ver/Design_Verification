///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_virtual_sequence_base.sv
// Author:      Cristian Florin Slav
// Date:        2024-12-30
// Description: Base class for the virtual sequences.
///////////////////////////////////////////////////////////////////////////////

`ifndef CFS_ALGN_VIRTUAL_SEQUENCE_BASE_SV
  `define CFS_ALGN_VIRTUAL_SEQUENCE_BASE_SV
 
  class cfs_algn_virtual_sequence_base extends uvm_sequence;
    
    `uvm_declare_p_sequencer(cfs_algn_virtual_sequencer)

    `uvm_object_utils(cfs_algn_virtual_sequence_base)
    
    function new(string name = "");
      super.new(name);
    endfunction
    
  endclass

`endif
    