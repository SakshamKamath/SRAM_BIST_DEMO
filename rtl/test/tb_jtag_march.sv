module tb_jtag_march;

  import march_pkg::*;

  localparam P_DATA_WIDTH   = 24;
  localparam P_ADDR_WIDTH   = 4;
  localparam P_IR_WIDTH     = 4;
  localparam P_IDCODE_WIDTH = 32;
  localparam IDCODE_VAL     = 32'h1080_0786;
  localparam P_FIFO_DEPTH   = 2;

  // Testbench Signals
  logic TEST_TCLK;
  logic TEST_TRSTNI;
  logic TEST_TMS;
  logic TEST_TDI;
  logic TEST_TDO;

  logic [P_ADDR_WIDTH-1:0] A_ADDR;
  logic [P_DATA_WIDTH-1:0] A_DIN;
  logic [P_DATA_WIDTH-1:0] A_BM;
  logic                    A_MEN;
  logic                    A_WEN;
  logic                    A_REN;
  logic                    A_CLK;
  logic                    A_DLY;
  logic [P_DATA_WIDTH-1:0] A_DOUT;

  // Clock Generation
  always #5 TEST_TCLK = ~TEST_TCLK; 
  always #5 A_CLK     = ~A_CLK;     

  // DUT Instantiation
  RM_IHPSG13_1P_core_BIST_wrapped #(
      .P_DATA_WIDTH  (P_DATA_WIDTH),
      .P_ADDR_WIDTH  (P_ADDR_WIDTH),
      .P_IR_WIDTH    (P_IR_WIDTH),
      .P_IDCODE_WIDTH(P_IDCODE_WIDTH),
      .P_FIFO_DEPTH  (P_FIFO_DEPTH),
      .IDCODE_VAL    (IDCODE_VAL)
  ) u_dut (
      .A_ADDR(A_ADDR),
      .A_DIN (A_DIN),
      .A_BM  (A_BM),
      .A_MEN (A_MEN),
      .A_WEN (A_WEN),
      .A_REN (A_REN),
      .A_CLK (A_CLK),
      .A_DLY (A_DLY),
      .A_DOUT(A_DOUT),

      .TEST_TDI   (TEST_TDI),
      .TEST_TCLK  (TEST_TCLK),
      .TEST_TRSTNI(TEST_TRSTNI),
      .TEST_TMS   (TEST_TMS),
      .TEST_TDO   (TEST_TDO)
  );


// Relevant Tasks

task automatic jtag_reset();
  integer i;
  begin
    // Drive initial signal levels synchronized to negedge
    @(negedge TEST_TCLK);
    TEST_TMS = 1'b1;
    TEST_TDI = 1'b0;

    // 5 consecutive TCLKs with TMS=1 guarantees TAP enters Test-Logic-Reset
    for (i = 0; i < 5; i = i + 1) begin
      @(negedge TEST_TCLK);
    end

    // Transition from Test-Logic-Reset -> Run-Test/Idle
    TEST_TMS = 1'b0;
    @(negedge TEST_TCLK);
  end
endtask

task automatic jtag_write_ir(
    input logic [3:0] ir_in,
    input integer     ir_len
);
  integer i;
  begin
    // Navigate TAP state machine: Idle -> Select-DR-Scan -> Select-IR-Scan -> Capture-IR -> Shift-IR
    @(negedge TEST_TCLK) TEST_TMS = 1'b1; // Select-DR-Scan
    @(negedge TEST_TCLK) TEST_TMS = 1'b1; // Select-IR-Scan
    @(negedge TEST_TCLK) TEST_TMS = 1'b0; // Capture-IR
    @(negedge TEST_TCLK) TEST_TMS = 1'b0; // Shift-IR

    // Shift LSB-first into IR
    for (i = 0; i < ir_len; i = i + 1) begin
      @(negedge TEST_TCLK);
      TEST_TDI = ir_in[i];

      // On the final bit, set TMS high to exit Shift-IR to Exit1-IR
      if (i == ir_len - 1) begin
        TEST_TMS = 1'b1; // Shift-IR -> Exit1-IR
      end else begin
        TEST_TMS = 1'b0; // Stay in Shift-IR
      end
    end

    // Complete TAP state transitions: Exit1-IR -> Update-IR -> Run-Test/Idle
    @(negedge TEST_TCLK);
    TEST_TMS = 1'b1; // Exit1-IR -> Update-IR

    @(negedge TEST_TCLK);
    TEST_TMS = 1'b0; // Update-IR -> Run-Test/Idle

    @(negedge TEST_TCLK); // Settle in Run-Test/Idle
  end
endtask

task jtag_shift_dr(
    input  [14:0] dr_in,   // Data to write into DR via TDI
    output [14:0] dr_out,  // Data captured from DR via TDO
    input  integer dr_len  // Length of the DR chain
);
    integer i;
    begin
        dr_out = 15'b0;

        // Navigate to Select-DR-Scan
        @(negedge TEST_TCLK) TEST_TMS = 1'b1; // Select-DR-Scan
        @(negedge TEST_TCLK) TEST_TMS = 1'b0; // Capture-DR
        @(negedge TEST_TCLK) TEST_TMS = 1'b0; // Shift-DR

        // Shift LSB-first into DR while reading TDO
        for (i = 0; i < dr_len; i = i + 1) begin
            TEST_TDI = dr_in[i];

            // Sample TDO on the current cycle
            dr_out[i] = TEST_TDO;

            // On the last bit, drive TMS high to exit Shift-DR state
            if (i == dr_len - 1)
                TEST_TMS = 1'b1; // Exit1-DR
            else
                TEST_TMS = 1'b0; // Shift-DR

            @(negedge TEST_TCLK);
        end

        // Complete TAP state transitions back to Idle
        TEST_TMS = 1'b1; // Update-DR
        @(negedge TEST_TCLK);
        TEST_TMS = 1'b0; // Run-Test/Idle
        @(negedge TEST_TCLK);
    end
endtask

task automatic jtag_write_dr(
    input  logic [14:0] dr_in,  // Data to shift in via TDI
    output logic [14:0] dr_out, // Data shifted out via TDO
    input  integer      dr_len  // Length of the DR chain in bits
);
  integer i;
  begin
    dr_out = '0;

    // Navigate TAP state machine: Idle -> Select-DR-Scan -> Capture-DR -> Shift-DR
    @(negedge TEST_TCLK) TEST_TMS = 1'b1; // Select-DR-Scan
    @(negedge TEST_TCLK) TEST_TMS = 1'b0; // Capture-DR
    @(negedge TEST_TCLK) TEST_TMS = 1'b0; // Shift-DR

    // Shift LSB-first into DR
    for (i = 0; i < dr_len; i = i + 1) begin
      @(negedge TEST_TCLK);
      TEST_TDI = dr_in[i];

      // Sample TDO on the active edge corresponding to the current shift cycle
      dr_out[i] = TEST_TDO;

      // On the final bit, set TMS high to transition Shift-DR -> Exit1-DR
      if (i == dr_len - 1) begin
        TEST_TMS = 1'b1; // Exit1-DR
      end else begin
        TEST_TMS = 1'b0; // Stay in Shift-DR
      end
    end

    // Complete TAP state transitions: Exit1-IR -> Update-DR -> Run-Test/Idle
    @(negedge TEST_TCLK);
    TEST_TMS = 1'b1; // Exit1-DR -> Update-DR (Generates update_dr pulse)

    @(negedge TEST_TCLK);
    TEST_TMS = 1'b0; // Update-DR -> Run-Test/Idle

    @(negedge TEST_TCLK); // Settle in Run-Test/Idle
  end
endtask


logic [14:0] dr_captured;

initial begin
    $dumpfile("tb_jtag_march.fst");
    $dumpvars(0, tb_jtag_march);
    // Initialize signals
    TEST_TCLK   = 1'b0;
    TEST_TRSTNI = 1'b0;
    TEST_TMS    = 1'b1;
    TEST_TDI    = 1'b0;
    #100;
    TEST_TRSTNI = 1'b1; // Release hard reset

    // Reset TAP FSM
    jtag_reset();

    // Write custom opcode '4'b0010' (INSTR_MBIST) into IR
    jtag_write_ir(4'b0010, 4);

    // Taking the tap controller to update dr state to start mbist
    jtag_write_dr(15'b0, dr_captured, 15);

    fork
      begin
        wait (
              (u_dut.u_bist_controller.seq_q == u_dut.u_bist_controller.DONE) || 
              (u_dut.u_bist_controller.seq_q == u_dut.u_bist_controller.ERR_ABORT)
             );
      end
      begin
        // Watchdog timeout guard
        #10000;
        $error("[%0t ns] TIMEOUT: BIST execution took too long!", $time);
        $finish;
      end
    join_any
    disable fork;

    // Evaluate Execution Result
    if (u_dut.u_bist_controller.fail_o) begin
      $display("[%0t ns] >>> BIST ABORTED / FAILED! <<<", $time);
    end else if (u_dut.u_bist_controller.done_o) begin
      $display("[%0t ns] >>> BIST COMPLETED SUCCESSFULLY! <<<", $time);
    end

    
    // 6. Read Erroneous Addresses from FIFO via JTAG
    
    if (u_dut.u_bist_controller.fail_o) begin
      $display("[%0t ns] Fetching error addresses from BIST FIFO...", $time);

      // Load the ERRADDR_LOAD instruction into IR (4'b0011)
      jtag_write_ir(4'b0011, 4);

      jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH);

      jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH);

      // // Read out each error address from the DR FIFO depth times
      // for (int i = 0; i < P_FIFO_DEPTH; i++) begin
      //   // Perform a JTAG DR scan to capture and shift out the stored address.
      //   // We pass 1'b0 dummy data for TDI since we are only reading TDO.
      //   jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH);

      //   $display("[%0t ns] FIFO Entry [%0d]: Error Address = 0x%0h", 
      //            $time, i, dr_captured[P_ADDR_WIDTH-1:0]);
      // end
    end
    #200;
    $finish;

end

endmodule






    // // 3. Shift out the DR chain to extract [ Valid_Bit | Fail_Address ]
    // // dr_len = 1 (Valid bit) + 14 (P_ADDR_WIDTH) = 15 bits
    // begin : read_fifo_loop
    //     reg [14:0] captured_dr;
    //     reg        valid_bit;
    //     reg [13:0] fail_addr;

    //     // Fetch 1st failed address from FIFO
    //     jtag_shift_dr(15'h0, captured_dr, 15);
    //     valid_bit = captured_dr[14];
    //     fail_addr = captured_dr[13:0];

    //     if (valid_bit) begin
    //         $display("[JTAG READ] Faulty Address Found: 0x%h", fail_addr);
    //     end else begin
    //         $display("[JTAG READ] FIFO Empty.");
    //     end
    // end