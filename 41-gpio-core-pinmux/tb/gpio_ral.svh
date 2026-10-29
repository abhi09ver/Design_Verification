// -----------------------------------------------------------------------------
// gpio_ral.svh : UVM register model for GPIO v1.0 (User Guide Table 6.1)
//
// Access types worth explaining in an interview:
//   i_data, sts_raw : RO + volatile (hardware changes them)
//   intr_sts        : W1C + volatile. The UG table says RO, but the text says
//                     write-1-to-clear. W1C is the correct model (spec gap).
//   intr_set        : WO, reads expected to return 0
// Volatile fields have compare turned off; gpio_intr_model predicts them.
// -----------------------------------------------------------------------------

// One per-pin vector register: a single field of GPIO_W bits at bit 0.
// Bits [31:GPIO_W] are reserved and read 0 (checked by SVA and the model).
class gpio_vec_reg extends uvm_reg;
  `uvm_object_utils(gpio_vec_reg)
  uvm_reg_field  f;
  string         m_access = "RW";
  bit            m_volatile;
  uvm_reg_data_t m_reset;

  function new(string name = "gpio_vec_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  function void setup(string access, bit volatile_f, uvm_reg_data_t reset_val);
    m_access   = access;
    m_volatile = volatile_f;
    m_reset    = reset_val;
  endfunction

  virtual function void build();
    f = uvm_reg_field::type_id::create("f");
    //          parent size    lsb access    volatile    reset    has_rst rand indiv
    f.configure(this, GPIO_W, 0, m_access, m_volatile, m_reset, 1,      1,   0);
  endfunction
endclass : gpio_vec_reg


class gpio_glb_reg extends uvm_reg;
  `uvm_object_utils(gpio_glb_reg)
  rand uvm_reg_field gie;   // [0] global interrupt enable
  rand uvm_reg_field gme;   // [1] global mask enable

  function new(string name = "gpio_glb_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    gie = uvm_reg_field::type_id::create("gie");
    gme = uvm_reg_field::type_id::create("gme");
    gie.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    gme.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);
  endfunction
endclass : gpio_glb_reg


class gpio_reg_block extends uvm_reg_block;
  `uvm_object_utils(gpio_reg_block)

  gpio_vec_reg i_data, o_data, io_dir;
  gpio_glb_reg glb;
  gpio_vec_reg intr_en, intr_mask, intr_type, intr_evnt;
  gpio_vec_reg intr_sts, intr_sts_raw, intr_set;

  function new(string name = "gpio_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  local function gpio_vec_reg add_vec(string name, bit [7:0] offset, string access,
                                      bit volatile_f, uvm_reg_data_t reset_val);
    string rights;
    gpio_vec_reg r = gpio_vec_reg::type_id::create(name);
    r.setup(access, volatile_f, reset_val);
    r.configure(this);
    r.build();
    rights = (access == "RO") ? "RO" : (access == "WO") ? "WO" : "RW";
    default_map.add_reg(r, offset, rights);
    return r;
  endfunction

  function void build_model(gpio_cfg cfg);
    default_map  = create_map("map", 0, 4, UVM_LITTLE_ENDIAN, 1);

    i_data       = add_vec("i_data",       ADDR_I_DATA,   "RO",  1, 0);
    o_data       = add_vec("o_data",       ADDR_O_DATA,   "RW",  0, cfg.def_o_val);
    io_dir       = add_vec("io_dir",       ADDR_IO_DIR,   "RW",  0, cfg.def_io_dir);

    glb = gpio_glb_reg::type_id::create("glb");
    glb.configure(this);
    glb.build();
    default_map.add_reg(glb, ADDR_GLB, "RW");

    intr_en      = add_vec("intr_en",      ADDR_INTR_EN,  "RW",  0, 0);
    intr_mask    = add_vec("intr_mask",    ADDR_INTR_MSK, "RW",  0, 0);
    intr_type    = add_vec("intr_type",    ADDR_INTR_TYP, "RW",  0, 0);
    intr_evnt    = add_vec("intr_evnt",    ADDR_INTR_EVT, "RW",  0, 0);
    intr_sts     = add_vec("intr_sts",     ADDR_INTR_STS, "W1C", 1, 0);
    intr_sts_raw = add_vec("intr_sts_raw", ADDR_STS_RAW,  "RO",  1, 0);
    intr_set     = add_vec("intr_set",     ADDR_INTR_SET, "WO",  0, 0);

    // Hardware-updated fields: the reference model checks these, not the mirror.
    i_data.f.set_compare(UVM_NO_CHECK);
    intr_sts.f.set_compare(UVM_NO_CHECK);
    intr_sts_raw.f.set_compare(UVM_NO_CHECK);

    lock_model();
  endfunction

  // Keep the built-in register sequences away from fields they can't handle.
  function void exclude_from_builtin_seqs(uvm_component ctx);
    uvm_reg skip_bash[$] = '{i_data, intr_sts, intr_sts_raw, intr_set};
    foreach (skip_bash[k])
      uvm_resource_db#(bit)::set({"REG::", skip_bash[k].get_full_name()},
                                 "NO_REG_BIT_BASH_TEST", 1, ctx);
    // i_data follows the pins, so it has no fixed reset value; intr_set is WO.
    uvm_resource_db#(bit)::set({"REG::", i_data.get_full_name()},
                               "NO_REG_HW_RESET_TEST", 1, ctx);
    uvm_resource_db#(bit)::set({"REG::", intr_set.get_full_name()},
                               "NO_REG_HW_RESET_TEST", 1, ctx);
  endfunction
endclass : gpio_reg_block
