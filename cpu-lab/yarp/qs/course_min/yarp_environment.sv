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
    mon2sb = new(1);

    // Create the agent and scoreboard
    agent = new(gen2drv, mon2sb, vif, num_tr);
    scoreboard = new(mon2sb);
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
