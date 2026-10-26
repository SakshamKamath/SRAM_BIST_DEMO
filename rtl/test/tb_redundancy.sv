module tb_redundancy;

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

task mem_write(
    input logic [P_ADDR_WIDTH-1:0] addr,
    input logic [P_DATA_WIDTH-1:0] data,
    input logic [P_DATA_WIDTH-1:0] bitmask = '1
  );
    @(posedge A_CLK);
    A_ADDR  <= addr;
    A_DIN   <= data;
    A_BM    <= bitmask;
    A_MEN   <= 1'b1;
    A_WEN   <= 1'b1;
    A_REN   <= 1'b0;

    @(posedge A_CLK); // Hold for 1 clock cycle
    A_MEN   <= 1'b0;
    A_WEN   <= 1'b0;
    $display("[%0t ns] [BUS WRITE] Addr: 0x%0h | Data: 0x%0h", $time, addr, data);
endtask

  // Drive Functional Read Operation
task mem_read(
    input  logic [P_ADDR_WIDTH-1:0] addr,
    output logic [P_DATA_WIDTH-1:0] data
  );
    @(posedge A_CLK);
    A_ADDR  <= addr;
    A_MEN   <= 1'b1;
    A_REN   <= 1'b1;
    A_WEN   <= 1'b0;

    @(posedge A_CLK); // Allow read evaluation
    #1; // Settling delay
    data     = A_DOUT;
    A_MEN   <= 1'b0;
    A_REN   <= 1'b0;
    $display("[%0t ns] [BUS READ]  Addr: 0x%0h | Data: 0x%0h", $time, addr, data);
endtask




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
    input  logic [127:0] dr_in,  // Data to shift in via TDI
    output logic [127:0] dr_out, // Data shifted out via TDO
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

function automatic logic [IsolBitWidth-1:0] reverse_bits(input logic [IsolBitWidth-1:0] in_payload);
  logic [IsolBitWidth-1:0] rev;
  for (int i = 0; i < IsolBitWidth; i++) begin
    rev[i] = in_payload[IsolBitWidth - 1 - i];
  end
  return rev;
endfunction


logic [127:0] dr_captured;

typedef enum logic [P_IR_WIDTH-1:0] {
    INSTR_IDCODE,
    INSTR_BYPASS,
    INSTR_MBIST_START,
    INSTR_MBIST_STATUS_READ,
    INSTR_MBIST_ERRADDR_LOAD,
    INSTR_MBIST_RESUME_OR_RESET,
    INSTR_MEMORY_REPAIR,
    INSTR_MEM_ISOLATION
} ir_type_t;

typedef enum logic [3:0] {
    IDLE,
    STAGE_0,
    STAGE_1,
    STAGE_2,
    STAGE_3,
    STAGE_4,
    STAGE_5,
    DONE,
    REPAIR_WAIT
} seq_e;

typedef struct packed {
    logic                      valid;
    logic [P_ADDR_WIDTH-1:0]   addr;
} addr_t;

typedef struct packed {
    addr_t   vaddr;
    logic [P_DATA_WIDTH-1:0] data;
    logic [P_DATA_WIDTH-1:0] bm;
} repair_isol_t;

typedef struct packed {
    repair_isol_t            redundancy;
    logic                    bist_en;
    logic                    men;
    logic                    wen;
    logic                    ren;
} mem_isol_t;

localparam int IsolBitWidth = $bits(mem_isol_t);
mem_isol_t test_payload, repair_payload;
logic [127:0] captured_payload;

logic [P_DATA_WIDTH-1:0] read_val;

initial begin
    $dumpfile("tb_redundancy.fst");
    $dumpvars(0, tb_redundancy);
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
    jtag_write_ir(INSTR_MBIST_START, 4);

    // Taking the tap controller to update dr state to start mbist
    jtag_write_dr(15'b0, dr_captured, 15);

    fork
      begin
        wait (
              (u_dut.u_bist_controller.seq_q == u_dut.u_bist_controller.DONE) || 
              (u_dut.u_bist_controller.seq_q == u_dut.u_bist_controller.REPAIR_WAIT)
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

    
    // Write custom opcode (INSTR_MBIST_STATUS_READ) into IR  --> SHould read 2'b10 as march not done and err fifo not empty
    jtag_write_ir(INSTR_MBIST_STATUS_READ, 4);

    // Tocapture and shift out the status 
    jtag_write_dr(15'b0, dr_captured, 3);


    // Poll and service errors until BIST reaches the DONE state
    while (u_dut.u_bist_controller.seq_q != DONE) begin
    
      // Check if BIST controller is asserting fail_o / paused in REPAIR_WAIT
      if (u_dut.u_bist_controller.fail_o || 
          u_dut.u_bist_controller.seq_q == REPAIR_WAIT) begin
        
        // $display("[%0t ns] BIST Paused / Fail detected. Fetching error addresses from FIFO...", $time);
    
        // Load ERRADDR_LOAD instruction into IR
        jtag_write_ir(INSTR_MBIST_ERRADDR_LOAD, 4);
    
        // Drain the FIFO until the valid bit (or empty signal) indicates no more entries
        // by performing a fixed number of reads as needed:
        repeat (5) begin
          jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH+2);
        //   $display("[%0t ns] Captured FIFO Data: 0x%h", $time, dr_captured);
        end
    
        // Read MBIST Status
        jtag_write_ir(INSTR_MBIST_STATUS_READ, 4);
        jtag_write_dr(15'b0, dr_captured, 3);
        // $display("[%0t ns] MBIST Status: 0b%b", $time, dr_captured[2:0]);
    
        // Pulse RESUME to kick MBIST back into testing
        // $display("[%0t ns] Issuing RESUME command to MBIST...", $time);
        jtag_write_ir(INSTR_MBIST_RESUME_OR_RESET, 4);
        jtag_write_dr(15'b0, dr_captured, 3);
    
      end else begin
        // Small delay/yield to prevent an infinite zero-time evaluation loop 
        // while waiting for BIST to either fault or finish.
        #(100); 
      end
    end
    
    $display("[%0t ns] MBIST Controller successfully reached DONE state!", $time);

    jtag_write_ir(INSTR_MBIST_ERRADDR_LOAD, 4);
    repeat (5) begin
        jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH+2);
        //   $display("[%0t ns] Captured FIFO Data: 0x%h", $time, dr_captured);
    end


    jtag_write_ir(INSTR_MBIST_RESUME_OR_RESET, 4);
    jtag_write_dr(15'b0, dr_captured, 3);


   
    // Step 1: Select the Memory Isolation Instruction in the JTAG IR
    $display("[%0t ns] [TB] Selecting INSTR_MEM_ISOLATION...", $time);
    jtag_write_ir(INSTR_MEM_ISOLATION, 4);

    // =========================================================================
    // TEST 1: WRITE & SHADOW UPDATE (Verify internal shift and shadow registers)
    // =========================================================================
    test_payload.redundancy.vaddr.valid = 1'b0;
    test_payload.redundancy.vaddr.addr  = 'h2; // Match P_ADDR_WIDTH
    test_payload.redundancy.data        = 'hDEADBEEE;
    test_payload.redundancy.bm          = 'hFFFFFFFF;
    test_payload.bist_en                = 1'b1;
    test_payload.men                    = 1'b1;
    test_payload.wen                    = 1'b1; // Write Enable Active
    test_payload.ren                    = 1'b0;

    $display("[%0t ns] [TB] Shifting Test Payload into DR...", $time);
    // Dummy response variable used for JTAG task compatibility
    jtag_write_dr(128'(test_payload), captured_payload, IsolBitWidth);

    // 1a. Check internal shift register (mem_isol_q) right after Shift-DR completes
    if (u_dut.i_jtag_tap_top.mem_isol_q === test_payload) begin
        $display("[%0t ns] [TB PASS] Shift Register (mem_isol_q) matched payload: 0x%h", $time, u_dut.i_jtag_tap_top.mem_isol_q);
    end else begin
        $error("[%0t ns] [TB FAIL] Shift Register mismatch! Expected: 0x%h, Got: 0x%h", $time, test_payload, u_dut.i_jtag_tap_top.mem_isol_q);
    end

    // Wait 1 clock cycle for Update-DR state to latch values into shadow register
    @(posedge TEST_TCLK);

    // 1b. Check Shadow Register (mem_isol_shadow_q) and Output Ports
    if (u_dut.i_jtag_tap_top.mem_isol_shadow_q === test_payload) begin
        $display("[%0t ns] [TB PASS] Shadow Register (mem_isol_shadow_q) updated correctly!", $time);
    end else begin
        $error("[%0t ns] [TB FAIL] Shadow Register mismatch! Expected: 0x%h, Got: 0x%h", $time, test_payload, u_dut.i_jtag_tap_top.mem_isol_shadow_q);
    end

    // 1c. Verify top-level isolation outputs driven by the shadow register
    if (u_dut.i_jtag_tap_top.isol_data_o === test_payload.redundancy.data &&
        u_dut.i_jtag_tap_top.isol_wen_o  === test_payload.wen &&
        u_dut.i_jtag_tap_top.isol_ren_o  === test_payload.ren) begin
        $display("[%0t ns] [TB PASS] Direct HW Output Ports driven accurately!", $time);
    end else begin
        $error("[%0t ns] [TB FAIL] Output Port Mismatch! isol_data_o: 0x%h, isol_wen_o: %b", 
               $time, u_dut.i_jtag_tap_top.isol_data_o, u_dut.i_jtag_tap_top.isol_wen_o);
    end

    // =========================================================================
    // TEST 2: READ / CAPTURE OPERATION (Verify mem_rdata_i parallel load)
    // =========================================================================
    // Force memory read data at top level to verify Capture-DR behavior
    // --- STEP 1: Apply Read Address and Assert Read Enable ---
    test_payload                       = '0;
    test_payload.redundancy.vaddr.valid = 1'b0;
    test_payload.redundancy.vaddr.addr  = 10'h2; // Target Memory Address
    test_payload.bist_en                = 1'b1;
    test_payload.men                    = 1'b1;
    test_payload.ren                    = 1'b1;   // Assert Read Enable
    test_payload.wen                    = 1'b0;
    
    $display("[%0t ns] [TB] Issue Read Command to RAM via JTAG DR...", $time);
    jtag_write_dr((test_payload), captured_payload, IsolBitWidth);
    
    // Wait 1 clock cycle for Update-DR to latch into mem_isol_shadow_q 
    // and for memory to respond with mem_rdata_i
    @(posedge TEST_TCLK); 
    #1; // Small delta delay to allow RAM output to settle on mem_rdata_i
    
    $display("[%0t ns] [TB] Driven RAM Address: 0x%h, RAM Output Data: 0x%h", 
             $time, u_dut.i_jtag_tap_top.isol_addr_o, u_dut.rdata);
    
    // --- STEP 2: Trigger Capture-DR to sample mem_rdata_i into mem_isol_q ---
    $display("[%0t ns] [TB] Starting 2nd DR Scan to Capture RAM Output...", $time);
    
    // Initiate a dummy scan (or next payload) to cycle through TAP Capture-DR state
    jtag_write_dr('d0, captured_payload, IsolBitWidth);
    
    // =========================================================
    //       STARTING MEMORY REPAIR FEATURE TESTBENCH
    //==========================================================

    $display("[%0t ns] [TB] Step 1: Loading INSTR_MEMORY_REPAIR into IR...", $time);
    jtag_write_ir(INSTR_MEMORY_REPAIR, 4);

    // 3. Construct Repair Payload for Address 2
    repair_payload = '0;
    repair_payload.redundancy.vaddr.valid = 1'b1;              // Enable repair
    repair_payload.redundancy.vaddr.addr  = 'd2;             // Target Address = 2
    

    jtag_write_dr(repair_payload, captured_payload, IsolBitWidth);



    mem_write(.addr(10'd2), .data(32'hAAAA_BBB0));

    mem_read(.addr(10'd2), .data(read_val));

    mem_write(.addr(10'd2), .data(32'hDEFE_BABE));

    mem_read(.addr(10'd2), .data(read_val));

    mem_write(.addr(10'd7), .data(32'hA050_DEFD));

    mem_read(.addr(10'd7), .data(read_val));


    mem_read(.addr(10'd2), .data(read_val));

// --------------------------------------------------------------------
    // // Read Erroneous Addresses from FIFO via JTAG
    // if (u_dut.u_bist_controller.fail_o) begin
    //   $display("[%0t ns] Fetching error addresses from BIST FIFO...", $time);

    //   // Load the ERRADDR_LOAD instruction into IR (4'b0011)
    //   jtag_write_ir(INSTR_MBIST_ERRADDR_LOAD, 4);

    //   jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH+2);

    //   jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH+2);

    //   jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH+2);

    //   jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH+2);

    //   jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH+2); // Valid bit 0 here


    // end

    // // Write custom opcode (INSTR_MBIST_STATUS_READ) into IR  --> SHould read 2'b00 as march not done and err fifo empty
    // jtag_write_ir(INSTR_MBIST_STATUS_READ, 4);

    // // Tocapture and shift out the status 
    // jtag_write_dr(15'b0, dr_captured, 3);


    // // Write custom opcode (INSTR_MBIST_RESUME_OR_RESET) into IR  --> Resumes March algo
    // jtag_write_ir(INSTR_MBIST_RESUME_OR_RESET, 4);

    // // Tocapture and shift out the status 
    // jtag_write_dr(15'b0, dr_captured, 3);


// -----------------------------------------------------------------
    #2000;
    $finish;

end

endmodule