module bndscan_jtag_top #(
    parameter NumIOPads      = 1,
    parameter IrWidth        = 4,
    parameter type PadType_t = logic,
    parameter type PadDir_t = logic
)(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic testmode_i,

    // JTAG Interface 
    input  logic tclk_i,
    input  logic trst_ni,
    input  logic tdi_i,
    input  logic tms_i,
    output logic tdo_o,
    output logic tdo_en_o,

    input  PadDir_t  [NumIOPads-1:0] PadCfg_i,
    input  PadType_t [NumIOPads-1:0] PadCnct_i,
    output PadType_t [NumIOPads-1:0] PadCnct_o
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

    bndscan_jtag_wrapper #(
        .NumIOPads(NumIOPads),
        .IrWidth(IrWidth),
        .PadType_t(PadType_t),
        .PadDir_t(PadDir_t)
    ) i_bndscan_jtag_wrap (
                           .clk_i,
                           .rst_ni,
                           .tclk_i,
                           .trst_ni,
                           .tdi_i,
                           .tms_i,
                           .tdo_o,
                           .tdo_en_o,
                           .test_logic_reset_i(test_logic_reset),
                           .capture_dr_i(capture_dr),      
                           .shift_dr_i(shift_dr),        
                           .update_dr_i(update_dr),       
                           .shift_ir_i(shift_ir),        
                           .capture_ir_i(capture_ir),      
                           .update_ir_i(update_ir),   
                           .PadCfg_i,
                           .PadCnct_i,
                           .PadCnct_o
                         );    

endmodule
