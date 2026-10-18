// --------------------------------------------------------
// Copyright (C) quicksilicon.io - All Rights Reserved
//
// Unauthorized copying of this file, via any medium is
// strictly prohibited
// Proprietary and confidential
// --------------------------------------------------------

// --------------------------------------------------------
// YARP - Agent
// --------------------------------------------------------

class yarp_agent;

  mailbox #(yarp_transaction) gen2drv;
  virtual yarp_interface      vif;
  int                         num_tr;
  yarp_generator              gen;
  yarp_driver                 drv;
  yarp_monitor                mon;

  function new (mailbox #(yarp_transaction) gen2drv, mailbox #(yarp_transaction) mon2sb, virtual yarp_interface vif, int num_tr);
    $display("[INFO] @ %0t: Creating the yarp_agent", $time);
    this.gen2drv = gen2drv;
    this.vif = vif;
    this.num_tr = num_tr;
    gen = new(gen2drv, num_tr);
    drv = new(gen2drv, vif);
    mon = new(mon2sb, vif);
  endfunction

  virtual task run ();
    // Run the reset driver sequence
    drv.reset_seq();
    fork
      drv.run();
      mon.run();
    join_none
    fork
      gen.run();
    join
    // [FIX A1] the generator returns up to 2 transactions before the driver
    // finishes them. Wait for the driver, THEN drain.
    wait (drv.n_done == num_tr);
    mon.end_of_test();
  endtask

endclass
