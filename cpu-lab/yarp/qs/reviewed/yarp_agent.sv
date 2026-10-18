// --------------------------------------------------------
// YARP - Agent (reviewed)
//   [A1] end of test waits until the DRIVER has finished num_tr, then
//        drains 32 cycles. The original started the drain when the
//        GENERATOR returned, which can be up to 2 transactions (~66
//        cycles) early. That silently skipped the last instruction, or
//        checked registers while a load was still pending.
// --------------------------------------------------------
class yarp_agent;

  virtual yarp_interface      vif;
  int                         num_tr;
  yarp_generator              gen;
  yarp_driver                 drv;
  yarp_monitor                mon;

  function new (mailbox #(yarp_transaction) gen2drv, mailbox #(yarp_transaction) mon2sb,
                virtual yarp_interface vif, int num_tr);
    this.vif    = vif;
    this.num_tr = num_tr;
    gen = new(gen2drv, num_tr);
    drv = new(gen2drv, vif);
    mon = new(mon2sb, vif);
  endfunction

  virtual task run ();
    drv.reset_seq();
    fork
      drv.run();
      mon.run();
    join_none
    gen.run();
    wait (drv.n_done == num_tr);                 // [A1]
    mon.end_of_test();
  endtask

endclass
