///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_env.sv
// Author:      Cristian Florin Slav
// Date:        2023-06-27
// Description: Environment class.
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_ALGN_ENV_SV
  `define CFS_ALGN_ENV_SV

  class cfs_algn_env#(int unsigned ALGN_DATA_WIDTH = 32) extends uvm_env implements uvm_ext_reset_handler;
    
    //Environment configuration class
    cfs_algn_env_config env_config;
    
    //APB agent handler
    cfs_apb_agent apb_agent;

    //MD RX agent handler
    cfs_md_agent_master#(ALGN_DATA_WIDTH) md_rx_agent;

    //MD TX agent handler
    cfs_md_agent_slave#(ALGN_DATA_WIDTH) md_tx_agent;
    
    //Model handler
    cfs_algn_model model;
  
    //Register predictor handler
    cfs_algn_reg_predictor#(cfs_apb_item_mon) predictor;
    
    //Scoreboard handler
    cfs_algn_scoreboard scoreboard;
    
    //Coverage handler
    cfs_algn_coverage coverage;
    
    //Virtual sequencer handler
    cfs_algn_virtual_sequencer virtual_sequencer;
    
    `uvm_component_param_utils(cfs_algn_env#(ALGN_DATA_WIDTH))
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      
      env_config = cfs_algn_env_config::type_id::create("env_config", this);
      
      env_config.set_has_checks(1);
      env_config.set_algn_data_width(ALGN_DATA_WIDTH);
      
      apb_agent = cfs_apb_agent::type_id::create("apb_agent", this);
      
      md_rx_agent = cfs_md_agent_master#(ALGN_DATA_WIDTH)::type_id::create("md_rx_agent", this);
      
      begin
        cfs_md_agent_config_slave#(ALGN_DATA_WIDTH) agent_config = cfs_md_agent_config_slave#(ALGN_DATA_WIDTH)::type_id::create("agent_config", this);
        
        agent_config.set_stuck_threshold(100);
        
        uvm_config_db#(uvm_ext_pkg::uvm_ext_agent_config#(.VIRTUAL_INTF(virtual cfs_md_if#(ALGN_DATA_WIDTH))))::set(this, "md_tx_agent", "agent_config", agent_config);
      end
      
      md_tx_agent = cfs_md_agent_slave#(ALGN_DATA_WIDTH)::type_id::create("md_tx_agent", this);
      
      model = cfs_algn_model::type_id::create("model", this);
      
      predictor = cfs_algn_reg_predictor#(cfs_apb_item_mon)::type_id::create("predictor", this);
      
      scoreboard = cfs_algn_scoreboard::type_id::create("scoreboard", this);
      
      if(env_config.get_has_coverage()) begin
        coverage = cfs_algn_coverage::type_id::create("coverage", this);
      end 
      
      virtual_sequencer = cfs_algn_virtual_sequencer::type_id::create("virtual_sequencer", this);
    endfunction
  
    virtual function void connect_phase(uvm_phase phase);
      cfs_algn_vif vif;
      string vif_name = "vif";
      
      //APB transaction adapter
      cfs_apb_reg_adapter adapter = cfs_apb_reg_adapter::type_id::create("adapter", this);

      super.connect_phase(phase);
      
      if(!uvm_config_db#(cfs_algn_vif)::get(this, "", vif_name, vif)) begin
        `uvm_fatal("NO_VIF", $sformatf("Could not get from the database the virtual interface using name \"%0s\"", vif_name))
      end
      else begin
        env_config.set_vif(vif);
      end
      
      //Configure the predictor with an address map and an adapter
      predictor.map     = model.reg_block.default_map;
      predictor.adapter = adapter;

      //Connect the APB monitor with the predictor
      apb_agent.monitor.output_port.connect(predictor.bus_in);
      
      //Connect the APB sequencer to the address map in order
      //to use the API of the registers to start APB transactions
      model.reg_block.default_map.set_sequencer(apb_agent.sequencer, adapter);
      
      predictor.env_config = env_config;
      
      model.env_config = env_config;
      
      
      //Pass the information from the MD agents to the model
      md_rx_agent.monitor.output_port.connect(model.port_in_rx);
      md_tx_agent.monitor.output_port.connect(model.port_in_tx);
      
      scoreboard.env_config = env_config;
      
      model.port_out_rx.connect(scoreboard.port_in_model_rx);
      model.port_out_tx.connect(scoreboard.port_in_model_tx);
      model.port_out_irq.connect(scoreboard.port_in_model_irq);
      md_rx_agent.monitor.output_port.connect(scoreboard.port_in_agent_rx);
      md_tx_agent.monitor.output_port.connect(scoreboard.port_in_agent_tx);
      
      if(coverage != null) begin
        model.port_out_split_info.connect(coverage.port_in_split_info);
      end
      
      virtual_sequencer.apb_sequencer   = apb_agent.sequencer;
      virtual_sequencer.md_rx_sequencer = cfs_md_sequencer_base_master'(md_rx_agent.sequencer);
      virtual_sequencer.md_tx_sequencer = cfs_md_sequencer_base_slave'(md_tx_agent.sequencer);
      virtual_sequencer.model           = model;
    endfunction 
    
    //Function to handle the reset
    virtual function void handle_reset(uvm_phase phase);
      model.handle_reset(phase);
      scoreboard.handle_reset(phase);
      
      if(coverage != null) begin
        coverage.handle_reset(phase);
      end 
    endfunction
  
    //Task for waiting reset to start
    protected virtual task wait_reset_start();
      apb_agent.agent_config.wait_reset_start();
    endtask
  
    //Task for waiting reset to end
    protected virtual task wait_reset_end();
      apb_agent.agent_config.wait_reset_end();
    endtask
    
    virtual task run_phase(uvm_phase phase);
      forever begin
        wait_reset_start();
        handle_reset(phase);
        wait_reset_end();
      end
    endtask
  endclass

`endif