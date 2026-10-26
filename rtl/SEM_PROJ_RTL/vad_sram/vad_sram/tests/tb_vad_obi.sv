`timescale 1ns/1ps

module tb_vad_obi;
  import croc_pkg::*;
  import user_pkg::*;

  localparam int ID_W = SbrObiCfg.IdWidth;

  logic clk = 1'b0;
  logic rst_n;
  sbr_obi_req_t req;
  sbr_obi_rsp_t rsp;
  logic i2s_sclk;
  logic i2s_wsel;
  logic i2s_sdat;
  logic wakeup_event;
  int unsigned event_count;
  int unsigned decision_count;

  always #5 clk = ~clk;

  vad_csr_wrapper dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .obi_req_i(req),
    .obi_rsp_o(rsp),
    .i2s_sclk_o(i2s_sclk),
    .i2s_wsel_o(i2s_wsel),
    .i2s_sdat_i(i2s_sdat),
    .vad_wakeup_event_o(wakeup_event)
  );

  always @(negedge clk) begin
    if (rst_n) begin
      if (wakeup_event)
        event_count++;
      if (dut.u_vad_subsystem.u_vad_dsp.state_q == 2'd3)
        decision_count++;
    end
  end

  task automatic idle_req;
    begin
      req = '0;
    end
  endtask

  task automatic issue(input logic write, input logic [31:0] address,
                       input logic [31:0] data, input logic [3:0] be,
                       input logic [ID_W-1:0] id);
    begin
      @(negedge clk);
      req = '0;
      req.req = 1'b1;
      req.a.addr = address;
      req.a.we = write;
      req.a.wdata = data;
      req.a.be = be;
      req.a.aid = id;
      req.a.a_optional = '0;
      @(posedge clk);
      #1;
      if (rsp.gnt !== 1'b1)
        $fatal(1, "OBI request was not granted at 0x%08x", address);
      if (rsp.rvalid !== 1'b1 || rsp.r.rid !== id || rsp.r.err !== 1'b0)
        $fatal(1, "OBI response mismatch at 0x%08x: valid=%b id=%0d expected=%0d err=%b",
               address, rsp.rvalid, rsp.r.rid, id, rsp.r.err);
      idle_req();
    end
  endtask

  task automatic write32(input logic [31:0] address, input logic [31:0] data,
                         input logic [3:0] be, input logic [ID_W-1:0] id);
    issue(1'b1, address, data, be, id);
  endtask

  task automatic read32(input logic [31:0] address, input logic [31:0] expected,
                        input logic [ID_W-1:0] id);
    begin
      issue(1'b0, address, '0, 4'hf, id);
      if (rsp.rvalid !== 1'b1)
        $fatal(1, "missing read response for 0x%08x", address);
      if (rsp.r.rid !== id)
        $fatal(1, "read response ID mismatch at 0x%08x: got %0d expected %0d",
               address, rsp.r.rid, id);
      if (rsp.r.err !== 1'b0)
        $fatal(1, "unexpected OBI error at 0x%08x", address);
      if (rsp.r.rdata !== expected)
        $fatal(1, "read 0x%08x got 0x%08x expected 0x%08x",
               address, rsp.r.rdata, expected);
    end
  endtask

  task automatic wait_decisions(input int unsigned count);
    int unsigned target;
    begin
      target = decision_count + count;
      wait (decision_count >= target);
      @(negedge clk);
    end
  endtask

  task automatic back_to_back_reads;
    logic [31:0] addresses [0:2];
    logic [31:0] values [0:2];
    logic [ID_W-1:0] ids [0:2];
    begin
      addresses[0] = 32'h20;
      addresses[1] = 32'h24;
      addresses[2] = 32'h28;
      values[0] = 32'h1;
      values[1] = 32'h1234_56dd;
      values[2] = 32'h0000_ab34;
      ids[0] = ID_W'(1);
      ids[1] = ID_W'(2);
      ids[2] = ID_W'(3);
      @(negedge clk);
      for (int i = 0; i < 3; i++) begin
        req = '0;
        req.req = 1'b1;
        req.a.addr = addresses[i];
        req.a.we = 1'b0;
        req.a.be = 4'hf;
        req.a.aid = ids[i];
        @(posedge clk);
        #1;
        if (rsp.rvalid !== 1'b1 || rsp.r.rid !== ids[i] ||
            rsp.r.err !== 1'b0 || rsp.r.rdata !== values[i])
          $fatal(1, "back-to-back read %0d failed: valid=%b id=%0d data=%08x",
                 i, rsp.rvalid, rsp.r.rid, rsp.r.rdata);
        if (i != 2) @(negedge clk);
      end
      idle_req();
      @(posedge clk);
      #1;
      if (rsp.rvalid !== 1'b0)
        $fatal(1, "spurious response after back-to-back reads");
    end
  endtask

  initial begin : run_test
    int unsigned before_events;
    rst_n = 1'b0;
    i2s_sdat = 1'b1;
    idle_req();
    event_count = 0;
    decision_count = 0;
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    read32(32'h20, 32'h0000_0001, ID_W'(1));
    read32(32'h24, 32'h0000_441b, ID_W'(2));
    read32(32'h28, 32'h0000_0014, ID_W'(3));

    // Byte enables independently preserve unselected bytes.
    write32(32'h24, 32'haabb_ccdd, 4'b0010, ID_W'(0));
    read32(32'h24, 32'h0000_cc1b, ID_W'(1));
    write32(32'h24, 32'h1234_56dd, 4'b1111, ID_W'(0));
    write32(32'h28, 32'hbeef_ab34, 4'b0011, ID_W'(0));
    back_to_back_reads();

    // Reserved low-byte offsets return zero and ignore writes. Higher address
    // aliases retain the baseline low-byte decode and still expose only CSRs
    // or name-ROM words, never SRAM contents.
    begin : reserved_checks
      logic [31:0] reserved [0:3];
      reserved[0] = 32'h30;
      reserved[1] = 32'h40;
      reserved[2] = 32'h80;
      reserved[3] = 32'hfc;
      for (int i = 0; i < 4; i++) begin
        write32(reserved[i], 32'hdead_beef, 4'hf, ID_W'(i));
        read32(reserved[i], 32'h0, ID_W'(i+1));
      end
    end
    read32(32'h100, 32'h616e_6e41, ID_W'(1));
    read32(32'h400, 32'h616e_6e41, ID_W'(2));
    read32(32'h120, 32'h1, ID_W'(3));
    read32(32'h124, 32'h1234_56dd, ID_W'(0));
    read32(32'h128, 32'h0000_ab34, ID_W'(1));
    read32(32'h430, 32'h0, ID_W'(2));

    // Through the real I2S serial pin, a constant one stream decodes as -1:
    // energy is FRAME_SIZE and ZCR is zero. Let several complete frames pass
    // before counting so initial receiver alignment is outside the check.
    write32(32'h20, 32'h1, 4'h1, ID_W'(0));
    write32(32'h24, 32'd319, 4'hf, ID_W'(0));
    write32(32'h28, 32'd0, 4'h3, ID_W'(0));
    before_events = event_count;
    wait_decisions(4);
    if (event_count < before_events + 2)
      $fatal(1, "constant-one I2S stream did not produce expected events");

    write32(32'h24, 32'd320, 4'hf, ID_W'(0));
    before_events = event_count;
    wait_decisions(3);
    if (event_count != before_events)
      $fatal(1, "strict energy threshold equality produced an event");

    write32(32'h24, 32'd319, 4'hf, ID_W'(0));
    write32(32'h20, 32'd0, 4'h1, ID_W'(0));
    before_events = event_count;
    wait_decisions(3);
    if (event_count != before_events)
      $fatal(1, "disabled I2S detector produced an event");

    write32(32'h20, 32'd1, 4'h1, ID_W'(0));
    i2s_sdat = 1'b0;
    wait_decisions(4); // allow the serial receiver and frame buffer to settle
    before_events = event_count;
    wait_decisions(3);
    if (event_count != before_events)
      $fatal(1, "constant-zero I2S stream produced an event");

    $display("PASS tb_vad_obi: CSR protocol, byte enables, aliases, and I2S smoke");
    $finish;
  end

  initial begin
    #100_000_000;
    $fatal(1, "tb_vad_obi timeout");
  end
endmodule
