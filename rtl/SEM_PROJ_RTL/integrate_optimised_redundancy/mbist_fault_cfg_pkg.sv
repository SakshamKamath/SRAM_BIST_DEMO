// Fault configuration for tc_sram_impl_fault.sv, compiled only with
// `run_vsim.sh --mbist-fault` (Tcl variable MBIST_FAULT=1 in compile_rtl.tcl).
//
// Each bank is one 256x64 macro holding two 32-bit words per row, bit-interleaved
// (see gen_512x32xBx1 in tc_sram_impl_mod.sv): word w lives in row w/2, even words on
// bits [2i], odd words on bits [2i+1]. add_word_fault() does that mapping for you.
// Byte address of word w in bank b: 0x1000_0000 + b*0x800 + w*4.
//
// Only FaultBank gets faults. Bank 0 holds the program and stack, so faults there
// break the CPU; keep FaultBank = 1 for software MBIST tests.

package mbist_fault_cfg_pkg;

  localparam int unsigned NumRows = 256;
  typedef logic [63:0] row_mask_t [0:NumRows-1];

  localparam int unsigned FaultBank = 1;

  // Sets the macro bits of 32-bit word `word` selected by `bits` in mask `m`.
  function automatic row_mask_t add_word_fault(row_mask_t m, int unsigned word, logic [31:0] bits);
    for (int i = 0; i < 32; i++)
      if (bits[i]) m[word / 2][2 * i + (word % 2)] = 1'b1;
    return m;
  endfunction

  // Same, but takes the CPU byte address (e.g. 32'h1000_0828). The address must lie in
  // bank FaultBank (0x1000_0000 + FaultBank*0x800 ... +0x7FF).
  function automatic row_mask_t add_addr_fault(row_mask_t m, logic [31:0] byte_addr, logic [31:0] bits);
    return add_word_fault(m, (byte_addr >> 2) & (2 * NumRows - 1), bits);
  endfunction

  // ---------------------------------------------------------------------------
  // Fault list: edit these functions. Default gives 7 errors (FIFO fills once):
  //   word  10 (0x1000_0828): all bits stuck-at-0 -> fails r1 in stages 2 and 4
  //   word  11 (0x1000_082C): bit 0 stuck-at-0    -> fails r1 in stages 2 and 4
  //   word 300 (0x1000_0CB0): bit 5 stuck-at-1    -> fails r0 in stages 1, 3 and 5
  // ---------------------------------------------------------------------------
  function automatic row_mask_t saf0_init();   // stuck-at-0
    row_mask_t m = '{default: '0};
    m = add_word_fault(m, 10, 32'hFFFF_FFFF);
    m = add_word_fault(m, 11, 32'h0000_0001);
    return m;
  endfunction

  function automatic row_mask_t saf1_init();   // stuck-at-1
    row_mask_t m = '{default: '0};
    m = add_word_fault(m, 300, 32'h0000_0020);
    return m;
  endfunction

  function automatic row_mask_t none_init();
    row_mask_t m = '{default: '0};
    return m;
  endfunction

  localparam row_mask_t MASK_SAF_0 = saf0_init();
  localparam row_mask_t MASK_SAF_1 = saf1_init();
  localparam row_mask_t MASK_TF_01 = none_init();  // transition 0->1 fails
  localparam row_mask_t MASK_TF_10 = none_init();  // transition 1->0 fails
  localparam row_mask_t MASK_RDF   = none_init();  // read destructive
  localparam row_mask_t MASK_IRF   = none_init();  // incorrect read
  localparam row_mask_t MASK_DRDF  = none_init();  // deceptive read destructive
  localparam row_mask_t MASK_WDF   = none_init();  // write disturb
  // Coupling faults (MASK_CF_WRITE/READ) keep the model defaults (none).

endpackage
