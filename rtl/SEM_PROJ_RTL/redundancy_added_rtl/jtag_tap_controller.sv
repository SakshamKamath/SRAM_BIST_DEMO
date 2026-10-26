module jtag_tap_controller (
    input tclk_i,
    input tms_i,
    input trst_ni,

    output run_test_idle_o,   
    output test_logic_reset_o,
    output capture_dr_o,      
    output select_dr_scan_o,  
    output exit1_dr_o,        
    output shift_dr_o,        
    output exit2_dr_o,        
    output pause_dr_o,        
    output select_ir_scan_o,  
    output update_dr_o,       
    output shift_ir_o,        
    output capture_ir_o,      
    output pause_ir_o,        
    output exit1_ir_o,        
    output update_ir_o,       
    output exit2_ir_o       
);


//All Possible FSM States 
typedef enum logic [3:0] {
    TEST_LOGIC_RESET,
    RUN_TEST_OR_IDLE,

    SELECT_DR_SCAN,
    CAPTURE_DR,
    SHIFT_DR,
    EXIT1_DR,
    PAUSE_DR,
    EXIT2_DR,
    UPDATE_DR,

    SELECT_IR_SCAN,
    CAPTURE_IR,
    SHIFT_IR,
    EXIT1_IR,
    PAUSE_IR,
    EXIT2_IR,
    UPDATE_IR
} tap_state_e;

//Registers 
tap_state_e state_d, state_q;


always_comb begin
    state_d = state_q;

    unique case (state_q)
        TEST_LOGIC_RESET:   begin
                                if(!tms_i) begin
                                    state_d = RUN_TEST_OR_IDLE;
                                end
                            end

        RUN_TEST_OR_IDLE:   begin
                                if(tms_i) begin
                                    state_d = SELECT_DR_SCAN;
                                end
                            end

        SELECT_DR_SCAN:     begin
                                if(tms_i) begin
                                    state_d = SELECT_IR_SCAN;
                                end
                                else begin
                                    state_d = CAPTURE_DR;
                                end
                            end

        CAPTURE_DR:         begin
                                if(tms_i) begin
                                    state_d = EXIT1_DR;
                                end
                                else begin
                                    state_d = SHIFT_DR;
                                end
                            end

        SHIFT_DR:           begin
                                if(tms_i) begin
                                    state_d = EXIT1_DR;
                                end
                            end

        EXIT1_DR:           begin
                                if(tms_i) begin
                                    state_d = UPDATE_DR;
                                end
                                else begin
                                    state_d = PAUSE_DR;
                                end
                            end

        PAUSE_DR:           begin
                                if(tms_i) begin
                                    state_d = EXIT2_DR;
                                end
                            end

        EXIT2_DR:           begin
                                if(tms_i) begin
                                    state_d = UPDATE_DR;
                                end
                                else begin
                                    state_d = SHIFT_DR;
                                end
                            end

        UPDATE_DR:          begin
                                if(tms_i) begin
                                    state_d = SELECT_DR_SCAN;
                                end
                                else begin
                                    state_d = RUN_TEST_OR_IDLE;
                                end        
                            end

        SELECT_IR_SCAN:     begin
                                if(tms_i) begin
                                    state_d = TEST_LOGIC_RESET;
                                end
                                else begin
                                    state_d = CAPTURE_IR;
                                end           
                            end

        CAPTURE_IR:         begin
                                if(tms_i) begin
                                    state_d = EXIT1_IR;
                                end
                                else begin
                                    state_d = SHIFT_IR;
                                end
                            end

        SHIFT_IR:           begin
                                if(tms_i) begin
                                    state_d = EXIT1_IR;
                                end            
                            end

        EXIT1_IR:           begin
                                if(tms_i) begin
                                    state_d = UPDATE_IR;
                                end
                                else begin
                                    state_d = PAUSE_IR;
                                end            
                            end

        PAUSE_IR:           begin
                                if(tms_i) begin
                                    state_d = EXIT2_IR;
                                end
                            end

        EXIT2_IR:           begin
                                if(tms_i) begin
                                    state_d = UPDATE_IR;
                                end
                                else begin
                                    state_d = SHIFT_IR;
                                end           
                            end

        UPDATE_IR:          begin
                                if(tms_i) begin
                                    state_d = SELECT_DR_SCAN;
                                end
                                else begin
                                    state_d = RUN_TEST_OR_IDLE;
                                end 
                            end

        default:            begin
                                state_d = TEST_LOGIC_RESET;
                            end

    endcase

end



//Flip-FLop Logic Instantiation
always_ff @(posedge tclk_i) begin
    if(!trst_ni)begin
        state_q <= TEST_LOGIC_RESET;
    end else begin
        state_q <= state_d;
    end

end

//Output Assignments

assign run_test_idle_o    = (state_q == RUN_TEST_OR_IDLE);
assign test_logic_reset_o = (state_q == TEST_LOGIC_RESET);
assign capture_dr_o       = (state_q == CAPTURE_DR);
assign select_dr_scan_o   = (state_q == SELECT_DR_SCAN);
assign exit1_dr_o         = (state_q == EXIT1_DR);
assign shift_dr_o         = (state_q == SHIFT_DR);
assign exit2_dr_o         = (state_q == EXIT2_DR);
assign pause_dr_o         = (state_q == PAUSE_DR);
assign select_ir_scan_o   = (state_q == SELECT_IR_SCAN);
assign update_dr_o        = (state_q == UPDATE_DR);
assign shift_ir_o         = (state_q == SHIFT_IR);
assign capture_ir_o       = (state_q == CAPTURE_IR);
assign pause_ir_o         = (state_q == PAUSE_IR);
assign exit1_ir_o         = (state_q == EXIT1_IR);
assign update_ir_o        = (state_q == UPDATE_IR);
assign exit2_ir_o         = (state_q == EXIT2_IR);


endmodule