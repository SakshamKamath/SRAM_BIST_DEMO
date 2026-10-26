module RM_IHPSG13_1P_core_BIST_wrapped #(
    parameter DataWidth    = 24,
    parameter AddrWidth    = 8,
    parameter IrWidth      = 4,
    parameter IdcodeWidth  = 32,
    parameter FifoDepth    = 2,
    parameter IdcodeValue  = 32'h1080_0786
)
    (
        input  [AddrWidth-1:0] A_ADDR,
        input  [DataWidth-1:0] A_DIN,
        input  [DataWidth-1:0] A_BM,
        input                     A_MEN,
        input                     A_WEN,
        input                     A_REN,
        input                     A_CLK,
        input                     A_DLY,
        output [DataWidth-1:0] A_DOUT,


        input                     TEST_TDI,
        input                     TEST_TCLK,
        input                     TEST_TRSTNI,
        input                     TEST_TMS,
        output                    TEST_TDO

    );


// Signals required for connecting
logic mbist_start, mbist_erraddr_read, march_resume_or_reset;

// Signals driven by march controller
logic [AddrWidth-1:0] march_addr;
logic [DataWidth-1:0] march_wdata;
logic [DataWidth-1:0] march_bitmask;
logic                 march_memen;
logic                 march_memwen;
logic                 march_memren;
logic                 march_busy;
logic                 march_fail;
logic                 march_done;
logic [AddrWidth-1:0] mbist_erraddr;

// Isolation Signals
logic [AddrWidth-1:0] isol_addr;
logic [DataWidth-1:0] isol_wdata;
logic                 isol_bist_en;
logic [DataWidth-1:0] isol_bitmask;
logic                 isol_memen;
logic                 isol_memwen;
logic                 isol_memren;

//Bypass or Repair signals
logic [AddrWidth-1:0] bypass_addr;
logic [DataWidth-1:0] bypass_data;
logic [DataWidth-1:0] bypass_bm  ;
logic                 bypass_men ;
logic                 bypass_wen ;
logic                 bypass_ren ;


// Buffering for signal renaming and better understanding
logic [DataWidth-1:0] march_rdata;
assign march_rdata = A_DOUT;



jtag_tap_top #(
    .IrWidth(IrWidth),
    .IdcodeWidth(IdcodeWidth),
    .AddrWidth(AddrWidth),
    .DataWidth(DataWidth),
    .IdcodeValue(IdcodeValue)
) i_jtag_tap_top (
    .tclk_i                (TEST_TCLK),
    .tms_i                 (TEST_TMS),
    .trst_ni               (TEST_TRSTNI),
    .tdi_i                 (TEST_TDI),
    .mbist_erraddr_i       (mbist_erraddr),
    .mbist_status_i        (march_done),
    .mbist_fifo_notempty_i (march_fail),
    .mem_rdata_i           (rdata),
    .repair_addr_i         (A_ADDR),
    .repair_men_i          (A_MEN ),
    .repair_wen_i          (A_WEN ),
    .repair_ren_i          (A_REN ),
    .repair_bm_i           (A_BM  ),
    .repair_wdata_i        (A_DIN ),
    .tdo_o                 (TEST_TDO),
    .tdo_en_o              (),
    .mbist_start_o         (mbist_start),
    .mbist_resume_o        (march_resume_or_reset),
    .mbist_erraddr_read_o  (mbist_erraddr_read),
    .isol_addr_o           (isol_addr),
    .isol_data_o           (isol_wdata),
    .isol_bm_o             (isol_bitmask),
    .isol_bist_en_o        (isol_bist_en),
    .isol_men_o            (isol_memen),
    .isol_wen_o            (isol_memwen),
    .isol_ren_o            (isol_memren),
    .repair_rdata_o        (A_DOUT),
    .bypass_addr_o         (bypass_addr),
    .bypass_data_o         (bypass_data),
    .bypass_bm_o           (bypass_bm),
    .bypass_men_o          (bypass_men),
    .bypass_wen_o          (bypass_wen),
    .bypass_ren_o          (bypass_ren)
);


  march_bist_controller #(
      .DataWidth(DataWidth),
      .AddrWidth(AddrWidth),
      .FifoDepth(FifoDepth)
  ) u_bist_controller (
      .tdi_i            (TEST_TDI),
      .tms_i            (TEST_TMS),
      .tclk_i           (TEST_TCLK),
      .trst_ni          (TEST_TRSTNI),
      .tdo_o            (),
      .start_i          (mbist_start),
      .resume_or_reset_i(march_resume_or_reset),
      .erraddr_rd_i     (mbist_erraddr_read),
      .busy_o           (march_busy),
      .done_o           (march_done),
      .fail_o           (march_fail),
      .rdata_i          (march_rdata),
      .memaddr_o        (march_addr),
      .wdata_o          (march_wdata),
      .membm_o          (march_bitmask),   
      .memen_o          (march_memen),
      .memren_o         (march_memren),
      .memwen_o         (march_memwen),
      .mbist_erraddr_o  (mbist_erraddr)
  );


//------------------------------ Only for Testing -------------------------------------

  // Localparam definitions matched to DataWidth (32-bit) and AddrWidth (1024 depth)
  localparam [DataWidth-1:0] MY_SAF_1 [0:(1<<AddrWidth)-1] = '{
      10'd2   : 32'h0000_0001, // Bit 0 stuck at 1 at Address 2 (0x02)
      default : 32'h0000_0000
  };

  localparam [DataWidth-1:0] MY_TF_01 [0:(1<<AddrWidth)-1] = '{
      10'd8   : 32'h0000_000F, // Bits [3:0] fail 0->1 transition at Address 8
      default : 32'h0000_0000
  };

  localparam [DataWidth-1:0] MY_RDF [0:(1<<AddrWidth)-1] = '{
      10'd6   : 32'h0000_8000, // Bit 31 has RDF at Address 6
      default : 32'h0000_0000
  };
  
// -----------------------------------------------------------------------------------

logic [DataWidth-1:0] rdata;

// Muxed BIST signals that will actually drive the SRAM instance
logic [AddrWidth-1:0] bist_mux_addr;
logic [DataWidth-1:0] bist_mux_wdata;
logic [DataWidth-1:0] bist_mux_bitmask;
logic                 bist_mux_memen;
logic                 bist_mux_memwen;
logic                 bist_mux_memren;


// If isol_bist_en is active, route JTAG isolation signals to SRAM.
// Otherwise, route March BIST Controller signals to SRAM.
assign bist_mux_addr    = (isol_bist_en) ? isol_addr    : march_addr;
assign bist_mux_wdata   = (isol_bist_en) ? isol_wdata   : march_wdata;
assign bist_mux_bitmask = (isol_bist_en) ? isol_bitmask : march_bitmask;
assign bist_mux_memen   = (isol_bist_en) ? isol_memen   : march_memen;
assign bist_mux_memwen  = (isol_bist_en) ? isol_memwen  : march_memwen;
assign bist_mux_memren  = (isol_bist_en) ? isol_memren  : march_memren;




 SRAM_1P_behavioral_bm_bist #(
      .DataWidth         (DataWidth),
      .AddrWidth         (AddrWidth),
      .EN_FAULT_INJECTION(1'b1),         // Master Fault Switch ON
      .MASK_SAF_1        (MY_SAF_1),
      .MASK_TF_01        (MY_TF_01),
      .MASK_RDF          (MY_RDF)
  ) u_sram_mem (
      .A_ADDR    (bypass_addr),
      .A_DIN     (bypass_data),
      .A_BM      (bypass_bm  ),
      .A_MEN     (bypass_men ),
      .A_WEN     (bypass_wen ),
      .A_REN     (bypass_ren ),
      .A_CLK     (A_CLK),
      .A_DLY     (1'b0),
      .A_DOUT    (rdata),

      .A_BIST_EN  (march_busy | isol_bist_en),
      .A_BIST_ADDR(bist_mux_addr),
      .A_BIST_DIN (bist_mux_wdata),
      .A_BIST_BM  (bist_mux_bitmask),
      .A_BIST_MEN (bist_mux_memen),
      .A_BIST_WEN (bist_mux_memwen),
      .A_BIST_REN (bist_mux_memren),
      .A_BIST_CLK (TEST_TCLK)
  );





endmodule