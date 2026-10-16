///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_reg_pkg.sv
// Author:      Cristian Florin Slav
// Date:        2024-05-27
// Description: Package containing the register definitions for the registers
//              in the Aligner module.
///////////////////////////////////////////////////////////////////////////////
`ifndef CFS_ALGN_REG_PKG_SV
  `define CFS_ALGN_REG_PKG_SV

  package cfs_algn_reg_pkg;
    import uvm_pkg::*;

  class cfs_algn_reg_ctrl extends uvm_reg;
    
    rand uvm_reg_field SIZE;

    rand uvm_reg_field OFFSET;

    rand uvm_reg_field CLR;
    
    local int unsigned ALGN_DATA_WIDTH;
    
    constraint legal_size {
      SIZE.value != 0;
    }
    
    constraint legal_size_offset {
      ((ALGN_DATA_WIDTH / 8) + OFFSET.value) % SIZE.value == 0;
      OFFSET.value + SIZE.value <= (ALGN_DATA_WIDTH / 8);
    }
    
    `uvm_object_utils(cfs_algn_reg_ctrl)
    
    function new(string name = "");
      super.new(.name(name), .n_bits(32), .has_coverage(UVM_NO_COVERAGE));
      
      ALGN_DATA_WIDTH = 8;
    endfunction
    
    virtual function void build();
      SIZE   = uvm_reg_field::type_id::create(.name("SIZE"),   .parent(null), .contxt(get_full_name()));
      OFFSET = uvm_reg_field::type_id::create(.name("OFFSET"), .parent(null), .contxt(get_full_name()));
      CLR    = uvm_reg_field::type_id::create(.name("CLR"),    .parent(null), .contxt(get_full_name()));
      
      SIZE.configure(
        .parent(                 this),
        .size(                   3),
        .lsb_pos(                0),
        .access(                 "RW"),
        .volatile(               0),
        .reset(                  3'b001),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      OFFSET.configure(
        .parent(                 this),
        .size(                   2),
        .lsb_pos(                8),
        .access(                 "RW"),
        .volatile(               0),
        .reset(                  2'b00),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      CLR.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                16),
        .access(                 "WO"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1), 
        .is_rand(                1),
        .individually_accessible(0));      
    endfunction
    
    virtual function void SET_ALGN_DATA_WIDTH(int unsigned value);
      //The minimum legal value for this field is 8.
      if(value < 8) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("The minimum legal value for ALGN_DATA_WIDTH is 8 but user tried to set it to %0d", value))
      end
      
      //The value must be a power of 2
      if($countones(value) != 1) begin
        `uvm_fatal("ALGORITHM_ISSUE", $sformatf("Thevalue for ALGN_DATA_WIDTH must be a power of 2 but user tried to set it to %0d", value))
      end
      
      ALGN_DATA_WIDTH = value;
    endfunction
    
    virtual function int unsigned GET_ALGN_DATA_WIDTH();
      return ALGN_DATA_WIDTH;
    endfunction

  endclass

  class cfs_algn_reg_status extends uvm_reg;
    
    rand uvm_reg_field CNT_DROP;

    rand uvm_reg_field RX_LVL;

    rand uvm_reg_field TX_LVL;
    
    `uvm_object_utils(cfs_algn_reg_status)
    
    function new(string name = "");
      super.new(.name(name), .n_bits(32), .has_coverage(UVM_NO_COVERAGE));
    endfunction
    
    virtual function void build();
      CNT_DROP = uvm_reg_field::type_id::create(.name("CNT_DROP"), .parent(null), .contxt(get_full_name()));
      RX_LVL   = uvm_reg_field::type_id::create(.name("RX_LVL"),   .parent(null), .contxt(get_full_name()));
      TX_LVL   = uvm_reg_field::type_id::create(.name("TX_LVL"),   .parent(null), .contxt(get_full_name()));
      
      CNT_DROP.configure(
        .parent(                 this),
        .size(                   8),
        .lsb_pos(                0),
        .access(                 "RO"),
        .volatile(               0),
        .reset(                  8'h00),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      RX_LVL.configure(
        .parent(                 this),
        .size(                   4),
        .lsb_pos(                8),
        .access(                 "RO"),
        .volatile(               0),
        .reset(                  4'h0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));

      TX_LVL.configure(
        .parent(                 this),
        .size(                   4),
        .lsb_pos(                16),
        .access(                 "RO"),
        .volatile(               0),
        .reset(                  4'h0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
    endfunction

  endclass

  class cfs_algn_reg_irqen extends uvm_reg;
    
    rand uvm_reg_field RX_FIFO_EMPTY;
    
    rand uvm_reg_field RX_FIFO_FULL;
    
    rand uvm_reg_field TX_FIFO_EMPTY;
    
    rand uvm_reg_field TX_FIFO_FULL;
    
    rand uvm_reg_field MAX_DROP;
    
    `uvm_object_utils(cfs_algn_reg_irqen)
    
    function new(string name = "");
      super.new(.name(name), .n_bits(32), .has_coverage(UVM_NO_COVERAGE));
    endfunction
    
    virtual function void build();
      RX_FIFO_EMPTY = uvm_reg_field::type_id::create(.name("RX_FIFO_EMPTY"), .parent(null), .contxt(get_full_name()));
      RX_FIFO_FULL  = uvm_reg_field::type_id::create(.name("RX_FIFO_FULL"),  .parent(null), .contxt(get_full_name()));
      TX_FIFO_EMPTY = uvm_reg_field::type_id::create(.name("TX_FIFO_EMPTY"), .parent(null), .contxt(get_full_name()));
      TX_FIFO_FULL  = uvm_reg_field::type_id::create(.name("TX_FIFO_FULL"),  .parent(null), .contxt(get_full_name()));
      MAX_DROP      = uvm_reg_field::type_id::create(.name("MAX_DROP"),      .parent(null), .contxt(get_full_name()));
      
      RX_FIFO_EMPTY.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                0),
        .access(                 "RW"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      RX_FIFO_FULL.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                1),
        .access(                 "RW"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      TX_FIFO_EMPTY.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                2),
        .access(                 "RW"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      TX_FIFO_FULL.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                3),
        .access(                 "RW"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      MAX_DROP.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                4),
        .access(                 "RW"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
    endfunction
  endclass

  class cfs_algn_reg_irq extends uvm_reg;
    
    rand uvm_reg_field RX_FIFO_EMPTY;
    
    rand uvm_reg_field RX_FIFO_FULL;
    
    rand uvm_reg_field TX_FIFO_EMPTY;
    
    rand uvm_reg_field TX_FIFO_FULL;
    
    rand uvm_reg_field MAX_DROP;
    
    `uvm_object_utils(cfs_algn_reg_irq)
    
    function new(string name = "");
      super.new(.name(name), .n_bits(32), .has_coverage(UVM_NO_COVERAGE));
    endfunction
    
    virtual function void build();
      RX_FIFO_EMPTY = uvm_reg_field::type_id::create(.name("RX_FIFO_EMPTY"), .parent(null), .contxt(get_full_name()));
      RX_FIFO_FULL  = uvm_reg_field::type_id::create(.name("RX_FIFO_FULL"),  .parent(null), .contxt(get_full_name()));
      TX_FIFO_EMPTY = uvm_reg_field::type_id::create(.name("TX_FIFO_EMPTY"), .parent(null), .contxt(get_full_name()));
      TX_FIFO_FULL  = uvm_reg_field::type_id::create(.name("TX_FIFO_FULL"),  .parent(null), .contxt(get_full_name()));
      MAX_DROP      = uvm_reg_field::type_id::create(.name("MAX_DROP"),      .parent(null), .contxt(get_full_name()));
      
      RX_FIFO_EMPTY.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                0),
        .access(                 "W1C"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      RX_FIFO_FULL.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                1),
        .access(                 "W1C"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      TX_FIFO_EMPTY.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                2),
        .access(                 "W1C"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      TX_FIFO_FULL.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                3),
        .access(                 "W1C"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      MAX_DROP.configure(
        .parent(                 this),
        .size(                   1),
        .lsb_pos(                4),
        .access(                 "W1C"),
        .volatile(               0),
        .reset(                  1'b0),
        .has_reset(              1),
        .is_rand(                1),
        .individually_accessible(0));
      
      RX_FIFO_EMPTY.value.rand_mode(1);
      RX_FIFO_FULL.value.rand_mode(1);
      TX_FIFO_EMPTY.value.rand_mode(1);
      TX_FIFO_FULL.value.rand_mode(1);
      MAX_DROP.value.rand_mode(1);
    endfunction
  endclass

  class cfs_algn_reg_block extends uvm_reg_block;

    rand cfs_algn_reg_ctrl   CTRL;
    
    rand cfs_algn_reg_status STATUS;
    
    rand cfs_algn_reg_irqen  IRQEN;
    
    rand cfs_algn_reg_irq    IRQ;
    
    
    `uvm_object_utils(cfs_algn_reg_block)
    
    function new(string name = "");
      super.new(name, UVM_NO_COVERAGE);
    endfunction
    
    virtual function void build();
      default_map = create_map(
        .name(           "apb_map"),
        .base_addr(      'h0000),
        .n_bytes(        4),
        .endian(         UVM_LITTLE_ENDIAN),
        .byte_addressing(1)
      );
      
      default_map.set_check_on_read(1);
      
      CTRL   = cfs_algn_reg_ctrl::type_id::create(  .name("CTRL"),   .parent(null), .contxt(get_full_name()));
      STATUS = cfs_algn_reg_status::type_id::create(.name("STATUS"), .parent(null), .contxt(get_full_name()));
      IRQEN  = cfs_algn_reg_irqen::type_id::create( .name("IRQEN"),  .parent(null), .contxt(get_full_name()));
      IRQ    = cfs_algn_reg_irq::type_id::create(   .name("IRQ"),    .parent(null), .contxt(get_full_name()));
      
      CTRL.configure(  .blk_parent(this));
      STATUS.configure(.blk_parent(this));
      IRQEN.configure( .blk_parent(this));
      IRQ.configure(   .blk_parent(this));
      
      CTRL.build();
      STATUS.build();
      IRQEN.build();
      IRQ.build();
      
      default_map.add_reg(.rg(CTRL),   .offset('h0000), .rights("RW"));
      default_map.add_reg(.rg(STATUS), .offset('h000C), .rights("RO"));
      default_map.add_reg(.rg(IRQEN),  .offset('h00F0), .rights("RW"));
      default_map.add_reg(.rg(IRQ),    .offset('h00F4), .rights("RW"));
      
    endfunction
    
  endclass


  endpackage

`endif
