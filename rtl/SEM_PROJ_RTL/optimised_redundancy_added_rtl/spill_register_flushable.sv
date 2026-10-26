// Copyright 2021 ETH Zurich and University of Bologna.
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Fabian Schuiki <fschuiki@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"

/// A register with handshakes that completely cuts any combinational paths
/// between the input and output. This spill register can be flushed.
module spill_register_flushable #(
  parameter type T           = logic,
  parameter bit  Bypass      = 1'b0   // make this spill register transparent
) (
  input  logic clk_i   ,
  input  logic rst_ni  ,
  input  logic valid_i ,
  input  logic flush_i ,
  output logic ready_o ,
  input  T     data_i  ,
  output logic valid_o ,
  input  logic ready_i ,
  output T     data_o

  //JTAG Interface
  // -- Tap Signals --
  input  logic isol_en_i,
  input  logic capture_dr_i,
  input  logic shift_dr_i,
  input  logic update_dr_i,

  // -- JTAG Signals --
  input  logic tdi_i,
  output logic tdo_o

);

// -- JTAG Repurpose Info
// Use register a as a shadow register to update into after shifting in register b complete


  if (Bypass) begin : gen_bypass
    assign valid_o = valid_i;
    assign ready_o = ready_i;
    assign data_o  = data_i;

    // -- JTAG addition
    assign tdo_o   = tdi_i;

  end else begin : gen_spill_reg
    // The A register.
    T a_data_q;
    logic a_full_q;
    logic a_fill, a_drain;

    //For JTAG Addition
    T a_data_d;
    localparam int unsigned TDataBits = $bits(T)


    always_ff @(posedge clk_i or negedge rst_ni) begin : ps_a_data
      if (!rst_ni)
        a_data_q <= T'('0);
      else 
        a_data_q <= a_data_d;
    end

    // -- JTAG addition
    always_comb begin
      a_data_d = a_data_q;

      if (isol_en_i && shift_dr_i) begin // JTAG Shift
        a_data_d = T'({tdi_i, a_data_q[TDataBits-1:1]});
      end
      else if (isol_en_i && capture_dr_i) begin // JTAG Capture
        a_data_d = data_i;
      end
      else if (a_fill) begin // Functional Mode
        a_data_d = data_i;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : ps_a_full
      if (!rst_ni)
        a_full_q <= 0;
      else if (a_fill || a_drain)
        a_full_q <= a_fill;
    end




    // The B register.
    T b_data_q;
    logic b_full_q;
    logic b_fill, b_drain;

    //For JTAG Addition
    T b_data_d;

    always_ff @(posedge clk_i or negedge rst_ni) begin : ps_b_data
      if (!rst_ni)
        b_data_q <= T'('0);
      else
        b_data_q <= b_data_d;
    end

    // -- JTAG addition
    always_comb begin
      b_data_d = b_data_q;

      if (isol_en_i && shift_dr_i) begin // JTAG Shift
        b_data_d = T'({tdi_i, b_data_q[TDataBits-1:1]});
      end
      else if (isol_en_i && update_dr_i) begin // JTAG Shadow Reg Update to transmit signals 
        b_data_d = a_data_q;
      end
      else if (b_fill) begin // Functional Mode
        b_data_d = data_i;
      end
    end




    always_ff @(posedge clk_i or negedge rst_ni) begin : ps_b_full
      if (!rst_ni)
        b_full_q <= 0;
      else if (b_fill || b_drain)
        b_full_q <= b_fill;
    end


    // Fill the A register when the A or B register is empty. Drain the A register
    // whenever it is full and being filled, or if a flush is requested.
    // This is only done when JTAG operations are not in force
    assign a_fill = valid_i && ready_o && (!flush_i) && (!isolate_en_i);
    assign a_drain = (a_full_q && !b_full_q) || flush_i;

    // Fill the B register whenever the A register is drained, but the downstream
    // circuit is not ready. Drain the B register whenever it is full and the
    // downstream circuit is ready, or if a flush is requested.
    assign b_fill = a_drain && (!ready_i) && (!flush_i);
    assign b_drain = (b_full_q && ready_i) || flush_i;

    // We can accept input as long as register B is not full.
    // Note: flush_i and valid_i must not be high at the same time,
    // otherwise an invalid handshake may occur
    // Upstream Ready tied to 0 when JTAG opn going on
    assign ready_o = isolate_en_i ? 1'b0: !a_full_q || !b_full_q;

    // The unit provides output as long as one of the registers is filled.
    assign valid_o = a_full_q | b_full_q;

    // We empty the spill register before the slice register.
    assign data_o = isolate_en_i ? b_data_q: (b_full_q ? b_data_q : a_data_q);

    // -- JTAG addition
    assign tdo_o   = a_data_q[0];

    `ifndef COMMON_CELLS_ASSERTS_OFF
    `ASSERT(flush_valid, flush_i |-> ~valid_i, clk_i, !rst_ni,
           "Trying to flush and feed the spill register simultaneously. You will lose data!")
   `endif
  end
endmodule
