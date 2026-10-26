`timescale 1ns/1ps

module tb_vad_datapath #(
  parameter int FRAME_SIZE = 320
);
  localparam int ADDR_W = (FRAME_SIZE > 1) ? $clog2(FRAME_SIZE) : 1;

  logic clk = 1'b0;
  logic rst_n;
  logic [15:0] audio_data;
  logic audio_valid;
  logic vad_wakeup;
  logic active_read_bank;
  logic [ADDR_W-1:0] read_addr;
  logic [15:0] read_data;
  logic vad_enable;
  logic [31:0] energy_threshold;
  logic [15:0] zcr_threshold;
  logic speech_detected;

  logic [15:0] samples [0:FRAME_SIZE-1];
  logic [15:0] burst_samples [0:2][0:FRAME_SIZE-1];
  logic [47:0] burst_energy [0:2];
  logic [15:0] burst_zcr [0:2];
  logic [2:0] burst_bank;
  longint unsigned expected_energy;
  int unsigned expected_zcr;
  int unsigned checks;
  int unsigned sync_read_checks;

  always #5 clk = ~clk;

  ping_pong_buffer #(
    .FRAME_SIZE(FRAME_SIZE),
    .WORD_WIDTH(16)
  ) buffer_dut (
    .clk_sys_i(clk),
    .rst_sys_ni(rst_n),
    .audio_data_i(audio_data),
    .audio_valid_i(audio_valid),
    .vad_wakeup_o(vad_wakeup),
    .active_read_bank_o(active_read_bank),
    .vad_read_addr_i(read_addr),
    .vad_read_data_o(read_data)
  );

  vad_core #(.FRAME_SIZE(FRAME_SIZE)) core_dut (
    .clk_sys_i(clk),
    .rst_sys_ni(rst_n),
    .vad_wakeup_i(vad_wakeup),
    .sram_addr_o(read_addr),
    .sram_data_i(read_data),
    .speech_detected_o(speech_detected),
    .vad_enable_i(vad_enable),
    .energy_threshold_i(energy_threshold),
    .zcr_threshold_i(zcr_threshold)
  );

  // The wakeup is registered with the final write. The core must spend one
  // full cycle in READ_WAIT after the SRAM captures address zero, then enter
  // PROCESS with the registered macro data available.
  always @(negedge clk) begin
    if (rst_n && vad_wakeup) begin
      @(posedge clk);
      #1;
      if (core_dut.state_q != 2'd1)
        $fatal(1, "core did not enter READ_WAIT after frame wakeup");
      @(posedge clk);
      #1;
      if (core_dut.state_q != 2'd2)
        $fatal(1, "core did not wait for synchronous SRAM data");
      sync_read_checks++;
    end
  end

  function automatic logic signed [15:0] reconstructed(input logic [15:0] raw);
    reconstructed = {raw[14], raw[14:0]};
  endfunction

  task automatic score_frame;
    logic signed [15:0] value;
    logic previous_sign;
    longint signed wide_value;
    begin
      expected_energy = 0;
      expected_zcr = 0;
      previous_sign = 1'b0;
      for (int i = 0; i < FRAME_SIZE; i++) begin
        value = reconstructed(samples[i]);
        wide_value = $signed({{48{value[15]}}, value});
        expected_energy += wide_value * wide_value;
        if ((i > 0) && (value[15] != previous_sign))
          expected_zcr++;
        previous_sign = value[15];
      end
    end
  endtask

  task automatic pulse_audio(input logic [15:0] value);
    begin
      @(negedge clk);
      audio_data = value;
      audio_valid = 1'b1;
      @(negedge clk);
      audio_valid = 1'b0;
      repeat (2) @(negedge clk);
    end
  endtask

  task automatic write_complete_frame;
    begin
      for (int i = 0; i < FRAME_SIZE; i++)
        pulse_audio(samples[i]);
    end
  endtask

  task automatic wait_for_decision;
    int unsigned cycles;
    begin
      cycles = 0;
      while (core_dut.state_q != 2'd3 && cycles < (FRAME_SIZE * 3 + 12)) begin
        @(negedge clk);
        cycles++;
      end
      if (core_dut.state_q != 2'd3)
        $fatal(1, "timeout waiting for DECIDE at FRAME_SIZE=%0d", FRAME_SIZE);
      #1;
    end
  endtask

  task automatic check_decision(input logic expected_event, input string label);
    begin
      wait_for_decision();
      if (core_dut.energy_acc_q !== expected_energy[47:0])
        $fatal(1, "%s energy mismatch: got %0d expected %0d", label,
               core_dut.energy_acc_q, expected_energy);
      if (core_dut.zcr_acc_q !== expected_zcr[15:0])
        $fatal(1, "%s ZCR mismatch: got %0d expected %0d", label,
               core_dut.zcr_acc_q, expected_zcr);
      if (speech_detected !== expected_event)
        $fatal(1, "%s decision mismatch: got %b expected %b (energy=%0d zcr=%0d)",
               label, speech_detected, expected_event, expected_energy, expected_zcr);
      checks++;
      @(negedge clk);
    end
  endtask

  task automatic set_pattern(input int unsigned pattern);
    begin
      for (int i = 0; i < FRAME_SIZE; i++) begin
        case (pattern)
          0: samples[i] = (i % 2 == 0) ? 16'h7fff : 16'h0002;
          1: samples[i] = (i % 3 == 0) ? 16'h3fff : 16'h4001;
          2: samples[i] = (i == 0) ? 16'h4000 :
                          (i == FRAME_SIZE-1) ? 16'h3fff :
                          (i % 5 == 0) ? 16'h0000 : 16'h7fff;
          default: samples[i] = (i % 2 == 0) ? 16'hc000 : 16'h3fff;
        endcase
      end
      score_frame();
    end
  endtask

  initial begin : run_test
    int unsigned half_frame;
    logic first_burst_bank;
    checks = 0;
    sync_read_checks = 0;
    rst_n = 1'b0;
    audio_data = '0;
    audio_valid = 1'b0;
    vad_enable = 1'b1;
    energy_threshold = '0;
    zcr_threshold = '1;

    if (FRAME_SIZE < 2 || FRAME_SIZE > 512)
      $fatal(1, "FRAME_SIZE must be in [2,512], got %0d", FRAME_SIZE);

    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // Bank zero, including first and last samples. Equality on energy must not
    // trigger; the next comparison verifies the strict greater-than rule and
    // that equality on ZCR is accepted.
    set_pattern(0);
    energy_threshold = expected_energy[31:0];
    zcr_threshold = expected_zcr[15:0];
    write_complete_frame();
    check_decision(1'b0, "energy equality");
    energy_threshold = expected_energy[31:0] - 1;
    write_complete_frame();
    check_decision(1'b1, "ZCR equality and energy greater-than");

    // Bank one gets a different content pattern; its sign transitions include
    // negative values and ensure the physical bank selection alternates.
    set_pattern(1);
    energy_threshold = expected_energy[31:0] - 1;
    zcr_threshold = expected_zcr[15:0];
    write_complete_frame();
    check_decision(1'b1, "alternating bank with negative samples");
    zcr_threshold = (expected_zcr == 0) ? 0 : expected_zcr[15:0] - 1;
    write_complete_frame();
    check_decision(1'b0, "ZCR threshold below reference");

    // Exercise explicit bit-14 sign reconstruction for -16384, +16383, and
    // zero. The endpoint values are placed at address 0 and FRAME_SIZE-1.
    set_pattern(2);
    energy_threshold = expected_energy[31:0] - 1;
    zcr_threshold = expected_zcr[15:0];
    write_complete_frame();
    check_decision(1'b1, "min/max/zero and endpoint addresses");

    // Disable suppresses an otherwise positive result.
    set_pattern(3);
    energy_threshold = '0;
    zcr_threshold = expected_zcr[15:0];
    vad_enable = 1'b0;
    write_complete_frame();
    check_decision(1'b0, "disabled detector");
    vad_enable = 1'b1;

    // Reset during capture discards the partial old frame. The next complete
    // frame must have exactly its own energy and ZCR.
    half_frame = FRAME_SIZE / 2;
    set_pattern(0);
    for (int i = 0; i < half_frame; i++) pulse_audio(samples[i]);
    @(negedge clk);
    rst_n = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    set_pattern(2);
    energy_threshold = expected_energy[31:0] - 1;
    zcr_threshold = expected_zcr[15:0];
    write_complete_frame();
    check_decision(1'b1, "reset during capture");

    // Reset while the core is partway through its synchronous SRAM scan.
    set_pattern(1);
    for (int i = 0; i < FRAME_SIZE; i++) pulse_audio(samples[i]);
    wait (core_dut.state_q == 2'd2 &&
          int'(core_dut.addr_q) >= (FRAME_SIZE / 2));
    @(negedge clk);
    rst_n = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    set_pattern(3);
    energy_threshold = expected_energy[31:0] - 1;
    zcr_threshold = expected_zcr[15:0];
    write_complete_frame();
    check_decision(1'b1, "reset during compute");

    // Prepare three distinct, consecutive frames. The MSB is flipped on
    // alternating samples while the lower 15 bits stay fixed, checking that
    // the bit-14 reconstruction remains independent of the noisy raw MSB.
    first_burst_bank = buffer_dut.write_bank;
    for (int f = 0; f < 3; f++) begin
      burst_bank[f] = first_burst_bank ^ 1'(f);
      for (int i = 0; i < FRAME_SIZE; i++) begin
        case (f)
          0: samples[i] = (i % 2 == 0) ? 16'h3fff : 16'h4001;
          1: samples[i] = (i % 5 == 0) ? 16'h4000 : 16'h0001;
          default: samples[i] = (i % 2 == 0) ? 16'h7fff : 16'h3ffe;
        endcase
        if (i % 2 == 0)
          samples[i][15] = ~samples[i][15];
        burst_samples[f][i] = samples[i];
      end
      score_frame();
      burst_energy[f] = expected_energy[47:0];
      burst_zcr[f] = expected_zcr[15:0];
    end
    if (burst_energy[0] == burst_energy[1] ||
        burst_energy[1] == burst_energy[2] ||
        burst_energy[0] == burst_energy[2])
      $fatal(1, "concurrent burst patterns must have distinct energies");

    // Keep writing at the four-cycle minimum while the checker independently
    // follows each DECIDE. The next bank starts receiving a frame while the
    // DSP is still reading the completed frame from the other bank.
    vad_enable = 1'b1;
    energy_threshold = 32'd0;
    zcr_threshold = 16'hffff;
    fork
      begin : burst_producer
        for (int f = 0; f < 3; f++) begin
          for (int i = 0; i < FRAME_SIZE; i++) begin
            if ((f > 0) && (i == 0) && (core_dut.state_q == 2'd0))
              $fatal(1, "next frame did not begin during the prior DSP scan");
            pulse_audio(burst_samples[f][i]);
          end
        end
      end
      begin : burst_checker
        for (int f = 0; f < 3; f++) begin
          wait (core_dut.state_q == 2'd3);
          #1;
          if (core_dut.energy_acc_q !== burst_energy[f])
            $fatal(1, "concurrent frame %0d energy got %0d expected %0d",
                   f, core_dut.energy_acc_q, burst_energy[f]);
          if (core_dut.zcr_acc_q !== burst_zcr[f])
            $fatal(1, "concurrent frame %0d ZCR got %0d expected %0d",
                   f, core_dut.zcr_acc_q, burst_zcr[f]);
          if (speech_detected !== 1'b1)
            $fatal(1, "concurrent frame %0d did not trigger", f);
          if (active_read_bank !== burst_bank[f])
            $fatal(1, "concurrent frame %0d read bank got %b expected %b",
                   f, active_read_bank, burst_bank[f]);
          @(negedge clk);
          wait (core_dut.state_q != 2'd3);
        end
      end
    join

    if (checks < 8)
      $fatal(1, "insufficient datapath checks: %0d", checks);
    if (sync_read_checks < 8)
      $fatal(1, "insufficient synchronous read checks: %0d", sync_read_checks);
    $display("PASS tb_vad_datapath FRAME_SIZE=%0d checks=%0d", FRAME_SIZE, checks);
    $finish;
  end

  initial begin
    #20_000_000;
    $fatal(1, "tb_vad_datapath timeout FRAME_SIZE=%0d", FRAME_SIZE);
  end
endmodule
