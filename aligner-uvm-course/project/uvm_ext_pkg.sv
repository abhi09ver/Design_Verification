///////////////////////////////////////////////////////////////////////////////
// File:        uvm_ext_pkg.sv
// Author:      Cristian Florin Slav
// Date:        2024-03-18
// Description: UVM Extensions package
///////////////////////////////////////////////////////////////////////////////
`ifndef UVM_EXT_PKG_SV
  `define UVM_EXT_PKG_SV

  `include "uvm_macros.svh"

  package uvm_ext_pkg;
    import uvm_pkg::*;

    class uvm_ext_agent_config#(type VIRTUAL_INTF = int) extends uvm_component;

      //Virtual interface
      protected VIRTUAL_INTF vif;

      //Active/Passive control
      protected uvm_active_passive_enum active_passive;

      //Switch to enable coverage
      protected bit has_coverage;

      //Switch to enable checks
      protected bit has_checks;

      `uvm_component_param_utils(uvm_ext_agent_config#(VIRTUAL_INTF))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);

        active_passive = UVM_ACTIVE;
        has_coverage   = 1;
        has_checks     = 1;
      endfunction

      //Getter for the virtual interface
      virtual function VIRTUAL_INTF get_vif();
        return vif;
      endfunction

      //Setter for the APB virtual interface
      virtual function void set_vif(VIRTUAL_INTF value);
        if(vif == null) begin
          vif = value;
        end
        else begin
          `uvm_fatal("ALGORITHM_ISSUE", "Trying to set the virtual interface more than once")
        end
      endfunction

      //Getter for the Active/Passive control
      virtual function uvm_active_passive_enum get_active_passive();
        return active_passive;
      endfunction

      //Setter for the Active/Passive control
      virtual function void set_active_passive(uvm_active_passive_enum value);
        active_passive = value;
      endfunction

      //Getter for the has_coverage control field
      virtual function bit get_has_coverage();
        return has_coverage;
      endfunction

      //Setter for the has_coverage control field
      virtual function void set_has_coverage(bit value);
        has_coverage = value;
      endfunction

      //Getter for the has_checks control field
      virtual function bit get_has_checks();
        return has_checks;
      endfunction

      //Setter for the has_checks control field
      virtual function void set_has_checks(bit value);
        has_checks = value;
      endfunction

      virtual function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);

        if(get_vif() == null) begin
          `uvm_fatal("ALGORITHM_ISSUE", "The APB virtual interface is not configured at \"Start of simulation\" phase")
        end 
        else begin
          `uvm_info("CONFIG", "The virtual interface is configured at \"Start of simulation\" phase", UVM_FULL)
        end
      endfunction

      //Task for waiting the reset to start
      virtual task wait_reset_start();
        `uvm_fatal("ALGORITHM_ISSUE", "One must implement wait_reset_start() task")
      endtask

      //Task for waiting the reset to be finished
      virtual task wait_reset_end();
        `uvm_fatal("ALGORITHM_ISSUE", "One must implement wait_reset_end() task")
      endtask

    endclass

    interface class uvm_ext_reset_handler; 

      //Function to handle the reset
      pure virtual function void handle_reset(uvm_phase phase);

    endclass

    class uvm_ext_monitor#(type VIRTUAL_INTF = int, type ITEM_MON = uvm_sequence_item) extends uvm_monitor implements uvm_ext_reset_handler;

      //Pointer to agent configuration
      uvm_ext_agent_config#(VIRTUAL_INTF) agent_config;

      //Port for sending the collected item
      uvm_analysis_port#(ITEM_MON) output_port;

      //Process for collect_transactions() task
      protected process process_collect_transactions;

      `uvm_component_param_utils(uvm_ext_monitor#(VIRTUAL_INTF, ITEM_MON))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);

        output_port = new("output_port", this);
      endfunction

      virtual task run_phase(uvm_phase phase);
        forever begin
          fork
            begin
              wait_reset_end();
              collect_transactions();

              disable fork;
            end 
          join
        end
      endtask

      //Task which drives one single item on the bus
      protected virtual task collect_transaction();
        `uvm_fatal("ALGORITHM_ISSUE", "One must implement collect_transaction() task")  
      endtask

      //Task for collecting all transactions
      protected virtual task collect_transactions();
        fork
          begin
            process_collect_transactions = process::self();

            forever begin
              collect_transaction();
            end

          end
        join
      endtask

      //Task for waiting the reset to be finished
      protected virtual task wait_reset_end();
        agent_config.wait_reset_end();
      endtask

      //Function to handle the reset
      virtual function void handle_reset(uvm_phase phase);
        if(process_collect_transactions != null) begin
          process_collect_transactions.kill();

          process_collect_transactions = null;
        end
      endfunction

    endclass

   `uvm_analysis_imp_decl(_item) 

   virtual class uvm_ext_cover_index_wrapper_base extends uvm_component;

     function new(string name = "", uvm_component parent);
       super.new(name, parent);
     endfunction

     //Function used to sample the information
     pure virtual function void sample(int unsigned value);

     //Function to print the coverage information.
     //This is only to be able to visualize some basic coverage information
     //in EDA Playground.
     //DON'T DO THIS IN A REAL PROJECT!!!
     pure virtual function string coverage2string();   
   endclass

    //Wrapper over the covergroup which covers indices.
    //The MAX_VALUE parameter is used to determine the maximum value to sample
    class uvm_ext_cover_index_wrapper#(int unsigned MAX_VALUE_PLUS_1 = 16) extends uvm_ext_cover_index_wrapper_base;

      `uvm_component_param_utils(uvm_ext_cover_index_wrapper#(MAX_VALUE_PLUS_1))

      covergroup cover_index with function sample(int unsigned value);
        option.per_instance = 1;

        index : coverpoint value {
          option.comment = "Index";
          bins values[MAX_VALUE_PLUS_1] = {[0:MAX_VALUE_PLUS_1-1]};
        }

      endgroup

      function new(string name = "", uvm_component parent);
        super.new(name, parent);

        cover_index = new();
        cover_index.set_inst_name($sformatf("%s_%s", get_full_name(), "cover_index"));
      endfunction

      //Function to print the coverage information.
      //This is only to be able to visualize some basic coverage information
      //in EDA Playground.
      //DON'T DO THIS IN A REAL PROJECT!!!
      virtual function string coverage2string();
        return {
          $sformatf("\n   cover_index:              %03.2f%%", cover_index.get_inst_coverage()),
          $sformatf("\n      index:                 %03.2f%%", cover_index.index.get_inst_coverage())
        };
      endfunction

      //Function used to sample the information
      virtual function void sample(int unsigned value);
        cover_index.sample(value);
      endfunction

    endclass

    class uvm_ext_coverage#(type VIRTUAL_INTF = int, type ITEM_MON = uvm_sequence_item) extends uvm_component implements uvm_ext_reset_handler;

      //Pointer to agent configuration
      uvm_ext_agent_config#(VIRTUAL_INTF) agent_config;

      //Port for receiving the collected item
      uvm_analysis_imp_item#(ITEM_MON, uvm_ext_coverage#(VIRTUAL_INTF, ITEM_MON)) port_item; 

      `uvm_component_param_utils(uvm_ext_coverage#(VIRTUAL_INTF, ITEM_MON))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);

        port_item = new("port_item", this);
      endfunction

      //Port associated with port_item port
      virtual function void write_item(ITEM_MON item);

      endfunction

      //Function to handle the reset
      virtual function void handle_reset(uvm_phase phase);

      endfunction

      //Function to print the coverage information.
      //This is only to be able to visualize some basic coverage information
      //in EDA Playground.
      //DON'T DO THIS IN A REAL PROJECT!!!
      virtual function string coverage2string();
        string result = "";

        uvm_component children[$];

        get_children(children);

        foreach(children[idx]) begin
          uvm_ext_cover_index_wrapper_base wrapper;

          if($cast(wrapper, children[idx])) begin
            result = $sformatf("%s\n\nChild component: %0s%0s", result, wrapper.get_name(), wrapper.coverage2string());
          end
        end

        return result;
      endfunction
 
      virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        //IMPORTANT: DON'T DO THIS IN A REAL PROJECT!!!
        `uvm_info("COVERAGE", $sformatf("Coverage: %0s", coverage2string()), UVM_DEBUG)
      endfunction 

    endclass

    class uvm_ext_sequencer#(type ITEM_DRV = uvm_sequence_item) extends uvm_sequencer#(.REQ(ITEM_DRV)) implements uvm_ext_reset_handler;

      `uvm_component_param_utils(uvm_ext_sequencer#(ITEM_DRV))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
      endfunction

      virtual function void handle_reset(uvm_phase phase);
        int objections_count;
        stop_sequences();

        objections_count = uvm_test_done.get_objection_count(this);

        if(objections_count > 0) begin
          uvm_test_done.drop_objection(this, $sformatf("Dropping %0d objections at reset", objections_count), objections_count);
        end

        start_phase_sequence(phase);
      endfunction

    endclass

    class uvm_ext_driver#(type VIRTUAL_INTF = int, type ITEM_DRV = uvm_sequence_item) extends uvm_driver#(.REQ(ITEM_DRV)) implements uvm_ext_reset_handler;

      //Pointer to agent configuration
      uvm_ext_agent_config#(VIRTUAL_INTF) agent_config;

      //process for drive_transactions() task
      protected process process_drive_transactions;

      `uvm_component_param_utils(uvm_ext_driver#(VIRTUAL_INTF, ITEM_DRV))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
      endfunction

      virtual task run_phase(uvm_phase phase);
        forever begin
          fork
            begin
              wait_reset_end();
              drive_transactions();

              disable fork;
            end
          join
        end
      endtask

      //Task which drives one single item on the bus
      protected virtual task drive_transaction(ITEM_DRV item);
        `uvm_fatal("ALGORITHM_ISSUE", "One must implement drive_transaction() task")  
      endtask

      //Task for driving all transactions
      protected virtual task drive_transactions();

        fork
          begin
            process_drive_transactions = process::self();

            forever begin
              ITEM_DRV item;

              seq_item_port.get_next_item(item);

              drive_transaction(item);

              seq_item_port.item_done();
            end
          end
        join
      endtask

      //Task for waiting the reset to be finished
      protected virtual task wait_reset_end();
        agent_config.wait_reset_end();
      endtask

      //Function to handle the reset
      virtual function void handle_reset(uvm_phase phase);
        if(process_drive_transactions != null) begin
          process_drive_transactions.kill();

          process_drive_transactions = null;
        end
      endfunction

    endclass

    class uvm_ext_agent#(type VIRTUAL_INTF = int, type ITEM_MON = uvm_sequence_item, type ITEM_DRV = uvm_sequence_item) extends uvm_agent implements uvm_ext_reset_handler;

      //Agent configuration handler
      uvm_ext_agent_config#(VIRTUAL_INTF) agent_config;

      //Monitor handler
      uvm_ext_monitor#(VIRTUAL_INTF, ITEM_MON) monitor;

      //Coverage handler
      uvm_ext_coverage#(VIRTUAL_INTF, ITEM_MON) coverage;

      //Driver handler
      uvm_ext_driver#(VIRTUAL_INTF, ITEM_DRV) driver;

      //Sequencer handler
      uvm_ext_sequencer#(ITEM_DRV) sequencer;

      `uvm_component_param_utils(uvm_ext_agent#(VIRTUAL_INTF, ITEM_MON, ITEM_DRV))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
      endfunction

      virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if(!uvm_config_db#(uvm_ext_agent_config#(VIRTUAL_INTF))::get(this, "", "agent_config", agent_config)) begin
          agent_config = uvm_ext_agent_config#(VIRTUAL_INTF)::type_id::create("agent_config", this);
        end

        monitor = uvm_ext_monitor#(VIRTUAL_INTF, ITEM_MON)::type_id::create("monitor", this);

        if(agent_config.get_has_coverage()) begin
          coverage = uvm_ext_coverage#(VIRTUAL_INTF, ITEM_MON)::type_id::create("coverage", this);
        end

        if(agent_config.get_active_passive() == UVM_ACTIVE) begin
          driver    = uvm_ext_driver#(VIRTUAL_INTF, ITEM_DRV)::type_id::create("driver", this);
          sequencer = uvm_ext_sequencer#(ITEM_DRV)::type_id::create("sequencer", this);
        end
      endfunction

      virtual function void connect_phase(uvm_phase phase);
        VIRTUAL_INTF vif;
        string       vif_name = "vif";

        super.connect_phase(phase);

        if(!uvm_config_db#(VIRTUAL_INTF)::get(this, "", vif_name, vif)) begin
          `uvm_fatal("NO_VIF", $sformatf("Could not get from the database the virtual interface using name \"%0s\"", vif_name))
        end
        else begin
          agent_config.set_vif(vif);
        end

        monitor.agent_config = agent_config;

        if(agent_config.get_has_coverage()) begin
          coverage.agent_config = agent_config;

          monitor.output_port.connect(coverage.port_item);
        end

        if(agent_config.get_active_passive() == UVM_ACTIVE) begin
          driver.seq_item_port.connect(sequencer.seq_item_export);

          driver.agent_config = agent_config;
        end
      endfunction

      //Task for waiting the reset to start
      protected virtual task wait_reset_start();
        agent_config.wait_reset_start();
      endtask

      //Task for waiting the reset to be finished
      protected virtual task wait_reset_end();
        agent_config.wait_reset_end();
      endtask

      //Function to handle the reset
      virtual function void handle_reset(uvm_phase phase);
        uvm_component children[$];

        get_children(children);

        foreach(children[idx]) begin
          uvm_ext_reset_handler reset_handler;

          if($cast(reset_handler, children[idx])) begin
            reset_handler.handle_reset(phase);
          end
        end
      endfunction

      virtual task run_phase(uvm_phase phase);
        forever begin
          wait_reset_start();
          handle_reset(phase);
          wait_reset_end();
        end
      endtask

    endclass

  endpackage

`endif