module tb_redundancy;

  import march_pkg::*;

  typedef struct packed {
    logic                      valid; // Only used for memory repair for addr_t type used in repair_isol_t
    logic [AddrWidth-1:0]   addr;
  } addr_t;

  typedef struct packed {
    addr_t   vaddr;
    logic [DataWidth-1:0] data;
    logic [DataWidth-1:0] bm;
  } repair_isol_t;

  typedef struct packed {
    repair_isol_t            redundancy;
    logic                    bist_en;
    logic                    men;
    logic                    wen;
    logic                    ren;
  } mem_isol_t;

  typedef enum logic [IrWidth-1:0] {
    Instr_Idcode,
    Instr_Bypass,
    Instr_MbistCtrl,
    Instr_MbistStatusRead,
    Instr_MbistErraddrLoad,
    Instr_MemRepair,
    Instr_MemIsolation
  } ir_type_t;

  localparam int IsolBitWidth = $bits(mem_isol_t);

  localparam DataWidth   = 24;
  localparam AddrWidth   = 4;
  localparam IrWidth     = 4;
  localparam IdcodeWidth = 32;
  localparam IdcodeValue = 32'h1080_0786;
  localparam FifoDepth   = 2;

  // Testbench Signals
  logic TEST_TCLK;
  logic TEST_TRSTNI;
  logic TEST_TMS;
  logic TEST_TDI;
  logic TEST_TDO;

  logic [AddrWidth-1:0] A_ADDR;
  logic [DataWidth-1:0] A_DIN;
  logic [DataWidth-1:0] A_BM;
  logic                 A_MEN;
  logic                 A_WEN;
  logic                 A_REN;
  logic                 A_CLK;
  logic                 A_DLY;
  logic [DataWidth-1:0] A_DOUT;

  // Clock Generation
  always #5 TEST_TCLK = ~TEST_TCLK; 
  always #5 A_CLK     = ~A_CLK;     

  // DUT Instantiation
  RM_IHPSG13_1P_core_BIST_wrapped #(
      .DataWidth  (DataWidth),
      .AddrWidth  (AddrWidth),
      .IrWidth    (IrWidth),
      .IdcodeWidth(IdcodeWidth),
      .FifoDepth  (FifoDepth),
      .IdcodeValue(IdcodeValue)
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
    input logic [AddrWidth-1:0] addr,
    input logic [DataWidth-1:0] data,
    input logic [DataWidth-1:0] bitmask = '1
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
    input  logic [AddrWidth-1:0] addr,
    output logic [DataWidth-1:0] data
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
    input  integer       dr_len  // Length of the DR chain in bits
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


      // On the final bit, set TMS high to transition Shift-DR -> Exit1-DR
      TEST_TMS = (i == dr_len - 1) ? 1'b1 : 1'b0; // Exit1-DR


      @(posedge TEST_TCLK);
      // Sample TDO on the active edge corresponding to the current shift cycle
      dr_out[i] = TEST_TDO;

    end

    // Complete TAP state transitions: Exit1-IR -> Update-DR -> Run-Test/Idle
    @(negedge TEST_TCLK);
    TEST_TMS = 1'b1; // Exit1-DR -> Update-DR (Generates update_dr pulse)

    @(negedge TEST_TCLK);
    TEST_TMS = 1'b0; // Update-DR -> Run-Test/Idle

    @(negedge TEST_TCLK); // Settle in Run-Test/Idle
  end
  dr_captured = dr_captured >> 1;
endtask

logic [127:0] dr_captured;

import jtag_pkg::*;
// typedef enum logic [IrWidth-1:0] {
//     Instr_Idcode,
//     Instr_Bypass,
//     Instr_MbistCtrl,
//     Instr_MbistStatusRead,
//     Instr_MbistErraddrLoad,
//     Instr_MemRepair,
//     Instr_MemIsolation
// } ir_type_t;


import march_pkg::*;
// typedef enum logic [3:0] {
//     St_Idle,
//     St_Stage0,
//     St_Stage1,
//     St_Stage2,
//     St_Stage3,
//     St_Stage4,
//     St_Stage5,
//     St_Done,
//     St_RepairWait
// } seq_e;

// typedef struct packed {
//     logic                   valid;
//     logic [AddrWidth-1:0]   addr;
// } addr_t;

// typedef struct packed {
//     addr_t   vaddr;
//     logic [DataWidth-1:0] data;
//     logic [DataWidth-1:0] bm;
// } repair_isol_t;

// typedef struct packed {
//     repair_isol_t            redundancy;
//     logic                    bist_en;
//     logic                    men;
//     logic                    wen;
//     logic                    ren;
// } mem_isol_t;

// localparam int IsolBitWidth = $bits(mem_isol_t);

mem_isol_t test_payload, repair_payload;
logic [127:0] captured_payload;

logic [DataWidth-1:0] read_val;

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

    // Write custom opcode Instr_MbistCtrl into IR
    jtag_write_ir(Instr_MbistCtrl, 4);

    // Taking the tap controller to update dr state to start mbist
    jtag_write_dr(15'b0, dr_captured, 15);

    fork
      begin
        wait (
              (u_dut.u_bist_controller.seq_q == u_dut.u_bist_controller.St_Done) || 
              (u_dut.u_bist_controller.seq_q == u_dut.u_bist_controller.St_RepairWait)
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

    
    // Write custom opcode (Instr_MbistStatusRead) into IR  --> SHould read 2'b10 as march not done and err fifo not empty
    jtag_write_ir(Instr_MbistStatusRead, 4);

    // Tocapture and shift out the status 
    jtag_write_dr(15'b0, dr_captured, 3);

    $display("Captured Status(TDO) Bin: 0b%0b", dr_captured[1:0]);

    // Poll and service errors until BIST reaches the St_Done state
    while (u_dut.u_bist_controller.seq_q != St_Done) begin
    
      // Check if BIST controller is asserting fail_o / paused in St_RepairWait
      if (u_dut.u_bist_controller.fail_o || 
          u_dut.u_bist_controller.seq_q == St_RepairWait) begin
        
        $display("[%0t ns] BIST Paused / Fail detected. Fetching error addresses from FIFO...", $time);
    
        // Load ERRADDR_LOAD instruction into IR
        jtag_write_ir(Instr_MbistErraddrLoad, 4);
    
        // Drain the FIFO until the valid bit (or empty signal) indicates no more entries
        // by performing a fixed number of reads as needed:
        repeat (5) begin
          jtag_write_dr({AddrWidth{1'b0}}, dr_captured, AddrWidth+2);
          $display("[%0t ns] Captured FIFO Data: 0x%h", $time, dr_captured[AddrWidth:0]);
        end
    
        // Read MBIST Status
        jtag_write_ir(Instr_MbistStatusRead, 4);

        jtag_write_dr(15'b0, dr_captured, 3);
        $display("[%0t ns] MBIST Status: 0b%b", $time, dr_captured[1:0]);
    
        if (u_dut.u_bist_controller.seq_q == St_Done) begin
          $display("[%0t ns] BIST Execution Completed (State: %s)!", $time, u_dut.u_bist_controller.seq_q.name());
          break; // Force immediate loop exit
        end

        // Pulse RESUME to kick MBIST back into testing
        $display("[%0t ns] Issuing RESUME command to MBIST...", $time);
        jtag_write_ir(Instr_MbistCtrl, 4);

        jtag_write_dr(15'b0, dr_captured, 1);
        $display("Captured Status(TDO) Bin: 0b%0b", dr_captured[1:0]);

      end else begin
        // Small delay/yield to prevent an infinite zero-time evaluation loop 
        // while waiting for BIST to either fault or finish.
        #(100); 
      end
    end
    
    $display("[%0t ns] MBIST Controller successfully reached St_Done state!", $time);

    jtag_write_ir(Instr_MbistErraddrLoad, 4);
    repeat (5) begin
        jtag_write_dr({AddrWidth{1'b0}}, dr_captured, AddrWidth+2);
          $display("[%0t ns] Captured FIFO Data: 0x%h", $time, dr_captured);
    end


    jtag_write_ir(Instr_MbistCtrl, 4);
    jtag_write_dr(15'b0, dr_captured, 2);


   
    // Step 1: Select the Memory Isolation Instruction in the JTAG IR
    $display("[%0t ns] [TB] Selecting Instr_MemIsolation...", $time);
    jtag_write_ir(Instr_MemIsolation, 4);

    // =========================================================================
    // TEST 1: WRITE & SHADOW UPDATE (Verify internal shift and shadow registers)
    // =========================================================================
    test_payload.redundancy.vaddr.valid = 1'b0;
    test_payload.redundancy.vaddr.addr  = 'h2; // Match AddrWidth
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

    $display("[%0t ns] [TB] Step 1: Loading Instr_MemRepair into IR...", $time);
    jtag_write_ir(Instr_MemRepair, 4);

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
    //   jtag_write_ir(Instr_MbistErraddrLoad, 4);

    //   jtag_write_dr({AddrWidth{1'b0}}, dr_captured, AddrWidth+2);

    //   jtag_write_dr({AddrWidth{1'b0}}, dr_captured, AddrWidth+2);

    //   jtag_write_dr({AddrWidth{1'b0}}, dr_captured, AddrWidth+2);

    //   jtag_write_dr({AddrWidth{1'b0}}, dr_captured, AddrWidth+2);

    //   jtag_write_dr({AddrWidth{1'b0}}, dr_captured, AddrWidth+2); // Valid bit 0 here


    // end

    // // Write custom opcode (Instr_MbistStatusRead) into IR  --> SHould read 2'b00 as march not done and err fifo empty
    // jtag_write_ir(Instr_MbistStatusRead, 4);

    // // Tocapture and shift out the status 
    // jtag_write_dr(15'b0, dr_captured, 3);


    // // Write custom opcode (Instr_MbistCtrl) into IR  --> Resumes March algo
    // jtag_write_ir(Instr_MbistCtrl, 4);

    // // Tocapture and shift out the status 
    // jtag_write_dr(15'b0, dr_captured, 3);


// -----------------------------------------------------------------
    #2000;
    $finish;

end

endmodule
