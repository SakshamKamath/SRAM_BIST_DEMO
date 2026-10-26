module obi_jtag_wrapper #(
    parameter IrWidth    = 2,
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
    /// The response struct for the manager ports (output ports).
    parameter type               mgr_port_obi_rsp_t = sbr_port_obi_rsp_t,
    /// The struct type for isolation bus signals
    parameter type               xcnct_isol_misc_t       = logic,
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
    input  logic                 tclk_i,
    input  logic                 tms_i,
    input  logic                 trst_ni,
    input  logic                 tdi_i,

    //TAP Controller Signals
    input  logic                 test_logic_reset_i,
    input  logic                 capture_dr_i,      
    input  logic                 shift_dr_i,        
    input  logic                 update_dr_i,       
    input  logic                 shift_ir_i,        
    input  logic                 capture_ir_i,      
    input  logic                 update_ir_i,   

    output logic                 tdo_o,
    output logic                 tdo_en_o,

    output logic                 xcnct_isol_en_o,
    output xcnct_isol_misc_t     xcnct_isol_o
);

typedef enum logic [IrWidth-1:0] {
    Instr_Bypass,
    Instr_XcnctIsolation
} ir_type_t;

logic [IrWidth-1:0] ir_shift_reg_q, ir_shift_reg_d;
ir_type_t ir_latched_q, ir_latched_d;


always_ff @(posedge tclk_i) begin
    if(!trst_ni)begin
        ir_shift_reg_q <= '0;
    end
    else begin
        ir_shift_reg_q <= ir_shift_reg_d;
    end
end

always_comb begin
    ir_shift_reg_d = ir_shift_reg_q;
    if(capture_ir_i) begin
        ir_shift_reg_d = { {(IrWidth - 2){1'b0}}, 2'b00 };  // As per the IEEE 1149.1 standard
    end
    if(shift_ir_i) begin
        ir_shift_reg_d = {tdi_i, ir_shift_reg_q[IrWidth-1:1]};
    end
end

// Currently latched instruction so that shifting does not affect the current instruction

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        ir_latched_q <= Instr_Bypass;
    end
    else begin
        ir_latched_q <= ir_latched_d;
    end
end

always_comb begin
    ir_latched_d = ir_latched_q;
    if(update_ir_i)begin
        ir_latched_d = ir_type_t'(ir_shift_reg_q);
    end
    if(test_logic_reset_i)begin
        ir_latched_d = Instr_Bypass;
    end
end


logic bypass_select, xcnct_isol_select;

always_comb begin : dr_select

    bypass_select        = 1'b0;
    xcnct_isol_select    = 1'b0;

    unique case (ir_latched_q)
        Instr_Bypass            : bypass_select        = 1'b1;
        Instr_XcnctIsolation    : xcnct_isol_select    = 1'b1;
        default                 : bypass_select        = 1'b1; 
    endcase

end



//----------------------- Bypass Register -------------------------

logic bypass_reg_q, bypass_reg_d;

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        bypass_reg_q <= 1'b0;
    end
    else begin
        bypass_reg_q <= bypass_reg_d;
    end
end

always_comb begin
    bypass_reg_d = bypass_reg_q;

    if(shift_dr_i) begin
        if(bypass_select) bypass_reg_d = tdi_i;
    end

    if(capture_dr_i) begin
        if(bypass_select) bypass_reg_d = 1'b0;
    end

    if(test_logic_reset_i) begin
        if(bypass_select) bypass_reg_d = 1'b0;
    end
end

//----------------------- Xcnct Isolation -------------------------


localparam int IsolBitWidth = $bits(xcnct_isol_misc_t);

xcnct_isol_misc_t xcnct_isol_d, xcnct_isol_q;

always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        xcnct_isol_q <= '0;
    end else begin
        xcnct_isol_q <= xcnct_isol_d;
    end
end

always_comb begin
    xcnct_isol_d = xcnct_isol_q;

    if (shift_dr_i) begin
        if (xcnct_isol_select) begin 
            xcnct_isol_d = {tdi_i, xcnct_isol_q[IsolBitWidth-1:1]};
        end
    end

    if(test_logic_reset_i) begin
            xcnct_isol_d = '0;
    end
end



//----------------------- MUXing for TDO -------------------------

logic tdo_en_q, tdo_en_d;
logic tdo_q, tdo_d;

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        tdo_q    <= 1'b0;
        tdo_en_q <= 1'b0;
    end
    else begin
        tdo_q    <= tdo_d;
        tdo_en_q <= tdo_en_d;
    end
end


always_comb begin
    tdo_d = tdo_q;

    if(shift_ir_i) begin
        tdo_d = ir_shift_reg_q[0];
    end
    else if (shift_dr_i) begin
        unique case(ir_latched_q)
            Instr_Bypass:              tdo_d = bypass_reg_q;

            Instr_XcnctIsolation:      tdo_d = xcnct_isol_q[0];

            default:                   tdo_d = bypass_reg_q;
        endcase
    end
end 


always_comb begin
    tdo_en_d = shift_ir_i || shift_dr_i;
end



assign tdo_o = tdo_q;
assign tdo_en_o = tdo_en_q;
assign xcnct_isol_en_o = xcnct_isol_select;
assign xcnct_isol_o    = xcnct_isol_q;   // isolation address map / default index to the multicut

endmodule