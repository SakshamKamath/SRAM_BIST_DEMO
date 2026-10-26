// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

package soc_ctrl_regs_pkg;

  // Internal address width. 7 bits covers offsets 0x00–0x7C (32 word-aligned registers).
  localparam int unsigned IntAddrWidth = 7;

  // Register offsets
  parameter logic [IntAddrWidth-1:0] SOC_CTRL_BOOTADDR_OFFSET   = 7'h00;
  parameter logic [IntAddrWidth-1:0] SOC_CTRL_FETCHEN_OFFSET    = 7'h04;
  parameter logic [IntAddrWidth-1:0] SOC_CTRL_CORESTATUS_OFFSET = 7'h08;
  parameter logic [IntAddrWidth-1:0] SOC_CTRL_BOOTMODE_OFFSET   = 7'h0c;
  parameter logic [IntAddrWidth-1:0] SOC_CTRL_SRAM_DLY_OFFSET   = 7'h10;
  parameter logic [IntAddrWidth-1:0] SOC_CTRL_INFO_OFFSET       = 7'h14;


  // BIST Register offsets
  parameter logic [IntAddrWidth-1:0] MBIST_START_OFFSET              = 7'h40;
  parameter logic [IntAddrWidth-1:0] MBIST_RESUME_OR_RESET_OFFSET    = 7'h44;
  parameter logic [IntAddrWidth-1:0] MBIST_ERRADDR_READ_OFFSET       = 7'h48;
  parameter logic [IntAddrWidth-1:0] MBIST_STATUS_READ_OFFSET0       = 7'h4c;  //Support for 8 macros, extend if more needed
  // Error-address FIFO of macro i is read at MBIST_ERRADDR_FIFO_OFFSET0 + 4*i (up to 8 macros: 0x50-0x6C).
  // Read data: {valid, 0..., word address}; every read pops one entry.
  parameter logic [IntAddrWidth-1:0] MBIST_ERRADDR_FIFO_OFFSET0      = 7'h50;

  // Typedef of Memory Macros
    typedef enum bit [31:0] {
      MemMacro     = 0,      // Instrn SRAM Macro
      DataMacro    = 1       // Data SRAM Macro
    } macro_e;

endpackage
