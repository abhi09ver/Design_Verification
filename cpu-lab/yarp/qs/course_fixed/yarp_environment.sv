// --------------------------------------------------------
// YARP - Environment
// --------------------------------------------------------
class yarp_environment;

  yarp_agent                   agent;
  yarp_scoreboard              scoreboard;
  mailbox #(yarp_transaction)  gen2drv;
  mailbox #(yarp_transaction)  mon2sb;

  function new (virtual yarp_interface vif, int num_tr);
    $display ("[INFO] @ %0t: Creating the yarp_environment", $time);
    // Create the mailbox
    gen2drv = new(1);
    mon2sb = new();      // [FIX E1] unbounded: the per-cycle monitor must never block

    // Create the agent and scoreboard
    agent = new(gen2drv, mon2sb, vif, num_tr);
    scoreboard = new(mon2sb);
    scoreboard.num_tr = num_tr;   // [FIX S3]
  endfunction

  virtual task run ();
    $display ("[INFO] @ %0t: Running yarp_environment", $time);
    fork
      scoreboard.run();
    join_none
    fork
      agent.run();
    join
    // Call end_of_test
    scoreboard.end_of_test();
    $display ("[INFO] @ %0t: YARP Environment: Run completed", $time);
  endtask

endclass
