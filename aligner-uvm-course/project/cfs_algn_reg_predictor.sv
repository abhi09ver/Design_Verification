///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_reg_predictor.sv
// Author:      Cristian Florin Slav
// Date:        2024-07-29
// Description: Custom register predcitor to filter out accesses with errors
//              and to verify that the response of the access is the expected
//              one.
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_ALGN_REG_PREDICTOR_SV
  `define CFS_ALGN_REG_PREDICTOR_SV

  class cfs_algn_reg_predictor#(type BUSTYPE = uvm_sequence_item) extends uvm_reg_predictor#(.BUSTYPE(BUSTYPE));
    
    //Pointer to the environment configuration
    cfs_algn_env_config env_config;

    `uvm_component_param_utils(cfs_algn_reg_predictor#(BUSTYPE))
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction
    
    //Get the value of a register field from a full register value
    protected virtual function uvm_reg_data_t get_reg_field_value(uvm_reg_field reg_field, uvm_reg_data_t reg_data);
      uvm_reg_data_t mask = (('h1 << reg_field.get_n_bits()) - 1) << reg_field.get_lsb_pos();
      
      return (mask & reg_data) >> reg_field.get_lsb_pos();
    endfunction
    
    //Getter for the expected reponse
    protected virtual function cfs_algn_reg_access_status_info get_exp_response(uvm_reg_bus_op operation);
      uvm_reg register;
      
      register = map.get_reg_by_offset(operation.addr, (operation.kind == UVM_READ));
      
      //Any access to a location on which no register is mapped must reutrn an APB error
      if(register == null) begin
        return cfs_algn_reg_access_status_info::new_instance(UVM_NOT_OK, "Access to a location on which no register is mapped");
      end
      
      //Any write access to a full read-only register must return an APB error.
      if(operation.kind == UVM_WRITE) begin
        uvm_reg_map_info info = map.get_reg_map_info(register);
        
        if(info.rights == "RO") begin
          return cfs_algn_reg_access_status_info::new_instance(UVM_NOT_OK, "Write access to a full read-only register");
        end
      end
      
      //Any read access from a full write-only register must return an APB error.
      if(operation.kind == UVM_READ) begin
        uvm_reg_map_info info = map.get_reg_map_info(register);
        
        if(info.rights == "WO") begin
          return cfs_algn_reg_access_status_info::new_instance(UVM_NOT_OK, "Read access from a full write-only register");
        end
      end
      
      //Illegal write access to the Control register.
      if(operation.kind == UVM_WRITE) begin
        cfs_algn_reg_ctrl ctrl;
        
        if($cast(ctrl, register)) begin
          uvm_reg_data_t size_value   = get_reg_field_value(ctrl.SIZE,   operation.data);
          uvm_reg_data_t offset_value = get_reg_field_value(ctrl.OFFSET, operation.data);
          
          //Trying to write value 0 in this field will return an APB error.
          if(size_value == 0) begin
            return cfs_algn_reg_access_status_info::new_instance(UVM_NOT_OK, "Write value 0 to CTRL.SIZE");
          end
          
          //Trying to write an illegal combination of (SIZE, OFFSET) will return an APB error.
          if(((env_config.get_algn_data_width() / 8) + offset_value) % size_value != 0) begin
            return cfs_algn_reg_access_status_info::new_instance(UVM_NOT_OK, $sformatf("Illegal access to CTRL -> OFFSET: %0d, SIZE: %0d, aligner data width: %0d",
                                                                offset_value, size_value, env_config.get_algn_data_width()));
          end
          
          //Trying to write an illegal combination: SIZE + OFFSET > aligner data width
          if(offset_value + size_value > (env_config.get_algn_data_width() / 8)) begin
            return cfs_algn_reg_access_status_info::new_instance(UVM_NOT_OK, $sformatf("Illegal access to CTRL -> OFFSET (%0d) + SIZE (%0d)  > aligner data width: %0d",
                                                                offset_value, size_value, env_config.get_algn_data_width()));
          end
        end
      end
      
      return cfs_algn_reg_access_status_info::new_instance(UVM_IS_OK, "All OK");
    endfunction
    
    virtual function void write(BUSTYPE tr);
      uvm_reg_bus_op operation;
      
      adapter.bus2reg(tr, operation);
      
      if(env_config.get_has_checks()) begin
        cfs_algn_reg_access_status_info exp_response = get_exp_response(operation);
        
        if(exp_response.status != operation.status) begin
          `uvm_error("DUT_ERROR", $sformatf("Mismatch detected for the bus operation status - expected: %0s, received: %0s on access: %0s - reason: %0s",
                                            exp_response.status.name(), operation.status.name(), tr.convert2string(), exp_response.info))
        end
      end
      
      if(operation.status == UVM_IS_OK) begin
        super.write(tr);
      end
      
    endfunction
    
  endclass

`endif
