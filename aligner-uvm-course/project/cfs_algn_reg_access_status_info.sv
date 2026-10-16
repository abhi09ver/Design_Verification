///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_reg_access_status_info.sv
// Author:      Cristian Florin Slav
// Date:        2024-07-29
// Description: Pair of status-info describing a register access response
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_ALGN_REG_ACCESS_STATUS_INFO_SV
  `define CFS_ALGN_REG_ACCESS_STATUS_INFO_SV

  class cfs_algn_reg_access_status_info;
  
    const uvm_status_e status;
    
    const string info;
    
    function new(uvm_status_e status, string info);
      this.status = status;
      this.info   = info;
    endfunction
    
    static function cfs_algn_reg_access_status_info new_instance(uvm_status_e status, string info);
      cfs_algn_reg_access_status_info result = new(status, info);
      
      return result;
    endfunction
    
  endclass

`endif