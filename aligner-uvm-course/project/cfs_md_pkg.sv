///////////////////////////////////////////////////////////////////////////////
// File:        cfs_md_pkg.sv
// Author:      Cristian Florin Slav
// Date:        2023-12-02
// Description: MD Agent package.
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_MD_PKG_SV
  `define CFS_MD_PKG_SV

  `include "uvm_macros.svh"

  `include "uvm_ext_pkg.sv"

  `include "cfs_md_if.sv"
 
  package cfs_md_pkg;

    import uvm_pkg::*;
    import uvm_ext_pkg::*;

    //MD response
    typedef enum bit {CFS_MD_OKAY = 0, CFS_MD_ERR = 1} cfs_md_response;

    class cfs_md_item_base extends uvm_sequence_item;

      `uvm_object_utils(cfs_md_item_base)

      function new(string name = "");
        super.new(name);
      endfunction

    endclass

    class cfs_md_item_drv extends cfs_md_item_base;

      `uvm_object_utils(cfs_md_item_drv)

      function new(string name = "");
        super.new(name);
      endfunction

    endclass

    class cfs_md_item_drv_master extends cfs_md_item_drv;

      //Pre drive delay
      rand int unsigned pre_drive_delay; 

      //Post drive delay
      rand int unsigned post_drive_delay;

      //Data driven by the master
      rand bit[7:0] data[$];

      //Offset of the data
      rand int unsigned offset;

      constraint pre_drive_delay_default {
        soft pre_drive_delay <= 5;
      }

      constraint post_drive_delay_default {
        soft post_drive_delay <= 5;
      }

      constraint data_default {
        soft data.size() == 1;
      }

      constraint data_hard {
        soft data.size() > 0;
      }

      constraint offset_default {
        soft offset == 0;
      }

      `uvm_object_utils(cfs_md_item_drv_master)

      function new(string name = "");
        super.new(name);
      endfunction

      virtual function string convert2string();
        string data_as_string = "{";

        foreach(data[idx]) begin
          data_as_string = $sformatf("%0s'h%02x%0s", data_as_string, data[idx], idx == data.size() - 1 ? "" : ", ");
        end

        data_as_string = $sformatf("%0s}", data_as_string);

        return $sformatf("data: %0s, offset: %0d, pre_drive_delay: %0d, post_drive_delay: %0d", data_as_string, offset, pre_drive_delay, post_drive_delay);

      endfunction

    endclass

    class cfs_md_item_drv_slave extends cfs_md_item_drv;

      //Length, in clock cycles, of the item - this controls after how many cycles the "ready" signal will be high.
      //A value of 0 means that the MD item will be one clock cycle long.
      rand int unsigned length;

      //Response
      rand cfs_md_response response;

      //Value of 'ready' signal at the end of the MD item
      rand bit ready_at_end;

      constraint length_default {
        soft length <= 5;
      }

      `uvm_object_utils(cfs_md_item_drv_slave)

      function new(string name = "");
        super.new(name);
      endfunction

      virtual function string convert2string();
        return $sformatf("length: %0d, response: %0s, ready_at_end: %0d", length, response.name(), ready_at_end);
      endfunction

    endclass

    class cfs_md_item_mon extends cfs_md_item_base;

      //Number of clock cycles from the previous item
      int unsigned prev_item_delay;

      //Lenght, in clock cycles, of the MD transfer
      int unsigned length;

      //Data monitored by the agent
      bit[7:0] data[$];

      //Offset of the data
      int unsigned offset;

      //Response
      cfs_md_response response;

      `uvm_object_utils(cfs_md_item_mon)

      function new(string name = "");
        super.new(name);
      endfunction

      virtual function string convert2string();
        string data_as_string = "{";

        foreach(data[idx]) begin
          data_as_string = $sformatf("%0s'h%02x%0s", data_as_string, data[idx], idx == data.size() - 1 ? "" : ", ");
        end

        data_as_string = $sformatf("%0s}", data_as_string); 

        return $sformatf("[%0t..%0s] data: %0s, size: %0d, offset: %0d, response: %0s, length: %0d, prev_item_delay: %0d", 
                         get_begin_time(), 
                         is_active() ? "" : $sformatf("%0t",  get_end_time()), 
                         data_as_string, data.size(), offset, response.name(), length, prev_item_delay);
      endfunction

    endclass

    class cfs_md_agent_config#(int unsigned DATA_WIDTH = 32) extends uvm_ext_agent_config#(.VIRTUAL_INTF(virtual cfs_md_if#(DATA_WIDTH)));

      typedef virtual cfs_md_if#(DATA_WIDTH) cfs_md_vif;

      //Delay used when detecting start of an MD transaction in the monitor
      local time sample_delay_start_tr;

      //Number of clock cycles after which an MD transfer is considered
      //stuck and an error is triggered
      local int unsigned stuck_threshold;

      `uvm_component_param_utils(cfs_md_agent_config#(DATA_WIDTH))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);

        sample_delay_start_tr = 1ns;
        stuck_threshold       = 1000;
      endfunction

      //Setter for the MD virtual interface
      virtual function void set_vif(cfs_md_vif value);
        super.set_vif(value);
        set_has_checks(get_has_checks());
      endfunction

      //Setter for the has_checks control field
      virtual function void set_has_checks(bit value);
        super.set_has_checks(value);

        if(vif != null) begin
          vif.has_checks = has_checks;
        end
      endfunction

      //Setter for sample_delay_start_tr_detection
      virtual function void set_sample_delay_start_tr(time value);
        sample_delay_start_tr = value;
      endfunction

      //Getter for sample_delay_start_tr_detection
      virtual function time get_sample_delay_start_tr();
        return sample_delay_start_tr;
      endfunction

      //Getter for the stuck threshold
      virtual function int unsigned get_stuck_threshold();
        return stuck_threshold;
      endfunction

      //Setter for stuck threshold
      virtual function void set_stuck_threshold(int unsigned value);
        stuck_threshold = value;
      endfunction

      virtual task run_phase(uvm_phase phase);
        forever begin
          @(vif.has_checks);

          if(vif.has_checks != get_has_checks()) begin
            `uvm_error("ALGORITHM_ISSUE", $sformatf("Can not change \"has_checks\" from MD interface directly - use %0s.set_has_checks()", get_full_name()))
          end
        end
      endtask

      //Task for waiting the reset to start
      virtual task wait_reset_start();
        if(vif.reset_n !== 0) begin
          @(negedge vif.reset_n);
        end
      endtask

      //Task for waiting the reset to be finished
      virtual task wait_reset_end();
        while(vif.reset_n == 0) begin
          @(posedge vif.clk);
        end
      endtask
    endclass

    class cfs_md_agent_config_slave#(int unsigned DATA_WIDTH = 32) extends cfs_md_agent_config#(DATA_WIDTH);

      //Value of "ready" signal at reset
      local bit ready_at_reset;

      `uvm_component_param_utils(cfs_md_agent_config_slave#(DATA_WIDTH))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);

        ready_at_reset = 1;
      endfunction

      //Setter for field ready_at_reset
      virtual function void set_ready_at_reset(bit value);
        ready_at_reset = value;
      endfunction

      //Getter for field ready_at_reset
      virtual function bit get_ready_at_reset();
        return ready_at_reset;
      endfunction

    endclass

    class cfs_md_agent_config_master#(int unsigned DATA_WIDTH = 32) extends cfs_md_agent_config#(DATA_WIDTH);

      `uvm_component_param_utils(cfs_md_agent_config_master#(DATA_WIDTH))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
      endfunction

    endclass
        
    class cfs_md_monitor#(int unsigned DATA_WIDTH = 32) extends uvm_ext_monitor#(.VIRTUAL_INTF(virtual cfs_md_if#(DATA_WIDTH)), .ITEM_MON(cfs_md_item_mon));

      typedef virtual cfs_md_if#(DATA_WIDTH) cfs_md_vif;

      //Pointer to agent configuration
      cfs_md_agent_config#(DATA_WIDTH) agent_config;

      `uvm_component_param_utils(cfs_md_monitor#(DATA_WIDTH))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
      endfunction

      virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase); 
         
        if($cast(agent_config, super.agent_config) == 0) begin
          `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Could not cast %0s to %0s", 
            super.agent_config.get_type_name(), cfs_md_agent_config#(DATA_WIDTH)::type_id::type_name))
        end
      endfunction

      //Task which drives one single item on the bus
      protected virtual task collect_transaction();
        cfs_md_vif vif = agent_config.get_vif();

        int unsigned data_width_in_bytes = DATA_WIDTH / 8;

        cfs_md_item_mon item = cfs_md_item_mon::type_id::create("item");

        #(agent_config.get_sample_delay_start_tr());

        while(vif.valid !== 1) begin
          @(posedge vif.clk);

          item.prev_item_delay++;

          #(agent_config.get_sample_delay_start_tr());
        end

        item.offset = vif.offset;

        for(int i = 0; i < vif.size; i++) begin
          item.data.push_back((vif.data >> ((item.offset + i) * 8)) & 8'hFF);
        end

        item.length = 1;
 
        void'(begin_tr(item));

        `uvm_info("ITEM_START", $sformatf("Monitor started collecting item: %0s", item.convert2string()), UVM_LOW)

        output_port.write(item);

        @(posedge vif.clk);

        while(vif.ready !== 1) begin
          @(posedge vif.clk);
          item.length++;

          if(agent_config.get_has_checks()) begin
            if(item.length >= agent_config.get_stuck_threshold()) begin
              `uvm_error("PROTOCOL_ERROR", $sformatf("The MD transfer reached the stuck threshold value of %0d", item.length))
            end
          end
        end

        item.response = cfs_md_response'(vif.err);

        end_tr(item);

        output_port.write(item);

        `uvm_info("ITEM_END", $sformatf("Monitored item: %0s", item.convert2string()), UVM_LOW)
      endtask

    endclass 

    class cfs_md_coverage#(int unsigned DATA_WIDTH = 32) extends uvm_ext_coverage#(.VIRTUAL_INTF(virtual cfs_md_if#(DATA_WIDTH)), .ITEM_MON(cfs_md_item_mon));

      typedef virtual cfs_md_if#(DATA_WIDTH) cfs_md_vif;

      //Pointer to agent configuration
      cfs_md_agent_config#(DATA_WIDTH) agent_config;

      //Wrapper over the coverage group covering the indices in the data signal
      //at which the bit of the data was 0
      uvm_ext_cover_index_wrapper#(DATA_WIDTH) wrap_cover_data_0;

      //Wrapper over the coverage group covering the indices in the data signal
      //at which the bit of the data was 1
      uvm_ext_cover_index_wrapper#(DATA_WIDTH) wrap_cover_data_1;

      `uvm_component_param_utils(cfs_md_coverage#(DATA_WIDTH))

      covergroup cover_item with function sample(cfs_md_item_mon item);
        option.per_instance = 1;

        offset : coverpoint item.offset {
          option.comment = "Offset of the MD access";
          bins values[]  = {[0:(DATA_WIDTH/8)-1]};
        }

        size : coverpoint item.data.size() {
          option.comment = "Size of the MD access";
          bins values[]  = {[1:(DATA_WIDTH/8)]};
        }

        response : coverpoint item.response {
          option.comment = "Response of the MD access";
        }

        length : coverpoint item.length {
          option.comment = "Length of the MD access";
          bins length_eq_1     = {1};
          bins length_le_10[9] = {[2:10]};
          bins length_gt_10    = {[11:$]};

          illegal_bins length_lt_1 = {0};
        }

        prev_item_delay : coverpoint item.prev_item_delay {
          option.comment = "Delay, in clock cycles, between two consecutive MD accesses";
          bins back2back       = {0};
          bins delay_le_5[5]   = {[1:5]};
          bins delay_gt_5      = {[6:$]};
        }

        offset_x_size : cross offset, size {
          ignore_bins ignore_offset_plus_size_gt_data_width = offset_x_size with (offset + size > (DATA_WIDTH / 8));
        }

      endgroup

      covergroup cover_reset with function sample(bit valid);
        option.per_instance = 1;

        access_ongoing : coverpoint valid {
          option.comment = "An MD access was ongoing at reset";
        }
      endgroup

      function new(string name = "", uvm_component parent);
        super.new(name, parent);

        cover_item = new();
        cover_item.set_inst_name($sformatf("%s_%s", get_full_name(), "cover_item"));

        cover_reset = new();
        cover_reset.set_inst_name($sformatf("%s_%s", get_full_name(), "cover_reset"));
      endfunction

      virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        wrap_cover_data_0 = uvm_ext_cover_index_wrapper#(DATA_WIDTH)::type_id::create("wrap_cover_data_0", this);
        wrap_cover_data_1 = uvm_ext_cover_index_wrapper#(DATA_WIDTH)::type_id::create("wrap_cover_data_1", this);
      endfunction

      virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase); 
         
        if($cast(agent_config, super.agent_config) == 0) begin
          `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Could not cast %0s to %0s", 
            super.agent_config.get_type_name(), cfs_md_agent_config#(DATA_WIDTH)::type_id::type_name))
        end
      endfunction

      //Port associated with port_item port
      virtual function void write_item(cfs_md_item_mon item);
        cover_item.sample(item);

        foreach(item.data[byte_index]) begin
          for(int bit_index = 0; bit_index < 8; bit_index++) begin
            if(item.data[byte_index][bit_index]) begin
              wrap_cover_data_1.sample((item.offset * 8) + (byte_index * 8) + bit_index);
            end
            else begin
              wrap_cover_data_0.sample((item.offset * 8) + (byte_index * 8) + bit_index);
            end
          end
        end

      endfunction

      //Function to handle the reset
      virtual function void handle_reset(uvm_phase phase);
        cfs_md_vif vif = agent_config.get_vif();

        cover_reset.sample(vif.valid);
      endfunction

      //Function to print the coverage information.
      //This is only to be able to visualize some basic coverage information
      //in EDA Playground.
      //DON'T DO THIS IN A REAL PROJECT!!!
      virtual function string coverage2string();
        string result = {
          $sformatf("\n   cover_item:         %03.2f%%", cover_item.get_inst_coverage()),
          $sformatf("\n      offset:          %03.2f%%", cover_item.offset.get_inst_coverage()),
          $sformatf("\n      size:            %03.2f%%", cover_item.size.get_inst_coverage()),
          $sformatf("\n      response:        %03.2f%%", cover_item.response.get_inst_coverage()),
          $sformatf("\n      length:          %03.2f%%", cover_item.length.get_inst_coverage()),
          $sformatf("\n      prev_item_delay: %03.2f%%", cover_item.prev_item_delay.get_inst_coverage()),
          $sformatf("\n      offset_x_size:   %03.2f%%", cover_item.offset_x_size.get_inst_coverage()),
          $sformatf("\n                                    "),
          $sformatf("\n   cover_reset:        %03.2f%%", cover_reset.get_inst_coverage()),
          $sformatf("\n      access_ongoing:  %03.2f%%", cover_reset.access_ongoing.get_inst_coverage()),
          super.coverage2string()
        };

        return result;
      endfunction

    endclass

    class cfs_md_sequencer_base#(type ITEM_DRV = cfs_md_item_drv) extends uvm_ext_sequencer#(.ITEM_DRV(ITEM_DRV));

      `uvm_component_param_utils(cfs_md_sequencer_base#(ITEM_DRV))

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
      endfunction

      virtual function int unsigned get_data_width();
        `uvm_fatal("ALGORITHM_ISSUE", "Implement get_data_width()")
      endfunction

    endclass

  class cfs_md_sequencer_base_master extends cfs_md_sequencer_base#(.ITEM_DRV(cfs_md_item_drv_master));

    `uvm_component_utils(cfs_md_sequencer_base_master)

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass
        
  class cfs_md_sequencer_master#(int unsigned DATA_WIDTH = 32) extends cfs_md_sequencer_base_master;

    `uvm_component_param_utils(cfs_md_sequencer_master#(DATA_WIDTH))

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function int unsigned get_data_width();
      return DATA_WIDTH;
    endfunction
    
  endclass

  class cfs_md_sequencer_base_slave extends cfs_md_sequencer_base#(.ITEM_DRV(cfs_md_item_drv_slave));

    //Port for receiving items from the monitor
    uvm_analysis_imp#(cfs_md_item_mon, cfs_md_sequencer_base_slave) port_from_mon; 
    
    //FIFO containing the pending item(s) on the bus
    uvm_tlm_fifo#(cfs_md_item_mon) pending_items;

    `uvm_component_utils(cfs_md_sequencer_base_slave)

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      port_from_mon = new("port_from_mon", this);
      pending_items = new("pending_items", this, 1);
    endfunction

    virtual function void write(cfs_md_item_mon item);
      if(item.is_active()) begin
        if(pending_items.is_full()) begin
          `uvm_fatal("ALGORITHM_ISSUE", 
                     $sformatf("FIFO %0s is full (size: %0d) - a possible cause is that there is no sequence started which pulls information from this FIFO",
                               pending_items.get_full_name(), pending_items.size()))
        end

        if(pending_items.try_put(item) == 0) begin
          `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Failed to push a new item in FIFO %0s", pending_items.get_full_name()))
        end
      end
    endfunction
    
    virtual function void handle_reset(uvm_phase phase);
      super.handle_reset(phase);
      
      pending_items.flush();
    endfunction
    
  endclass

  class cfs_md_sequencer_slave#(int unsigned DATA_WIDTH = 32) extends cfs_md_sequencer_base_slave;

    `uvm_component_param_utils(cfs_md_sequencer_slave#(DATA_WIDTH))

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function int unsigned get_data_width();
      return DATA_WIDTH;
    endfunction
    
  endclass

  class cfs_md_driver#(int unsigned DATA_WIDTH = 32, type ITEM_DRV = cfs_md_item_drv) extends uvm_ext_driver#(.VIRTUAL_INTF(virtual cfs_md_if#(DATA_WIDTH)), .ITEM_DRV(ITEM_DRV));

    //Pointer to agent configuration
    cfs_md_agent_config#(DATA_WIDTH) agent_config;

    `uvm_component_param_utils(cfs_md_driver#(DATA_WIDTH, ITEM_DRV))

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase); 
         
      if($cast(agent_config, super.agent_config) == 0) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Could not cast %0s to %0s", 
                                                super.agent_config.get_type_name(), cfs_md_agent_config#(DATA_WIDTH)::type_id::type_name))
      end
    endfunction

  endclass

  class cfs_md_driver_master#(int unsigned DATA_WIDTH = 32) extends cfs_md_driver#(.DATA_WIDTH(DATA_WIDTH), .ITEM_DRV(cfs_md_item_drv_master));

    typedef virtual cfs_md_if#(DATA_WIDTH) cfs_md_vif;

    `uvm_component_param_utils(cfs_md_driver_master#(DATA_WIDTH))

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction

    //Task which drives one single item on the bus
    protected virtual task drive_transaction(cfs_md_item_drv_master item);
      
      cfs_md_vif vif = agent_config.get_vif();
       
      int unsigned data_width_in_bytes = DATA_WIDTH / 8;

      `uvm_info("ITEM_START", $sformatf("Driving \"%0s\": %0s", item.get_full_name(), item.convert2string()), UVM_LOW)
      
      if(item.offset + item.data.size() > data_width_in_bytes) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Trying to drive an item with offset %0d and %0d bytes but the width of the data bus, in bytes, is %0d", item.offset, item.data.size(), data_width_in_bytes))
      end

      for(int i = 0; i < item.pre_drive_delay; i++) begin
        @(posedge vif.clk);
      end

      vif.valid  <= 1;
      
      begin
        bit[DATA_WIDTH-1:0] data = 0;
        
        foreach(item.data[idx]) begin
          bit[DATA_WIDTH-1:0] temp = item.data[idx] << ((item.offset + idx) * 8);
          
          data = data | temp;
        end
        
        vif.data <= data;
      end
      
      vif.offset <= item.offset;
      vif.size   <= item.data.size();
      
      @(posedge vif.clk);

      while(vif.ready !== 1) begin
        @(posedge vif.clk);
      end

      vif.valid  <= 0;
      vif.data   <= 0;
      vif.offset <= 0;
      vif.size   <= 0;
      
      for(int i = 0; i < item.post_drive_delay; i++) begin
        @(posedge vif.clk);
      end
    endtask

    //Function to handle the reset
    virtual function void handle_reset(uvm_phase phase);
      cfs_md_vif vif = agent_config.get_vif();
      
      super.handle_reset(phase);
      
      vif.valid  <= 0;
      vif.data   <= 0;
      vif.offset <= 0;
      vif.size   <= 0;
      
    endfunction

  endclass

  class cfs_md_driver_slave#(int unsigned DATA_WIDTH = 32) extends cfs_md_driver#(.DATA_WIDTH(DATA_WIDTH), .ITEM_DRV(cfs_md_item_drv_slave));
    
    //Pointer to the agent configuration component
    cfs_md_agent_config_slave#(DATA_WIDTH) agent_config;

    typedef virtual cfs_md_if#(DATA_WIDTH) cfs_md_vif;

    `uvm_component_param_utils(cfs_md_driver_slave#(DATA_WIDTH))

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
    endfunction
    
    virtual function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      
      if(super.agent_config == null) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("At this point the pointer to agent_config from %0s should not be null", get_full_name()))
      end
      
      if($cast(agent_config, super.agent_config) == 0) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Could not cast %0s to %0s", super.agent_config.get_full_name(), cfs_md_agent_config_slave#(DATA_WIDTH)::type_id::type_name))
      end
      
    endfunction

    //Task which drives one single item on the bus
    protected virtual task drive_transaction(cfs_md_item_drv_slave item);
       
      cfs_md_vif vif = agent_config.get_vif();
      
      `uvm_info("ITEM_START", $sformatf("Driving \"%0s\": %0s", item.get_full_name(), item.convert2string()), UVM_LOW)
      
      if(vif.valid !== 1) begin
        `uvm_error("ALGORITHM_ISSUE", $sformatf("Trying to drive a slave item when there is no item started by the master - item: %0s", item.convert2string()))
      end
      
      vif.ready <= 0;
      
      for(int i = 0; i < item.length; i++) begin
        @(posedge vif.clk);
      end

      vif.ready <= 1;
      vif.err   <= bit'(item.response);
      
      @(posedge vif.clk);
      
      vif.ready <= item.ready_at_end;
      vif.err   <= 0;
    endtask

    //Function to handle the reset
    virtual function void handle_reset(uvm_phase phase);
      cfs_md_vif vif = agent_config.get_vif();
      
      super.handle_reset(phase);
      
      vif.ready <= agent_config.get_ready_at_reset();
      vif.err   <= 0;
      
    endfunction

  endclass

  class cfs_md_agent#(int unsigned DATA_WIDTH = 32, type ITEM_DRV = cfs_md_item_drv) extends uvm_ext_agent#(.VIRTUAL_INTF(virtual cfs_md_if#(DATA_WIDTH)), .ITEM_MON(cfs_md_item_mon), .ITEM_DRV(ITEM_DRV));
    
    typedef virtual cfs_md_if#(DATA_WIDTH) cfs_md_vif;

    `uvm_component_param_utils(cfs_md_agent#(DATA_WIDTH, ITEM_DRV))

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      uvm_ext_agent_config#(.VIRTUAL_INTF(cfs_md_vif))::type_id::set_inst_override(cfs_md_agent_config#(DATA_WIDTH)::get_type(), "agent_config", this);
      uvm_ext_monitor#(.VIRTUAL_INTF(cfs_md_vif), .ITEM_MON(cfs_md_item_mon))::type_id::set_inst_override(cfs_md_monitor#(DATA_WIDTH)::get_type(), "monitor", this);
      uvm_ext_coverage#(.VIRTUAL_INTF(cfs_md_vif), .ITEM_MON(cfs_md_item_mon))::type_id::set_inst_override(cfs_md_coverage#(DATA_WIDTH)::get_type(), "coverage", this);
      uvm_ext_driver#(.VIRTUAL_INTF(cfs_md_vif), .ITEM_DRV(ITEM_DRV))::type_id::set_inst_override(cfs_md_driver#(DATA_WIDTH, ITEM_DRV)::get_type(), "driver", this);
      uvm_ext_sequencer#(.ITEM_DRV(ITEM_DRV))::type_id::set_inst_override(cfs_md_sequencer_base#(ITEM_DRV)::get_type(), "sequencer", this);
    endfunction

  endclass

  class cfs_md_agent_slave#(int unsigned DATA_WIDTH = 32) extends cfs_md_agent#(DATA_WIDTH, cfs_md_item_drv_slave);
    
    `uvm_component_param_utils(cfs_md_agent_slave#(DATA_WIDTH))

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      cfs_md_agent_config#(DATA_WIDTH)::type_id::set_inst_override(cfs_md_agent_config_slave#(DATA_WIDTH)::get_type(), "agent_config", this);
      cfs_md_driver#(DATA_WIDTH, cfs_md_item_drv_slave)::type_id::set_inst_override(cfs_md_driver_slave#(DATA_WIDTH)::get_type(), "driver", this);
      cfs_md_sequencer_base#(cfs_md_item_drv_slave)::type_id::set_inst_override(cfs_md_sequencer_slave#(DATA_WIDTH)::get_type(), "sequencer", this);
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      
      connect_port_from_mon_to_slave_seqr();
    endfunction
    
    //Function to connect port_from_mon_to_slave_seqr of the sequencer to the output_port of the monitor.
    //This allows future extensions of the agent to avoid using this mechanism to drive items on the bus.
    protected virtual function void connect_port_from_mon_to_slave_seqr();
      if(agent_config.get_active_passive() == UVM_ACTIVE) begin
        cfs_md_sequencer_slave#(DATA_WIDTH) sequencer;
        
        if($cast(sequencer, super.sequencer) == 0) begin
          `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Could not cast %0s to %0s", super.sequencer.get_full_name(), cfs_md_sequencer_slave#(DATA_WIDTH)::type_id::type_name))
        end
        
        monitor.output_port.connect(sequencer.port_from_mon);
      end
    endfunction

  endclass

  class cfs_md_agent_master#(int unsigned DATA_WIDTH = 32) extends cfs_md_agent#(DATA_WIDTH, cfs_md_item_drv_master);
    
    `uvm_component_param_utils(cfs_md_agent_master#(DATA_WIDTH))

    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      cfs_md_agent_config#(DATA_WIDTH)::type_id::set_inst_override(cfs_md_agent_config_master#(DATA_WIDTH)::get_type(), "agent_config", this);
      cfs_md_driver#(DATA_WIDTH, cfs_md_item_drv_master)::type_id::set_inst_override(cfs_md_driver_master#(DATA_WIDTH)::get_type(), "driver", this);
      cfs_md_sequencer_base#(cfs_md_item_drv_master)::type_id::set_inst_override(cfs_md_sequencer_master#(DATA_WIDTH)::get_type(), "sequencer", this);
    endfunction

  endclass


  class cfs_md_sequence_base#(type ITEM_DRV = cfs_md_item_drv) extends uvm_sequence#(.REQ(ITEM_DRV));
    
    `uvm_object_param_utils(cfs_md_sequence_base#(ITEM_DRV))
    
    function new(string name = "");
      super.new(name);
    endfunction

  endclass

  class cfs_md_sequence_base_slave extends cfs_md_sequence_base#(.ITEM_DRV(cfs_md_item_drv_slave));
    
    `uvm_declare_p_sequencer(cfs_md_sequencer_base_slave)
    
    `uvm_object_utils(cfs_md_sequence_base_slave)
    
    function new(string name = "");
      super.new(name);
    endfunction

  endclass
          
  class cfs_md_sequence_base_master extends cfs_md_sequence_base#(.ITEM_DRV(cfs_md_item_drv_master));
    
    `uvm_declare_p_sequencer(cfs_md_sequencer_base_master)
    
    `uvm_object_utils(cfs_md_sequence_base_master)
    
    function new(string name = "");
      super.new(name);
    endfunction

  endclass

  class cfs_md_sequence_simple_master extends cfs_md_sequence_base_master;
    
    //Item to drive
    rand cfs_md_item_drv_master item;
  
    //Bus data_width - used for simulators not supporting functions in constraints
    local int unsigned data_width;
    
    constraint item_hard {
      item.data.size() > 0;
      item.data.size() <= data_width / 8;
      
      item.offset      <  data_width / 8;
      
      item.data.size() + item.offset <= data_width / 8;
    }
    
    `uvm_object_utils(cfs_md_sequence_simple_master)
    
    function new(string name = "");
      super.new(name);
      
      item = cfs_md_item_drv_master::type_id::create("item");
      
      item.data_default.constraint_mode(0);
      item.offset_default.constraint_mode(0);
    endfunction
  
    function void pre_randomize();
      data_width = p_sequencer.get_data_width();
    endfunction
    
    virtual task body();
      `uvm_send(item)
    endtask

  endclass

  class cfs_md_sequence_simple_slave extends cfs_md_sequence_base_slave;
    
    //Item to drive
    rand cfs_md_item_drv_slave item;
    
    `uvm_object_utils(cfs_md_sequence_simple_slave)
    
    function new(string name = "");
      super.new(name);
      
      item = cfs_md_item_drv_slave::type_id::create("item");
    endfunction
    
    virtual task body();
      `uvm_send(item)
    endtask

  endclass

  class cfs_md_sequence_slave_response extends cfs_md_sequence_base_slave;
    
    `uvm_object_utils(cfs_md_sequence_slave_response)
    
    function new(string name = "");
      super.new(name);
    endfunction
    
    virtual task body();
      cfs_md_item_mon item_mon;
      
      p_sequencer.pending_items.get(item_mon);
      
      begin
        cfs_md_sequence_simple_slave seq;
        
        `uvm_do_with(seq, {
          //item_mon.data[0] == 'h85 -> seq.item.response == CFS_MD_ERR;
          //item_mon.data[0] != 'h85 -> seq.item.response == CFS_MD_OKAY;
        })
      end
    endtask

  endclass

  class cfs_md_sequence_slave_response_forever extends cfs_md_sequence_base_slave;
    
    `uvm_object_utils(cfs_md_sequence_slave_response_forever)
    
    function new(string name = "");
      super.new(name);
    endfunction
    
    virtual task body();
      forever begin
        cfs_md_sequence_slave_response seq = cfs_md_sequence_slave_response::type_id::create("seq");
        
        `uvm_do_on(seq, p_sequencer)
      end
    endtask

  endclass

  endpackage

`endif
