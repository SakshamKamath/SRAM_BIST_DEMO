module obi_multicut #(
    /// The OBI configuration for the subordinate ports (input ports).
    parameter obi_pkg::obi_cfg_t SbrPortObiCfg      = obi_pkg::ObiDefaultConfig,
    /// The OBI configuration for the manager ports (output ports).
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
    /// The struct type for isolation bus signals
    parameter type               xcnct_isol_misc_t  = logic,
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
    /// Bypass enable for request side cuts.
    parameter bit [NumSbrPorts-1:0] BypassReqSbr    = '0,
    /// Bypass enable for response side cuts.
    parameter bit [NumSbrPorts-1:0] BypassRspSbr    = '0,
    /// Bypass enable for manager side requests.
    parameter bit [NumMgrPorts-1:0] BypassReqMgr    = '0,
    /// Bypass enable for manager side responses.
    parameter bit [NumMgrPorts-1:0] BypassRspMgr    = '0
) (
    input  logic clk_i,
    input  logic rst_ni,
    // input  logic testmode_i,

    // JTAG Interface 
    input  logic tdi_i,
    input  logic isol_en_i,
    input  logic capture_dr_i,
    input  logic shift_dr_i,
    input  logic update_dr_i,
    output logic tdo_o,

    // Subordinate Side Signals facing the Managers
    input  sbr_port_obi_req_t [NumSbrPorts-1:0] mst_cut_sbr_ports_req_i, // From Master to xbar
    input  sbr_port_obi_rsp_t [NumSbrPorts-1:0] xbar_cut_sbr_ports_rsp_i, // From xbar to Master

    output sbr_port_obi_req_t [NumSbrPorts-1:0] cut_xbar_sbr_ports_req_o,
    output sbr_port_obi_rsp_t [NumSbrPorts-1:0] cut_mst_sbr_ports_rsp_o,

    // Manager Side Signals facing the Subordinates
    input  mgr_port_obi_req_t [NumMgrPorts-1:0] xbar_cut_mgr_ports_req_i, // From xbar to slave
    input  mgr_port_obi_rsp_t [NumMgrPorts-1:0] slv_cut_mgr_ports_rsp_i, // From slave to xbar

    output mgr_port_obi_req_t [NumMgrPorts-1:0] cut_slv_mgr_ports_req_o,
    output mgr_port_obi_rsp_t [NumMgrPorts-1:0] cut_xbar_mgr_ports_rsp_o,

    // Miscellaneous Signals
    input  addr_map_rule_t [NumAddrRules-1:0]   addr_map_i,
    input  logic [NumSbrPorts-1:0]              en_default_idx_i,
    input  logic [NumSbrPorts-1:0][cf_math_pkg::idx_width(NumMgrPorts)-1:0] default_idx_i,

    output addr_map_rule_t [NumAddrRules-1:0]   addr_map_o,
    output logic [NumSbrPorts-1:0]              en_default_idx_o,
    output logic [NumSbrPorts-1:0][cf_math_pkg::idx_width(NumMgrPorts)-1:0] default_idx_o,

    // Isolation Bus
    input  xcnct_isol_misc_t                    xcnct_isol_miscbus_i

);


localparam int IsolBitWidth = $bits(xcnct_isol_misc_t);

xcnct_isol_misc_t xcnct_isol_misc_d, xcnct_isol_misc_q;

always_ff @(posedge clk_i) begin
  if(!rst_ni) begin
    xcnct_isol_misc_q <= '0;
  end
  else begin
    xcnct_isol_misc_q <= xcnct_isol_misc_d;   
  end

end

always_comb begin
  xcnct_isol_misc_d = xcnct_isol_misc_q;

  if(isol_en_i) begin
    if(update_dr_i) xcnct_isol_misc_d = xcnct_isol_miscbus_i;
  end
  else begin
    xcnct_isol_misc_d = xcnct_isol_misc_t'{
                                            addrmap        : addr_map_i,
                                            en_default_idx : en_default_idx_i,
                                            default_idx    : default_idx_i
                                          };
  end

end


// To Daisy Chain the cuts
localparam int unsigned TotalCuts = NumSbrPorts + NumMgrPorts;
logic [TotalCuts:0] scan_chain;

assign scan_chain[0] = tdi_i;
assign tdo_o         = scan_chain[TotalCuts];


// Subordinate Side
for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_sbr_cuts
    obi_cut_mod #(
      .ObiCfg            ( SbrPortObiCfg      ),
      .obi_a_chan_t      ( sbr_port_a_chan_t  ),
      .obi_r_chan_t      ( sbr_port_r_chan_t  ),
      .obi_req_t         ( sbr_port_obi_req_t ),
      .obi_rsp_t         ( sbr_port_obi_rsp_t ),
      .xcnct_isol_t      ( xcnct_isol_misc_t  ),
      .BypassReq         ( BypassReqSbr[i]    ),
      .BypassRsp         ( BypassRspSbr[i]    )
    ) i_sbr_obi_cut      ( 
      .clk_i,
      .rst_ni,

      .sbr_port_req_i ( mst_cut_sbr_ports_req_i[i]  ),
      .sbr_port_rsp_o ( cut_mst_sbr_ports_rsp_o[i]  ),

      .mgr_port_req_o ( cut_xbar_sbr_ports_req_o[i] ),
      .mgr_port_rsp_i ( xbar_cut_sbr_ports_rsp_i[i] ),

      // JTAG Control
      .isol_en_i,
      .capture_dr_i,
      .shift_dr_i,
      .update_dr_i,

      // Scan Chain Connection: Daisy-chained through the array
      .tdi_i          ( scan_chain[i]     ),
      .tdo_o          ( scan_chain[i+1]   )
    );
    end

for (genvar j = 0; j < NumMgrPorts; j++) begin : gen_mgr_cuts
    // Offset index in the scan chain to continue after SBR cuts
    localparam int unsigned ChainIdx = NumSbrPorts + j;

    obi_cut_mod #(
      .ObiCfg            ( MgrPortObiCfg      ),
      .obi_a_chan_t      ( mgr_port_a_chan_t  ),
      .obi_r_chan_t      ( mgr_port_r_chan_t  ),
      .obi_req_t         ( mgr_port_obi_req_t ),
      .obi_rsp_t         ( mgr_port_obi_rsp_t ),
      .xcnct_isol_t      ( xcnct_isol_misc_t  ),
      .BypassReq         ( BypassReqMgr[j]    ),
      .BypassRsp         ( BypassRspMgr[j]    )
    ) i_mgr_obi_cut (
      .clk_i,
      .rst_ni,

      .sbr_port_req_i ( xbar_cut_mgr_ports_req_i[j] ),
      .sbr_port_rsp_o ( cut_xbar_mgr_ports_rsp_o[j] ),

      .mgr_port_req_o ( cut_slv_mgr_ports_req_o[j]  ),
      .mgr_port_rsp_i ( slv_cut_mgr_ports_rsp_i[j]  ),

      // JTAG Control
      .isol_en_i,
      .capture_dr_i,
      .shift_dr_i,
      .update_dr_i,

      // Scan Chain Connection: Continues from SBR chain end
      .tdi_i          ( scan_chain[ChainIdx]   ),
      .tdo_o          ( scan_chain[ChainIdx+1] )
    );
  end


// Output Assignments

assign addr_map_o       = xcnct_isol_misc_q.addrmap;
assign en_default_idx_o = xcnct_isol_misc_q.en_default_idx;
assign default_idx_o    = xcnct_isol_misc_q.default_idx;


endmodule
