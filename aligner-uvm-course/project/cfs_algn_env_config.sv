///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_env_config.sv
// Author:      Cristian Florin Slav
// Date:        2024-07-29
// Description: Configuration class for the Aligner environment
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_ALGN_ENV_CONFIG_SV
  `define CFS_ALGN_ENV_CONFIG_SV

  class cfs_algn_env_config extends uvm_component;
    
    //Virtual interface
    protected cfs_algn_vif vif;
    
    //Switch to enable checks
    local bit has_checks;
    
    //Switch to enable coverage
    local bit has_coverage;
    
    //Aligner data width
    local int unsigned algn_data_width;
    
    //Threshold, in clock cycles, in which to wait for the RX response
    local int unsigned exp_rx_response_threshold;
    
    //Threshold, in clock cycles, in which to wait for the TX item
    local int unsigned exp_tx_item_threshold;
    
    //Threshold, in clock cycles, in which to wait for the interrupt request
    local int unsigned exp_irq_threshold;
    
    `uvm_component_utils(cfs_algn_env_config)
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      has_checks                = 1;
      has_coverage              = 1;
      algn_data_width           = 8;
      exp_rx_response_threshold = 10;
      exp_tx_item_threshold     = 10;
      exp_irq_threshold         = 10;
    endfunction
    
    //Getter for the has_checks control field
    virtual function bit get_has_checks();
      return has_checks;
    endfunction
        
    //Setter for the has_checks control field
    virtual function void set_has_checks(bit value);
      has_checks = value;
    endfunction
    
    //Getter for the has_coverage control field
    virtual function bit get_has_coverage();
      return has_coverage;
    endfunction
        
    //Setter for the has_coverage control field
    virtual function void set_has_coverage(bit value);
      has_coverage = value;
    endfunction
    
    //Getter for the algn_data_width control field
    virtual function int unsigned get_algn_data_width();
      return algn_data_width;
    endfunction
    
    //setter for the algn_data_width control field
    virtual function void set_algn_data_width(int unsigned value);
      //The minimum legal value for this field is 8.
      if(value < 8) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("The minimum legal value for algn_data_width is 8 but user tried to set it to %0d", value))
      end
      
      //The value must be a power of 2
      if($countones(value) != 1) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Thevalue for algn_data_width must be a power of 2 but user tried to set it to %0d", value))
      end
      
      algn_data_width = value;
    endfunction
    
    //Getter for the virtual interface
    virtual function cfs_algn_vif get_vif();
      return vif;
    endfunction
    
    //Setter for the virtual interface
    virtual function void set_vif(cfs_algn_vif value);
      if(vif == null) begin
        vif = value;
      end
      else begin
        `uvm_fatal("ALGORITHM_ISSUE", "Trying to set the virtual interface more than once")
      end
    endfunction
    
    //Getter for exp_rx_response_threshold
    virtual function int unsigned get_exp_rx_response_threshold();
      return exp_rx_response_threshold;
    endfunction
    
    //Setter for exp_rx_response_threshold
    virtual function void set_exp_rx_response_threshold(int unsigned value);
      exp_rx_response_threshold = value;
    endfunction
    
    //Getter for exp_tx_item_threshold
    virtual function int unsigned get_exp_tx_item_threshold();
      return exp_tx_item_threshold;
    endfunction
    
    //Setter for exp_tx_item_threshold
    virtual function void set_exp_tx_item_threshold(int unsigned value);
      exp_tx_item_threshold = value;
    endfunction
    
    //Getter for exp_irq_threshold
    virtual function int unsigned get_exp_irq_threshold();
      return exp_irq_threshold;
    endfunction
    
    //Setter for exp_irq_threshold
    virtual function void set_exp_irq_threshold(int unsigned value);
      exp_irq_threshold = value;
    endfunction
    
    virtual function void start_of_simulation_phase(uvm_phase phase);
      super.start_of_simulation_phase(phase);
      
      if(get_vif() == null) begin
        `uvm_fatal("ALGORITHM_ISSUE", "The Aligner virtual interface is not configured at \"Start of simulation\" phase")
      end
      else begin
        `uvm_info("CONFIG", "The Aligner virtual interface is configured at \"Start of simulation\" phase", UVM_FULL)
      end
    endfunction
    
  endclass

`endif