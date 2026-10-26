module tb_march_bist_top;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  parameter P_DATA_WIDTH = 32;
  parameter P_ADDR_WIDTH = 9;
  parameter NUM_WORDS    = 512;
  parameter P_FIFO_DEPTH = 2;
  parameter CLK_PERIOD   = 10;

  parameter FAULT_ADDR   = 10'd42;
  parameter FAULT_MASK   = 32'h0000_0001;

  // ---------------------------------------------------------------------------
  // Testbench Signals
  // ---------------------------------------------------------------------------
  logic tclk;
  logic trst_n;
  logic tdi;
  logic tms;
  logic tdo;

  logic start;
  logic busy;
  logic done;
  logic fail;

  // Controller <-> Memory Interface
  logic [P_ADDR_WIDTH-1:0] memaddr;
  logic [P_DATA_WIDTH-1:0] wdata;
  logic [P_DATA_WIDTH-1:0] rdata;
  logic [P_DATA_WIDTH/8-1:0] membm; 
  logic                    memen;
  logic                    memren;
  logic                    memwen;

  // ---------------------------------------------------------------------------
  // Clock Generation
  // ---------------------------------------------------------------------------
  initial begin
    tclk = 0;
    forever #(CLK_PERIOD / 2) tclk = ~tclk;
  end

  // ---------------------------------------------------------------------------
  // Unit Under Test (UUT): March BIST Controller
  // ---------------------------------------------------------------------------
  march_bist_controller #(
      .P_DATA_WIDTH(P_DATA_WIDTH),
      .P_ADDR_WIDTH(P_ADDR_WIDTH),
      .P_FIFO_DEPTH(P_FIFO_DEPTH)
  ) u_bist_controller (
      .tdi_i    (tdi),
      .tms_i    (tms),
      .tclk_i   (tclk),
      .trst_ni  (trst_n),
      .tdo_o    (tdo),
      .start_i  (start),
      .busy_o   (busy),
      .done_o   (done),
      .fail_o   (fail),
      .rdata_i  (rdata),
      .memaddr_o(memaddr),
      .wdata_o  (wdata),
      .membm_o  (membm),   
      .memen_o  (memen),
      .memren_o (memren),
      .memwen_o (memwen)
  );

 // ---------------------------------------------------------------------------
  // Memory Under Test (MUT): Behavioral SRAM
  // Fixed Parameter Bit-Widths and Array Dimensions
  // ---------------------------------------------------------------------------
  logic [31:0] membm_32b; // 32-bit expanded mask

  assign membm_32b = { {8{membm[3]}}, 
                       {8{membm[2]}}, 
                       {8{membm[1]}}, 
                       {8{membm[0]}} };

  // Localparam definitions matched to P_DATA_WIDTH (32-bit) and P_ADDR_WIDTH (1024 depth)
  localparam [P_DATA_WIDTH-1:0] MY_SAF_1 [0:(1<<P_ADDR_WIDTH)-1] = '{
      10'd42  : 32'h0000_0001, // Bit 0 stuck at 1 at Address 42 (0x02A)
      default : 32'h0000_0000
  };

  localparam [P_DATA_WIDTH-1:0] MY_TF_01 [0:(1<<P_ADDR_WIDTH)-1] = '{
      10'd10  : 32'h0000_000F, // Bits [3:0] fail 0->1 transition at Address 10
      default : 32'h0000_0000
  };

  localparam [P_DATA_WIDTH-1:0] MY_RDF [0:(1<<P_ADDR_WIDTH)-1] = '{
      10'd16  : 32'h8000_0000, // Bit 31 has RDF at Address 16
      default : 32'h0000_0000
  };

 
  SRAM_1P_behavioral_bm_bist #(
      .P_DATA_WIDTH      (P_DATA_WIDTH),
      .P_ADDR_WIDTH      (P_ADDR_WIDTH),
      .EN_FAULT_INJECTION(1'b1),         // Master Fault Switch ON
      .MASK_SAF_1        (MY_SAF_1),
      .MASK_TF_01        (MY_TF_01),
      .MASK_RDF          (MY_RDF)
  ) u_sram_mem (
      .A_ADDR    (memaddr),
      .A_DIN     (wdata),
      .A_BM      (membm_32b),
      .A_MEN     (memen),
      .A_WEN     (memwen),
      .A_REN     (memren),
      .A_CLK     (tclk),
      .A_DLY     (1'b0),
      .A_DOUT    (rdata),

      .A_BIST_EN (1'b0),
      .A_BIST_ADDR('0),
      .A_BIST_DIN ('0),
      .A_BIST_BM  ('0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_CLK (1'b0)
  );

  // ---------------------------------------------------------------------------
  // Test Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    // Setup waveform dumping
    $dumpfile("tb_march_bist_top.fst");
    $dumpvars(0, tb_march_bist_top);
    trst_n = 1'b0;
    start  = 1'b0;
    tdi    = 1'b0;
    tms    = 1'b0;

    $display("=========================================================");
    $display("       Starting March MSS BIST Controller Testbench      ");
    $display("=========================================================");

    #(CLK_PERIOD * 2);
    trst_n = 1'b1;
    #(CLK_PERIOD * 2);

    // -------------------------------------------------------------------------
    // TEST 1: Golden / Healthy Run (No dynamic fault active)
    // -------------------------------------------------------------------------
    $display("\n[TEST 1] Running March BIST on Memory...");
    run_bist_test();

    // if (u_bist_controller.seq_q == u_bist_controller.DONE) begin
    //   $display(">>> BIST RUN COMPLETED SUCCESSFULLY (DONE)");
    // end else if (u_bist_controller.seq_q == u_bist_controller.ERR_ABORT) begin
    //   $display(">>> BIST DETECTED A FAULT AND ABORTED (ERR_ABORT)");
    // end else begin
    //   $display(">>> TEST TERMINATED IN STATE: %0d", u_bist_controller.seq_q);
    // end
    if (done) begin
      $display(">>> BIST RUN COMPLETED SUCCESSFULLY (DONE)");
    end else if (fail) begin
      $display(">>> BIST DETECTED A FAULT AND ABORTED (FAIL)");
    end else if (busy) begin
      $display(">>> BIST STILL RUNNING");
    end else begin 
      $display(">>> BIST TERMINATED WITHOUT COMPLETION");
    end

    $display("\n=========================================================");
    $display("                   Testbench Completed                  ");
    $display("=========================================================");
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Helper Task
  // ---------------------------------------------------------------------------
  task automatic run_bist_test();
    begin
      @(posedge tclk);
      start = 1'b1;
      @(posedge tclk);
      start = 1'b0;

      wait(busy == 1'b1);
      wait(busy == 1'b0);
      
      @(posedge tclk);
    end
  endtask

endmodule
