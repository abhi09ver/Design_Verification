// --------------------------------------------------------
// YARP - Environment (reviewed)
//   [E1] mon2sb is unbounded. The monitor must never block, because it
//        samples every cycle.
//   [E2] end_of_test gets the last register snapshot, taken after the drain.
// --------------------------------------------------------
class yarp_environment;

  yarp_agent                   agent;
  yarp_scoreboard              scoreboard;
  mailbox #(yarp_transaction)  gen2drv;
  mailbox #(yarp_transaction)  mon2sb;
  virtual yarp_interface       vif;

  function new (virtual yarp_interface vif, int num_tr);
    this.vif   = vif;
    gen2drv    = new(1);
    mon2sb     = new();                                  // [E1]
    agent      = new(gen2drv, mon2sb, vif, num_tr);
    scoreboard = new(mon2sb, num_tr);
  endfunction

  virtual task run ();
    yarp_transaction last = new();
    fork
      scoreboard.run();
    join_none
    agent.run();
    @(negedge vif.clk);
    last.arch_reg = vif.arch_reg;                         // [E2]
    scoreboard.end_of_test(last);
  endtask

endclass
