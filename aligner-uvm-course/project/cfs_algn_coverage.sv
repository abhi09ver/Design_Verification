///////////////////////////////////////////////////////////////////////////////
// File:        cfs_algn_coverage.sv
// Author:      Cristian Florin Slav
// Date:        2024-12-13
// Description: Coverage component for the Aligner module.
///////////////////////////////////////////////////////////////////////////////

`ifndef CFS_ALGN_COVERAGE_SV
  `define CFS_ALGN_COVERAGE_SV
 
  `uvm_analysis_imp_decl(_in_split_info) 

  class cfs_algn_coverage extends uvm_component implements uvm_ext_reset_handler;
    
    //Analysis implementation port for split information from model
    uvm_analysis_imp_in_split_info#(cfs_algn_split_info, cfs_algn_coverage) port_in_split_info;
    
    covergroup cover_split with function sample(cfs_algn_split_info info);
      option.per_instance = 1;

      ctrl_offset : coverpoint info.ctrl_offset {
        option.comment = "Value of CTRL.OFFSET";
        bins values[]  = {[0:3]};
      }
      
      ctrl_size : coverpoint info.ctrl_size {
        option.comment = "Value of CTRL.SIZE";
        bins values[]  = {[1:4]};
      }
      
      md_offset : coverpoint info.md_offset {
        option.comment = "Value of the MD transaction offset";
        bins values[]  = {[0:3]};
      }
      
      md_size : coverpoint info.md_size {
        option.comment = "Value of the MD transaction size";
        bins values[]  = {[1:4]};
      }
      
      num_bytes_needed : coverpoint info.num_bytes_needed {
        option.comment = "Number of bytes needed during the split";
        bins values[]  = {[1:3]};
      }
      
      all : cross ctrl_offset, ctrl_size, md_offset, md_size, num_bytes_needed {
        ignore_bins ignore_ctrl = (binsof(ctrl_offset) intersect {0} && binsof(ctrl_size) intersect {3})       || 
                                  (binsof(ctrl_offset) intersect {1} && binsof(ctrl_size) intersect {2, 3, 4}) || 
                                  (binsof(ctrl_offset) intersect {2} && binsof(ctrl_size) intersect {3, 4})    || 
                                  (binsof(ctrl_offset) intersect {3} && binsof(ctrl_size) intersect {2, 3, 4});
        //TODO: other combinations should be ignored from this cross
      }

    endgroup

    `uvm_component_utils(cfs_algn_coverage)
    
    function new(string name = "", uvm_component parent);
      super.new(name, parent);
      
      port_in_split_info = new("port_in_split_info", this);
      
      cover_split = new();
      cover_split.set_inst_name($sformatf("%0s_%0s", get_full_name(), "cover_split"));

    endfunction
    
    virtual function void write_in_split_info(cfs_algn_split_info info);
      cover_split.sample(info);
    endfunction
    
    virtual function void handle_reset(uvm_phase phase);
      
    endfunction
    
    //Function to print the coverage information.
    //This is only to be able to visualize some basic coverage information
    //in EDA Playground.
    //DON'T DO THIS IN A REAL PROJECT!!!
    virtual function string coverage2string();
      string result = {
        $sformatf("\n   cover_split:            %03.2f%%", cover_split.get_inst_coverage()),
        $sformatf("\n      ctrl_offset:         %03.2f%%", cover_split.ctrl_offset.get_inst_coverage()),
        $sformatf("\n      ctrl_size:           %03.2f%%", cover_split.ctrl_size.get_inst_coverage()),
        $sformatf("\n      md_offset:           %03.2f%%", cover_split.md_offset.get_inst_coverage()),
        $sformatf("\n      md_size:             %03.2f%%", cover_split.md_size.get_inst_coverage()),
        $sformatf("\n      num_bytes_needed:    %03.2f%%", cover_split.num_bytes_needed.get_inst_coverage()),
        $sformatf("\n      all:                 %03.2f%%", cover_split.all.get_inst_coverage())
      };
 
      return result;
    endfunction

    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);

      //IMPORTANT: DON'T DO THIS IN A REAL PROJECT!!!
      `uvm_info("COVERAGE", $sformatf("Coverage: %0s", coverage2string()), UVM_DEBUG)
    endfunction
  endclass

`endif
    