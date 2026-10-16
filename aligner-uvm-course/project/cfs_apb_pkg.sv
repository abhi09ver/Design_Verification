///////////////////////////////////////////////////////////////////////////////
// File:        cfs_apb_pkg.sv
// Author:      Cristian Florin Slav
// Date:        2023-07-05
// Description: APB Agent package.
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_APB_PKG_SV
  `define CFS_APB_PKG_SV

  `include "uvm_macros.svh"

  `include "uvm_ext_pkg.sv"

  `include "cfs_apb_if.sv"

  package cfs_apb_pkg;
    import uvm_pkg::*;
    import uvm_ext_pkg::*;

    //Virtual interface type
    typedef virtual cfs_apb_if cfs_apb_vif;

    //APB direction
    typedef enum bit {CFS_APB_READ = 0, CFS_APB_WRITE = 1} cfs_apb_dir;

    //APB address
    typedef bit[`CFS_APB_MAX_ADDR_WIDTH-1:0] cfs_apb_addr;

    //APB data
    typedef bit[`CFS_APB_MAX_DATA_WIDTH-1:0] cfs_apb_data;

    //APB response
    typedef enum bit {CFS_APB_OKAY = 0, CFS_APB_ERR = 1} cfs_apb_response;

    class cfs_apb_item_base extends uvm_sequence_item;

      //Direction
      rand cfs_apb_dir dir;

      //Address
      rand cfs_apb_addr addr;

      //Data
      rand cfs_apb_data data;

      `uvm_object_utils(cfs_apb_item_base)

      function new(string name = "");
        super.new(name);
      endfunction

      virtual function string convert2string();
        string result = $sformatf("dir: %0s, addr: %0x", dir.name(), addr);

        return result;
      endfunction

    endclass

    class cfs_apb_item_drv extends cfs_apb_item_base;

      //Pre drive delay
      rand int unsigned pre_drive_delay;

      //Post drive delay
      rand int unsigned post_drive_delay;

      constraint pre_drive_delay_default {
        soft pre_drive_delay <= 5;
      }

      constraint post_drive_delay_default {
        soft post_drive_delay <= 5;
      }

      `uvm_object_utils(cfs_apb_item_drv)

      function new(string name = "");
        super.new(name);
      endfunction

      virtual function string convert2string();
        string result = super.convert2string();

        if(dir == CFS_APB_WRITE) begin
          result = $sformatf("%s, data: %0x", result, data);
        end

        result = $sformatf("%s, pre_drive_delay: %0d, post_drive_delay: %0d", 
                           result, pre_drive_delay, post_drive_delay);

        return result;
      endfunction

    endclass

    class cfs_apb_item_mon extends cfs_apb_item_base;

      //Response
      cfs_apb_response response;

      //Lenght, in clock cycles, of the APB transfer
      int unsigned length;

      //Number of clock cycles from the previous item
      int unsigned prev_item_delay;

      `uvm_object_utils(cfs_apb_item_mon)

      function new(string name = "");
        super.new(name);
      endfunction

      virtual function string convert2string();
        string result = super.convert2string();

        result = $sformatf("%s, data: %0x, response: %0s, length: %0d, prev_item_delay: %0d",
                           result, data, response.name(), length, prev_item_delay);

        return result;
      endfunction

    endclass

    class cfs_apb_agent_config extends uvm_ext_agent_config#(.VIRTUAL_INTF(cfs_apb_vif));

      //Number of clock cycles after which an APB transfer is considered
      //stuck and an error is triggered
      local int unsigned stuck_threshold;

      `uvm_component_utils(cfs_apb_agent_config)

      function new(string name = "", uvm_component parent);
        super.new(name, parent);

        stuck_threshold = 1000;
      endfunction

      //Setter for the APB virtual interface
      virtual function void set_vif(cfs_apb_vif value);
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

      //Getter for the stuck threshold
      virtual function int unsigned get_stuck_threshold();
        return stuck_threshold;
      endfunction

      //Setter for stuck threshold
      virtual function void set_stuck_threshold(int unsigned value);
        if(value <= 2) begin
          `uvm_error("ALGORITHM_ISSUE", $sformatf("Tried to set stuck_threshold to value %d but the minimum length of an APB transfer is 2", value))
        end

        stuck_threshold = value;
      endfunction

      virtual task run_phase(uvm_phase phase);
        forever begin
          @(vif.has_checks);

          if(vif.has_checks != get_has_checks()) begin
            `uvm_error("ALGORITHM_ISSUE", $sformatf("Can not change \"has_checks\" from APB interface directly - use %0s.set_has_checks()", get_full_name()))
          end
        end
      endtask

      //Task for waiting the reset to start
      virtual task wait_reset_start();
        if(vif.preset_n !== 0) begin
          @(negedge vif.preset_n);
        end
      endtask

      //Task for waiting the reset to be finished
      virtual task wait_reset_end();
        while(vif.preset_n == 0) begin
          @(posedge vif.pclk);
        end
      endtask

    endclass

    class cfs_apb_monitor extends uvm_ext_monitor#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_MON(cfs_apb_item_mon));

      //Pointer to agent configuration
      cfs_apb_agent_config agent_config;

      `uvm_component_utils(cfs_apb_monitor)

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
      endfunction
      
      virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
         
        if($cast(agent_config, super.agent_config) == 0) begin
          `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Could not cast %0s to %0s", 
             super.agent_config.get_type_name(), cfs_apb_agent_config::type_id::type_name))
        end
      endfunction

      //Task which drives one single item on the bus
      protected virtual task collect_transaction();
        cfs_apb_vif vif = agent_config.get_vif();
        cfs_apb_item_mon item = cfs_apb_item_mon::type_id::create("item");

        while(vif.psel !== 1) begin
          @(posedge vif.pclk);
          item.prev_item_delay++;
        end

        item.addr   = vif.paddr;
        item.dir    = cfs_apb_dir'(vif.pwrite);
        item.length = 1;

        if(item.dir == CFS_APB_WRITE) begin
          item.data = vif.pwdata;
        end

        @(posedge vif.pclk);
        item.length++;

        while(vif.pready !== 1) begin
          @(posedge vif.pclk);
          item.length++;

          if(agent_config.get_has_checks()) begin
            if(item.length >= agent_config.get_stuck_threshold()) begin
              `uvm_error("PROTOCOL_ERROR", $sformatf("The APB transfer reached the stuck threshold value of %0d", item.length))
            end
          end
        end

        item.response = cfs_apb_response'(vif.pslverr);

        if(item.dir == CFS_APB_READ) begin
          item.data = vif.prdata;
        end
 
        output_port.write(item);

        `uvm_info("ITEM_END", $sformatf("Monitored item:: %0s", item.convert2string()), UVM_LOW)

        @(posedge vif.pclk);
      endtask

    endclass

    class cfs_apb_coverage extends uvm_ext_coverage#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_MON(cfs_apb_item_mon));

      //Pointer to agent configuration
      cfs_apb_agent_config agent_config;

      //Wrapper over the coverage group covering the indices in the PADDR signal
      //at which the bit of the PADDR was 0
      uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_ADDR_WIDTH) wrap_cover_addr_0;

      //Wrapper over the coverage group covering the indices in the PADDR signal
      //at which the bit of the PADDR was 1
      uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_ADDR_WIDTH) wrap_cover_addr_1;

      //Wrapper over the coverage group covering the indices in the PWDATA signal
      //at which the bit of the PWDATA was 0
      uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_DATA_WIDTH) wrap_cover_wr_data_0;

      //Wrapper over the coverage group covering the indices in the PWDATA signal
      //at which the bit of the PWDATA was 1
      uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_DATA_WIDTH) wrap_cover_wr_data_1;

      //Wrapper over the coverage group covering the indices in the PRDATA signal
      //at which the bit of the PRDATA was 0
      uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_DATA_WIDTH) wrap_cover_rd_data_0;

      //Wrapper over the coverage group covering the indices in the PRDATA signal
      //at which the bit of the PRDATA was 1
      uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_DATA_WIDTH) wrap_cover_rd_data_1;

      `uvm_component_utils(cfs_apb_coverage)

      covergroup cover_item with function sample(cfs_apb_item_mon item);
        option.per_instance = 1;

        direction : coverpoint item.dir {
          option.comment = "Direction of the APB access";
        }

        response : coverpoint item.response {
          option.comment = "Response of the APB access";
        }

        length : coverpoint item.length {
          option.comment = "Length of the APB access";
          bins length_eq_2     = {2};
          bins length_le_10[8] = {[3:10]};
          bins length_gt_10    = {[11:$]};

          illegal_bins length_lt_2 = {[$:1]};
        }

        prev_item_delay : coverpoint item.prev_item_delay {
          option.comment = "Delay, in clock cycles, between two consecutive APB accesses";
          bins back2back       = {0};
          bins delay_le_5[5]   = {[1:5]};
          bins delay_gt_5      = {[6:$]};
        }

        response_x_direction : cross response, direction;

        trans_direction : coverpoint item.dir {
          option.comment = "Transitions of APB direction";
          bins direction_trans[] = (CFS_APB_READ, CFS_APB_WRITE => CFS_APB_READ, CFS_APB_WRITE);
        }

      endgroup

      covergroup cover_reset with function sample(bit psel);
        option.per_instance = 1;

        access_ongoing : coverpoint psel {
          option.comment = "An APB access was ongoing at reset";
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

        wrap_cover_addr_0    = uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_ADDR_WIDTH)::type_id::create("wrap_cover_addr_0",    this);
        wrap_cover_addr_1    = uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_ADDR_WIDTH)::type_id::create("wrap_cover_addr_1",    this);
        wrap_cover_wr_data_0 = uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_DATA_WIDTH)::type_id::create("wrap_cover_wr_data_0", this);
        wrap_cover_wr_data_1 = uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_DATA_WIDTH)::type_id::create("wrap_cover_wr_data_1", this);
        wrap_cover_rd_data_0 = uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_DATA_WIDTH)::type_id::create("wrap_cover_rd_data_0", this);
        wrap_cover_rd_data_1 = uvm_ext_cover_index_wrapper#(`CFS_APB_MAX_DATA_WIDTH)::type_id::create("wrap_cover_rd_data_1", this);
      endfunction

      virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
         
        if($cast(agent_config, super.agent_config) == 0) begin
          `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Could not cast %0s to %0s", 
             super.agent_config.get_type_name(), cfs_apb_agent_config::type_id::type_name))
        end
      endfunction

      //Port associated with port_item port
      virtual function void write_item(cfs_apb_item_mon item);
        cover_item.sample(item);

        for(int i = 0; i < `CFS_APB_MAX_ADDR_WIDTH; i++) begin
          if(item.addr[i]) begin
            wrap_cover_addr_1.sample(i);
          end
          else begin
            wrap_cover_addr_0.sample(i);
          end
        end

        for(int i = 0; i < `CFS_APB_MAX_DATA_WIDTH; i++) begin
          case(item.dir)
            CFS_APB_WRITE : begin
              if(item.data[i]) begin
                wrap_cover_wr_data_1.sample(i);
              end
              else begin
                wrap_cover_wr_data_0.sample(i);
              end
            end
            CFS_APB_READ : begin
              if(item.data[i]) begin
                wrap_cover_rd_data_1.sample(i);
              end
              else begin
                wrap_cover_rd_data_0.sample(i);
              end
            end
            default : begin
              `uvm_error("ALGORITHM_ISSUE", $sformatf("Current version of the code does not support item.dir: %0s", item.dir.name()))
            end
          endcase 
        end
      endfunction

      //Function to handle the reset
      virtual function void handle_reset(uvm_phase phase);
        cfs_apb_vif vif = agent_config.get_vif();

        cover_reset.sample(vif.psel);
      endfunction

      //Function to print the coverage information.
      //This is only to be able to visualize some basic coverage information
      //in EDA Playground.
      //DON'T DO THIS IN A REAL PROJECT!!!
      virtual function string coverage2string();
        string result = {
          $sformatf("\n   cover_item:              %03.2f%%", cover_item.get_inst_coverage()),
          $sformatf("\n      direction:            %03.2f%%", cover_item.direction.get_inst_coverage()),
          $sformatf("\n      trans_direction:      %03.2f%%", cover_item.trans_direction.get_inst_coverage()),
          $sformatf("\n      response:             %03.2f%%", cover_item.response.get_inst_coverage()),
          $sformatf("\n      response_x_direction: %03.2f%%", cover_item.response_x_direction.get_inst_coverage()),
          $sformatf("\n      length:               %03.2f%%", cover_item.length.get_inst_coverage()),
          $sformatf("\n      prev_item_delay:      %03.2f%%", cover_item.prev_item_delay.get_inst_coverage()),
          $sformatf("\n                                    "),
          $sformatf("\n   cover_reset:             %03.2f%%", cover_reset.get_inst_coverage()),
          $sformatf("\n      access_ongoing:       %03.2f%%", cover_reset.access_ongoing.get_inst_coverage()),
          super.coverage2string()
        };

        return result;
      endfunction

    endclass

    class cfs_apb_driver extends uvm_ext_driver#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_DRV(cfs_apb_item_drv));

      //Pointer to agent configuration
      cfs_apb_agent_config agent_config;

      `uvm_component_utils(cfs_apb_driver)

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
      endfunction

      virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase); 
         
        if($cast(agent_config, super.agent_config) == 0) begin
          `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Could not cast %0s to %0s", 
             super.agent_config.get_type_name(), cfs_apb_agent_config::type_id::type_name))
        end
      endfunction

      //Task which drives one single item on the bus
      protected virtual task drive_transaction(cfs_apb_item_drv item);
        cfs_apb_vif vif = agent_config.get_vif();

        `uvm_info("ITEM_START", $sformatf("Driving \"%0s\": %0s", item.get_full_name(), item.convert2string()), UVM_LOW)

        for(int i = 0; i < item.pre_drive_delay; i++) begin
          @(posedge vif.pclk);
        end

        vif.psel   <= 1;
        vif.pwrite <= bit'(item.dir);
        vif.paddr  <= item.addr;

        if(item.dir == CFS_APB_WRITE) begin
          vif.pwdata <= item.data;
        end

        @(posedge vif.pclk);

        vif.penable <= 1;

        @(posedge vif.pclk);

        while(vif.pready !== 1) begin
          @(posedge vif.pclk);
        end

        vif.psel    <= 0;
        vif.penable <= 0;
        vif.pwrite  <= 0;
        vif.paddr   <= 0;
        vif.pwdata  <= 0;

        for(int i = 0; i < item.post_drive_delay; i++) begin
          @(posedge vif.pclk);
        end
      endtask

      //Function to handle the reset
      virtual function void handle_reset(uvm_phase phase);
        cfs_apb_vif vif = agent_config.get_vif();

        super.handle_reset(phase);

        //Initialize the signals
        vif.psel    <= 0;
        vif.penable <= 0;
        vif.pwrite  <= 0;
        vif.paddr   <= 0;
        vif.pwdata  <= 0;
      endfunction

    endclass

    class cfs_apb_agent extends uvm_ext_agent#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_MON(cfs_apb_item_mon), .ITEM_DRV(cfs_apb_item_drv));

      `uvm_component_utils(cfs_apb_agent)

      function new(string name = "", uvm_component parent);
        super.new(name, parent);
        
        uvm_ext_agent_config#(.VIRTUAL_INTF(cfs_apb_vif))::type_id::set_inst_override(cfs_apb_agent_config::get_type(), "agent_config", this);
        uvm_ext_monitor#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_MON(cfs_apb_item_mon))::type_id::set_inst_override(cfs_apb_monitor::get_type(), "monitor", this);
        uvm_ext_coverage#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_MON(cfs_apb_item_mon))::type_id::set_inst_override(cfs_apb_coverage::get_type(), "coverage", this);
        uvm_ext_driver#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_DRV(cfs_apb_item_drv))::type_id::set_inst_override(cfs_apb_driver::get_type(), "driver", this);
      endfunction

    endclass

    class cfs_apb_sequence_base extends uvm_sequence#(.REQ(cfs_apb_item_drv));

      `uvm_declare_p_sequencer(uvm_ext_sequencer#(.ITEM_DRV(cfs_apb_item_drv)))

      `uvm_object_utils(cfs_apb_sequence_base)

      function new(string name = "");
        super.new(name);
      endfunction

    endclass

    class cfs_apb_sequence_simple extends cfs_apb_sequence_base;

      //Item to drive
      rand cfs_apb_item_drv item;

      `uvm_object_utils(cfs_apb_sequence_simple)

      function new(string name = "");
        super.new(name);

        item = cfs_apb_item_drv::type_id::create("item");
      endfunction

      virtual task body();
        `uvm_send(item)
      endtask

    endclass

    class cfs_apb_sequence_rw extends cfs_apb_sequence_base;

      //Address
      rand cfs_apb_addr addr;

      //Write data
      rand cfs_apb_data wr_data;

      `uvm_object_utils(cfs_apb_sequence_rw)

      function new(string name = "");
        super.new(name);
      endfunction

      virtual task body();

        //The above code can be replaced with `uvm_do macros
        cfs_apb_item_drv item;

        `uvm_do_with(item, {
          dir  == CFS_APB_READ;
          addr == local::addr;
        });

        `uvm_do_with(item, {
          dir  == CFS_APB_WRITE;
          addr == local::addr;
          data == wr_data;
        });

      endtask

    endclass

    class cfs_apb_sequence_random extends cfs_apb_sequence_base;

      //NUmber of items to drive
      rand int unsigned num_items;

      constraint num_items_default {
        soft num_items inside {[1:10]}; 
      }

      `uvm_object_utils(cfs_apb_sequence_random)

      function new(string name = "");
        super.new(name);
      endfunction

      virtual task body();
        for(int i = 0; i < num_items; i++) begin
          cfs_apb_sequence_simple seq = cfs_apb_sequence_simple::type_id::create("seq");
          
          `uvm_do(seq)
        end
      endtask

    endclass

  class cfs_apb_reg_adapter extends uvm_reg_adapter;
    
    `uvm_object_utils(cfs_apb_reg_adapter)
    
    function new(string name = "");
      super.new(name);  
    endfunction
    
    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
      cfs_apb_item_mon item_mon;
      cfs_apb_item_drv item_drv;
      
      if($cast(item_mon, bus_item)) begin
        rw.kind = item_mon.dir == CFS_APB_WRITE? UVM_WRITE : UVM_READ;
        
        rw.addr   = item_mon.addr;
        rw.data   = item_mon.data;
        rw.status = item_mon.response == CFS_APB_OKAY ? UVM_IS_OK : UVM_NOT_OK;
      end
      else if($cast(item_drv, bus_item)) begin
        rw.kind = item_drv.dir == CFS_APB_WRITE? UVM_WRITE : UVM_READ;
        
        rw.addr   = item_drv.addr;
        rw.data   = item_drv.data;
        rw.status = UVM_IS_OK;
      end
      else begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Class not supported: %0s", bus_item.get_type_name()))
      end
      
    endfunction
    
    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      cfs_apb_item_drv item = cfs_apb_item_drv::type_id::create("item");
      
      void'(item.randomize() with {
        item.dir  == (rw.kind == UVM_WRITE) ? CFS_APB_WRITE : CFS_APB_READ;
        item.data == rw.data;
        item.addr == rw.addr;
      });
      
      return item;
    endfunction
    
  endclass


  endpackage

`endif