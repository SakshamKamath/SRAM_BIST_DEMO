module mem_jtag_top #(
    parameter IrWidth    = 4,
    parameter MemIDValue = 32'h1080_0786,
    parameter AddrWidth  = 10, 
    parameter DataWidth  = 32,
    parameter MemIDWidth = 32
) (
    input  logic                 tclk_i,
    input  logic                 tms_i,
    input  logic                 trst_ni,
    input  logic                 tdi_i,
    // input  logic                 testmode_i,

    input  logic [AddrWidth-1:0] mbist_erraddr_i,
    input  logic                 mbist_status_i,
    input  logic                 mbist_fifo_notempty_i,
    input  logic [DataWidth-1:0] mem_rdata_i,

    input  logic [AddrWidth-1:0] repair_addr_i,
    input  logic                 repair_men_i,
    input  logic                 repair_wen_i,
    input  logic                 repair_ren_i,
    input  logic [DataWidth-1:0] repair_bm_i,
    input  logic [DataWidth-1:0] repair_wdata_i,

    output logic                 tdo_o,
    output logic                 tdo_en_o, 

    output logic                 mbist_start_o,
    output logic                 mbist_resume_o,
    output logic                 mbist_erraddr_read_o,

    // Goes to the BIST interface of the memory
    output logic [AddrWidth-1:0] isol_addr_o,
    output logic [DataWidth-1:0] isol_data_o,
    output logic [DataWidth-1:0] isol_bm_o,
    output logic                 isol_bist_en_o,
    output logic                 isol_men_o,
    output logic                 isol_wen_o,
    output logic                 isol_ren_o,

    //Goes to the system bus from the repair element
    output logic [DataWidth-1:0] repair_rdata_o, 

    //Go to the memory functional interface
    output logic [AddrWidth-1:0] bypass_addr_o, 
    output logic [DataWidth-1:0] bypass_data_o, 
    output logic [DataWidth-1:0] bypass_bm_o,
    output logic                 bypass_men_o,
    output logic                 bypass_wen_o,
    output logic                 bypass_ren_o
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
                                    // .select_dr_scan_o(select_dr_scan),  
                                    // .exit1_dr_o(exit1_dr),        
                                    // .exit2_dr_o(exit2_dr),        
                                    // .pause_dr_o(pause_dr),        
                                    // .select_ir_scan_o(select_ir_scan),  
                                    // .pause_ir_o(pause_ir),        
                                    // .exit1_ir_o(exit1_ir),        
                                    // .exit2_ir_o(exit2_ir)        
                                  );




    mem_jtag_wrapper #(
                    .IrWidth    (IrWidth),
                    .MemIDValue (MemIDValue),
                    .AddrWidth  (AddrWidth),
                    .DataWidth  (DataWidth),
                    .MemIDWidth (MemIDWidth)

    ) u_jtag_register_logic   (
                     .tclk_i,
                     .tms_i,
                     .trst_ni,
                     .tdi_i,
                    //  .testmode_i,
                     .mbist_erraddr_i,
                     .mbist_status_i,
                     .mbist_fifo_notempty_i,
                     .mem_rdata_i,
                     .repair_addr_i,
                     .repair_men_i,
                     .repair_wen_i,
                     .repair_ren_i,
                     .repair_bm_i,
                     .repair_wdata_i,
                     .test_logic_reset_i (test_logic_reset),
                     .capture_dr_i       (capture_dr      ),      
                     .shift_dr_i         (shift_dr        ),        
                     .update_dr_i        (update_dr       ),       
                     .shift_ir_i         (shift_ir        ),        
                     .capture_ir_i       (capture_ir      ),      
                     .update_ir_i        (update_ir       ),       
                     .tdo_o,
                     .tdo_en_o, 
                     .mbist_start_o,
                     .mbist_resume_o,
                     .mbist_erraddr_read_o,
                     .isol_addr_o,
                     .isol_data_o,
                     .isol_bm_o,
                     .isol_bist_en_o,
                     .isol_men_o,
                     .isol_wen_o,
                     .isol_ren_o,
                     .repair_rdata_o, 
                     .bypass_addr_o, 
                     .bypass_data_o, 
                     .bypass_bm_o,
                     .bypass_men_o,
                     .bypass_wen_o,
                     .bypass_ren_o
    );

endmodule