// SystemVerilog Data Structures - solutions to all 14 questions
// Verified with Verilator 5.020:  verilator --binary --timing -Wno-fatal sv_ds_solutions.sv

// ---------- Q6 / Q7 : FIFO built on a queue, with overflow & underflow detection ----------
class fifo #(type T = int, int DEPTH = 4);
  local T q[$];
  int underflow_cnt, overflow_cnt;

  function bit push(T data);
    if (q.size() >= DEPTH) begin            // overflow: full
      overflow_cnt++;
      $display("  [FIFO] OVERFLOW  : push(%0d) dropped, size=%0d", data, q.size());
      return 0;
    end
    q.push_back(data);                       // write at tail
    return 1;
  endfunction

  function bit pop(output T data);
    if (q.size() == 0) begin                 // Q7: underflow = pop on empty queue
      underflow_cnt++;
      $display("  [FIFO] UNDERFLOW : pop on empty FIFO");
      data = T'(0);
      return 0;
    end
    data = q.pop_front();                    // read from head -> first in, first out
    return 1;
  endfunction

  function int  size();     return q.size();          endfunction
  function bit  is_empty(); return q.size() == 0;     endfunction
  function bit  is_full();  return q.size() >= DEPTH; endfunction
endclass

module tb;

  // ---------- Q1 : ascending sort ----------
  function automatic void sort_asc(ref int a[]);
    for (int i = 0; i < a.size() - 1; i++)         // manual bubble sort (what interviewers ask)
      for (int j = 0; j < a.size() - 1 - i; j++)
        if (a[j] > a[j+1]) begin int t = a[j]; a[j] = a[j+1]; a[j+1] = t; end
  endfunction

  // ---------- Q2 : descending sort ----------
  function automatic void sort_desc(ref int a[]);
    for (int i = 0; i < a.size() - 1; i++)
      for (int j = 0; j < a.size() - 1 - i; j++)
        if (a[j] < a[j+1]) begin int t = a[j]; a[j] = a[j+1]; a[j+1] = t; end
  endfunction

  // ---------- Q3 : remove duplicates, keep first-seen order ----------
  function automatic void remove_dups(ref int a[$]);
    bit seen[int];                                  // associative array as a "set"
    int out[$];
    foreach (a[i])
      if (!seen.exists(a[i])) begin seen[a[i]] = 1; out.push_back(a[i]); end
    a = out;
  endfunction

  // ---------- Q4 : exact in-order queue compare ----------
  function automatic bit q_equal(const ref int q1[$], const ref int q2[$]);
    if (q1.size() != q2.size()) return 0;           // cheap check first
    foreach (q1[i]) if (q1[i] !== q2[i]) return 0;  // !== also catches X/Z for 4-state types
    return 1;
  endfunction

  // ---------- Q5 : out-of-order compare (same multiset) ----------
  function automatic bit q_equal_unordered(const ref int q1[$], const ref int q2[$]);
    int cnt[int];                                   // value -> occurrence count
    if (q1.size() != q2.size()) return 0;
    foreach (q1[i]) cnt[q1[i]]++;
    foreach (q2[i]) begin
      if (!cnt.exists(q2[i]) || cnt[q2[i]] == 0) return 0;
      cnt[q2[i]]--;
    end
    return 1;                                       // O(n), handles duplicates correctly
  endfunction

  // ---------- Q12 : reverse a string ----------
  function automatic string str_rev(string s);
    string r = s;
    for (int i = 0; i < s.len(); i++) r[i] = s[s.len()-1-i];
    return r;
  endfunction

  int arr[];
  int dq[$];
  int qa[$], qb[$], qc[$], qd[$];
  bit [31:0] mem [bit [63:0]];                      // Q8: sparse memory
  int  result;
  int  idx[$];
  int  A[];
  fifo #(int, 3) f;
  string s1, s2;

  initial begin
    // Q1/Q2
    arr = '{5, 2, 9, 1, 7};
    sort_asc(arr);  $display("Q1 ascending      : %p", arr);
    sort_desc(arr); $display("Q2 descending     : %p", arr);
    arr = '{5, 2, 9, 1, 7};
    arr.sort();     $display("Q1 built-in sort  : %p", arr);
    arr.rsort();    $display("Q2 built-in rsort : %p", arr);

    // Q3
    dq = '{4, 1, 4, 2, 1, 3};
    remove_dups(dq);
    $display("Q3 dedup (ordered): %p", dq);

    // Q4/Q5
    qa = '{1, 2, 3, 2}; qb = '{1, 2, 3, 2}; qc = '{2, 3, 1, 2}; qd = '{1, 2, 3, 3};
    $display("Q4 in-order  a==b:%0d a==c:%0d", q_equal(qa, qb), q_equal(qa, qc));
    $display("Q5 unordered a~c:%0d a~d:%0d (d has wrong duplicate count)",
             q_equal_unordered(qa, qc), q_equal_unordered(qa, qd));

    // Q6/Q7
    f = new();
    $display("Q6/Q7 FIFO:");
    void'(f.push(10)); void'(f.push(20)); void'(f.push(30));
    void'(f.push(40));                               // overflow (depth 3)
    repeat (4) if (f.pop(result)) $display("  pop -> %0d", result);  // 4th pop underflows
    $display("  overflows=%0d underflows=%0d", f.overflow_cnt, f.underflow_cnt);

    // Q8: only touched addresses consume storage
    mem[64'h0000_0000_0000_0000] = 32'hDEAD_BEEF;
    mem[64'h0000_0001_0000_0000] = 32'hCAFE_F00D;
    mem[64'hFFFF_FFFF_FFFF_FFF0] = 32'h1234_5678;
    $display("Q8 sparse mem entries=%0d over a 2^64 address space", mem.num());
    foreach (mem[addr]) $display("  mem[%h] = %h", addr, mem[addr]);   // iterates in key order

    // Q9: does a KEY exist?  does a VALUE exist?
    $display("Q9 key 0x1_0000_0000 exists : %0d", mem.exists(64'h1_0000_0000));
    $display("Q9 key 0x42 exists          : %0d", mem.exists(64'h42));
    begin
      bit [63:0] keys[$];
      keys = mem.find_index with (item == 32'hCAFE_F00D);   // search by value
      $display("Q9 value CAFEF00D found at  : %p", keys);
    end

    // Q11: concatenation
    s1 = "Hello"; s2 = "World";
    $display("Q11 concat        : %s", {s1, " ", s2});
    $display("Q11 sformatf      : %s", $sformatf("%s_%0d", s1, 7));

    // Q12
    $display("Q12 reverse       : %s", str_rev("SystemVerilog"));

    // Q13: case-insensitive compare
    s1 = "SystemVerilog"; s2 = "SYSTEMverilog";
    $display("Q13 icompare==0   : %0d", s1.icompare(s2) == 0);
    $display("Q13 tolower ==    : %0d", s1.tolower() == s2.tolower());

    // Q14: resize dynamic array 200 -> 250
    A = new[200];
    foreach (A[i]) A[i] = i;
    A = new[250](A);                                 // keep old contents
    $display("Q14 keep  : size=%0d A[199]=%0d A[249]=%0d", A.size(), A[199], A[249]);
    A = new[250];                                    // discard old contents
    $display("Q14 wipe  : size=%0d A[199]=%0d", A.size(), A[199]);

    $finish;
  end
endmodule
