// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

module soc_ctrl_regs #(
  parameter type               obi_req_t = logic,
  parameter type               obi_rsp_t = logic,
  parameter int unsigned BootAddrDefault = 32'h0,

  // MBIST macros: croc SRAM banks first, then any user-domain macros (at most 8)
  parameter int unsigned NumMbistMacros  = croc_pkg::NumSramBanks,

  //Do not override
  parameter int unsigned NumSramBanks    = croc_pkg:: NumSramBanks,
  parameter int unsigned ErrAddrWidth    = $clog2(croc_pkg::SramBankNumWords)  // word address within a bank
) (
  input  logic                        clk_i,
  input  logic                        rst_ni,
  input  obi_req_t                    obi_req_i,
  output obi_rsp_t                    obi_rsp_o,
  // To hardware
  output logic                        fetch_en_o,
  output logic                        sram_dly_o,
  // MBIST Signals
  input  logic [NumMbistMacros-1:0][3:0]mbist_status_i,
  input  logic [NumMbistMacros-1:0][ErrAddrWidth-1:0] mbist_erraddr_i,  // head of each error FIFO
  output logic [NumMbistMacros-1:0]     mbist_start_o,
  output logic [NumMbistMacros-1:0]     mbist_resume_or_reset_o,
  output logic [NumMbistMacros-1:0]     mbist_erraddr_read_o
);
  import croc_pkg::*;
  import soc_ctrl_regs_pkg::*;

  // Read-only hardware info assembled from compile-time configuration.
  // Ordered by what integrators are most likely to change: SoC-level first, then
  // core-level, then memory. Reserved bits leave room for future fields in each group.
  //
  // Field layout (MSB first):
  //   --- SoC ---
  //   [31:28] version         Croc SoC major version (croc_pkg::PulpJtagIdCode.version + 1)
  //   [27]    idma_present    iDMA enabled (croc_pkg::iDMAEnable)
  //   [26:24] reserved        0  (reserved for future SoC-level features)
  //   --- Core ---
  //   [23:21] core_id         Core type: 000=CVE2, 001=Ibex, 111=custom, others are reserved (croc_pkg::CoreId)
  //   [20]    pmp_enable      Core specifics, for CVE2: PMP enabled (croc_pkg::CorePMPEnable)
  //   [19:16] reserved        0  (reserved for future core-level features)
  //   --- Memory ---
  //   [15:13] sram_banks      Number of SRAM banks (croc_pkg::NumSramBanks)
  //   [12:5]  sram_bank_words Words per SRAM bank / 64 (croc_pkg::SramBankNumWords)
  //   [4:0]   reserved        0 (reserved for future memory config details)

  localparam logic [31:0] HwInfoWord = {
    4'(PulpJtagIdCode.version),        // [31:28] version
    1'(iDMAEnable),                    // [27]    idma_present
    3'b0,                              // [26:24] reserved (SoC features)
    3'(CoreId),                        // [23:21] core_id
    1'(CorePMPEnable),                 // [20]    pmp_enable
    4'b0,                              // [19:16] reserved (core features)
    3'(NumSramBanks),                  // [15:12] sram_banks
    8'(SramBankNumWords / 64),         // [11:5]  sram_bank_words (in units of 64 words)
    5'b0                               // [4:0]   reserved
  };

  // read-write registers
  logic [31:0]   boot_addr_d,   boot_addr_q;
  logic           fetch_en_d,    fetch_en_q;
  logic [31:0] core_status_d, core_status_q;
  logic          boot_mode_d,   boot_mode_q;
  logic           sram_dly_d,    sram_dly_q;

  logic [31:0] mbist_start_d          , mbist_start_q;
  logic [31:0] mbist_resume_or_reset_d, mbist_resume_or_reset_q;
  logic [31:0] mbist_erraddr_read_d   , mbist_erraddr_read_q;
  logic [31:0] mbist_status_d         , mbist_status_q;


  `FF(boot_addr_q, boot_addr_d,                         BootAddrDefault, clk_i, rst_ni)
  `FF(fetch_en_q, fetch_en_d,                                 1'b1, clk_i, rst_ni)
  `FF(core_status_q, core_status_d,                             '0, clk_i, rst_ni)
  `FF(boot_mode_q, boot_mode_d,                                 '0, clk_i, rst_ni)
  `FF(sram_dly_q, sram_dly_d,                                   '0, clk_i, rst_ni)
  `FF(mbist_start_q, mbist_start_d,                             '0, clk_i, rst_ni)
  `FF(mbist_resume_or_reset_q, mbist_resume_or_reset_d,         '0, clk_i, rst_ni)
  `FF(mbist_erraddr_read_q, mbist_erraddr_read_d,               '0, clk_i, rst_ni)
  `FF(mbist_status_q, mbist_status_d,                           '0, clk_i, rst_ni)

  // OBI handling, A-phase fields needed in the R-phase
  logic                               req_q;
  logic                               we_q;
  logic [$bits(obi_req_i.a.aid)-1:0]  id_q;
  logic [IntAddrWidth-1:2]            addr_q;  // word-aligned address bits only

  `FF(req_q,  obi_req_i.req,                      '0, clk_i, rst_ni)
  `FF(we_q,   obi_req_i.a.we,                     '0, clk_i, rst_ni)
  `FF(id_q,   obi_req_i.a.aid,                    '0, clk_i, rst_ni)
  `FF(addr_q, obi_req_i.a.addr[IntAddrWidth-1:2], '0, clk_i, rst_ni)

  // byte-enable mask: expands each BE bit to a full byte for masked writes
  logic [31:0] be_mask;
  for (genvar i = 0; unsigned'(i) < 32/8; ++i ) begin : gen_write_mask
    assign be_mask[8*i +: 8] = {8{obi_req_i.a.be[i]}};
  end

  assign fetch_en_o = fetch_en_q;
  assign sram_dly_o = sram_dly_q;

  // Error-address FIFO windows: MBIST_ERRADDR_FIFO_OFFSET0 + 4*i for macro i
  logic [IntAddrWidth-1:0] a_offset, r_offset;
  assign a_offset = {obi_req_i.a.addr[IntAddrWidth-1:2], 2'b00};
  assign r_offset = {addr_q, 2'b00};

  logic                    a_erraddr_hit, r_erraddr_hit;
  logic [IntAddrWidth-3:0] a_erraddr_idx, r_erraddr_idx;
  assign a_erraddr_idx = a_offset[IntAddrWidth-1:2] - MBIST_ERRADDR_FIFO_OFFSET0[IntAddrWidth-1:2];
  assign r_erraddr_idx = r_offset[IntAddrWidth-1:2] - MBIST_ERRADDR_FIFO_OFFSET0[IntAddrWidth-1:2];
  assign a_erraddr_hit = (a_offset >= MBIST_ERRADDR_FIFO_OFFSET0) && (a_erraddr_idx < NumMbistMacros);
  assign r_erraddr_hit = (r_offset >= MBIST_ERRADDR_FIFO_OFFSET0) && (r_erraddr_idx < NumMbistMacros);

  // Pop-on-read: the pop pulse lands in the R phase, so the read returns the current head
  // and the FIFO advances at the end of that cycle.
  logic [NumMbistMacros-1:0] erraddr_pop_d, erraddr_pop_q;
  `FF(erraddr_pop_q, erraddr_pop_d, '0, clk_i, rst_ni)

  always_comb begin
    erraddr_pop_d = '0;
    if (obi_req_i.req && !obi_req_i.a.we && a_erraddr_hit)
      erraddr_pop_d[a_erraddr_idx] = 1'b1;
  end

  // Address phase: update writable registers
  always_comb begin : write_fsm
    boot_addr_d   = boot_addr_q;
    fetch_en_d    = fetch_en_q;
    core_status_d = core_status_q;
    boot_mode_d   = boot_mode_q;
    sram_dly_d    = sram_dly_q;

    mbist_start_d           = '0;
    mbist_resume_or_reset_d = '0;
    mbist_erraddr_read_d    = '0;

    if (obi_req_i.req && obi_req_i.a.we) begin
      unique case ({obi_req_i.a.addr[IntAddrWidth-1:2], 2'b00})
        SOC_CTRL_BOOTADDR_OFFSET    :   boot_addr_d   = obi_req_i.a.wdata & be_mask;
        SOC_CTRL_FETCHEN_OFFSET     :   fetch_en_d    = obi_req_i.a.wdata[0] & be_mask[0];
        SOC_CTRL_CORESTATUS_OFFSET  :   core_status_d = obi_req_i.a.wdata & be_mask;
        SOC_CTRL_BOOTMODE_OFFSET    :   boot_mode_d   = obi_req_i.a.wdata[0] & be_mask[0];
        SOC_CTRL_SRAM_DLY_OFFSET    :   sram_dly_d    = obi_req_i.a.wdata[0] & be_mask[0];

        MBIST_START_OFFSET          :   mbist_start_d           = obi_req_i.a.wdata & be_mask;
        MBIST_RESUME_OR_RESET_OFFSET:   mbist_resume_or_reset_d = obi_req_i.a.wdata & be_mask;
        MBIST_ERRADDR_READ_OFFSET   :   mbist_erraddr_read_d    = obi_req_i.a.wdata & be_mask;
        default: ;  // invalid address: no write, error signalled in R phase
      endcase
    end
  end

  // Response phase: send back read data or acknowledge write
  always_comb begin : obi_response
    obi_rsp_o        = '0;
    obi_rsp_o.gnt    = 1'b1;
    obi_rsp_o.rvalid = req_q;
    obi_rsp_o.r.rid  = id_q;
    mbist_status_d   = mbist_status_i;
    if (req_q) begin
      if (!we_q && r_erraddr_hit) begin
        // valid = fail bit (FIFO not empty) of that macro
        obi_rsp_o.r.rdata = {mbist_status_i[r_erraddr_idx][2], {(31-ErrAddrWidth){1'b0}},
                             mbist_erraddr_i[r_erraddr_idx]};
      end else if (!we_q) begin
        unique case ({addr_q, 2'b00})
          SOC_CTRL_BOOTADDR_OFFSET:   obi_rsp_o.r.rdata = boot_addr_q;
          SOC_CTRL_FETCHEN_OFFSET:    obi_rsp_o.r.rdata = {31'h0, fetch_en_q};
          SOC_CTRL_CORESTATUS_OFFSET: obi_rsp_o.r.rdata = core_status_q;
          SOC_CTRL_BOOTMODE_OFFSET:   obi_rsp_o.r.rdata = {31'h0, boot_mode_q};
          SOC_CTRL_SRAM_DLY_OFFSET:   obi_rsp_o.r.rdata = {31'b0, sram_dly_q};
          SOC_CTRL_INFO_OFFSET:       obi_rsp_o.r.rdata = HwInfoWord;
          MBIST_STATUS_READ_OFFSET0:  obi_rsp_o.r.rdata = mbist_status_q;
          default: begin
            obi_rsp_o.r.rdata = 32'hBADCAB1E;
            obi_rsp_o.r.err   = 1'b1;
          end
        endcase
      end else begin
        unique case ({addr_q, 2'b00})
          SOC_CTRL_BOOTADDR_OFFSET,
          SOC_CTRL_FETCHEN_OFFSET,
          SOC_CTRL_CORESTATUS_OFFSET,
          SOC_CTRL_BOOTMODE_OFFSET,
          SOC_CTRL_SRAM_DLY_OFFSET,
          MBIST_START_OFFSET,          
          MBIST_RESUME_OR_RESET_OFFSET,
          MBIST_ERRADDR_READ_OFFSET   :  ;  // valid write, no error
          default: obi_rsp_o.r.err = 1'b1;
        endcase
      end
    end
  end


assign mbist_start_o            =  mbist_start_q[NumMbistMacros-1:0];
assign mbist_resume_or_reset_o  =  mbist_resume_or_reset_q[NumMbistMacros-1:0];
assign mbist_erraddr_read_o     =  mbist_erraddr_read_q[NumMbistMacros-1:0] | erraddr_pop_q;  // write to 0x48 = discard, read of FIFO window = pop

// One status nibble per macro in MBIST_STATUS_READ_OFFSET0, FIFO windows up to 0x6C
`ifndef SYNTHESIS
initial assert (NumMbistMacros >= NumSramBanks && NumMbistMacros <= 8)
  else $fatal(1, "soc_ctrl_regs: NumMbistMacros must be between NumSramBanks and 8");
`endif

endmodule
