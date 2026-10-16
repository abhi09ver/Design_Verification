///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_clr_cnt_drop.sv
// Author:      Cristian Florin Slav
// Date:        2024-08-05
// Description: Callback register field for clearing STATUS.CNT_DROP counter.
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_ALGN_CLR_CNT_DROP_SV
  `define CFS_ALGN_CLR_CNT_DROP_SV

  class cfs_algn_clr_cnt_drop extends uvm_reg_cbs; 
    
    //Pointer to CNT_DROP register field
    uvm_reg_field cnt_drop;

    `uvm_object_utils(cfs_algn_clr_cnt_drop)
    
    function new(string name = "");
      super.new(name);
    endfunction
    
    virtual function void post_predict(
      input uvm_reg_field fld, 
      input uvm_reg_data_t previous, 
      inout uvm_reg_data_t value, 
      input uvm_predict_e kind, 
      input uvm_path_e path, 
      input uvm_reg_map map);
      
      if(kind == UVM_PREDICT_WRITE) begin
        if(value == 1) begin
          void'(cnt_drop.predict(0));
          
          value = 0;
          
          `uvm_info("CNT_DROP", $sformatf("Clearing %0s", cnt_drop.get_full_name()), UVM_HIGH)
        end
      end
      
    endfunction
    
  endclass

`endif