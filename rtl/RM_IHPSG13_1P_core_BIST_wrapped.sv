module RM_IHPSG13_1P_core_BIST_wrapped #(
    parameter P_DATA_WIDTH    = 24,
    parameter P_ADDR_WIDTH    = 8,
    parameter P_IR_WIDTH      = 4,
    parameter P_IDCODE_WIDTH  = 32,
    parameter P_FIFO_DEPTH    = 2,
    parameter IDCODE_VAL      = 32'h1080_0786
)
    (
        input  [P_ADDR_WIDTH-1:0] A_ADDR,
        input  [P_DATA_WIDTH-1:0] A_DIN,
        input  [P_DATA_WIDTH-1:0] A_BM,
        input                     A_MEN,
        input                     A_WEN,
        input                     A_REN,
        input                     A_CLK,
        input                     A_DLY,
        output [P_DATA_WIDTH-1:0] A_DOUT,


        input                     TEST_TDI,
        input                     TEST_TCLK,
        input                     TEST_TRSTNI,
        input                     TEST_TMS,
        output                    TEST_TDO

    );


// Signals required for connecting
logic mbist_start, mbist_erraddr_read;

// Signals driven by march controller
logic [P_ADDR_WIDTH-1:0] march_addr;
logic [P_DATA_WIDTH-1:0] march_wdata;
logic [P_DATA_WIDTH-1:0] march_bitmask;
logic                    march_memen;
logic                    march_memwen;
logic                    march_memren;
logic                    march_busy;
logic                    march_fail;
logic                    march_done;
logic [P_ADDR_WIDTH-1:0] mbist_erraddr;



// Buffering for signal renaming and better understanding
logic [P_DATA_WIDTH-1:0] march_rdata;
assign march_rdata = A_DOUT;



jtag_tap_top #(
    .P_IR_WIDTH(P_IR_WIDTH),
    .P_IDCODE_WIDTH(P_IDCODE_WIDTH),
    .P_ADDR_WIDTH(P_ADDR_WIDTH+1),
    .IDCODE_VAL(IDCODE_VAL)
) i_jtag_tap_top (
    .tclk_i                (TEST_TCLK),
    .tms_i                 (TEST_TMS),
    .trst_ni               (TEST_TRSTNI),
    .tdi_i                 (TEST_TDI),
    .mbist_erraddr_i       (mbist_erraddr),
    .mbist_status_i        (march_done),
    .mbist_fifo_notempty_i (march_fail),
    .tdo_o                 (TEST_TDO),
    .tdo_en_o              (),
    .mbist_start_o         (mbist_start),
    .mbist_erraddr_read_o  (mbist_erraddr_read)
);


  march_bist_controller #(
      .P_DATA_WIDTH(P_DATA_WIDTH),
      .P_ADDR_WIDTH(P_ADDR_WIDTH),
      .P_FIFO_DEPTH(P_FIFO_DEPTH)
  ) u_bist_controller (
      .tdi_i            (TEST_TDI),
      .tms_i            (TEST_TMS),
      .tclk_i           (TEST_TCLK),
      .trst_ni          (TEST_TRSTNI),
      .tdo_o            (),
      .start_i          (mbist_start),
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

  // Localparam definitions matched to P_DATA_WIDTH (32-bit) and P_ADDR_WIDTH (1024 depth)
  localparam [P_DATA_WIDTH-1:0] MY_SAF_1 [0:(1<<P_ADDR_WIDTH)-1] = '{
      10'd2   : 32'h0000_0001, // Bit 0 stuck at 1 at Address 2 (0x02)
      default : 32'h0000_0000
  };

  localparam [P_DATA_WIDTH-1:0] MY_TF_01 [0:(1<<P_ADDR_WIDTH)-1] = '{
      10'd8   : 32'h0000_000F, // Bits [3:0] fail 0->1 transition at Address 8
      default : 32'h0000_0000
  };

  localparam [P_DATA_WIDTH-1:0] MY_RDF [0:(1<<P_ADDR_WIDTH)-1] = '{
      10'd6   : 32'h0000_8000, // Bit 31 has RDF at Address 6
      default : 32'h0000_0000
  };
  
// -----------------------------------------------------------------------------------


 SRAM_1P_behavioral_bm_bist #(
      .P_DATA_WIDTH      (P_DATA_WIDTH),
      .P_ADDR_WIDTH      (P_ADDR_WIDTH),
      .EN_FAULT_INJECTION(1'b1),         // Master Fault Switch ON
      .MASK_SAF_1        (MY_SAF_1),
      .MASK_TF_01        (MY_TF_01),
      .MASK_RDF          (MY_RDF)
  ) u_sram_mem (
      .A_ADDR    (A_ADDR),
      .A_DIN     (A_DIN),
      .A_BM      (A_BM),
      .A_MEN     (A_MEN),
      .A_WEN     (A_WEN),
      .A_REN     (A_REN),
      .A_CLK     (A_CLK),
      .A_DLY     (1'b0),
      .A_DOUT    (A_DOUT),

      .A_BIST_EN  (march_busy),
      .A_BIST_ADDR(march_addr),
      .A_BIST_DIN (march_wdata),
      .A_BIST_BM  (march_bitmask),
      .A_BIST_MEN (march_memen),
      .A_BIST_WEN (march_memwen),
      .A_BIST_REN (march_memren),
      .A_BIST_CLK (TEST_TCLK)
  );





endmodule