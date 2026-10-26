`timescale 1ns/1ps

// Checks the SRAM debug CSRs of vad_csr_wrapper: CPU write/read of both frame
// banks, auto-increment, read forwarding, audio drop in debug mode, running the
// VAD core on a CPU-written frame (KICK) and the sticky speech flag.
module tb_vad_sram_dbg;
  import croc_pkg::*;
  import user_pkg::*;

  localparam int ID_W       = SbrObiCfg.IdWidth;
  localparam int FRAME_SIZE = 320;

  localparam logic [31:0] VAD_ENABLE    = 32'h20;
  localparam logic [31:0] ENERGY_THRESH = 32'h24;
  localparam logic [31:0] ZCR_THRESH    = 32'h28;
  localparam logic [31:0] SRAM_CTRL     = 32'h2C;
  localparam logic [31:0] SRAM_ADDR     = 32'h30;
  localparam logic [31:0] SRAM_WDATA    = 32'h34;
  localparam logic [31:0] SRAM_CMD      = 32'h38;
  localparam logic [31:0] SRAM_RDATA    = 32'h3C;
  localparam logic [31:0] SRAM_STATUS   = 32'h40;
  localparam logic [31:0] LAST_ENERGY_LO = 32'h44;
  localparam logic [31:0] LAST_ENERGY_HI = 32'h48;
  localparam logic [31:0] LAST_ZCR       = 32'h4C;

  localparam logic [31:0] CTRL_DBG_EN   = 32'h1;
  localparam logic [31:0] CTRL_BANK1    = 32'h2;
  localparam logic [31:0] CTRL_AUTO_INC = 32'h4;
  localparam logic [31:0] CTRL_IRQ_EN   = 32'h8;
  localparam logic [31:0] CMD_WRITE     = 32'h1;
  localparam logic [31:0] CMD_READ      = 32'h2;
  localparam logic [31:0] CMD_KICK      = 32'h4;
  localparam logic [31:0] CMD_EVAL      = 32'h8;

  logic clk = 1'b0;
  logic rst_n;
  sbr_obi_req_t req;
  sbr_obi_rsp_t rsp;
  logic i2s_sclk;
  logic i2s_wsel;
  logic i2s_sdat;
  logic wakeup_event;
  logic vad_irq;

  // MBIST ports (normally driven by soc_ctrl_regs), index = frame bank
  logic [1:0]      mbist_start = '0;
  logic [1:0]      mbist_resume = '0;
  logic [1:0]      mbist_erraddr_rd = '0;
  logic [1:0][3:0] mbist_status;     // {pause, fail, busy, done}
  logic [1:0][8:0] mbist_erraddr;

  // Stuck-at-1 fault injection into bank 1: bit fault_bit of words fault_lo..fault_hi
  logic        fault_on = 1'b0;
  int unsigned fault_lo, fault_hi, fault_bit;
  int unsigned event_count;
  int unsigned checks;

  always #5 clk = ~clk;

  vad_csr_wrapper dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .obi_req_i(req),
    .obi_rsp_o(rsp),
    .i2s_sclk_o(i2s_sclk),
    .i2s_wsel_o(i2s_wsel),
    .i2s_sdat_i(i2s_sdat),
    .vad_wakeup_event_o(wakeup_event),
    .vad_irq_o(vad_irq),
    .mbist_start_i(mbist_start),
    .mbist_resume_i(mbist_resume),
    .mbist_erraddrread_i(mbist_erraddr_rd),
    .mbist_status_o(mbist_status),
    .mbist_erraddr_o(mbist_erraddr)
  );

  always @(negedge clk)
    if (rst_n && wakeup_event)
      event_count++;

  // One OBI transaction per cycle: consecutive calls issue back-to-back requests
  task automatic issue(input logic write, input logic [31:0] address,
                       input logic [31:0] data, output logic [31:0] rdata);
    begin
      @(negedge clk);
      req = '0;
      req.req = 1'b1;
      req.a.addr = address;
      req.a.we = write;
      req.a.wdata = data;
      req.a.be = 4'hf;
      req.a.aid = '0;
      @(posedge clk);
      #1;
      if (rsp.gnt !== 1'b1 || rsp.rvalid !== 1'b1 || rsp.r.err !== 1'b0)
        $fatal(1, "OBI handshake failed at 0x%08x", address);
      rdata = rsp.r.rdata;
      req = '0;
    end
  endtask

  task automatic write32(input logic [31:0] address, input logic [31:0] data);
    logic [31:0] unused;
    issue(1'b1, address, data, unused);
  endtask

  task automatic read32(input logic [31:0] address, input logic [31:0] expected,
                        input string what);
    logic [31:0] rdata;
    issue(1'b0, address, '0, rdata);
    if (rdata !== expected)
      $fatal(1, "%s: read 0x%02x got 0x%08x expected 0x%08x", what, address, rdata, expected);
    checks++;
  endtask

  task automatic read_status(output logic [31:0] status);
    issue(1'b0, SRAM_STATUS, '0, status);
  endtask

  function automatic logic [15:0] pattern(input int bank, input int addr);
    return (bank != 0) ? ~(16'(addr) ^ 16'h5A5A) : (16'(addr) ^ 16'hA5A5);
  endfunction

  task automatic fill_bank(input int bank, input int words, input bit use_pattern,
                           input logic [15:0] value);
    write32(SRAM_CTRL, CTRL_DBG_EN | CTRL_AUTO_INC | ((bank != 0) ? CTRL_BANK1 : 32'h0));
    write32(SRAM_ADDR, 32'h0);
    for (int i = 0; i < words; i++) begin
      write32(SRAM_WDATA, {16'h0, use_pattern ? pattern(bank, i) : value});
      write32(SRAM_CMD, CMD_WRITE);
    end
  endtask

  // Re-applied after every clock edge, so the cell reads back 1 whatever was written
  always @(negedge clk)
    if (fault_on)
      for (int unsigned w = fault_lo; w <= fault_hi; w++)
        dut.u_vad_subsystem.u_i2s_ingestion.u_ping_pong.u_bank_1.u_frame_sram
          .i_SRAM_1P_behavioral_bm_bist.memory[w][fault_bit] = 1'b1;

  task automatic mbist_pulse(input int which, input int bank);
    @(negedge clk);
    case (which)
      0: mbist_start[bank]      = 1'b1;
      1: mbist_resume[bank]     = 1'b1;
      2: mbist_erraddr_rd[bank] = 1'b1;
      default: ;
    endcase
    @(negedge clk);
    mbist_start = '0; mbist_resume = '0; mbist_erraddr_rd = '0;
    repeat (2) @(negedge clk); // status is registered
  endtask

  // Pops every logged error address of one bank; checks each lies in lo..hi
  task automatic mbist_drain(input int bank, input int unsigned lo, input int unsigned hi,
                             inout int unsigned count);
    while (mbist_status[bank][2]) begin
      if (32'(mbist_erraddr[bank]) < lo || 32'(mbist_erraddr[bank]) > hi)
        $fatal(1, "MBIST bank %0d logged address %0d, expected %0d..%0d",
               bank, mbist_erraddr[bank], lo, hi);
      count++;
      mbist_pulse(2, bank);
    end
  endtask

  // Runs the march on one bank like the software driver: drain on pause, resume, wait done
  task automatic mbist_run(input int bank, input int unsigned lo, input int unsigned hi,
                           output int unsigned errors, output int unsigned pauses,
                           output bit failed);
    int unsigned cycles = 0;
    errors = 0; pauses = 0; failed = 1'b0;
    mbist_pulse(0, bank);
    if (mbist_status[bank][1] !== 1'b1) $fatal(1, "MBIST bank %0d did not start", bank);
    while (mbist_status[bank][0] !== 1'b1) begin
      if (mbist_status[bank][3]) begin
        pauses++; failed = 1'b1;
        mbist_drain(bank, lo, hi, errors);
        mbist_pulse(1, bank);
      end
      @(negedge clk);
      if (++cycles > 50_000) $fatal(1, "MBIST bank %0d timed out", bank);
    end
    if (mbist_status[bank][2]) failed = 1'b1;
    mbist_drain(bank, lo, hi, errors);
    mbist_pulse(1, bank); // St_Done -> St_Idle
    if (mbist_status[bank] !== 4'b0000)
      $fatal(1, "MBIST bank %0d status 0x%0h after reset, expected 0", bank, mbist_status[bank]);
  endtask

  task automatic kick_and_wait(input int bank);
    write32(SRAM_CTRL, CTRL_DBG_EN | ((bank != 0) ? CTRL_BANK1 : 32'h0));
    write32(SRAM_CMD, CMD_KICK);
    // READ_WAIT + PROCESS per sample, plus wakeup and DECIDE
    repeat (2 * FRAME_SIZE + 10) @(posedge clk);
  endtask

  initial begin
    logic [31:0] status, status2;
    int unsigned events_before;

    req = '0;
    i2s_sdat = 1'b0;
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // Reset values
    read32(SRAM_CTRL,  32'h0, "reset SRAM_CTRL");
    read32(SRAM_ADDR,  32'h0, "reset SRAM_ADDR");
    read32(SRAM_WDATA, 32'h0, "reset SRAM_WDATA");
    read32(SRAM_RDATA, 32'h0, "reset SRAM_RDATA");
    read_status(status);
    if (status[0] !== 1'b0 || status[1] !== 1'b1 || status[2] !== 1'b0 || status[3] !== 1'b0)
      $fatal(1, "reset SRAM_STATUS 0x%08x", status);

    // Register read-back and field masking
    write32(SRAM_CTRL, 32'hffff_fff0 | CTRL_IRQ_EN | CTRL_AUTO_INC | CTRL_BANK1);
    read32(SRAM_CTRL, CTRL_IRQ_EN | CTRL_AUTO_INC | CTRL_BANK1, "SRAM_CTRL masking");
    write32(SRAM_CTRL, 32'h0);
    write32(SRAM_ADDR, 32'hffff_ffff);
    read32(SRAM_ADDR, 32'h1ff, "SRAM_ADDR masking");
    write32(SRAM_WDATA, 32'hdead_beef);
    read32(SRAM_WDATA, 32'h0000_beef, "SRAM_WDATA masking");
    read32(SRAM_CMD, 32'h0, "SRAM_CMD reads zero");

    // Commands are ignored while DBG_EN is clear: no access, no auto-increment
    write32(SRAM_ADDR, 32'h5);
    write32(SRAM_CMD, CMD_WRITE | CMD_READ | CMD_KICK);
    read32(SRAM_ADDR, 32'h5, "no auto-increment without DBG_EN");
    read32(SRAM_RDATA, 32'h0, "no read without DBG_EN");
    read_status(status);
    if (status[3] !== 1'b0) $fatal(1, "read pending without DBG_EN");

    // Fill the whole macro depth of both banks, then read everything back
    fill_bank(0, 512, 1'b1, '0);
    read32(SRAM_ADDR, 32'h0, "auto-increment wraps at 512");
    fill_bank(1, 512, 1'b1, '0);
    for (int bank = 0; bank < 2; bank++) begin
      write32(SRAM_CTRL, CTRL_DBG_EN | CTRL_AUTO_INC | ((bank != 0) ? CTRL_BANK1 : 32'h0));
      write32(SRAM_ADDR, 32'h0);
      for (int i = 0; i < 512; i++) begin
        write32(SRAM_CMD, CMD_READ);
        // Issued in the next cycle: exercises forwarding of the in-flight read
        read32(SRAM_RDATA, {16'h0, pattern(bank, i)}, $sformatf("bank %0d word %0d", bank, i));
      end
    end

    // Captured read data stays stable afterwards
    write32(SRAM_CTRL, CTRL_DBG_EN);
    write32(SRAM_ADDR, 32'd77);
    write32(SRAM_CMD, CMD_READ);
    repeat (20) @(posedge clk);
    read32(SRAM_RDATA, {16'h0, pattern(0, 77)}, "captured read data");
    read32(SRAM_ADDR, 32'd77, "no auto-increment when AUTO_INC is clear");

    // Audio is dropped in debug mode: the writer does not advance
    i2s_sdat = 1'b1;
    read_status(status);
    repeat (20 * 16 * 32) @(posedge clk); // about 20 I2S samples
    read_status(status2);
    if (status2[12:4] !== status[12:4] || status2[2] !== status[2])
      $fatal(1, "audio writer advanced in debug mode: 0x%08x -> 0x%08x", status, status2);
    read32(SRAM_RDATA, {16'h0, pattern(0, 77)}, "SRAM untouched by audio in debug mode");
    i2s_sdat = 1'b0;

    // KICK: a frame of -1 samples has energy FRAME_SIZE and zero ZCR
    write32(VAD_ENABLE, 32'h1);
    write32(ENERGY_THRESH, FRAME_SIZE - 1);
    write32(ZCR_THRESH, 32'h0);
    fill_bank(1, FRAME_SIZE, 1'b0, 16'hffff);
    events_before = event_count;
    kick_and_wait(1);
    if (event_count != events_before + 1) $fatal(1, "KICK on bank 1 did not detect speech");
    read_status(status);
    if (status[0] !== 1'b1) $fatal(1, "sticky speech flag not set");
    // Interrupt is a level that follows the sticky flag when enabled
    if (vad_irq !== 1'b0) $fatal(1, "interrupt asserted while IRQ_EN is clear");
    write32(SRAM_CTRL, CTRL_DBG_EN | CTRL_BANK1 | CTRL_IRQ_EN);
    repeat (50) @(posedge clk);
    if (vad_irq !== 1'b1) $fatal(1, "interrupt not held high by the sticky flag");
    write32(SRAM_STATUS, 32'h0);
    read_status(status);
    if (status[0] !== 1'b1 || vad_irq !== 1'b1) $fatal(1, "sticky flag cleared by writing 0");
    write32(SRAM_STATUS, 32'h1);
    read_status(status);
    if (status[0] !== 1'b0) $fatal(1, "sticky flag not cleared by W1C");
    if (vad_irq !== 1'b0) $fatal(1, "interrupt not released after W1C");
    write32(SRAM_CTRL, CTRL_DBG_EN | CTRL_BANK1);

    // Same frame, energy threshold equal to the energy: no detection
    write32(ENERGY_THRESH, FRAME_SIZE);
    events_before = event_count;
    kick_and_wait(1);
    if (event_count != events_before) $fatal(1, "KICK detected speech at energy == threshold");

    // The core reads BANK_SEL: a silent frame in bank 0 must not detect,
    // although bank 1 would with this threshold
    write32(ENERGY_THRESH, FRAME_SIZE - 1);
    fill_bank(0, FRAME_SIZE, 1'b0, 16'h0000);
    events_before = event_count;
    kick_and_wait(0);
    if (event_count != events_before) $fatal(1, "KICK on bank 0 used bank 1 data");
    read_status(status);
    if (status[0] !== 1'b0) $fatal(1, "sticky flag set without detection");
    checks += 6;

    // Last frame result: kept after the frame, matches a model of the core
    begin : last_result_checks
      logic [47:0] energy;
      logic [15:0] zcr;
      logic signed [15:0] sample;
      logic [15:0] word;
      logic prev;

      read32(LAST_ENERGY_LO, 32'h0, "LAST_ENERGY_LO of the silent frame");
      read32(LAST_ZCR, 32'h0, "LAST_ZCR of the silent frame");

      fill_bank(0, FRAME_SIZE, 1'b1, '0);
      energy = '0; zcr = '0; prev = 1'b0;
      for (int i = 0; i < FRAME_SIZE; i++) begin
        word   = pattern(0, i);
        sample = {word[14], word[14:0]}; // same sign repair as vad_core
        energy += 48'(32'(sample) * 32'(sample));
        if (i > 0 && sample[15] != prev) zcr++;
        prev = sample[15];
      end
      kick_and_wait(0);
      read32(LAST_ENERGY_LO, energy[31:0], "LAST_ENERGY_LO of the pattern frame");
      read32(LAST_ENERGY_HI, {16'h0, energy[47:32]}, "LAST_ENERGY_HI of the pattern frame");
      read32(LAST_ZCR, {16'h0, zcr}, "LAST_ZCR of the pattern frame");

      // Software can overwrite the stored result; unused bits read zero
      write32(LAST_ENERGY_LO, 32'hdead_beef);
      write32(LAST_ENERGY_HI, 32'hffff_1234);
      write32(LAST_ZCR, 32'hffff_abcd);
      read32(LAST_ENERGY_LO, 32'hdead_beef, "LAST_ENERGY_LO write");
      read32(LAST_ENERGY_HI, 32'h0000_1234, "LAST_ENERGY_HI write");
      read32(LAST_ZCR, 32'h0000_abcd, "LAST_ZCR write");

      // EVAL runs the speech decision on the stored values
      write32(ENERGY_THRESH, 32'd1000);
      write32(ZCR_THRESH, 32'd5);
      write32(SRAM_STATUS, 32'h1);
      begin : eval_cases
        // energy hi, energy lo, zcr, vad enable, DBG_EN, expected detection
        logic [15:0] e_hi [7] = '{16'h0, 16'h0, 16'h1, 16'h0, 16'h0, 16'h0, 16'h0};
        logic [31:0] e_lo [7] = '{32'd1001, 32'd1000, 32'd0, 32'd5000, 32'd5000, 32'd5000, 32'd5000};
        logic [15:0] z    [7] = '{16'd5, 16'd0, 16'd5, 16'd6, 16'd0, 16'd0, 16'd0};
        bit          en   [7] = '{1, 1, 1, 1, 0, 1, 1};
        bit          dbg  [7] = '{1, 1, 1, 1, 1, 0, 1};
        bit          exp  [7] = '{1, 0, 1, 0, 0, 0, 1};
        for (int c = 0; c < 7; c++) begin
          write32(LAST_ENERGY_HI, {16'h0, e_hi[c]});
          write32(LAST_ENERGY_LO, e_lo[c]);
          write32(LAST_ZCR, {16'h0, z[c]});
          write32(VAD_ENABLE, {31'h0, en[c]});
          write32(SRAM_CTRL, dbg[c] ? CTRL_DBG_EN : 32'h0);
          events_before = event_count;
          write32(SRAM_CMD, CMD_EVAL);
          repeat (3) @(posedge clk);
          read_status(status);
          if (event_count != events_before + 32'(exp[c]) || status[0] !== exp[c])
            $fatal(1, "EVAL case %0d: events %0d status 0x%08x, expected detection %0d",
                   c, event_count - events_before, status, exp[c]);
          // EVAL leaves the stored values untouched
          read32(LAST_ENERGY_LO, e_lo[c], $sformatf("EVAL case %0d keeps LAST_ENERGY_LO", c));
          read32(LAST_ZCR, {16'h0, z[c]}, $sformatf("EVAL case %0d keeps LAST_ZCR", c));
          write32(SRAM_STATUS, 32'h1);
        end
      end

      // The next frame replaces inserted values
      write32(SRAM_CTRL, CTRL_DBG_EN);
      kick_and_wait(0);
      read32(LAST_ENERGY_LO, energy[31:0], "frame overwrites inserted LAST_ENERGY_LO");
      read32(LAST_ZCR, {16'h0, zcr}, "frame overwrites inserted LAST_ZCR");
      write32(VAD_ENABLE, 32'h1);
      write32(SRAM_STATUS, 32'h1);
    end

    // MBIST of the frame SRAMs (DBG_EN stays set, so no audio or VAD access meanwhile)
    begin : mbist_checks
      int unsigned errors, pauses;
      bit failed;
      int unsigned probe [5] = '{0, 5, 77, 319, 511};

      if (mbist_status !== '0) $fatal(1, "MBIST status not idle after reset");

      // Marker in bank 0 must survive a BIST of bank 1
      write32(SRAM_CTRL, CTRL_DBG_EN);
      write32(SRAM_ADDR, 32'd5);
      write32(SRAM_WDATA, 32'h0000_5a5a);
      write32(SRAM_CMD, CMD_WRITE);

      // Fault-free banks pass and are left all zeros
      mbist_run(1, 0, 0, errors, pauses, failed);
      if (failed || errors != 0) $fatal(1, "fault-free bank 1 failed MBIST (%0d errors)", errors);
      write32(SRAM_CTRL, CTRL_DBG_EN);
      write32(SRAM_ADDR, 32'd5);
      write32(SRAM_CMD, CMD_READ);
      read32(SRAM_RDATA, 32'h0000_5a5a, "bank 0 untouched by bank 1 MBIST");
      mbist_run(0, 0, 0, errors, pauses, failed);
      if (failed || errors != 0) $fatal(1, "fault-free bank 0 failed MBIST (%0d errors)", errors);
      for (int bank = 0; bank < 2; bank++)
        for (int i = 0; i < 5; i++) begin
          write32(SRAM_CTRL, CTRL_DBG_EN | ((bank != 0) ? CTRL_BANK1 : 32'h0));
          write32(SRAM_ADDR, probe[i]);
          write32(SRAM_CMD, CMD_READ);
          read32(SRAM_RDATA, 32'h0, $sformatf("bank %0d word %0d zero after MBIST", bank, probe[i]));
        end

      // One stuck-at-1 cell: r0 fails once per address in stages 1, 3 and 5
      fault_lo = 77; fault_hi = 77; fault_bit = 0; fault_on = 1'b1;
      mbist_run(1, 77, 77, errors, pauses, failed);
      if (!failed || errors != 3 || pauses != 0)
        $fatal(1, "single fault: failed=%0d errors=%0d pauses=%0d, expected 1/3/0",
               failed, errors, pauses);

      // Five faulty words: the 4-entry FIFO fills, the march pauses and resumes
      fault_lo = 10; fault_hi = 14; fault_bit = 20;
      mbist_run(1, 10, 14, errors, pauses, failed);
      if (!failed || errors != 15 || pauses == 0)
        $fatal(1, "multi fault: failed=%0d errors=%0d pauses=%0d, expected 1/15/>0",
               failed, errors, pauses);
      fault_on = 1'b0;

      // Functional port works again after MBIST
      write32(SRAM_CTRL, CTRL_DBG_EN | CTRL_BANK1);
      write32(SRAM_ADDR, 32'd200);
      write32(SRAM_WDATA, 32'h0000_1234);
      write32(SRAM_CMD, CMD_WRITE);
      write32(SRAM_CMD, CMD_READ);
      read32(SRAM_RDATA, 32'h0000_1234, "functional access after MBIST");
      checks += 6;
    end

    // Leaving debug mode resumes normal audio capture and detection
    write32(ENERGY_THRESH, FRAME_SIZE - 1);
    write32(SRAM_CTRL, 32'h0);
    i2s_sdat = 1'b1;
    events_before = event_count;
    repeat (4 * FRAME_SIZE * 16 * 32) @(posedge clk); // about four frames
    if (event_count < events_before + 2) $fatal(1, "normal operation did not resume after debug mode");
    read_status(status);
    if (status[0] !== 1'b1) $fatal(1, "sticky flag not set in normal operation");

    $display("PASS tb_vad_sram_dbg checks=%0d", checks + 1);
    $finish;
  end

endmodule
