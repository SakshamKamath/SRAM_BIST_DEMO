module bndscan_jtag_wrapper import croc_pkg::*;
#(
    parameter NumIOPads = 1,
    parameter IrWidth   = 4,
    parameter type PadType_t = logic,
    parameter type PadDir_t  = logic
)(
    input  logic                     clk_i,
    input  logic                     rst_ni,

    // JTAG Interface 
    input  logic                     tclk_i,
    input  logic                     trst_ni,
    input  logic                     tdi_i,
    input  logic                     tms_i,
    output logic                     tdo_o,
    output logic                     tdo_en_o,


    //TAP Controller Signals
    input  logic                     test_logic_reset_i,
    input  logic                     capture_dr_i,      
    input  logic                     shift_dr_i,        
    input  logic                     update_dr_i,       
    input  logic                     shift_ir_i,        
    input  logic                     capture_ir_i,      
    input  logic                     update_ir_i,   

    input  PadDir_t  [NumIOPads-1:0] PadCfg_i,
    input  PadType_t [NumIOPads-1:0] PadCnct_i,
    output PadType_t [NumIOPads-1:0] PadCnct_o
);

typedef enum logic [IrWidth-1:0] {
    Instr_Bypass,
    Instr_SamplePreload,
    Instr_Extest,
    Instr_Intest
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
    if(update_ir_i) begin
        ir_latched_d = ir_type_t'(ir_shift_reg_q);
    end
    if(test_logic_reset_i) begin
        ir_latched_d = Instr_Bypass;
    end
end


logic bypass_select, extest_select, intest_select, sampnpre_select;

always_comb begin : dr_select

    bypass_select        = 1'b0;
    sampnpre_select      = 1'b0;
    extest_select        = 1'b0;
    intest_select        = 1'b0;

    unique case (ir_latched_q)
        Instr_Bypass            : bypass_select        = 1'b1;
        Instr_SamplePreload     : sampnpre_select      = 1'b1;
        Instr_Extest            : extest_select        = 1'b1;
        Instr_Intest            : intest_select        = 1'b1;
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


//----------------------- BSC Register -------------------------

logic     [NumIOPads-1:0] bsc_shiftreg_d, bsc_shiftreg_q; 
logic     [NumIOPads-1:0] bsc_latchedreg_d, bsc_latchedreg_q; 


always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        bsc_shiftreg_q <= '0;
    end else begin
        bsc_shiftreg_q <= bsc_shiftreg_d;
    end
end


always_comb begin
    bsc_shiftreg_d = bsc_shiftreg_q;

    if (shift_dr_i) begin
        if (sampnpre_select) begin 
            bsc_shiftreg_d = {tdi_i, bsc_shiftreg_q[NumIOPads-1:1]};
        end

        if(extest_select) begin
            bsc_shiftreg_d = {tdi_i, bsc_shiftreg_q[NumIOPads-1:1]};
        end

        if(intest_select) begin
            bsc_shiftreg_d = {tdi_i, bsc_shiftreg_q[NumIOPads-1:1]};
        end
    end

    if(capture_dr_i) begin
        for (int i = 0; i < NumIOPads; i++) begin
            if(sampnpre_select) begin
                bsc_shiftreg_d[i] = (PadCfg_i[i] == PAD_IN) ? PadCnct_i[i].p2c : PadCnct_i[i].c2p;
            end

            if(extest_select) begin
                bsc_shiftreg_d[i] = (PadCfg_i[i] == PAD_IN) ? PadCnct_i[i].p2c : PadCnct_i[i].c2p;
            end

            if(intest_select) begin
                bsc_shiftreg_d[i] = (PadCfg_i[i] == PAD_IN) ? bsc_latchedreg_q[i] : PadCnct_i[i].c2p;
            end
        end
    end

    if(test_logic_reset_i) begin
            bsc_shiftreg_d = '0;
    end
end


always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        bsc_latchedreg_q <= '0;
    end else begin
        bsc_latchedreg_q <= bsc_latchedreg_d;
    end
end

always_comb begin

    bsc_latchedreg_d = bsc_latchedreg_q;

    if(update_dr_i) begin
        if(sampnpre_select) begin
            bsc_latchedreg_d = bsc_shiftreg_q;
        end

        if(extest_select) begin
            bsc_latchedreg_d = bsc_shiftreg_q;
        end

        if(intest_select) begin 
            bsc_latchedreg_d = bsc_shiftreg_q;
        end
    end


    if(test_logic_reset_i) begin
            bsc_latchedreg_d = '0;
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

            Instr_SamplePreload:       tdo_d = bsc_shiftreg_q[0];

            Instr_Extest:              tdo_d = bsc_shiftreg_q[0];

            Instr_Intest:              tdo_d = bsc_shiftreg_q[0];

            default:                   tdo_d = bypass_reg_q;
        endcase
    end
end 


always_comb begin
    tdo_en_d = shift_ir_i || shift_dr_i;
end



//----------------------- System-Side Pad Intercept MUX -------------------------

always_comb begin
    PadCnct_o = PadCnct_i; // Default just pass through

    for (int i = 0; i < NumIOPads; i++) begin
        
        if (PadCfg_i[i] == PAD_IN) begin // For Input PADs
            if (intest_select) begin
                PadCnct_o[i] = bsc_latchedreg_q[i];
            end else begin
                PadCnct_o[i] = PadCnct_i[i];
            end

        end else begin
            if (extest_select) begin
                PadCnct_o[i] = bsc_latchedreg_q[i];
            end else begin
                PadCnct_o[i] = PadCnct_i[i];
            end

        end
    end
end

assign tdo_o = tdo_q;
assign tdo_en_o = tdo_en_q;

endmodule