// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module obi_cut_mod #(
    /// The OBI configuration.
  parameter obi_pkg::obi_cfg_t ObiCfg       = obi_pkg::ObiDefaultConfig,
  /// The obi A channel struct.
  parameter type               obi_a_chan_t = logic,
  /// The obi R channel struct.
  parameter type               obi_r_chan_t = logic,
  /// The request struct.
  parameter type               obi_req_t    = logic,
  /// The response struct.
  parameter type               obi_rsp_t    = logic,
  /// Isolation Bus type struct
  parameter type               xcnct_isol_t = logic,
  /// Bypass enable, can be individually overridden!
  parameter bit                Bypass       = 1'b0,
  /// Bypass enable for Request side.
  parameter bit                BypassReq    = Bypass,
  /// Bypass enable for Response side.
  parameter bit                BypassRsp    = Bypass,
  /// In isolation, drive req (A valid_o) from the scan cell for one step
  parameter bit                IsolDriveReq    = 1'b0,
  /// In isolation, grant (A ready_o = 1) during every step
  parameter bit                IsolDriveGnt    = 1'b0,
  /// In isolation, drive rvalid (R valid_o) from the scan cell for one step
  parameter bit                IsolDriveRvalid = 1'b0,
  /// Subordinate-side cut: in sub-access mode, a step with the A cell's valid bit set issues
  /// one real transaction to the subordinate (on the system clock); the R cell captures the reply
  parameter bit                IsolSubAccess   = 1'b0
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  /// System clock of the subordinate (clk_i is TCK during isolation)
  input  logic     sys_clk_i,

  input  obi_req_t sbr_port_req_i,
  output obi_rsp_t sbr_port_rsp_o,

  output obi_req_t mgr_port_req_o,
  input  obi_rsp_t mgr_port_rsp_i,

  //JTAG Interface
  input  logic tdi_i,
  output logic tdo_o,

  // -- Tap Signals --
  input  logic isol_en_i,
  input  logic sub_access_i,
  input  logic capture_dr_i,
  input  logic shift_dr_i,
  input  logic update_dr_i

);

  logic spreg_daisy_chain;
  logic a_valid_o, a_step_valid;

  spill_register_mod #(
    .T              ( obi_a_chan_t ),
    .Bypass         ( BypassReq    ),
    .IsolDriveValid ( IsolDriveReq ),
    .IsolDriveReady ( IsolDriveGnt )
  ) i_reg_a (
    .clk_i,
    .rst_ni,
    .valid_i    ( sbr_port_req_i.req          ),
    .ready_o    ( sbr_port_rsp_o.gnt          ),
    .data_i     ( sbr_port_req_i.a            ),
    .valid_o    ( a_valid_o                   ),
    .ready_i    ( mgr_port_rsp_i.gnt          ),
    .data_o     ( mgr_port_req_o.a            ),
    .isol_en_i,
    .capture_dr_i,
    .shift_dr_i,
    .update_dr_i,
    .isol_cap_live_i   ( 1'b0         ),
    .isol_step_valid_o ( a_step_valid ),
    .tdi_i,
    .tdo_o(spreg_daisy_chain)
  );

  logic ready_o;
  logic ready_i;

  if (ObiCfg.UseRReady) begin : gen_use_rready
    assign mgr_port_req_o.rready = ready_o;
    assign ready_i = sbr_port_req_i.rready;
  end else begin : gen_no_use_rready
    assign ready_i = 1'b1;
  end

  // Response into the R register: the subordinate, or (sub-access) the stored reply
  logic        r_valid_in, r_cap_live;
  obi_r_chan_t r_data_in;

  if (IsolSubAccess) begin : gen_sub_access
    logic        fire_q, acc_req, acc_done, acc_done_tck;
    obi_r_chan_t acc_rsp;

    // TCK domain: toggle once per step whose A cell valid bit is set
    always_ff @(posedge clk_i or negedge rst_ni) begin : ps_fire
      if (!rst_ni)                                fire_q <= 1'b0;
      else if (sub_access_i && a_step_valid)      fire_q <= ~fire_q;
    end

    obi_cut_sub_access #(
      .obi_r_chan_t ( obi_r_chan_t )
    ) i_sub_access (
      .clk_i    ( sys_clk_i                ),
      .rst_ni,
      .en_i     ( sub_access_i             ),
      .fire_i   ( fire_q                   ),
      .req_o    ( acc_req                  ),
      .gnt_i    ( mgr_port_rsp_i.gnt       ),
      .rvalid_i ( mgr_port_rsp_i.rvalid    ),
      .r_i      ( mgr_port_rsp_i.r         ),
      .done_o   ( acc_done                 ),
      .rsp_o    ( acc_rsp                  )
    );

    // Done back into the TCK domain; the reply data is stable once done is seen
    sync #(.STAGES(2)) i_sync_done (
      .clk_i,
      .rst_ni,
      .serial_i ( acc_done     ),
      .serial_o ( acc_done_tck )
    );

    // The A payload (b register, stable between Updates) goes out with the engine's req
    assign mgr_port_req_o.req = a_valid_o | acc_req;
    assign r_valid_in = sub_access_i ? acc_done_tck : mgr_port_rsp_i.rvalid;
    assign r_data_in  = sub_access_i ? acc_rsp      : mgr_port_rsp_i.r;
    assign r_cap_live = sub_access_i;
  end else begin : gen_no_sub_access
    assign mgr_port_req_o.req = a_valid_o;
    assign r_valid_in = mgr_port_rsp_i.rvalid;
    assign r_data_in  = mgr_port_rsp_i.r;
    assign r_cap_live = 1'b0;
  end

  spill_register_mod #(
    .T              ( obi_r_chan_t    ),
    .Bypass         ( BypassRsp       ),
    .IsolDriveValid ( IsolDriveRvalid ),
    .IsolDriveReady ( 1'b0            )
  ) i_req_r (
    .clk_i,
    .rst_ni,
    .valid_i    ( r_valid_in                  ),
    .ready_o    ( ready_o                     ),
    .data_i     ( r_data_in                   ),
    .valid_o    ( sbr_port_rsp_o.rvalid       ),
    .ready_i    ( ready_i                     ),
    .data_o     ( sbr_port_rsp_o.r            ),
    .isol_en_i,
    .capture_dr_i,
    .shift_dr_i,
    .update_dr_i,
    .isol_cap_live_i   ( r_cap_live ),
    .isol_step_valid_o (            ),
    .tdi_i(spreg_daisy_chain),
    .tdo_o
  );

endmodule


/// One JTAG-triggered transaction to a subordinate, on the subordinate's (system) clock.
/// fire_i toggles in the TCK domain; each toggle issues one req, held until gnt, then waits
/// for rvalid and keeps the reply (rsp_o) with done_o set until the next transaction.
/// The A payload is driven by the cut's b register, which is stable while this runs.
module obi_cut_sub_access #(
  parameter type obi_r_chan_t = logic
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        en_i,      // sub-access mode (TCK domain, quasi-static)
  input  logic        fire_i,    // toggle (TCK domain)
  output logic        req_o,
  input  logic        gnt_i,
  input  logic        rvalid_i,
  input  obi_r_chan_t r_i,
  output logic        done_o,
  output obi_r_chan_t rsp_o
);

  logic en_s, fire_s, fire_q;

  sync #(.STAGES(2)) i_sync_en   (.clk_i, .rst_ni, .serial_i(en_i),   .serial_o(en_s));
  sync #(.STAGES(2)) i_sync_fire (.clk_i, .rst_ni, .serial_i(fire_i), .serial_o(fire_s));

  typedef enum logic [1:0] { Idle, Req, WaitRsp } state_e;
  state_e state_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : ps_engine
    if (!rst_ni) begin
      state_q <= Idle;
      fire_q  <= 1'b0;
      done_o  <= 1'b0;
      rsp_o   <= obi_r_chan_t'('0);
    end else begin
      fire_q <= fire_s;
      unique case (state_q)
        Idle: begin
          if (!en_s) begin
            done_o <= 1'b0;
          end else if (fire_s != fire_q) begin
            done_o  <= 1'b0;
            state_q <= Req;
          end
        end
        // req stays high until granted (never withdrawn), also if the mode is left meanwhile
        Req:     if (gnt_i)    state_q <= WaitRsp;
        WaitRsp: if (rvalid_i) begin
          rsp_o   <= r_i;
          done_o  <= 1'b1;
          state_q <= Idle;
        end
        default: state_q <= Idle;
      endcase
    end
  end

  assign req_o = (state_q == Req);

endmodule
