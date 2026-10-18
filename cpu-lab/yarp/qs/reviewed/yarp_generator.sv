// --------------------------------------------------------
// Copyright (C) quicksilicon.io - All Rights Reserved
//
// Unauthorized copying of this file, via any medium is
// strictly prohibited
// Proprietary and confidential
// --------------------------------------------------------

// --------------------------------------------------------
// YARP - Generator
// --------------------------------------------------------

class yarp_generator;

  mailbox #(yarp_transaction)  gen2drv;
  yarp_transaction             blueprint;
  int                          num_tr;

  function new (mailbox #(yarp_transaction) gen2drv, int num_tr);
    this.gen2drv = gen2drv;
    this.num_tr = num_tr;
    blueprint = new();
  endfunction

  virtual task run ();
    repeat (num_tr) begin
      if (blueprint.randomize()==0) $fatal(1, "[FATAL] @ %0t: Failed to randomize the blueprint object", $time);
      gen2drv.put(blueprint.copy());
    end
  endtask

endclass
