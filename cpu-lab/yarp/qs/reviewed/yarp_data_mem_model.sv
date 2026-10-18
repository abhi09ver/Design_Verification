// --------------------------------------------------------
// YARP - Data Memory Model (reviewed)
//   [M1] Misaligned accesses are handled byte by byte instead of $fatal.
//        The spec says "handle", and with random register values a
//        misaligned address is normal stimulus, not a TB error.
//   [M2] Unwritten bytes read as 0 (checked with exists()), the same
//        policy as the C model, so there is no X and no tool warning.
//   [M3] Only the reserved size 2'b10 is fatal.
// --------------------------------------------------------
import riscv_pkg::*;
class yarp_data_mem_model;
  static bit [7:0]    mem [bit [31:0]];
  static int unsigned n_misaligned;

  static function int size_of (mem_access_size_t byte_en);
    case (byte_en)
      WORD      : return 4;
      HALF_WORD : return 2;
      BYTE      : return 1;
      default   : $fatal(1, "[MEM] reserved byte_en 2'b%2b", byte_en);
    endcase
    return 0;
  endfunction

  static function void write (bit [31:0] address, bit [31:0] data, mem_access_size_t byte_en);
    int n = size_of(byte_en);
    if (address % n) n_misaligned++;
    for (int i = 0; i < n; i++) mem[address + i] = data[i*8 +: 8];
  endfunction

  // returns right-aligned data (the YARP load-data contract)
  static function bit [31:0] read (bit [31:0] address, mem_access_size_t byte_en);
    bit [31:0] data = '0;
    int n = size_of(byte_en);
    if (address % n) n_misaligned++;
    for (int i = 0; i < n; i++)
      data[i*8 +: 8] = mem.exists(address + i) ? mem[address + i] : 8'h00;
    return data;
  endfunction
endclass
