module obi_jtag_top #(
    /// Width of the Instruction Register Used in JTAG Wrapper Module
    parameter                    IrWidth            = 2,
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
    input  logic testmode_i,

    // JTAG Interface 
    input  logic tclk_i,
    input  logic trst_ni,
    input  logic tdi_i,
    input  logic tms_i,
    output logic tdo_o,

    // Subordinate Side Signals facing the Managers
    input  sbr_port_obi_req_t [NumSbrPorts-1:0] mst_cut_sbr_ports_req_i, // From Master to xbar
    input  sbr_port_obi_rsp_t [NumSbrPorts-1:0] xbar_cut_sbr_ports_rsp_i, // From xbar to Master

    output sbr_port_obi_req_t [NumSbrPorts-1:0] cut_xbar_sbr_ports_req_o,
    output sbr_port_obi_rsp_t [NumSbrPorts-1:0] cut_mst_sbr_ports_rsp_o,

    // Manager Side Signals facing the Subordinates
    input   mgr_port_obi_req_t [NumMgrPorts-1:0] xbar_cut_mgr_ports_req_i, // From xbar to slave
    input   mgr_port_obi_rsp_t [NumMgrPorts-1:0] slv_cut_mgr_ports_rsp_i, // From slave to xbar

    output  mgr_port_obi_req_t [NumMgrPorts-1:0] cut_slv_mgr_ports_req_o,
    output  mgr_port_obi_rsp_t [NumMgrPorts-1:0] cut_xbar_mgr_ports_rsp_o,

    // Miscellaneous Signals
    input  addr_map_rule_t [NumAddrRules-1:0]   addr_map_i,
    input  logic [NumSbrPorts-1:0]              en_default_idx_i,
    input  logic [NumSbrPorts-1:0][cf_math_pkg::idx_width(NumMgrPorts)-1:0] default_idx_i,

    output addr_map_rule_t [NumAddrRules-1:0]   addr_map_o,
    output logic [NumSbrPorts-1:0]              en_default_idx_o,
    output logic [NumSbrPorts-1:0][cf_math_pkg::idx_width(NumMgrPorts)-1:0] default_idx_o

);


    //Controller Instantiated
    logic run_test_idle, test_logic_reset, capture_dr, select_dr_scan, 
          exit1_dr, shift_dr, exit2_dr, pause_dr, select_ir_scan,
          update_dr, shift_ir, capture_ir, pause_ir, exit1_ir, update_ir, exit2_ir;

    jtag_tap_controller i_tap_fsm (
        .tclk_i,
        .tms_i,
        .trst_ni,
        .run_test_idle_o(run_test_idle),   
        .test_logic_reset_o(test_logic_reset),
        .capture_dr_o(capture_dr),      
        .shift_dr_o(shift_dr),        
        .update_dr_o(update_dr),       
        .shift_ir_o(shift_ir),        
        .capture_ir_o(capture_ir),      
        .update_ir_o(update_ir)       
    );

    // Definition for Isolation Bus Signals

    typedef struct packed {
        addr_map_rule_t   [NumAddrRules-1:0]                                          addrmap;
        logic             [NumSbrPorts-1:0 ]                                          en_default_idx;
        logic             [NumSbrPorts-1:0 ][cf_math_pkg::idx_width(NumMgrPorts)-1:0] default_idx;
    } xcnct_isol_misc_t;



    // wrapper and multicut modules
    logic xcnct_isol_en, tdo_chained;
    xcnct_isol_misc_t xcnct_isol_miscbus;
    logic tck;

    tc_clk_mux2 i_dft_tck_mux (
      .clk0_i    ( clk_i         ),
      .clk1_i    ( tclk_i         ), 
      .clk_sel_i ( xcnct_isol_en ),
      .clk_o     ( tck           )
    );

    obi_multicut #(
        .SbrPortObiCfg      (SbrPortObiCfg      ),
        .MgrPortObiCfg      (MgrPortObiCfg      ),
        .sbr_port_obi_req_t (sbr_port_obi_req_t ),
        .sbr_port_a_chan_t  (sbr_port_a_chan_t  ),
        .sbr_port_obi_rsp_t (sbr_port_obi_rsp_t ),
        .sbr_port_r_chan_t  (sbr_port_r_chan_t  ),
        .mgr_port_obi_req_t (mgr_port_obi_req_t ),
        .mgr_port_a_chan_t  (mgr_port_a_chan_t  ),
        .mgr_port_obi_rsp_t (mgr_port_obi_rsp_t ),
        .mgr_port_r_chan_t  (mgr_port_r_chan_t  ),
        .xcnct_isol_misc_t  (xcnct_isol_misc_t  ),
        .NumSbrPorts        (NumSbrPorts        ),
        .NumMgrPorts        (NumMgrPorts        ),
        .NumMaxTrans        (NumMaxTrans        ),
        .NumAddrRules       (NumAddrRules       ),
        .addr_map_rule_t    (addr_map_rule_t    ),
        .BypassReqSbr       (BypassReqSbr       ),
        .BypassRspSbr       (BypassRspSbr       ),
        .BypassReqMgr       (BypassReqMgr       ),
        .BypassRspMgr       (BypassRspMgr       )
    ) i_obi_multicut (
                      .clk_i(tck),
                      .rst_ni,
                      .tdi_i(tdo_chained),
                      .isol_en_i(xcnct_isol_en),
                      .capture_dr_i(capture_dr),
                      .shift_dr_i(shift_dr),
                      .update_dr_i(update_dr),
                      .tdo_o,
                      .mst_cut_sbr_ports_req_i, 
                      .cut_xbar_sbr_ports_req_o,
                      .xbar_cut_sbr_ports_rsp_i,
                      .cut_mst_sbr_ports_rsp_o,
                      .xbar_cut_mgr_ports_req_i, 
                      .cut_slv_mgr_ports_req_o,
                      .slv_cut_mgr_ports_rsp_i, 
                      .cut_xbar_mgr_ports_rsp_o,
                      .addr_map_i,
                      .en_default_idx_i,
                      .default_idx_i,
                      .addr_map_o,
                      .en_default_idx_o,
                      .default_idx_o,
                      .xcnct_isol_miscbus_i(xcnct_isol_miscbus)
                     );


    obi_jtag_wrapper #(
        .IrWidth            (IrWidth            ),
        .sbr_port_obi_req_t (sbr_port_obi_req_t ),
        .sbr_port_a_chan_t  (sbr_port_a_chan_t  ),
        .sbr_port_obi_rsp_t (sbr_port_obi_rsp_t ),
        .sbr_port_r_chan_t  (sbr_port_r_chan_t  ),
        .mgr_port_obi_req_t (mgr_port_obi_req_t ),
        .mgr_port_obi_rsp_t (mgr_port_obi_rsp_t ),
        .xcnct_isol_misc_t  (xcnct_isol_misc_t  ),
        .NumSbrPorts        (NumSbrPorts        ),
        .NumMgrPorts        (NumMgrPorts        ),
        .NumMaxTrans        (NumMaxTrans        ),
        .NumAddrRules       (NumAddrRules       ),
        .addr_map_rule_t    (addr_map_rule_t    ),
        .BypassReqSbr       (BypassReqSbr       ),
        .BypassRspSbr       (BypassRspSbr       ),
        .BypassReqMgr       (BypassReqMgr       ),
        .BypassRspMgr       (BypassRspMgr       )
    ) i_obi_jtag_wrap (
                       .tclk_i,
                       .tms_i,
                       .trst_ni,
                       .tdi_i,

                       //TAP Controller Signals
                       .test_logic_reset_i(test_logic_reset),
                       .capture_dr_i(capture_dr),
                       .shift_dr_i(shift_dr),
                       .update_dr_i(update_dr),    
                       .shift_ir_i(shift_ir),        
                       .capture_ir_i(capture_ir),      
                       .update_ir_i(update_ir),   

                       .tdo_o(tdo_chained),
                       .tdo_en_o(),

                       .xcnct_isol_en_o(xcnct_isol_en),
                       .xcnct_isol_o(xcnct_isol_miscbus)
                      );




endmodule
