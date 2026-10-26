// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

/// An OBI crossbar interconnect.
module obi_xbar #(
  /// The OBI configuration for the subordinate ports (input ports).
  parameter obi_pkg::obi_cfg_t SbrPortObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The OBI configuration for the manager ports (ouput ports).
  parameter obi_pkg::obi_cfg_t MgrPortObiCfg      = SbrPortObiCfg,
  /// The request struct for the subordinate ports (input ports).
  parameter type               sbr_port_obi_req_t = logic,
  /// The A channel struct for the subordinate ports (input ports).
  parameter type               sbr_port_a_chan_t  = logic,
  /// The response struct for the subordinate ports (input ports).
  parameter type               sbr_port_obi_rsp_t = logic,
  /// The R channel struct for the subordinate ports (input ports).
  parameter type               sbr_port_r_chan_t  = logic,
  /// The request struct for the manager ports (output ports).
  parameter type               mgr_port_obi_req_t = sbr_port_obi_req_t,
  /// The A channel struct for the manager ports (output ports).
  parameter type               mgr_port_a_chan_t  = logic,
  /// The response struct for the manager ports (output ports).
  parameter type               mgr_port_obi_rsp_t = sbr_port_obi_rsp_t,
  /// The R channel struct for the manager ports (output ports).
  parameter type               mgr_port_r_chan_t  = logic,
  /// The number of subordinate ports (input ports).
  parameter int unsigned       NumSbrPorts        = 32'd0,
  /// The number of manager ports (output ports).
  parameter int unsigned       NumMgrPorts        = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans        = 32'd0,
  /// The number of address rules.
  parameter int unsigned       NumAddrRules       = 32'd0,
  /// The address map rule type.
  parameter type               addr_map_rule_t    = logic,
  /// Use the extended ID field (aid & rid) to route the response
  parameter bit                UseIdForRouting    = 1'b0,
  /// Connectivity matrix to disable certain paths.
  parameter bit [NumSbrPorts-1:0][NumMgrPorts-1:0] Connectivity = '1,
  /// Bypass enable for request side cuts (Subordinate side).
  parameter bit [NumSbrPorts-1:0] BypassReqSbr    = '0,
  /// Bypass enable for response side cuts (Subordinate side).
  parameter bit [NumSbrPorts-1:0] BypassRspSbr    = '0,
  /// Bypass enable for manager side requests (Manager side).
  parameter bit [NumMgrPorts-1:0] BypassReqMgr    = '0,
  /// Bypass enable for manager side responses(Manager side).
  parameter bit [NumMgrPorts-1:0] BypassRspMgr    = '0
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic testmode_i,

  //JTAG Interface
  input  logic trst_ni,
  input  logic tclk_i,
  input  logic tdi_i,
  input  logic tms_i,
  output logic tdo_o,

  // Subordinate External Boundary Ports (Facing Managers)
  input  sbr_port_obi_req_t [NumSbrPorts-1:0] sbr_ports_req_i,
  output sbr_port_obi_rsp_t [NumSbrPorts-1:0] sbr_ports_rsp_o,

  // Manager External Boundary Ports (Facing Subordinates)
  output mgr_port_obi_req_t [NumMgrPorts-1:0] mgr_ports_req_o,
  input  mgr_port_obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp_i,

  input  addr_map_rule_t [NumAddrRules-1:0]   addr_map_i,
  input  logic [NumSbrPorts-1:0]              en_default_idx_i,
  input  logic [NumSbrPorts-1:0][cf_math_pkg::idx_width(NumMgrPorts)-1:0] default_idx_i
);


  // Xbar Output Signals entering the OBI Cut
  mgr_port_obi_req_t [NumMgrPorts-1:0] cut_in_mgr_ports_req; 
  sbr_port_obi_rsp_t [NumSbrPorts-1:0] cut_in_sbr_ports_rsp;

  // Xbar Input signals exiting from the OBI Cut
  sbr_port_obi_req_t [NumSbrPorts-1:0] cut_out_sbr_ports_req;
  mgr_port_obi_rsp_t [NumMgrPorts-1:0] cut_out_mgr_ports_rsp;
  addr_map_rule_t [NumAddrRules-1:0]   cut_out_addr_map;
  logic [NumSbrPorts-1:0]              cut_out_en_default_idx;
  logic [NumSbrPorts-1:0][cf_math_pkg::idx_width(NumMgrPorts)-1:0] cut_out_default_idx;




  // Multicut with JTAG capabilities 
  obi_jtag_top #(
    .SbrPortObiCfg      (SbrPortObiCfg),
    .MgrPortObiCfg      (MgrPortObiCfg),
    .sbr_port_obi_req_t (sbr_port_obi_req_t),
    .sbr_port_a_chan_t  (sbr_port_a_chan_t),
    .sbr_port_obi_rsp_t (sbr_port_obi_rsp_t),
    .sbr_port_r_chan_t  (sbr_port_r_chan_t),
    .mgr_port_obi_req_t (mgr_port_obi_req_t),
    .mgr_port_a_chan_t  (mgr_port_a_chan_t),
    .mgr_port_obi_rsp_t (mgr_port_obi_rsp_t),
    .mgr_port_r_chan_t  (mgr_port_r_chan_t),
    .NumSbrPorts        (NumSbrPorts),
    .NumMgrPorts        (NumMgrPorts),
    .NumMaxTrans        (NumMaxTrans),
    .NumAddrRules       (NumAddrRules),
    .addr_map_rule_t    (addr_map_rule_t),
    .BypassReqSbr       (BypassReqSbr),
    .BypassRspSbr       (BypassRspSbr),
    .BypassReqMgr       (BypassReqMgr),
    .BypassRspMgr       (BypassRspMgr)
) i_obi_jtag_top (
                  .clk_i                        (clk_i),
                  .rst_ni                       (rst_ni),
                  .testmode_i                   (testmode_i),
                  .tclk_i                       (tclk_i),
                  .trst_ni                      (trst_ni),
                  .tdi_i                        (tdi_i),
                  .tms_i                        (tms_i),
                  .tdo_o                        (tdo_o),
                  .mst_cut_sbr_ports_req_i      (sbr_ports_req_i), 
                  .cut_xbar_sbr_ports_req_o     (cut_out_sbr_ports_req),
                  .xbar_cut_sbr_ports_rsp_i     (cut_in_sbr_ports_rsp), 
                  .cut_mst_sbr_ports_rsp_o      (sbr_ports_rsp_o),
                  .xbar_cut_mgr_ports_req_i     (cut_in_mgr_ports_req), 
                  .cut_slv_mgr_ports_req_o      (mgr_ports_req_o),
                  .slv_cut_mgr_ports_rsp_i      (mgr_ports_rsp_i), 
                  .cut_xbar_mgr_ports_rsp_o     (cut_out_mgr_ports_rsp),
                  .addr_map_i                   (addr_map_i),
                  .addr_map_o                   (cut_out_addr_map),
                  .en_default_idx_i             (en_default_idx_i),
                  .en_default_idx_o             (cut_out_en_default_idx),
                  .default_idx_i                (default_idx_i),
                  .default_idx_o                (cut_out_default_idx)
                 );


  logic [NumSbrPorts-1:0][cf_math_pkg::idx_width(NumMgrPorts)-1:0] sbr_port_select;

  // Signals from the demuxes
  sbr_port_obi_req_t [NumSbrPorts-1:0][NumMgrPorts-1:0] sbr_reqs;
  sbr_port_obi_rsp_t [NumSbrPorts-1:0][NumMgrPorts-1:0] sbr_rsps;

  // Signals to the muxes
  sbr_port_obi_req_t [NumMgrPorts-1:0][NumSbrPorts-1:0] mgr_reqs;
  sbr_port_obi_rsp_t [NumMgrPorts-1:0][NumSbrPorts-1:0] mgr_rsps;

  for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_demux
    addr_decode #(
      .NoIndices ( NumMgrPorts                         ),
      .NoRules   ( NumAddrRules                        ),
      .addr_t    ( logic [MgrPortObiCfg.AddrWidth-1:0] ),
      .rule_t    ( addr_map_rule_t                     )
    ) i_addr_decode (
      .addr_i          ( cut_out_sbr_ports_req[i].a.addr ),
      .addr_map_i      ( cut_out_addr_map                ),
      .idx_o           ( sbr_port_select[i]              ),
      .dec_valid_o     (                                 ),
      .dec_error_o     (                                 ),
      .en_default_idx_i( cut_out_en_default_idx[i]       ),
      .default_idx_i   ( cut_out_default_idx[i]          )
    );

    obi_demux #(
      .ObiCfg      ( SbrPortObiCfg      ),
      .obi_req_t   ( sbr_port_obi_req_t ),
      .obi_rsp_t   ( sbr_port_obi_rsp_t ),
      .NumMgrPorts ( NumMgrPorts        ),
      .NumMaxTrans ( NumMaxTrans        )
    ) i_demux (
      .clk_i,
      .rst_ni,
      .sbr_port_select_i ( sbr_port_select[i]            ),
      .sbr_port_req_i    ( cut_out_sbr_ports_req[i]      ),
      .sbr_port_rsp_o    ( cut_in_sbr_ports_rsp[i]       ),
      .mgr_ports_req_o   ( sbr_reqs[i]                   ),
      .mgr_ports_rsp_i   ( sbr_rsps[i]                   )
    );
  end

  for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_interco_sbr
    for (genvar j = 0; j < NumMgrPorts; j++) begin : gen_interco_mgr
      if (Connectivity[i][j]) begin : gen_connected
        assign mgr_reqs[j][i] = sbr_reqs[i][j];
        assign sbr_rsps[i][j] = mgr_rsps[j][i];
      end else begin : gen_err_sbr
        assign mgr_reqs[j][i].req = 1'b0;
        if (MgrPortObiCfg.UseRReady) begin : gen_rready
          assign mgr_reqs[j][i].rready = 1'b0;
        end
        assign mgr_reqs[j][i].a   = '0;
        if (MgrPortObiCfg.Integrity) begin : gen_integrity
          assign mgr_reqs[j][i].reqpar = 1'b1;
          if (MgrPortObiCfg.UseRReady) begin : gen_int_rready
            assign mgr_reqs[j][i].rreadypar = 1'b1;
          end
        end
        obi_err_sbr #(
          .ObiCfg      ( SbrPortObiCfg      ),
          .obi_req_t   ( sbr_port_obi_req_t ),
          .obi_rsp_t   ( sbr_port_obi_rsp_t ),
          .NumMaxTrans ( NumMaxTrans        ),
          .RspData     ( 32'hBADCAB1E       )
        ) i_err_sbr (
          .clk_i,
          .rst_ni,
          .testmode_i,
          .obi_req_i (sbr_reqs[i][j]),
          .obi_rsp_o (sbr_rsps[i][j])
        );
      end
    end
  end

  for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_mux
    obi_mux #(
      .SbrPortObiCfg      ( SbrPortObiCfg      ),
      .MgrPortObiCfg      ( MgrPortObiCfg      ),
      .sbr_port_obi_req_t ( sbr_port_obi_req_t ),
      .sbr_port_a_chan_t  ( sbr_port_a_chan_t  ),
      .sbr_port_obi_rsp_t ( sbr_port_obi_rsp_t ),
      .sbr_port_r_chan_t  ( sbr_port_r_chan_t  ),
      .mgr_port_obi_req_t ( mgr_port_obi_req_t ),
      .mgr_port_obi_rsp_t ( mgr_port_obi_rsp_t ),
      .NumSbrPorts        ( NumSbrPorts        ),
      .NumMaxTrans        ( NumMaxTrans        ),
      .UseIdForRouting    ( UseIdForRouting    )
    ) i_mux (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .sbr_ports_req_i ( mgr_reqs[i]                ),
      .sbr_ports_rsp_o ( mgr_rsps[i]                ),
      .mgr_port_req_o  ( cut_in_mgr_ports_req[i]    ),
      .mgr_port_rsp_i  ( cut_out_mgr_ports_rsp[i]   )
    );
  end

endmodule

`include "obi/typedef.svh"
`include "obi/assign.svh"

module obi_xbar_intf #(
  /// The OBI configuration for the subordinate ports (input ports).
  parameter obi_pkg::obi_cfg_t SbrPortObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The OBI configuration for the manager ports (ouput ports).
  parameter obi_pkg::obi_cfg_t MgrPortObiCfg      = SbrPortObiCfg,
  /// The number of subordinate ports (input ports).
  parameter int unsigned       NumSbrPorts        = 32'd0,
  /// The number of manager ports (output ports).
  parameter int unsigned       NumMgrPorts        = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans        = 32'd0,
  /// The number of address rules.
  parameter int unsigned       NumAddrRules       = 32'd0,
  /// The address map rule type.
  parameter type               addr_map_rule_t    = logic,
  /// Use the extended ID field (aid & rid) to route the response
  parameter bit                UseIdForRouting    = 1'b0,
  /// Connectivity matrix to disable certain paths.
  parameter bit [NumSbrPorts-1:0][NumMgrPorts-1:0] Connectivity = '1
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        testmode_i,
  input  logic        trst_ni,
  input  logic        tclk_i,
  input  logic        tdi_i,
  input  logic        tms_i,
  output logic        tdo_o,
  OBI_BUS.Subordinate sbr_ports [NumSbrPorts],

  OBI_BUS.Manager     mgr_ports [NumMgrPorts],

  input  addr_map_rule_t [NumAddrRules-1:0]   addr_map_i,
  input  logic [NumSbrPorts-1:0]              en_default_idx_i,
  input  logic [NumSbrPorts-1:0][cf_math_pkg::idx_width(NumMgrPorts)-1:0] default_idx_i
);

  `OBI_TYPEDEF_ALL(sbr_port_obi, SbrPortObiCfg)
  `OBI_TYPEDEF_ALL(mgr_port_obi, MgrPortObiCfg)

  sbr_port_obi_req_t [NumSbrPorts-1:0] sbr_ports_req;
  sbr_port_obi_rsp_t [NumSbrPorts-1:0] sbr_ports_rsp;

  mgr_port_obi_req_t [NumMgrPorts-1:0] mgr_ports_req;
  mgr_port_obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp;

  for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_sbr_ports_assign
    `OBI_ASSIGN_TO_REQ(sbr_ports_req[i], sbr_ports[i], SbrPortObiCfg)
    `OBI_ASSIGN_FROM_RSP(sbr_ports[i], sbr_ports_rsp[i], SbrPortObiCfg)
  end

  for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_mgr_ports_assign
    `OBI_ASSIGN_FROM_REQ(mgr_ports[i], mgr_ports_req[i], MgrPortObiCfg)
    `OBI_ASSIGN_TO_RSP(mgr_ports_rsp[i], mgr_ports[i], MgrPortObiCfg)
  end

  obi_xbar #(
    .SbrPortObiCfg      ( SbrPortObiCfg         ),
    .MgrPortObiCfg      ( MgrPortObiCfg         ),
    .sbr_port_obi_req_t ( sbr_port_obi_req_t    ),
    .sbr_port_a_chan_t  ( sbr_port_obi_a_chan_t ),
    .sbr_port_obi_rsp_t ( sbr_port_obi_rsp_t    ),
    .sbr_port_r_chan_t  ( sbr_port_obi_r_chan_t ),
    .mgr_port_obi_req_t ( mgr_port_obi_req_t    ),
    .mgr_port_obi_rsp_t ( mgr_port_obi_rsp_t    ),
    .NumSbrPorts        ( NumSbrPorts           ),
    .NumMgrPorts        ( NumMgrPorts           ),
    .NumMaxTrans        ( NumMaxTrans           ),
    .NumAddrRules       ( NumAddrRules          ),
    .addr_map_rule_t    ( addr_map_rule_t       ),
    .UseIdForRouting    ( UseIdForRouting       ),
    .Connectivity       ( Connectivity          )
  ) i_obi_xbar (
    .clk_i,
    .rst_ni,
    .testmode_i,
    .trst_ni,
    .tclk_i,
    .tdi_i,
    .tms_i,
    .tdo_o,
    .sbr_ports_req_i  ( sbr_ports_req    ),
    .sbr_ports_rsp_o  ( sbr_ports_rsp    ),
    .mgr_ports_req_o  ( mgr_ports_req    ),
    .mgr_ports_rsp_i  ( mgr_ports_rsp    ),
    .addr_map_i       ( addr_map_i       ),
    .en_default_idx_i ( en_default_idx_i ),
    .default_idx_i    ( default_idx_i    )
  );

endmodule
