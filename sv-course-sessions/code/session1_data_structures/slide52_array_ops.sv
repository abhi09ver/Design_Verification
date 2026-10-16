// Slide 52 - dynamic array operations on arr = '{7,2,9,4,2,7,1}
// Verified with Verilator 5.020: verilator --binary -Wno-fatal slide52_array_ops.sv
module tb;
  int arr[];
  int q[$];          // array locator methods (min/max/find*/unique) return a QUEUE
  int iq[$];         // index queue for find_index / find_first_index

  initial begin
    // 1. Ascending
    arr = '{7, 2, 9, 4, 2, 7, 1};
    arr.sort();
    $display("1 sort      : %p", arr);

    // 2. Descending
    arr = '{7, 2, 9, 4, 2, 7, 1};
    arr.rsort();
    $display("2 rsort     : %p", arr);

    // 3. Reverse (order reversed, not sorted)
    arr = '{7, 2, 9, 4, 2, 7, 1};
    arr.reverse();
    $display("3 reverse   : %p", arr);

    // 4. Smallest - min() returns a queue, take element [0]
    arr = '{7, 2, 9, 4, 2, 7, 1};
    q = arr.min();
    $display("4 min       : %0d", q[0]);

    // 5. Largest
    q = arr.max();
    $display("5 max       : %0d", q[0]);

    // 6. Sum - result width = element width; widen it to avoid overflow
    $display("6 sum       : %0d", arr.sum());
    $display("6 sum (wide): %0d", arr.sum() with (longint'(item)));

    // 7. Remove even numbers - keep the odd ones
    arr = arr.find with (item % 2 != 0);
    $display("7 odd only  : %p", arr);

    // 8. Index of first element > 5 - returns a queue (empty if no match)
    arr = '{7, 2, 9, 4, 2, 7, 1};
    iq = arr.find_first_index with (item > 5);
    if (iq.size()) $display("8 first >5  : index %0d (value %0d)", iq[0], arr[iq[0]]);
    else           $display("8 first >5  : none");

    // 9a. Duplicates - slide's approach (O(n*d) because of 'inside')
    begin
      int seen[int];
      int dups[$];
      foreach (arr[i]) begin
        if (seen.exists(arr[i])) begin
          if (!(arr[i] inside {dups})) dups.push_back(arr[i]);
        end else seen[arr[i]] = 1;
      end
      $display("9a dups     : %p", dups);
    end

    // 9b. Duplicates - counting approach (O(n), also gives how many times)
    begin
      int cnt[int];
      foreach (arr[i]) cnt[arr[i]]++;
      foreach (cnt[v]) if (cnt[v] > 1) $display("9b dup      : %0d appears %0d times", v, cnt[v]);
    end
    $finish;
  end
endmodule
