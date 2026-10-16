// -----------------------------------------------------------------------------
// gpio_tests.svh : tests
//
// One base test builds the environment; each named test just picks a virtual
// sequence. Any sequence can also be run without a new class:
//   +UVM_TESTNAME=gpio_base_test +GPIO_VSEQ=gpio_glitch_vseq
// -----------------------------------------------------------------------------

class gpio_base_test extends uvm_test;
  `uvm_component_utils(gpio_base_test)
  gpio_env env;
  gpio_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Subclasses override this to choose their stimulus.
  virtual function string vseq_name();
    return "gpio_full_vseq";
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = gpio_cfg::type_id::create("cfg");
    uvm_config_db#(gpio_cfg)::set(this, "*", "cfg", cfg);
    env = gpio_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  task run_phase(uvm_phase phase);
    string         name = vseq_name();
    uvm_object     obj;
    gpio_base_vseq vseq;
    void'($value$plusargs("GPIO_VSEQ=%s", name));

    obj = uvm_factory::get().create_object_by_name(name, get_full_name(), name);
    if (!$cast(vseq, obj))
      `uvm_fatal("VSEQ", {"unknown virtual sequence: ", name})

    phase.raise_objection(this, {"running ", name});
    if (!vseq.randomize()) `uvm_fatal("RAND", "vseq randomize failed")
    vseq.start(env.vseqr);
    #(20 * CLK_PERIOD_NS * 1ns);            // let the last transfers drain
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    `uvm_info("RESULT", errs == 0 ? "** TEST PASSED **" : "** TEST FAILED **", UVM_NONE)
  endfunction
endclass : gpio_base_test


`define GPIO_TEST(TNAME, VSEQ) \
  class TNAME extends gpio_base_test; \
    `uvm_component_utils(TNAME) \
    function new(string name, uvm_component parent); super.new(name, parent); endfunction \
    virtual function string vseq_name(); return `"VSEQ`"; endfunction \
  endclass

`GPIO_TEST(gpio_reset_test,       gpio_reset_vseq)
`GPIO_TEST(gpio_reg_access_test,  gpio_reg_access_vseq)
`GPIO_TEST(gpio_out_drive_test,   gpio_out_drive_vseq)
`GPIO_TEST(gpio_in_sample_test,   gpio_in_sample_vseq)
`GPIO_TEST(gpio_intr_rand_test,   gpio_intr_rand_vseq)
`GPIO_TEST(gpio_level_storm_test, gpio_level_storm_vseq)
`GPIO_TEST(gpio_w1c_race_test,    gpio_w1c_race_vseq)
`GPIO_TEST(gpio_mask_pending_test, gpio_mask_pending_vseq)
`GPIO_TEST(gpio_ie_swset_test,    gpio_ie_swset_vseq)
`GPIO_TEST(gpio_glitch_test,      gpio_glitch_vseq)
`GPIO_TEST(gpio_multi_pin_test,   gpio_multi_pin_vseq)
`GPIO_TEST(gpio_reconfig_test,    gpio_reconfig_live_vseq)
`GPIO_TEST(gpio_apb_robust_test,  gpio_apb_robust_vseq)
`GPIO_TEST(gpio_full_test,        gpio_full_vseq)
