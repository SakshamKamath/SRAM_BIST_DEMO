module jtag_tap_top #(
    parameter P_IR_WIDTH = 4,
    parameter IDCODE_VAL = 32'h1080_0786,
    parameter P_ADDR_WIDTH = 10, // Also includes valid bit
    parameter P_IDCODE_WIDTH = 32

)
    (
    input                    tclk_i,
    input                    tms_i,
    input                    trst_ni,
    input                    tdi_i,

    input [P_ADDR_WIDTH-1:0] mbist_erraddr_i,
    input                    mbist_status_i,
    input                    mbist_fifo_notempty_i,

    output                   tdo_o,
    output                   tdo_en_o,

    output                   mbist_start_o,
    output                   mbist_erraddr_read_o
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
                                .select_dr_scan_o(select_dr_scan),  
                                .exit1_dr_o(exit1_dr),        
                                .shift_dr_o(shift_dr),        
                                .exit2_dr_o(exit2_dr),        
                                .pause_dr_o(pause_dr),        
                                .select_ir_scan_o(select_ir_scan),  
                                .update_dr_o(update_dr),       
                                .shift_ir_o(shift_ir),        
                                .capture_ir_o(capture_ir),      
                                .pause_ir_o(pause_ir),        
                                .exit1_ir_o(exit1_ir),        
                                .update_ir_o(update_ir),       
                                .exit2_ir_o(exit2_ir)        
                              );



//----------------------- Instruction Register -------------------------

//All Possible Instructions with their opcodes --TODO

typedef enum logic [P_IR_WIDTH-1:0] {
    INSTR_IDCODE,
    INSTR_BYPASS,
    INSTR_MBIST_START,
    INSTR_MBIST_STATUS_READ,
    INSTR_MBIST_ERRADDR_LOAD,
    INSTR_MEMORY_REPAIR
} ir_type_t;


logic [P_IR_WIDTH-1:0] ir_shift_reg_q, ir_shift_reg_d;
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
    if(capture_ir) begin
        ir_shift_reg_d = { {(P_IR_WIDTH - 2){1'b0}}, 2'b01 };  // As per the IEEE 1149.1 standard
    end
    else if(shift_ir) begin
        ir_shift_reg_d = {tdi_i, ir_shift_reg_q[P_IR_WIDTH-1:1]};
    end
end

// Currently latched instruction so that shifting does not affect the current instruction

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        ir_latched_q <= INSTR_IDCODE;
    end
    else begin
        ir_latched_q <= ir_latched_d;
    end
end

always_comb begin
    ir_latched_d = ir_latched_q;
    if(test_logic_reset)begin
        ir_latched_d = INSTR_IDCODE;
    end
    else if(update_ir)begin
        ir_latched_d = ir_type_t'(ir_shift_reg_q);
    end
end



//----------------------- Bypass Register -------------------------

//If ir_latched_q has INSTR_BYPASS 

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
    if(shift_dr && (ir_latched_q == INSTR_BYPASS)) begin
        bypass_reg_d = tdi_i;
    end
end



//----------------------- MBIST Register -------------------------

logic mbist_reg_q, mbist_reg_d;

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        mbist_reg_q <= 1'b0;
    end
    else begin
        mbist_reg_q <= mbist_reg_d;
    end
end


always_comb begin
    if(update_dr && (ir_latched_q == INSTR_MBIST_START)) begin
        mbist_reg_d = 1'b1;
    end
    else begin
        mbist_reg_d = 1'b0;
    end
end




//----------------------- IDCODE Register -------------------------

// Stores the Unique ID for every device, good for debugging

logic [P_IDCODE_WIDTH-1:0] idcode_reg_q, idcode_reg_d;

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        idcode_reg_q <= IDCODE_VAL;
    end
    else begin
        idcode_reg_q <= idcode_reg_d;
    end
end

always_comb begin
    idcode_reg_d = idcode_reg_q;
    if(capture_dr && (ir_latched_q == INSTR_IDCODE)) begin
        idcode_reg_d = IDCODE_VAL;
    end
    else if(shift_dr && (ir_latched_q == INSTR_IDCODE)) begin
        idcode_reg_d = {tdi_i, idcode_reg_q[P_IDCODE_WIDTH-1:1]};
    end
end


//----------------------- Error Address DR Register -------------------------

logic [P_ADDR_WIDTH-1:0] err_addr_reg_q, err_addr_reg_d;

always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        err_addr_reg_q <= '0;
    end else begin
        err_addr_reg_q <= err_addr_reg_d;
    end
end

always_comb begin
    err_addr_reg_d = err_addr_reg_q;
    if (ir_latched_q == INSTR_MBIST_ERRADDR_LOAD) begin
        if (capture_dr) begin
            // Capture parallel erroneous address into the shift register
            err_addr_reg_d = {mbist_fifo_notempty_i, mbist_erraddr_i}; 
        end else if (shift_dr) begin
            // Right-shift out via TDO while shifting in TDI
            err_addr_reg_d = {tdi_i, err_addr_reg_q[P_ADDR_WIDTH-1:1]};
        end
    end
end



//----------------------- MBIST Status DR Register -------------------------

logic [1:0] mbist_status_reg_q, mbist_status_reg_d  ;

always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        mbist_status_reg_q <= '0;
    end else begin
        mbist_status_reg_q <= mbist_status_reg_d;
    end
end

always_comb begin
    mbist_status_reg_d = mbist_status_reg_q;
    if (ir_latched_q == INSTR_MBIST_STATUS_READ) begin
        if (capture_dr) begin
            // Capture parallel mbist status into the shift register
            mbist_status_reg_d = {mbist_fifo_notempty_i, mbist_status_i}; 
        end else if (shift_dr) begin
            // Right-shift out via TDO while shifting in TDI
            mbist_status_reg_d = {tdi_i, mbist_status_reg_q[1]};
        end
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

    if(shift_ir) begin
        tdo_d = ir_shift_reg_q[0];
    end
    else if (shift_dr) begin
        unique case(ir_latched_q)
            INSTR_IDCODE:              tdo_d = idcode_reg_q[0];

            INSTR_BYPASS:              tdo_d = bypass_reg_q;

            INSTR_MBIST_ERRADDR_LOAD:  tdo_d = err_addr_reg_q[0];

            INSTR_MBIST_STATUS_READ:   tdo_d = mbist_status_reg_q[0];

            default:                   tdo_d = bypass_reg_q;

        endcase
    end
end 


always_comb begin
    tdo_en_d = shift_ir || shift_dr;
end




// Output Assignments

assign tdo_o = tdo_q;
assign tdo_en_o = tdo_en_q;

assign mbist_start_o = mbist_reg_q;
assign mbist_erraddr_read_o = capture_dr && (ir_latched_q == INSTR_MBIST_ERRADDR_LOAD) && mbist_fifo_notempty_i;

endmodule