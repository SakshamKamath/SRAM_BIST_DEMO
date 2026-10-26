// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Adapted from submissions/vlsi2_21fs26/rtl/user_domain.sv.
// Original author: Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"

module user_domain
  import user_pkg::*;
  import croc_pkg::*;
#(
  parameter int unsigned GpioCount = 16,
  parameter int unsigned NumExternalIrqs = 4
) (
  input  logic clk_i,
  input  logic ref_clk_i,
  input  logic rst_ni,
  input  logic testmode_i,

  input  sbr_obi_req_t user_sbr_obi_req_i,
  output sbr_obi_rsp_t user_sbr_obi_rsp_o,
  output mgr_obi_req_t user_mgr_obi_req_o,
  input  mgr_obi_rsp_t user_mgr_obi_rsp_i,

  input  logic [GpioCount-1:0] gpio_in_sync_i,
  output logic [NumExternalIrqs-1:0] interrupts_o,

  output logic vad_i2s_sclk_o,
  output logic vad_i2s_wsel_o,
  input  logic vad_i2s_sdat_i,

  // MBIST of the VAD frame SRAMs, driven by soc_ctrl_regs (index 0 = bank 0, 1 = bank 1)
  input  logic [NumUserMbistMacros-1:0]       mbist_start_i,
  input  logic [NumUserMbistMacros-1:0]       mbist_resume_or_reset_i,
  input  logic [NumUserMbistMacros-1:0]       mbist_erraddr_read_i,
  output logic [NumUserMbistMacros-1:0][3:0]  mbist_status_o,
  output logic [NumUserMbistMacros-1:0][8:0]  mbist_erraddr_o
);

  // Audio capture writes the internal SRAM directly; there is no OBI manager.
  assign user_mgr_obi_req_o = '0;

  sbr_obi_req_t [NumDemuxSbr-1:0] subordinate_req;
  sbr_obi_rsp_t [NumDemuxSbr-1:0] subordinate_rsp;
  typedef logic [cf_math_pkg::idx_width(NumDemuxSbr)-1:0] user_idx_t;
  user_idx_t user_idx;

  // Decode from a local copy of the request. With the fully optimized QuestaSim 2023.4 build
  // (vlog -svinputport=compat), logic fed by a member of the input port struct was not
  // re-evaluated, so every access was decoded to UserError. Functionally a plain wire.
  sbr_obi_req_t user_sbr_req;
  assign user_sbr_req = user_sbr_obi_req_i;

  addr_decode #(
    .NoIndices (NumDemuxSbr),
    .NoRules   ($size(UserAddrMap)),
    .addr_t    (logic [SbrObiCfg.AddrWidth-1:0]),
    .rule_t    (addr_map_rule_t),
    .Napot     (1'b0)
  ) i_addr_decode_periphs (
    .addr_i           (user_sbr_req.a.addr),
    .addr_map_i       (UserAddrMap),
    .idx_o            (user_idx),
    .dec_valid_o      (),
    .dec_error_o      (),
    .en_default_idx_i (1'b1),
    .default_idx_i    (user_idx_t'(UserError))
  );

  obi_demux #(
    .ObiCfg      (SbrObiCfg),
    .obi_req_t   (sbr_obi_req_t),
    .obi_rsp_t   (sbr_obi_rsp_t),
    .NumMgrPorts (NumDemuxSbr),
    .NumMaxTrans (2)
  ) i_obi_demux (
    .clk_i,
    .rst_ni,
    .sbr_port_select_i (user_idx),
    .sbr_port_req_i    (user_sbr_req),
    .sbr_port_rsp_o    (user_sbr_obi_rsp_o),
    .mgr_ports_req_o   (subordinate_req),
    .mgr_ports_rsp_i   (subordinate_rsp)
  );

  logic vad_irq;

  vad_csr_wrapper i_vad_csr_wrapper (
    .clk_i,
    .rst_ni,
    .obi_req_i          (subordinate_req[UserDesign]),
    .obi_rsp_o          (subordinate_rsp[UserDesign]),
    .i2s_sclk_o         (vad_i2s_sclk_o),
    .i2s_wsel_o         (vad_i2s_wsel_o),
    .i2s_sdat_i         (vad_i2s_sdat_i),
    .vad_wakeup_event_o (),
    .vad_irq_o          (vad_irq),
    .mbist_start_i       (mbist_start_i),
    .mbist_resume_i      (mbist_resume_or_reset_i),
    .mbist_erraddrread_i (mbist_erraddr_read_i),
    .mbist_status_o      (mbist_status_o),
    .mbist_erraddr_o     (mbist_erraddr_o)
  );

  // Level interrupt: enabled with SRAM_CTRL.IRQ_EN, cleared by writing 1 to SRAM_STATUS.SPEECH
  always_comb begin
    interrupts_o = '0;
    interrupts_o[0] = vad_irq;
  end

  obi_err_sbr #(
    .ObiCfg      (SbrObiCfg),
    .obi_req_t   (sbr_obi_req_t),
    .obi_rsp_t   (sbr_obi_rsp_t),
    .NumMaxTrans (1),
    .RspData     (32'hBADCAB1E)
  ) i_user_err (
    .clk_i,
    .rst_ni,
    .testmode_i,
    .obi_req_i (subordinate_req[UserError]),
    .obi_rsp_o (subordinate_rsp[UserError])
  );

  `ASSERT_INIT(InterruptCount, NumExternalIrqs >= 1,
               "The VAD requires at least one external interrupt")
  `ASSERT_INIT(MbistMacroCount, NumUserMbistMacros == 2,
               "The VAD has exactly two frame SRAMs with MBIST")
  `ASSERT_INIT(MbistErrAddrWidth, $clog2(SramBankNumWords) == 9,
               "soc_ctrl_regs error addresses must be 9 bits wide for the 512-word VAD SRAMs")

endmodule
