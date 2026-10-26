module jtag_tap_controller (
    input  logic tclk_i,
    input  logic tms_i,
    input  logic trst_ni,

    output logic run_test_idle_o,   
    output logic test_logic_reset_o,
    output logic capture_dr_o,      
    output logic shift_dr_o,        
    output logic update_dr_o,       
    output logic shift_ir_o,        
    output logic capture_ir_o,      
    output logic update_ir_o       
    // output logic SelectDrScan_o,  
    // output logic Exit1Dr_o,        
    // output logic Exit2Dr_o,        
    // output logic PauseDr_o,        
    // output logic SelectIrScan_o,  
    // output logic PauseIr_o,        
    // output logic Exit1Ir_o,        
    // output logic Exit2Ir_o       
);


//All Possible FSM States 
typedef enum logic [3:0] {
    TestLogicReset,
    RunTestOrIdle,

    SelectDrScan,
    CaptureDr,
    ShiftDr,
    Exit1Dr,
    PauseDr,
    Exit2Dr,
    UpdateDr,

    SelectIrScan,
    CaptureIr,
    ShiftIr,
    Exit1Ir,
    PauseIr,
    Exit2Ir,
    UpdateIr
} tap_state_e;

//Registers 
tap_state_e state_d, state_q;


always_comb begin
    state_d = state_q;

    unique case (state_q)
        TestLogicReset:     begin
                                if(!tms_i) begin
                                    state_d = RunTestOrIdle;
                                end
                            end

        RunTestOrIdle:      begin
                                if(tms_i) begin
                                    state_d = SelectDrScan;
                                end
                            end

        SelectDrScan:       begin
                                if(tms_i) begin
                                    state_d = SelectIrScan;
                                end
                                else begin
                                    state_d = CaptureDr;
                                end
                            end

        CaptureDr:          begin
                                if(tms_i) begin
                                    state_d = Exit1Dr;
                                end
                                else begin
                                    state_d = ShiftDr;
                                end
                            end

        ShiftDr:            begin
                                if(tms_i) begin
                                    state_d = Exit1Dr;
                                end
                            end

        Exit1Dr:            begin
                                if(tms_i) begin
                                    state_d = UpdateDr;
                                end
                                else begin
                                    state_d = PauseDr;
                                end
                            end

        PauseDr:            begin
                                if(tms_i) begin
                                    state_d = Exit2Dr;
                                end
                            end

        Exit2Dr:            begin
                                if(tms_i) begin
                                    state_d = UpdateDr;
                                end
                                else begin
                                    state_d = ShiftDr;
                                end
                            end

        UpdateDr:           begin
                                if(tms_i) begin
                                    state_d = SelectDrScan;
                                end
                                else begin
                                    state_d = RunTestOrIdle;
                                end        
                            end

        SelectIrScan:       begin
                                if(tms_i) begin
                                    state_d = TestLogicReset;
                                end
                                else begin
                                    state_d = CaptureIr;
                                end           
                            end

        CaptureIr:          begin
                                if(tms_i) begin
                                    state_d = Exit1Ir;
                                end
                                else begin
                                    state_d = ShiftIr;
                                end
                            end

        ShiftIr:            begin
                                if(tms_i) begin
                                    state_d = Exit1Ir;
                                end            
                            end

        Exit1Ir:            begin
                                if(tms_i) begin
                                    state_d = UpdateIr;
                                end
                                else begin
                                    state_d = PauseIr;
                                end            
                            end

        PauseIr:            begin
                                if(tms_i) begin
                                    state_d = Exit2Ir;
                                end
                            end

        Exit2Ir:            begin
                                if(tms_i) begin
                                    state_d = UpdateIr;
                                end
                                else begin
                                    state_d = ShiftIr;
                                end           
                            end

        UpdateIr:           begin
                                if(tms_i) begin
                                    state_d = SelectDrScan;
                                end
                                else begin
                                    state_d = RunTestOrIdle;
                                end 
                            end

        default:            begin
                                state_d = TestLogicReset;
                            end

    endcase

end



//Flip-FLop Logic Instantiation
always_ff @(posedge tclk_i) begin
    if(!trst_ni)begin
        state_q <= TestLogicReset;
    end else begin
        state_q <= state_d;
    end

end

//Output Assignments

assign test_logic_reset_o = (state_q == TestLogicReset);
assign capture_dr_o       = (state_q == CaptureDr);
assign shift_dr_o         = (state_q == ShiftDr);
assign update_dr_o        = (state_q == UpdateDr);
assign shift_ir_o         = (state_q == ShiftIr);
assign capture_ir_o       = (state_q == CaptureIr);
assign update_ir_o        = (state_q == UpdateIr);
// assign run_test_idle_o    = (state_q == RunTestOrIdle);
// assign SelectDrScan_o   = (state_q == SelectDrScan);
// assign Exit1Dr_o         = (state_q == Exit1Dr);
// assign Exit2Dr_o         = (state_q == Exit2Dr);
// assign PauseDr_o         = (state_q == PauseDr);
// assign SelectIrScan_o   = (state_q == SelectIrScan);
// assign PauseIr_o         = (state_q == PauseIr);
// assign Exit1Ir_o         = (state_q == Exit1Ir);
// assign Exit2Ir_o         = (state_q == Exit2Ir);


endmodule