// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`define TRACE_WAVE

module tb_croc_soc #(
  parameter int unsigned GpioCount = 32,
  parameter int unsigned P_ADDR_WIDTH = 4,
  parameter int unsigned P_FIFO_DEPTH = 2
);

  import tb_croc_pkg::*;

  // Signals partially controlled by the VIP
  logic rst_n;
  logic sys_clk;
  logic ref_clk;

  logic jtag_tck;
  logic jtag_trst_n;
  logic jtag_tms;
  logic jtag_tdi;
  logic jtag_tdo;

  logic uart_rx;
  logic uart_tx;

  logic [GpioCount-1:0] gpio_in;
  logic [GpioCount-1:0] gpio_out;
  logic [GpioCount-1:0] gpio_out_en;

  string binary_path;

  initial begin
    if ($value$plusargs("binary=%s", binary_path)) begin
      $display("Running program: %s", binary_path);
    end else begin
      $display("No binary path provided. Running helloworld.");
      binary_path = "../sw/bin/helloworld.hex";
    end
  end

  ////////////
  //  VIP   //
  ////////////
  // Drives clocks and reset signals
  croc_vip #(
    .GpioCount ( GpioCount )
  ) i_vip (
    .rst_no        ( rst_n        ),
    .sys_clk_o     ( sys_clk      ),
    .ref_clk_o     ( ref_clk      ),
    .jtag_tck_o    ( jtag_tck     ),
    .jtag_trst_no  ( jtag_trst_n  ),
    .jtag_tms_o    ( jtag_tms     ),
    .jtag_tdi_o    ( jtag_tdi     ),
    .jtag_tdo_i    ( jtag_tdo     ),
    .uart_rx_o     ( uart_rx      ),
    .uart_tx_i     ( uart_tx      ),
    .gpio_out_en_i ( gpio_out_en  ),
    .gpio_out_i    ( gpio_out     ),
    .gpio_in_o     ( gpio_in      )
  );

  ////////////
  //  DUT   //
  ////////////
  `ifdef TARGET_NETLIST_YOSYS
  \croc_soc$croc_chip.i_croc_soc i_croc_soc (
  `else
  croc_soc #(
    .GpioCount ( GpioCount )
  ) i_croc_soc (
  `endif
    .clk_i          ( sys_clk     ),
    .rst_ni         ( rst_n       ),
    .ref_clk_i      ( ref_clk     ),
    .testmode_i     ( 1'b0        ),
    .status_o       (             ),
    .jtag_tck_i     ( jtag_tck    ),
    .jtag_tdi_i     ( jtag_tdi    ),
    .jtag_tdo_o     ( jtag_tdo    ),
    .jtag_tms_i     ( jtag_tms    ),
    .jtag_trst_ni   ( jtag_trst_n ),
    .uart_rx_i      ( uart_rx     ),
    .uart_tx_o      ( uart_tx     ),
    .gpio_i         ( gpio_in     ),
    .gpio_o         ( gpio_out    ),
    .gpio_out_en_o  ( gpio_out_en )
  `ifndef TARGET_NETLIST_YOSYS
    // No microphone model: hold the I2S data line low so no X reaches the VAD
   ,.vad_i2s_sclk_o  (             ),
    .vad_i2s_wsel_o  (             ),
    .vad_i2s_sdat_i  ( 1'b0        )
  `endif
  );

  ///////////////////////////////
  // Low-Level Direct JTAG Tasks
  ///////////////////////////////

  task automatic jtag_reset();
    integer i;
    begin
      @(negedge jtag_tck);
      force jtag_tms = 1'b1;
      force jtag_tdi = 1'b0;

      for (i = 0; i < 5; i = i + 1) begin
        @(negedge jtag_tck);
      end

      force jtag_tms = 1'b0;
      @(negedge jtag_tck);
    end
  endtask

  task automatic jtag_write_ir(
      input logic [3:0] ir_in,
      input integer     ir_len
  );
    integer i;
    begin
      @(negedge jtag_tck) force jtag_tms = 1'b1; // Select-DR-Scan
      @(negedge jtag_tck) force jtag_tms = 1'b1; // Select-IR-Scan
      @(negedge jtag_tck) force jtag_tms = 1'b0; // Capture-IR
      @(negedge jtag_tck) force jtag_tms = 1'b0; // Shift-IR

      for (i = 0; i < ir_len; i = i + 1) begin
        @(negedge jtag_tck);
        force jtag_tdi = ir_in[i];

        if (i == ir_len - 1) begin
          force jtag_tms = 1'b1; // Exit1-IR
        end else begin
          force jtag_tms = 1'b0; // Shift-IR
        end
      end

      @(negedge jtag_tck);
      force jtag_tms = 1'b1; // Update-IR

      @(negedge jtag_tck);
      force jtag_tms = 1'b0; // Run-Test/Idle

      @(negedge jtag_tck);
    end
  endtask

  task automatic jtag_write_dr(
      input  logic [14:0] dr_in,
      output logic [14:0] dr_out,
      input  integer      dr_len
  );
    integer i;
    begin
      dr_out = '0;

      @(negedge jtag_tck) force jtag_tms = 1'b1; // Select-DR-Scan
      @(negedge jtag_tck) force jtag_tms = 1'b0; // Capture-DR
      @(negedge jtag_tck) force jtag_tms = 1'b0; // Shift-DR

      for (i = 0; i < dr_len; i = i + 1) begin
        @(negedge jtag_tck);
        force jtag_tdi = dr_in[i];
        dr_out[i] = jtag_tdo;

        if (i == dr_len - 1) begin
          force jtag_tms = 1'b1; // Exit1-DR
        end else begin
          force jtag_tms = 1'b0; // Shift-DR
        end
      end

      @(negedge jtag_tck);
      force jtag_tms = 1'b1; // Update-DR

      @(negedge jtag_tck);
      force jtag_tms = 1'b0; // Run-Test/Idle

      @(negedge jtag_tck);
    end
  endtask

  /////////////////
  //  Testbench  //
  /////////////////

  logic [14:0] dr_captured;
  logic [31:0] tb_data;

  initial begin
    $timeformat(-9, 0, "ns", 12);

    // 1. Wait for systemic reset release
    wait (rst_n == 1'b1);
    #100;

    $display("[%0t ns] Overriding JTAG bus for internal March BIST execution...", $time);

    // 2. Intercept JTAG lines via force
    force jtag_trst_n = 1'b0;
    #100;
    force jtag_trst_n = 1'b1;

    // 3. Reset JTAG TAP
    jtag_reset();

    // 4. Send INSTR_MBIST (4'b0010) into IR
    $display("[%0t ns] Sending INSTR_MBIST opcode (4'b0010)...", $time);
    jtag_write_ir(4'b0010, 4);

    // 5. Trigger Update-DR state to initiate March sequence
    jtag_write_dr(15'b0, dr_captured, 15);

    // 6. Monitor BIST execution within the SRAM module hierarchy
    fork
      begin
        wait (
          (i_croc_soc.i_croc.i_sram.i_tc_sram_impl.u_bist_controller.seq_q == i_croc_soc.i_sram.i_tc_sram_impl.u_bist_controller.DONE) || 
          (i_croc_soc.i_croc.i_sram.i_tc_sram_impl.u_bist_controller.seq_q == i_croc_soc.i_sram.i_tc_sram_impl.u_bist_controller.ERR_ABORT)
        );
      end
      begin
        #50000;
        $error("[%0t ns] TIMEOUT: March BIST execution took too long!", $time);
        $finish;
      end
    join_any
    disable fork;

    // 7. Evaluate execution output
    if (i_croc_soc.i_sram.i_tc_sram_impl.u_bist_controller.fail_o) begin
      $display("[%0t ns] >>> MARCH BIST ABORTED / FAILED! <<<", $time);
    end else if (i_croc_soc.i_sram.i_tc_sram_impl.u_bist_controller.done_o) begin
      $display("[%0t ns] >>> MARCH BIST COMPLETED SUCCESSFULLY! <<<", $time);
    end

    // 8. Read out error addresses if failures occurred
    if (i_croc_soc.i_sram.i_tc_sram_impl.u_bist_controller.fail_o) begin
      $display("[%0t ns] Fetching error addresses from BIST FIFO over JTAG...", $time);

      // Load ERRADDR_LOAD instruction (4'b0011) into IR
      jtag_write_ir(4'b0011, 4);

      for (int i = 0; i < P_FIFO_DEPTH; i++) begin
        jtag_write_dr({P_ADDR_WIDTH{1'b0}}, dr_captured, P_ADDR_WIDTH);
        $display("[%0t ns] FIFO Entry [%0d]: Error Address = 0x%0h", 
                 $time, i, dr_captured[P_ADDR_WIDTH-1:0]);
      end
    end

    // 9. Release JTAG bus control back to VIP
    $display("[%0t ns] Releasing JTAG drivers back to VIP...", $time);
    release jtag_tck;
    release jtag_trst_n;
    release jtag_tms;
    release jtag_tdi;

    // 10. Proceed with normal Croc SoC boot routine
    i_vip.jtag_init();
    i_vip.jtag_load_hex(binary_path);

    $display("@%t | [CORE] Waking core via CLINT msip", $time);
    i_vip.jtag_write_reg32(ClintBaseAddr, 32'h1);

    i_vip.jtag_halt();
    i_vip.jtag_resume();

    $display("@%t | [CORE] Wait for end of code...", $time);
    i_vip.jtag_wait_for_eoc(tb_data);

    repeat(50) @(posedge sys_clk);
    $finish();
  end

  ////////////////
  //  Waveform  //
  ////////////////
  initial begin
    `ifdef TRACE_WAVE
      `ifdef VERILATOR
        $dumpfile("croc.fst");
        $dumpvars(1, i_croc_soc);
      `else
        $dumpfile("croc.vcd");
        $dumpvars(1, i_croc_soc);
      `endif
    `endif
  end

  final begin
    `ifdef TRACE_WAVE
      $dumpflush;
    `endif
  end

endmodule