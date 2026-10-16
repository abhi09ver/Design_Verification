///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_model.sv
// Author:      Cristian Florin Slav
// Date:        2024-06-19
// Description: Model of the Aligner
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_ALGN_MODEL_SV
  `define CFS_ALGN_MODEL_SV

  `uvm_analysis_imp_decl(_in_rx) 
  `uvm_analysis_imp_decl(_in_tx)
  
  class cfs_algn_model extends uvm_component implements uvm_ext_reset_handler;
    
    //Pointer to the environment configuration
    cfs_algn_env_config env_config;
 
    //Register block
    cfs_algn_reg_block reg_block;
    
    //Analysis implementation port for receiving information from RX side
    uvm_analysis_imp_in_rx#(cfs_md_item_mon, cfs_algn_model) port_in_rx;
    
    //Analysis implementation port for receiving information from TX side
    uvm_analysis_imp_in_tx#(cfs_md_item_mon, cfs_algn_model) port_in_tx;
    
    //Port for sending the expected response on the RX interface
    uvm_analysis_port#(cfs_md_response) port_out_rx;
    
    //Port for sending the expected response on the TX interface
    uvm_analysis_port#(cfs_md_item_mon) port_out_tx;
    
    //Port for sending the expected interrupt request
    uvm_analysis_port#(bit) port_out_irq;
    
    //Port for sending the split information
    uvm_analysis_port#(cfs_algn_split_info) port_out_split_info;
     
    
    //Model of the RX FIFO
    protected uvm_tlm_fifo#(cfs_md_item_mon) rx_fifo; 
    
    //Model of the TX FIFO
    protected uvm_tlm_fifo#(cfs_md_item_mon) tx_fifo;
    
    //Intermediate buffer containing information ready to be aligned
    protected cfs_md_item_mon buffer[$];
    
    //Event to synchronize the completing of the TX transaction
    protected uvm_event tx_complete;

    //Buffered value of the expected interrupt request
    protected bit exp_irq;

    
    //Pointer to the process of the task push_to_rx_fifo()
    local process process_push_to_rx_fifo;
    
    //Pointer to the process of the task build_buffer()
    local process process_build_buffer;
    
    //Pointer to the process of the task align()
    local process process_align;
    
    //Pointer to the process of the task tx_ctrl()
    local process process_tx_ctrl;
    
    //Pointer to the process from inside function set_rx_fifo_empty()
    local process process_set_rx_fifo_empty;
    
    //Pointer to the process from inside function set_rx_fifo_full()
    local process process_set_rx_fifo_full;
    
    //Pointer to the process from inside function set_tx_fifo_empty()
    local process process_set_tx_fifo_empty;
    
    //Pointer to the process from inside function set_tx_fifo_full()
    local process process_set_tx_fifo_full;
    
    //Pointer to the process of the task send_exp_irq()
    local process process_send_exp_irq;
    
    
    `uvm_component_utils(cfs_algn_model)
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);  
      
      port_in_rx          = new("port_in_rx",   this); 
      port_in_tx          = new("port_in_tx",   this);
      port_out_rx         = new("port_out_rx",  this);
      port_out_tx         = new("port_out_tx",  this);
      port_out_irq        = new("port_out_irq", this);
      port_out_split_info = new("port_out_split_info", this);
      
      rx_fifo      = new("rx_fifo", this, 8);
      tx_fifo      = new("tx_fifo", this, 8);
      
      tx_complete = new("tx_complete");
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      
      if(reg_block == null) begin
        reg_block = cfs_algn_reg_block::type_id::create("reg_block", this);
        
        reg_block.build();
        reg_block.lock_model();
      end
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
      cfs_algn_clr_cnt_drop cbs = cfs_algn_clr_cnt_drop::type_id::create("cbs", this); 
      
      super.connect_phase(phase);
      
      //Connect the pointer to CNT_DROP
      cbs.cnt_drop = reg_block.STATUS.CNT_DROP;
      
      //Register the callback
      uvm_callbacks#(uvm_reg_field, cfs_algn_clr_cnt_drop)::add(reg_block.CTRL.CLR, cbs);
    endfunction
    
    virtual function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      
      reg_block.CTRL.SET_ALGN_DATA_WIDTH(env_config.get_algn_data_width());
    endfunction
    
    //Function to kill a process
    virtual function void kill_process(ref process p);
      if(p != null) begin
        p.kill();
        
        p = null;
      end
    endfunction
    
    virtual function void handle_reset(uvm_phase phase);
      reg_block.reset("HARD");
      
      kill_process(process_push_to_rx_fifo);
      kill_process(process_build_buffer);
      kill_process(process_align);
      kill_process(process_tx_ctrl);
      kill_process(process_send_exp_irq);
      
      kill_process(process_set_rx_fifo_empty);
      kill_process(process_set_rx_fifo_full);
      kill_process(process_set_tx_fifo_empty);
      kill_process(process_set_tx_fifo_full);
      
      tx_complete.reset();
      
      rx_fifo.flush();
      tx_fifo.flush();
      buffer = {};
      exp_irq = 0;
      
      build_buffer_nb();
      align_nb();
      tx_ctrl_nb();
      send_exp_irq_nb();
    endfunction
    
    //Function to determine if the model is empty
    virtual function bit is_empty();
      if(rx_fifo.used() != 0) begin
        return 0;
      end 
      
      if(tx_fifo.used() != 0) begin
        return 0;
      end 
      
      if(buffer.size() != 0) begin
        return 0;
      end 
      
      return 1;
    endfunction
    
    //Get the expected response
    protected virtual function cfs_md_response get_exp_response(cfs_md_item_mon item);
      //Size of the access is 0.
      if(item.data.size() == 0) begin
        return CFS_MD_ERR;
      end
      
      //Illegal combination between size and offset: (aligner data width + offset) % size != 0
      if(((env_config.get_algn_data_width() / 8) + item.offset) % item.data.size() != 0) begin
        return CFS_MD_ERR;
      end
      
      //Illegal combination between size and offset: size + offset > aligner data width
      if(item.offset + item.data.size() > (env_config.get_algn_data_width() / 8)) begin
        return CFS_MD_ERR;
      end
      
      return CFS_MD_OKAY;
    endfunction
    
    //Function for setting IRQ.MAX_DROP flag
    protected virtual function void set_max_drop();
      void'(reg_block.IRQ.MAX_DROP.predict(1));
      
      `uvm_info("CNT_DROP", $sformatf("Drop counter reached max value - %0s: %0d",
                                   reg_block.IRQEN.MAX_DROP.get_full_name(),
                                      reg_block.IRQEN.MAX_DROP.get_mirrored_value()), UVM_MEDIUM)
      
      if(reg_block.IRQEN.MAX_DROP.get_mirrored_value() == 1) begin
        exp_irq = 1;
      end
    endfunction
    
    //Function for setting IRQ.RX_FIFO_FULL flag
    protected virtual function void set_rx_fifo_full();
      fork
        begin 
          process_set_rx_fifo_full = process::self();
          
          repeat(2) begin
            uvm_wait_for_nba_region();  
          end 
          
          void'(reg_block.IRQ.RX_FIFO_FULL.predict(1));

          `uvm_info("RX_FIFO", $sformatf("RX FIFO became full - %0s: %0d",
                                       reg_block.IRQEN.RX_FIFO_FULL.get_full_name(),
                                       reg_block.IRQEN.RX_FIFO_FULL.get_mirrored_value()), UVM_MEDIUM)

          if(reg_block.IRQEN.RX_FIFO_FULL.get_mirrored_value() == 1) begin
            exp_irq = 1;
          end
          
          process_set_rx_fifo_full = null;
        end
      join_none
    endfunction 
    
    //Function for setting IRQ.RX_FIFO_EMPTY flag
    protected virtual function void set_rx_fifo_empty();
      fork
        begin
          process_set_rx_fifo_empty = process::self();
          
          repeat(2) begin
            uvm_wait_for_nba_region();  
          end 
          
          void'(reg_block.IRQ.RX_FIFO_EMPTY.predict(1));

          `uvm_info("RX_FIFO", $sformatf("RX FIFO became empty - %0s: %0d",
                                       reg_block.IRQEN.RX_FIFO_EMPTY.get_full_name(),
                                       reg_block.IRQEN.RX_FIFO_EMPTY.get_mirrored_value()), UVM_MEDIUM)
 
          if(reg_block.IRQEN.RX_FIFO_EMPTY.get_mirrored_value() == 1) begin
            exp_irq = 1;
          end
          
          process_set_rx_fifo_empty = null;
        end
      join_none
    endfunction 
    
    //Function for setting IRQ.TX_FIFO_FULL flag
    protected virtual function void set_tx_fifo_full();
      fork
        begin
          process_set_tx_fifo_full = process::self();
          
          repeat(2) begin
            uvm_wait_for_nba_region();  
          end 
          
          void'(reg_block.IRQ.TX_FIFO_FULL.predict(1));

          `uvm_info("TX_FIFO", $sformatf("TX FIFO became full - %0s: %0d",
                                       reg_block.IRQEN.TX_FIFO_FULL.get_full_name(),
                                       reg_block.IRQEN.TX_FIFO_FULL.get_mirrored_value()), UVM_MEDIUM)

          if(reg_block.IRQEN.TX_FIFO_FULL.get_mirrored_value() == 1) begin
            exp_irq = 1;
          end
          
          process_set_tx_fifo_full = null;
        end
      join_none
    endfunction 
    
    //Function for setting IRQ.TX_FIFO_EMPTY flag
    protected virtual function void set_tx_fifo_empty();
      fork
        begin
          process_set_tx_fifo_empty = process::self();
          
          repeat(2) begin
            uvm_wait_for_nba_region();  
          end 
          
          void'(reg_block.IRQ.TX_FIFO_EMPTY.predict(1));

          `uvm_info("TX_FIFO", $sformatf("TX FIFO became empty - %0s: %0d",
                                       reg_block.IRQEN.TX_FIFO_EMPTY.get_full_name(),
                                       reg_block.IRQEN.TX_FIFO_EMPTY.get_mirrored_value()), UVM_MEDIUM)

          if(reg_block.IRQEN.TX_FIFO_EMPTY.get_mirrored_value() == 1) begin
            exp_irq = 1;
          end
          
          process_set_tx_fifo_empty = null;
        end
      join_none
    endfunction 
    
    //Function for killing a process from within function set_rx_fifo_full()
    protected virtual function void kill_set_rx_fifo_full();
      fork
        begin
          uvm_wait_for_nba_region();  
          
          kill_process(process_set_rx_fifo_full);
        end
      join_none
    endfunction
    
    //Function for killing a process from within function set_rx_fifo_empty()
    protected virtual function void kill_set_rx_fifo_empty();
      fork
        begin
          uvm_wait_for_nba_region();  
          
          kill_process(process_set_rx_fifo_empty);
        end
      join_none
    endfunction
    
    //Function for killing a process from within function set_tx_fifo_full()
    protected virtual function void kill_set_tx_fifo_full();
      fork
        begin
          uvm_wait_for_nba_region();  
          
          kill_process(process_set_tx_fifo_full);
        end
      join_none
    endfunction
    
    //Function for killing a process from within function set_tx_fifo_empty()
    protected virtual function void kill_set_tx_fifo_empty();
      fork
        begin
          uvm_wait_for_nba_region();  
          
          kill_process(process_set_tx_fifo_empty);
        end
      join_none
    endfunction
    
    //Function to increment STATUS.CNT_DROP whenever an error is detected
    protected virtual function void inc_cnt_drop(cfs_md_response response);
      uvm_reg_data_t max_value = ('h1 << reg_block.STATUS.CNT_DROP.get_n_bits()) - 1;
      
      if(reg_block.STATUS.CNT_DROP.get_mirrored_value() < max_value) begin
        void'(reg_block.STATUS.CNT_DROP.predict(reg_block.STATUS.CNT_DROP.get_mirrored_value() + 1));
        
        `uvm_info("CNT_DROP", $sformatf("Increment %9s: %0d due to: %0s",
                                     reg_block.STATUS.CNT_DROP.get_full_name(),
                                     reg_block.STATUS.CNT_DROP.get_mirrored_value,
                                        response.name()), UVM_LOW)
        
        if(reg_block.STATUS.CNT_DROP.get_mirrored_value() == max_value) begin
          set_max_drop();
        end
      end
      
    endfunction
    
    //Function to increment STATUS.RX_LVL whenever new data is pushed in RX FIFO
    protected virtual function void inc_rx_lvl();
      void'(reg_block.STATUS.RX_LVL.predict(reg_block.STATUS.RX_LVL.get_mirrored_value() + 1));
      
      if(reg_block.STATUS.RX_LVL.get_mirrored_value() == rx_fifo.size()) begin
        set_rx_fifo_full();
      end
    endfunction
    
    //Function to decrement STATS.RX_LVL whenever data is popped from RX FIFO
    protected virtual function void dec_rx_lvl();
      void'(reg_block.STATUS.RX_LVL.predict(reg_block.STATUS.RX_LVL.get_mirrored_value() - 1));
      
      if(reg_block.STATUS.RX_LVL.get_mirrored_value() == 0) begin
        set_rx_fifo_empty();
      end
    endfunction
    
    //Function to increment STATUS.TX_LVL whenever new data is pushed in TX FIFO
    protected virtual function void inc_tx_lvl();
      void'(reg_block.STATUS.TX_LVL.predict(reg_block.STATUS.TX_LVL.get_mirrored_value() + 1));
      
      if(reg_block.STATUS.TX_LVL.get_mirrored_value() == tx_fifo.size()) begin
        set_tx_fifo_full();
      end
    endfunction
    
    //Function to decrement STATUS.TX_LVL whenever data is popped from TX FIFO
    protected virtual function void dec_tx_lvl();
      void'(reg_block.STATUS.TX_LVL.predict(reg_block.STATUS.TX_LVL.get_mirrored_value() - 1));
      
      if(reg_block.STATUS.TX_LVL.get_mirrored_value() == 0) begin
        set_tx_fifo_empty();
      end
    endfunction
    
    //Task for trying to synchronize a push to RX FIFO with RTL
    protected virtual task sync_push_to_rx_fifo();
      cfs_algn_vif vif = env_config.get_vif();
      
      fork
        begin
          fork
            begin
              @(posedge vif.clk iff(vif.rx_fifo_push)); 
            end
            begin
              repeat(10) begin
                 @(posedge vif.clk iff(reg_block.STATUS.RX_LVL.get_mirrored_value() < rx_fifo.size())); 
              end
              
              `uvm_warning("DUT_WARNING", "RX FIFO push did NOT synchronize with RTL")
            end
          join_any
          
          disable fork;
        end
      join
    endtask
    
    //Task for trying to synchronize a pop from RX FIFO with RTL
    protected virtual task sync_pop_from_rx_fifo();
      cfs_algn_vif vif = env_config.get_vif();
      
      fork
        begin
          fork
            begin
              @(posedge vif.clk iff(vif.rx_fifo_pop)); 
            end
            begin
              repeat(10) begin
                 @(posedge vif.clk iff((reg_block.STATUS.RX_LVL.get_mirrored_value() > 0) && (reg_block.STATUS.TX_LVL.get_mirrored_value() < tx_fifo.size()))); 
              end
              
              `uvm_warning("DUT_WARNING", "RX FIFO pop did NOT synchronize with RTL")
            end
          join_any
          
          disable fork;
        end
      join
    endtask
    
    //Task for trying to synchronize a push to TX FIFO with RTL
    protected virtual task sync_push_to_tx_fifo();
      cfs_algn_vif vif = env_config.get_vif();
      
      fork
        begin
          fork
            begin
              @(posedge vif.clk iff(vif.tx_fifo_push)); 
            end
            begin
              repeat(10) begin
                 @(posedge vif.clk iff(reg_block.STATUS.TX_LVL.get_mirrored_value() < tx_fifo.size())); 
              end
              
              `uvm_warning("DUT_WARNING", "TX FIFO push did NOT synchronize with RTL")
            end
          join_any
          
          disable fork;
        end
      join
    endtask
    
    //Task for trying to synchronize a pop from TX FIFO with RTL
    protected virtual task sync_pop_from_tx_fifo();
      cfs_algn_vif vif = env_config.get_vif();
      
      fork
        begin
          fork
            begin
             @(posedge vif.clk iff(vif.tx_fifo_pop)); 
            end
            begin
              repeat(200) begin
                 @(posedge vif.clk iff(reg_block.STATUS.TX_LVL.get_mirrored_value() > 0)); 
              end
              
              `uvm_warning("DUT_WARNING", "TX FIFO pop did NOT synchronize with RTL")
            end
          join_any
          
          disable fork;
        end
      join
    endtask
    
    //Task to push to RX FIFO the incoming data
    protected virtual task push_to_rx_fifo(cfs_md_item_mon item);
      sync_push_to_rx_fifo();
      
      rx_fifo.put(item);
      
      kill_set_rx_fifo_empty();
      
      inc_rx_lvl(); 
      
      `uvm_info("RX_FIFO", $sformatf("RX FIFO push - new level: %0d, pushed entry: %0s",
                                   reg_block.STATUS.RX_LVL.get_mirrored_value(),
                                     item.convert2string()), UVM_LOW)
      
      port_out_rx.write(CFS_MD_OKAY);
    endtask
    
    //Task to pop from RX FIFO
    protected virtual task pop_from_rx_fifo(ref cfs_md_item_mon item);
      sync_pop_from_rx_fifo();
      
      rx_fifo.get(item);
      
      kill_set_rx_fifo_full();
      
      dec_rx_lvl();
      
      `uvm_info("RX_FIFO", $sformatf("RX FIFO pop - new level: %0d, popped entry: %0s",
                                   reg_block.STATUS.RX_LVL.get_mirrored_value(),
                                     item.convert2string()), UVM_LOW)
    endtask
    
    //Task to push to TX FIFO the aligned data
    protected virtual task push_to_tx_fifo(cfs_md_item_mon item);
      sync_push_to_tx_fifo();
      
      tx_fifo.put(item);
      
      kill_set_tx_fifo_empty();
      
      inc_tx_lvl();
      
      `uvm_info("TX_FIFO", $sformatf("TX FIFO push - new level: %0d, pushed entry: %0s",
                                   reg_block.STATUS.TX_LVL.get_mirrored_value(),
                                     item.convert2string()), UVM_LOW)
    endtask
    
    //Task to pop from TX FIFO the aligned data
    protected virtual task pop_from_tx_fifo(ref cfs_md_item_mon item);
      sync_pop_from_tx_fifo();
      
      tx_fifo.get(item);
      
      kill_set_tx_fifo_full();
      
      dec_tx_lvl();
      
      `uvm_info("TX_FIFO", $sformatf("TX FIFO pop - new level: %0d, popped entry: %0s",
                                   reg_block.STATUS.TX_LVL.get_mirrored_value(),
                                     item.convert2string()), UVM_LOW)
    endtask
    
    //Task for building the buffer
    protected virtual task build_buffer(); 
      cfs_algn_vif vif = env_config.get_vif();
      
      forever begin
        int unsigned ctrl_size   = reg_block.CTRL.SIZE.get_mirrored_value();
        
        if((buffer.sum() with (item.data.size())) <= ctrl_size) begin
          cfs_md_item_mon rx_item;
          
          pop_from_rx_fifo(rx_item);
          
          buffer.push_back(rx_item);
        end
        else begin
          @(posedge vif.clk);
        end
      end
    endtask
    
    //Task for performing the align logic
    protected virtual task align();
      cfs_algn_vif vif = env_config.get_vif();
      
      forever begin
        int unsigned ctrl_size   = reg_block.CTRL.SIZE.get_mirrored_value();
        int unsigned ctrl_offset = reg_block.CTRL.OFFSET.get_mirrored_value();
        
        uvm_wait_for_nba_region();
        
        if(ctrl_size <= (buffer.sum() with (item.data.size()))) begin
          while(ctrl_size <= (buffer.sum() with (item.data.size()))) begin
          	cfs_md_item_mon tx_item = cfs_md_item_mon::type_id::create("tx_item", this);
          
          	tx_item.offset = ctrl_offset;
          	
            void'(tx_item.begin_tr(buffer[0].get_begin_time()));
            
            while(tx_item.data.size() != ctrl_size) begin
              cfs_md_item_mon buffer_item = buffer.pop_front();
              
              if(tx_item.data.size() + buffer_item.data.size() <= ctrl_size) begin
                
                foreach(buffer_item.data[idx]) begin
                  tx_item.data.push_back(buffer_item.data[idx]);
                end
                
                if(tx_item.data.size() == ctrl_size) begin
                  tx_item.end_tr(buffer_item.get_end_time());
                  
                  push_to_tx_fifo(tx_item);
                end
              end 
              else begin
                int unsigned num_bytes_needed = ctrl_size - tx_item.data.size();
                
                cfs_md_item_mon splitted_items[$];
                
                split(num_bytes_needed, buffer_item, splitted_items);
                
                buffer.push_front(splitted_items[1]);
                buffer.push_front(splitted_items[0]);
                
                begin
                  cfs_algn_split_info info = cfs_algn_split_info::type_id::create("info", this);
                  
                  info.ctrl_offset         = ctrl_offset;
                  info.ctrl_size           = ctrl_size;
                  info.md_offset           = buffer_item.offset;
                  info.md_size             = buffer_item.data.size();
                  info.num_bytes_needed    = num_bytes_needed;
                  
                  port_out_split_info.write(info);
                end 
              end
            end
          
          end
        end
        else begin
          @(posedge vif.clk);
        end
      end 
    endtask
    
    //Function to split an item in two
    protected virtual function void split(int unsigned num_bytes, cfs_md_item_mon item, ref cfs_md_item_mon items[$]);
      if((num_bytes == 0) || (num_bytes >= item.data.size())) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Can not split an item using as num_bytes a value of %0d. The size of the data queue in the item is %0d",
                                                num_bytes, item.data.size()))
      end 
      
      for(int i = 0; i < 2; i++) begin
        cfs_md_item_mon splitted_item = cfs_md_item_mon::type_id::create("splitted_item", this);
        
        if(i == 0) begin
          splitted_item.offset = item.offset;
          
          for(int j = 0; j < num_bytes; j++) begin
            splitted_item.data.push_back(item.data[j]);
          end
        end 
        else begin
          splitted_item.offset = item.offset + num_bytes;
          
          for(int j = num_bytes; j < item.data.size(); j++) begin
            splitted_item.data.push_back(item.data[j]);
          end
        end
        
        splitted_item.prev_item_delay = item.prev_item_delay;
        splitted_item.length          = item.length;
        splitted_item.response        = item.response;
        
        void'(splitted_item.begin_tr(item.get_begin_time()));
        
        if(!item.is_active()) begin
          splitted_item.end_tr(item.get_end_time());
        end 
        
        items.push_back(splitted_item);
      end
    endfunction
    
    //Task to model the TX Controller
    protected virtual task tx_ctrl();
      cfs_md_item_mon item;
      
      forever begin
        pop_from_tx_fifo(item);
        
        port_out_tx.write(item);
        
        tx_complete.wait_trigger();
      end
    endtask
       
    //Task for sending the expected interrupt request
    protected virtual task send_exp_irq();
      cfs_algn_vif vif = env_config.get_vif();
      
      forever begin
        @(negedge vif.clk);
        
        if(exp_irq == 1) begin
          port_out_irq.write(exp_irq);
          
          exp_irq = 0;
        end 
      end 
    endtask
    
    //Function to push to RX FIFO the incoming data
    local virtual function void push_to_rx_fifo_nb(cfs_md_item_mon item);
      if(process_push_to_rx_fifo != null) begin
        `uvm_fatal("ALGORITHM_ISSUE", "Can not start two instances of push_to_rx_fifo() tasks")
      end
      
      fork
        begin
          process_push_to_rx_fifo = process::self();
          
          push_to_rx_fifo(item);
          
          process_push_to_rx_fifo = null;
        end
      join_none
      
    endfunction
    
    //Function start the build_buffer() task
    local virtual function void build_buffer_nb();
      if(process_build_buffer != null) begin
        `uvm_fatal("ALGORITHM_ISSUE", "Can not start two instances of build_buffer() tasks")
      end
      
      fork
        begin
          process_build_buffer = process::self();
          
          build_buffer();
          
          process_build_buffer = null;
        end
      join_none
      
    endfunction
    
    //Function start the align() task
    local virtual function void align_nb();
      if(process_align != null) begin
        `uvm_fatal("ALGORITHM_ISSUE", "Can not start two instances of align() tasks")
      end
      
      fork
        begin
          process_align = process::self();
          
          align();
          
          process_align = null;
        end
      join_none
      
    endfunction
    
    //Function start the tx_ctrl() task
    local virtual function void tx_ctrl_nb();
      if(process_tx_ctrl != null) begin
        `uvm_fatal("ALGORITHM_ISSUE", "Can not start two instances of tx_ctrl() tasks")
      end
      
      fork
        begin
          process_tx_ctrl = process::self();
          
          tx_ctrl();
          
          process_tx_ctrl = null;
        end
      join_none
      
    endfunction
    
    //Function start the send_exp_irq() task
    local virtual function void send_exp_irq_nb();
      if(process_send_exp_irq != null) begin
        `uvm_fatal("ALGORITHM_ISSUE", "Can not start two instances of send_exp_irq() tasks")
      end
      
      fork
        begin
          process_send_exp_irq = process::self();
          
          send_exp_irq();
          
          process_send_exp_irq = null;
        end
      join_none
      
    endfunction
     
    
    virtual function void write_in_rx(cfs_md_item_mon item_mon);
      if(item_mon.is_active()) begin
        cfs_md_response exp_response = get_exp_response(item_mon);
        
        case(exp_response)
          CFS_MD_ERR : begin
            inc_cnt_drop(exp_response);
            
            port_out_rx.write(exp_response);
          end
          CFS_MD_OKAY : begin
             push_to_rx_fifo_nb(item_mon);
          end
          default : begin
            `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Un-supported value for exp_response: %0s", exp_response.name()))
          end
        endcase
      end
    endfunction
    
    virtual function void write_in_tx(cfs_md_item_mon item_mon);
      if(!item_mon.is_active()) begin
        tx_complete.trigger();
      end 
    endfunction
    
  endclass

`endif