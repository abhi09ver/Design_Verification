///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_virtual_sequence_rx_err.sv
// Description: Virtual sequence which sends one MD RX transaction that is
//              always illegal (the aligner must answer with CFS_MD_ERR).
///////////////////////////////////////////////////////////////////////////////

`ifndef CFS_ALGN_VIRTUAL_SEQUENCE_RX_ERR_SV
  `define CFS_ALGN_VIRTUAL_SEQUENCE_RX_ERR_SV

  class cfs_algn_virtual_sequence_rx_err extends cfs_algn_virtual_sequence_rx;

    //Width of the MD RX data bus, in bytes
    local int unsigned data_width_in_bytes;

    //The inner sequence's item_hard constraint already enforces
    //size > 0 and offset + size <= data_width_in_bytes, so the only way
    //to make the transfer illegal is to break the alignment rule
    //checked by the model: (data_width_in_bytes + offset) % size != 0
    constraint rx_err {
      ((data_width_in_bytes + seq.item.offset) % seq.item.data.size()) != 0;
    }

    `uvm_object_utils(cfs_algn_virtual_sequence_rx_err)

    function new(string name = "");
      super.new(name);
    endfunction

    function void pre_randomize();
      super.pre_randomize();

      data_width_in_bytes = p_sequencer.md_rx_sequencer.get_data_width() / 8;
    endfunction

  endclass

`endif
