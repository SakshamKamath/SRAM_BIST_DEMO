module jtag_tap_top #(
    parameter IrWidth = 4,
    parameter IdcodeValue = 32'h1080_0786,
    parameter AddrWidth = 10, // Also includes valid bit
    parameter DataWidth = 32,
    parameter IdcodeWidth = 32

)
    (
    input                  tclk_i,
    input                  tms_i,
    input                  trst_ni,
    input                  tdi_i,

    input [AddrWidth-1:0]  mbist_erraddr_i,
    input                  mbist_status_i,
    input                  mbist_fifo_notempty_i,
    input [DataWidth-1:0]  mem_rdata_i,

    input [AddrWidth-1:0]  repair_addr_i,
    input                  repair_men_i,
    input                  repair_wen_i,
    input                  repair_ren_i,
    input [DataWidth-1:0]  repair_bm_i,
    input [DataWidth-1:0]  repair_wdata_i,

    output                 tdo_o,
    output                 tdo_en_o, 

    output                 mbist_start_o,
    output                 mbist_resume_o,
    output                 mbist_erraddr_read_o,

    // Goes to the BIST interface of the memory
    output [AddrWidth-1:0] isol_addr_o,
    output [DataWidth-1:0] isol_data_o,
    output [DataWidth-1:0] isol_bm_o,
    output                 isol_bist_en_o,
    output                 isol_men_o,
    output                 isol_wen_o,
    output                 isol_ren_o,

    //Goes to the system bus from the repair element
    output [DataWidth-1:0] repair_rdata_o, 

    //Go to the memory functional interface
    output [AddrWidth-1:0] bypass_addr_o, 
    output [DataWidth-1:0] bypass_data_o, 
    output [DataWidth-1:0] bypass_bm_o,
    output                 bypass_men_o,
    output                 bypass_wen_o,
    output                 bypass_ren_o
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

//All Possible Instructions with their opcodes

import jtag_pkg::*;
typedef enum logic [IrWidth-1:0] {
    Instr_Idcode,
    Instr_Bypass,
    Instr_MbistCtrl,
    Instr_MbistStatusRead,
    Instr_MbistErraddrLoad,
    Instr_MemRepair,
    Instr_MemIsolation
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
    if(capture_ir) begin
        ir_shift_reg_d = { {(IrWidth - 2){1'b0}}, 2'b01 };  // As per the IEEE 1149.1 standard
    end
    if(shift_ir) begin
        ir_shift_reg_d = {tdi_i, ir_shift_reg_q[IrWidth-1:1]};
    end
end

// Currently latched instruction so that shifting does not affect the current instruction

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        ir_latched_q <= Instr_Idcode;
    end
    else begin
        ir_latched_q <= ir_latched_d;
    end
end

always_comb begin
    ir_latched_d = ir_latched_q;
    if(update_ir)begin
        ir_latched_d = ir_type_t'(ir_shift_reg_q);
    end
    if(test_logic_reset)begin
        ir_latched_d = Instr_Idcode;
    end
end


//----------------------- Select Signals for DR -------------------------


logic idcode_select, bypass_select, mbist_ctrl_select, 
      mbist_status_select, mbist_erraddr_select,
      mem_repair_select, mem_isol_select;

always_comb begin : dr_select

    idcode_select        = 1'b0;
    bypass_select        = 1'b0;
    mbist_ctrl_select    = 1'b0;
    mbist_status_select  = 1'b0;
    mbist_erraddr_select = 1'b0;
    mem_repair_select    = 1'b0;
    mem_isol_select      = 1'b0;

    unique case (ir_latched_q)
        Instr_Idcode            : idcode_select        = 1'b1;
        Instr_Bypass            : bypass_select        = 1'b1;
        Instr_MbistCtrl         : mbist_ctrl_select    = 1'b1;
        Instr_MbistStatusRead   : mbist_status_select  = 1'b1;
        Instr_MbistErraddrLoad  : mbist_erraddr_select = 1'b1;
        Instr_MemRepair         : mem_repair_select    = 1'b1;
        Instr_MemIsolation      : mem_isol_select      = 1'b1;
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

    if(shift_dr) begin
        if(bypass_select) bypass_reg_d = tdi_i;
    end

    if(capture_dr) begin
        if(bypass_select) bypass_reg_d = 1'b0;
    end

    if(test_logic_reset) begin
        if(bypass_select) bypass_reg_d = 1'b0;
    end
end



//----------------------- MBIST Shared Start, Resume and Reset Register -------------------------

logic mbist_ctrl_reg_q, mbist_ctrl_reg_d;

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        mbist_ctrl_reg_q <= 1'b0;
    end
    else begin
        mbist_ctrl_reg_q <= mbist_ctrl_reg_d;
    end
end


always_comb begin
    mbist_ctrl_reg_d = 1'b0;

    if(update_dr) begin
        if(mbist_ctrl_select) mbist_ctrl_reg_d = 1'b1;
    end

    if(test_logic_reset) begin
        if(mbist_ctrl_select) mbist_ctrl_reg_d = 1'b0;
    end
end



//----------------------- IDCODE Register -------------------------

// Stores the Unique ID for every device, good for debugging

logic [IdcodeWidth-1:0] idcode_reg_q, idcode_reg_d;

always_ff @(posedge tclk_i) begin
    if(!trst_ni) begin
        idcode_reg_q <= IdcodeValue;
    end
    else begin
        idcode_reg_q <= idcode_reg_d;
    end
end

always_comb begin
    idcode_reg_d = idcode_reg_q;
    
    if (capture_dr) begin
        if (idcode_select) idcode_reg_d = IdcodeValue;
    end

    if (shift_dr) begin
        if (idcode_select) idcode_reg_d = {tdi_i, idcode_reg_q[IdcodeWidth-1:1]};
    end

    if (test_logic_reset) begin
        idcode_reg_d = IdcodeValue;
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

    if (capture_dr) begin
        if (mbist_status_select) mbist_status_reg_d = {mbist_fifo_notempty_i, mbist_status_i};
    end

    if (shift_dr) begin
        if (mbist_status_select) mbist_status_reg_d = {tdi_i, mbist_status_reg_q[1]};
    end

    if (test_logic_reset) begin
        mbist_status_reg_d = 2'b0;
    end

end

//----------------------- Error Address DR Register -------------------------

typedef struct packed {
    logic                      valid; // Only used for memory repair for addr_t type used in repair_isol_t
    logic [AddrWidth-1:0]   addr;
} addr_t;

typedef struct packed {
    addr_t   vaddr;
    logic [DataWidth-1:0] data;
    logic [DataWidth-1:0] bm;
} repair_isol_t;

typedef struct packed {
    repair_isol_t            redundancy;
    logic                    bist_en;
    logic                    men;
    logic                    wen;
    logic                    ren;
} mem_isol_t;

localparam int IsolBitWidth = $bits(mem_isol_t);


addr_t err_addr_reg_q, err_addr_reg_d;

always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        err_addr_reg_q <= '0;
    end else begin
        err_addr_reg_q <= err_addr_reg_d;
    end
end

always_comb begin
    err_addr_reg_d = err_addr_reg_q;

    if (capture_dr) begin
        if (mbist_erraddr_select) err_addr_reg_d = {mbist_fifo_notempty_i, mbist_erraddr_i};
    end

    if (shift_dr) begin
        if (mbist_erraddr_select) err_addr_reg_d = {tdi_i, err_addr_reg_q[AddrWidth-1:1]};
    end

    if (test_logic_reset) begin
        err_addr_reg_d = '0;
    end
end


//----------------------- Memory Isolation -------------------------


mem_isol_t mem_isol_d, mem_isol_q;


// Address hit detection when valid bit high and address matches
logic repair_hit;

assign repair_hit = mem_isol_q.redundancy.vaddr.valid && 
                   (repair_addr_i == mem_isol_q.redundancy.vaddr.addr);



always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        mem_isol_q <= '0;
    end else begin
        mem_isol_q <= mem_isol_d;
    end
end

always_comb begin
    mem_isol_d = mem_isol_q;

    if (capture_dr) begin
        if (mem_isol_select) mem_isol_d.redundancy.data = mem_rdata_i;
    end

    if (shift_dr) begin
        if (mem_isol_select | mem_repair_select) begin 
            mem_isol_d = {tdi_i, mem_isol_q[IsolBitWidth-1:1]};
        end
    end

    if (repair_men_i && repair_ren_i) begin
        if (repair_hit) begin
            // Latched repair data stored into bm
            mem_isol_d.redundancy.bm = mem_isol_q.redundancy.data; 
        end else begin
            // Normal memory read data stored into bm
            mem_isol_d.redundancy.bm = mem_rdata_i; 
        end
    end

    //Remap based on valid addr in repair element 1  -- DOUBT: Assuming memory functional interface wouldn't be used during shifting
    if (repair_hit && repair_wen_i & repair_men_i) begin

        mem_isol_d.redundancy.data = (repair_wdata_i & repair_bm_i) | 
                                     (mem_isol_q.redundancy.data & ~repair_bm_i);

    end
end


// Latch the relevant bits for controlling memory ports

mem_isol_t mem_isol_shadow_d, mem_isol_shadow_q;


always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        mem_isol_shadow_q <= '0;
    end else begin
        mem_isol_shadow_q <= mem_isol_shadow_d;
    end
end

always_comb begin
    mem_isol_shadow_d = mem_isol_shadow_q;

    if (update_dr) begin
        if (mem_isol_select) mem_isol_shadow_d = mem_isol_q;
    end

    if (test_logic_reset || !mem_isol_select) begin
        mem_isol_shadow_d = '0;
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
            Instr_Idcode:              tdo_d = idcode_reg_q[0];

            Instr_Bypass:              tdo_d = bypass_reg_q;

            Instr_MbistErraddrLoad:  tdo_d = err_addr_reg_q[0];

            Instr_MbistStatusRead:   tdo_d = mbist_status_reg_q[0];

            Instr_MemIsolation:       tdo_d = mem_isol_q[0];

            Instr_MemRepair:       tdo_d = mem_isol_q[0];

            default:                   tdo_d = bypass_reg_q;
        endcase
    end
end 


always_comb begin
    tdo_en_d = shift_ir || shift_dr;
end



//----------------------- Redundancy and Bypass logic -------------------------

logic [AddrWidth-1:0] bypass_addr;  
logic [DataWidth-1:0] bypass_data;  
logic [DataWidth-1:0] bypass_bm; 
logic                 bypass_men;
logic                 bypass_wen;
logic                 bypass_ren;

logic [DataWidth-1:0] repair_rdata; 
logic                 rephit_rd_latency_d, rephit_rd_latency_q; // for sram rd latency



always_comb begin
    rephit_rd_latency_d = rephit_rd_latency_q;
    if(repair_men_i && repair_ren_i) begin
        rephit_rd_latency_d = repair_hit;
    end
end


always_ff @( posedge tclk_i ) begin
    if(!trst_ni) begin
        rephit_rd_latency_q <= 1'b0;
    end
    else begin
        rephit_rd_latency_q <= rephit_rd_latency_d;
    end
end


// Bypass the signals to memory if valid bit 0 else read/write from repair elements
always_comb begin
    // Pass-through standard inputs
    bypass_addr  = repair_addr_i;
    bypass_data  = repair_wdata_i;
    bypass_bm    = repair_bm_i;
    bypass_men   = repair_men_i;
    bypass_wen   = repair_wen_i;
    bypass_ren   = repair_ren_i;

    

    // Remap whenever address hits and repair entry is valid (Irrespective of ir_latched_q)
    if(rephit_rd_latency_q) begin
        repair_rdata = mem_isol_q.redundancy.bm;
    end
    else begin
        repair_rdata = mem_rdata_i;
    end

    if (repair_hit) begin
        if (repair_men_i) begin
            bypass_ren   = 1'b0;                         // Inhibit main memory read
            bypass_men   = 1'b0;
            bypass_wen   = 1'b0;                         // Inhibit main memory write
        end
    end

end




// Output Assignments

assign tdo_o = tdo_q;
assign tdo_en_o = tdo_en_q;

assign mbist_start_o = mbist_ctrl_reg_q;
assign mbist_resume_o = mbist_ctrl_reg_q;
assign mbist_erraddr_read_o = capture_dr && (ir_latched_q == Instr_MbistErraddrLoad) && mbist_fifo_notempty_i;

assign isol_addr_o     = mem_isol_shadow_q.redundancy.vaddr.addr;
assign isol_data_o     = mem_isol_shadow_q.redundancy.data;
assign isol_bm_o       = mem_isol_shadow_q.redundancy.bm;
assign isol_bist_en_o  = mem_isol_shadow_q.bist_en;
assign isol_men_o      = mem_isol_shadow_q.men;
assign isol_wen_o      = mem_isol_shadow_q.wen;
assign isol_ren_o      = mem_isol_shadow_q.ren;

assign bypass_addr_o  = bypass_addr;
assign bypass_data_o  = bypass_data;
assign bypass_bm_o    = bypass_bm  ;
assign bypass_men_o   = bypass_men ;
assign bypass_wen_o   = bypass_wen ;
assign bypass_ren_o   = bypass_ren ;

assign repair_rdata_o = repair_rdata;
endmodule