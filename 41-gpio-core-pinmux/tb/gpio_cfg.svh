// -----------------------------------------------------------------------------
// gpio_cfg.svh : build parameters, register offsets and spec-gap decisions
// -----------------------------------------------------------------------------

// ---- register offsets (User Guide Table 6.1) ----
localparam bit [7:0] ADDR_I_DATA   = 8'h00;  // RO
localparam bit [7:0] ADDR_O_DATA   = 8'h04;  // RW
localparam bit [7:0] ADDR_IO_DIR   = 8'h08;  // RW  0 = output, 1 = input
localparam bit [7:0] ADDR_GLB      = 8'h0C;  // RW  [0] GIE, [1] GME
localparam bit [7:0] ADDR_INTR_EN  = 8'h10;  // RW
localparam bit [7:0] ADDR_INTR_MSK = 8'h14;  // RW  1 = masked
localparam bit [7:0] ADDR_INTR_TYP = 8'h18;  // RW  0 = level, 1 = edge
localparam bit [7:0] ADDR_INTR_EVT = 8'h1C;  // RW  0 = low/falling, 1 = high/rising
localparam bit [7:0] ADDR_INTR_STS = 8'h20;  // W1C masked status
localparam bit [7:0] ADDR_STS_RAW  = 8'h24;  // RO  raw status
localparam bit [7:0] ADDR_INTR_SET = 8'h28;  // WO  software set (gated by IE)
localparam bit [7:0] ADDR_LAST     = ADDR_INTR_SET;

typedef enum {OUT_NO_MATCH, OUT_DROPPED, OUT_MASKED, OUT_SET} outcome_e;
typedef enum {RACE_W1C_WITH_EVENT, RACE_W1C_WHILE_LEVEL,
              RACE_UNMASK_PENDING, RACE_IE_OFF_PENDING} race_e;

class gpio_cfg extends uvm_object;
  `uvm_object_utils(gpio_cfg)

  // Must match the DUT parameters in tb_top (single source: the package constants).
  bit [GPIO_W-1:0] def_o_val  = DEF_O_VAL;
  bit [GPIO_W-1:0] def_io_dir = DEF_IO_DIR;
  bit [GPIO_W-1:0] en_sync    = EN_SYNC;
  bit [GPIO_W-1:0] en_glf     = EN_GLF;

  // Glitch-filter length in clocks. The User Guide does not give it.
  // PLACEHOLDER: read it from irq_sync.sv once the RTL is unlocked.
  int unsigned glf_len = GLF_LEN;

  // Pin event -> visible in status / o_intr. The model treats a pin as
  // "uncertain" for lat_max clocks after anything changes it, so the checks
  // stay valid across EN_SYNC / EN_GLF builds.
  int unsigned lat_max = 2 + GLF_LEN + 3;

  // ---- spec-gap decisions (confirm with the designer, then fix here) ----
  // GME: assumed "per-pin mask bits apply only when GME = 1".
  bit gme_enables_mask = 1;
  // Unmapped / unaligned reads: assumed to complete and return 0.
  bit unmapped_reads_zero = 1;

  function new(string name = "gpio_cfg");
    super.new(name);
  endfunction

  function int unsigned filt_len(int i);
    return (en_glf[i] && en_sync[i]) ? glf_len : 1;
  endfunction
endclass : gpio_cfg
