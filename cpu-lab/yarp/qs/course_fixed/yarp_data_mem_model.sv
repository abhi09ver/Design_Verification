// --------------------------------------------------------
// Copyright (C) quicksilicon.io - All Rights Reserved
//
// Unauthorized copying of this file, via any medium is
// strictly prohibited
// Proprietary and confidential
// --------------------------------------------------------

// --------------------------------------------------------
// YARP - Data Memory Model
// --------------------------------------------------------
import riscv_pkg::*;
// ------------------------------------------------------------------
// Implement the data memory model using a static class
// ------------------------------------------------------------------
class yarp_data_mem_model;
  // ------------------------------------------------------------------
  // Declare a static associative array as the main memory
  // ------------------------------------------------------------------
  static logic[7:0] mem [int];
  
  // ------------------------------------------------------------------
  // Write method should write data into the memory along with byte en
  // ------------------------------------------------------------------
  static function void write (bit[31:0] address, bit[31:0] data, mem_access_size_t byte_en);
    // Determine alignment and size based on byte enable
    int size;
    case (byte_en)
      WORD:       size = 4;
      HALF_WORD:  size = 2;
      BYTE:       size = 1;
      default: $fatal(1, "Invalid byte enable: 2'b%2b", byte_en);
    endcase

    // [FIX M1] misaligned is legal stimulus (rs1 holds random values):
    // handle it byte by byte, the same policy as the C model. No $fatal.

    // Write data to memory
    for (int i = 0; i < size; i++) begin
      mem[address + i] = data[i*8 +: 8];
    end
  endfunction
  
  // ------------------------------------------------------------------
  // Read method should return the read data from the memory
  // ------------------------------------------------------------------
  static function bit[31:0] read (bit[31:0] address, mem_access_size_t byte_en);
    // Determine alignment and size based on byte enable
    int       size;
    bit[31:0] data;

    case (byte_en)
      WORD:       size = 4;
      HALF_WORD:  size = 2;
      BYTE:       size = 1;
      default: $fatal(1, "Invalid byte enable: 2'b%2b", byte_en);
    endcase

    // [FIX M1] no alignment $fatal (see write)
    // [FIX M2] unwritten bytes read as 0 (no X, no tool warning)
    data = '0;
    for (int i = 0; i < size; i++) begin
      data[i*8 +: 8] = mem.exists(address + i) ? mem[address + i] : 8'h00;
    end

    return data;
  endfunction

endclass
