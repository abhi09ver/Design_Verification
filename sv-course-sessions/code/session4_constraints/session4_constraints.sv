// Session 4 "Constrain the Chaos" - all 12 constraint questions.
// Each class is randomized many times and the result is CHECKED by plain code,
// so a wrong constraint fails loudly instead of "looking random".

// ---------------------------------------------------------------------------
// Q1. AXI transaction must not cross a 4KB boundary
// ---------------------------------------------------------------------------
class axi_4k;
  rand bit [31:0] addr;
  rand bit [7:0]  len;     // AWLEN: beats = len + 1 (AXI4 INCR: up to 256)
  rand bit [2:0]  size;    // AWSIZE: bytes per beat = 2**size

  constraint c_size { size <= 2; }   // e.g. 32-bit data bus -> max 4 bytes/beat
  constraint c_align { addr % (1 << size) == 0; }   // aligned start (simplifies the math)
  // start offset inside the 4K page + total bytes must stay within the page
  constraint c_4k { (addr % 4096) + ((32'(len) + 1) << size) <= 4096; }
endclass

// ---------------------------------------------------------------------------
// Q2. Two non-overlapping regions (64B and 128B) inside 0x20000 .. 0x40000
// ---------------------------------------------------------------------------
class two_regions;
  rand bit [31:0] s1, s2;           // start addresses
  localparam int SZ1 = 64, SZ2 = 128;

  constraint c_range {
    s1 >= 32'h20000;  s1 + SZ1 - 1 <= 32'h40000;
    s2 >= 32'h20000;  s2 + SZ2 - 1 <= 32'h40000;
  }
  // either region 1 ends before region 2 starts, or the other way round
  constraint c_no_overlap { (s1 + SZ1 <= s2) || (s2 + SZ2 <= s1); }
  constraint c_natural_align { s1 % SZ1 == 0; s2 % SZ2 == 0; }   // optional, common follow-up
endclass

// ---------------------------------------------------------------------------
// Q3. Address aligned to 2B, 4B or 8B (alignment picked per transaction)
// ---------------------------------------------------------------------------
class aligned_addr;
  rand bit [31:0] addr;
  rand int unsigned align;
  constraint c_align_sel { align inside {2, 4, 8}; }
  constraint c_aligned   { addr % align == 0; }       // == addr[log2(align)-1:0] == 0
  constraint c_order     { solve align before addr; } // spread align evenly (see notes)
endclass

// ---------------------------------------------------------------------------
// Q4. Pattern 1 2 2 1 1 2 2 1 1 2 2 1 ...  (period 4: 1,2,2,1)
// ---------------------------------------------------------------------------
class pattern_1221;
  rand int unsigned a[];
  constraint c_size { a.size() == 16; }
  constraint c_pat  { foreach (a[i]) a[i] == ((i % 4 == 0 || i % 4 == 3) ? 1 : 2); }
endclass

// ---------------------------------------------------------------------------
// Q5. Sorted dynamic array, ascending or descending, chosen by a knob
// ---------------------------------------------------------------------------
class sorted_arr;
  rand int unsigned a[];
  rand bit          ascending;
  constraint c_size { a.size() inside {[5:10]}; }
  constraint c_val  { foreach (a[i]) a[i] < 1000; }
  constraint c_sort {
    foreach (a[i]) if (i > 0) {
      ascending  -> a[i] > a[i-1];     // strict: unique values; use >= to allow repeats
      !ascending -> a[i] < a[i-1];
    }
  }
endclass

// ---------------------------------------------------------------------------
// Q6. Even numbers between 50 and 100
// ---------------------------------------------------------------------------
class even_50_100;
  rand int unsigned x;
  constraint c { x inside {[50:100]}; x % 2 == 0; }
endclass

// ---------------------------------------------------------------------------
// Q7. APB: writes generated more often than reads
// ---------------------------------------------------------------------------
class apb_wr_bias;
  rand bit pwrite;
  constraint c_bias { pwrite dist {1 := 3, 0 := 1}; }   // ~75% writes, ~25% reads
endclass

// Exact version: in a burst of N transfers, writes = 3 x reads
class apb_wr_ratio;
  rand bit pwrite[20];
  // cast each bit to int: a plain pwrite.sum() is 1 bit wide and would wrap
  constraint c_ratio { pwrite.sum() with (int'(item)) == 15; }  // 15 writes, 5 reads
endclass

// ---------------------------------------------------------------------------
// Q8. Random prime number (2..199)
// ---------------------------------------------------------------------------
class prime_num;
  localparam int MAX = 200;
  rand int unsigned n;
  int unsigned div[MAX];          // NOT rand: only its index i is used as a divisor
  constraint c_range { n inside {[2:MAX-1]}; }
  // n must not be divisible by any i in 2 .. n-1
  constraint c_prime { foreach (div[i]) (i >= 2 && i < n) -> (n % i != 0); }
endclass

// ---------------------------------------------------------------------------
// Q9. Randomize x and y but not z
// ---------------------------------------------------------------------------
class xyz;
  rand int x, y, z;
  constraint c { x inside {[1:100]}; y inside {[1:100]}; z inside {[1:100]}; }
endclass

// ---------------------------------------------------------------------------
// Q10. Odd index -> even value, even index -> odd value
// ---------------------------------------------------------------------------
class odd_even_idx;
  rand int unsigned a[];
  constraint c_size { a.size() == 10; }
  constraint c_val  { foreach (a[i]) a[i] < 100; }
  constraint c_par  { foreach (a[i]) (i % 2 == 1) ? (a[i] % 2 == 0) : (a[i] % 2 == 1); }
endclass

// ---------------------------------------------------------------------------
// Q11. Insert "101" into a 64-bit random number, inside bit positions 20..25
// ---------------------------------------------------------------------------
class seq_101;
  rand bit [63:0] num;
  rand int unsigned pos;                 // LSB position of the 3-bit pattern
  constraint c_pos { pos inside {[20:23]}; }   // pos..pos+2 must stay within 20..25
  constraint c_seq { ((num >> pos) & 64'h7) == 64'b101; }
endclass

// ---------------------------------------------------------------------------
// Q12. Phone numbers by mode
//   mode 0 : emergency 101 / 100 / 911
//   mode 1 : 10-digit local number, not starting with an emergency sequence
//   mode 2 : STD number = state code + 8-digit subscriber number
// ---------------------------------------------------------------------------
typedef enum bit [1:0] {EMERGENCY = 0, LOCAL = 1, STD = 2} mode_e;
typedef enum bit [1:0] {KARNATAKA, DELHI, MAHARASHTRA, TAMIL_NADU} state_e;

class phone_book;
  rand mode_e       mode[];
  rand state_e      state[];
  rand bit [63:0]   num[];       // 64 bits: a 10-digit number does not fit in 32 bits
  rand bit [63:0]   std_code[];
  rand bit [63:0]   subscriber[];

  constraint c_size {
    mode.size() == 9; state.size() == mode.size(); num.size() == mode.size();
    std_code.size() == mode.size(); subscriber.size() == mode.size();
  }
  constraint c_modes {
    foreach (num[i]) {
      mode[i] == EMERGENCY -> num[i] inside {101, 100, 911};

      if (mode[i] == LOCAL) {
        num[i] inside {[64'd1_000_000_000 : 64'd9_999_999_999]};     // exactly 10 digits
        num[i] / 64'd10_000_000 != 100;                              // first 3 digits are
        num[i] / 64'd10_000_000 != 101;                              // not an emergency code
        num[i] / 64'd10_000_000 != 911;
      }

      if (mode[i] == STD) {
        (state[i] == KARNATAKA)   -> std_code[i] == 80;   // 080
        (state[i] == DELHI)       -> std_code[i] == 11;   // 011
        (state[i] == MAHARASHTRA) -> std_code[i] == 22;   // 022
        (state[i] == TAMIL_NADU)  -> std_code[i] == 44;   // 044
        subscriber[i] inside {[64'd20_000_000 : 64'd99_999_999]};    // 8 digits
        num[i] == std_code[i] * 64'd100_000_000 + subscriber[i];
      }
    }
  }
  // make sure all three modes appear in one array
  constraint c_mix { foreach (mode[i]) mode[i] == mode_e'(i % 3); }
endclass

// ===========================================================================
module tb;
  int errors = 0;
  localparam int N = 200;      // randomizations per question

  task automatic check(bit ok, string what);
    if (!ok) begin errors++; $display("  FAIL: %s", what); end
  endtask

  initial begin
    // ---------------- Q1
    begin
      axi_4k t = new(); int maxb = 0;
      repeat (N) begin
        check(t.randomize() == 1, "Q1 randomize");
        // last byte must be in the same 4K page as the first byte
        check((t.addr >> 12) == ((t.addr + ((32'(t.len) + 1) << t.size) - 1) >> 12), "Q1 4K");
      end
      $display("Q1  addr=%h len=%0d size=%0d -> last byte %h (same 4K page)",
               t.addr, t.len, t.size, t.addr + ((32'(t.len)+1) << t.size) - 1);
    end

    // ---------------- Q2
    begin
      two_regions t = new();
      repeat (N) begin
        check(t.randomize() == 1, "Q2 randomize");
        check(t.s1 >= 'h20000 && t.s1 + 63 <= 'h40000, "Q2 range1");
        check(t.s2 >= 'h20000 && t.s2 + 127 <= 'h40000, "Q2 range2");
        check(t.s1 + 64 <= t.s2 || t.s2 + 128 <= t.s1, "Q2 overlap");
      end
      $display("Q2  R1=[%h:%h] R2=[%h:%h]", t.s1, t.s1+63, t.s2, t.s2+127);
    end

    // ---------------- Q3
    begin
      aligned_addr t = new(); int hist[int];
      repeat (N) begin
        check(t.randomize() == 1, "Q3 randomize");
        check(t.addr % t.align == 0, "Q3 align");
        hist[t.align]++;
      end
      $display("Q3  addr=%h align=%0d   alignment histogram %p", t.addr, t.align, hist);
    end

    // ---------------- Q4
    begin
      pattern_1221 t = new(); string s = "";
      check(t.randomize() == 1, "Q4 randomize");
      foreach (t.a[i]) s = {s, $sformatf("%0d", t.a[i])};
      check(s == "1221122112211221", "Q4 pattern");
      $display("Q4  %s", s);
    end

    // ---------------- Q5
    begin
      sorted_arr t = new();
      repeat (N) begin
        check(t.randomize() == 1, "Q5 randomize");
        foreach (t.a[i]) if (i > 0)
          check(t.ascending ? t.a[i] > t.a[i-1] : t.a[i] < t.a[i-1], "Q5 order");
      end
      void'(t.randomize() with { ascending == 1; }); $display("Q5  asc  %p", t.a);
      void'(t.randomize() with { ascending == 0; }); $display("Q5  desc %p", t.a);
    end

    // ---------------- Q6
    begin
      even_50_100 t = new(); int vals[$];
      repeat (N) begin
        check(t.randomize() == 1, "Q6 randomize");
        check(t.x >= 50 && t.x <= 100 && t.x % 2 == 0, "Q6 even");
      end
      repeat (8) begin void'(t.randomize()); vals.push_back(t.x); end
      $display("Q6  %p", vals);
    end

    // ---------------- Q7
    begin
      apb_wr_bias  b = new(); apb_wr_ratio r = new(); int w = 0;
      repeat (1000) begin void'(b.randomize()); w += b.pwrite; end
      check(w > 650 && w < 850, "Q7 dist");
      check(r.randomize() == 1, "Q7 ratio randomize");
      check(r.pwrite.sum() with (int'(item)) == 15, "Q7 ratio");
      $display("Q7  dist: %0d writes / %0d reads in 1000 ; exact: %p", w, 1000 - w, r.pwrite);
    end

    // ---------------- Q8
    begin
      prime_num t = new(); int vals[$];
      repeat (N) begin
        bit is_p = 1;
        check(t.randomize() == 1, "Q8 randomize");
        for (int d = 2; d * d <= t.n; d++) if (t.n % d == 0) is_p = 0;
        check(is_p, $sformatf("Q8 prime %0d", t.n));
        if (vals.size() < 10) vals.push_back(t.n);
      end
      $display("Q8  %p", vals);
    end

    // ---------------- Q9 : three ways
    begin
      xyz t = new(); int z0;
      t.z = 42;
      // (a) inline argument list: only x and y are randomized this call
      check(t.randomize(x, y) == 1, "Q9a"); check(t.z == 42, "Q9a z");
      // (b) rand_mode(0): z behaves as a state variable until turned back on
      t.z.rand_mode(0);
      check(t.randomize() == 1, "Q9b"); check(t.z == 42, "Q9b z");
      t.z.rand_mode(1);
      $display("Q9  x=%0d y=%0d z=%0d (z held)", t.x, t.y, t.z);
      // (c) or simply declare z without 'rand' in the class
    end

    // ---------------- Q10
    begin
      odd_even_idx t = new();
      repeat (N) begin
        check(t.randomize() == 1, "Q10 randomize");
        foreach (t.a[i]) check((t.a[i] % 2) == ((i % 2) ? 0 : 1), "Q10 parity");
      end
      $display("Q10 %p", t.a);
    end

    // ---------------- Q11
    begin
      seq_101 t = new();
      repeat (N) begin
        check(t.randomize() == 1, "Q11 randomize");
        check(t.num[t.pos +: 3] == 3'b101 && t.pos >= 20 && t.pos + 2 <= 25, "Q11 seq");
      end
      $display("Q11 num=%b", t.num);
      $display("    101 at bits [%0d:%0d], bits[25:20] = %b", t.pos + 2, t.pos, t.num[25:20]);
    end

    // ---------------- Q12
    begin
      phone_book t = new();
      repeat (50) begin
        check(t.randomize() == 1, "Q12 randomize");
        foreach (t.num[i]) case (t.mode[i])
          EMERGENCY: check(t.num[i] inside {100, 101, 911}, "Q12 emergency");
          LOCAL:     check(t.num[i] >= 64'd1_000_000_000 && t.num[i] <= 64'd9_999_999_999 &&
                           !((t.num[i] / 10_000_000) inside {100, 101, 911}), "Q12 local");
          STD:       check(t.num[i] / 100_000_000 inside {80, 11, 22, 44}, "Q12 std");
        endcase
      end
      foreach (t.num[i])
        if (t.mode[i] == STD) $display("Q12 %-9s 0%0d-%0d  (%s)", t.mode[i].name(),
                                       t.std_code[i], t.subscriber[i], t.state[i].name());
        else                  $display("Q12 %-9s %0d", t.mode[i].name(), t.num[i]);
    end

    $display("\n==== %0d check failures ====", errors);
    $finish;
  end
endmodule
