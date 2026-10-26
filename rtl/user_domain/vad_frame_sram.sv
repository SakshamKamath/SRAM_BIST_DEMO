// Physical frame storage: one sample occupies the low half of a 32-bit SRAM word.
// Reads are registered by the macro. SRAM contents have no reset or initialization.
//
// Each macro has its own March BIST controller (as in tc_sram_impl_mod.sv), driving the
// macro's BIST port. While the controller runs, the macro ignores the functional port.
// The march tests all 32 bits and leaves the macro all zeros.
module vad_frame_sram (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        mem_enable_i,
    input  logic        write_enable_i,
    input  logic        read_enable_i,
    input  logic [8:0]  addr_i,
    input  logic [15:0] data_i,
    output logic [15:0] data_o,

    // MBIST control and status (from/to soc_ctrl_regs)
    input  logic        mbist_start_i,
    input  logic        mbist_resume_i,
    input  logic        mbist_erraddrread_i,
    output logic [3:0]  mbist_status_o,     // {pause, fail, busy, done}
    output logic [8:0]  mbist_erraddr_o     // head of the error-address FIFO
);

localparam int unsigned DataWidth = 32;
localparam int unsigned AddrWidth = 9;
localparam int unsigned FifoDepth = 2;      // 2**FifoDepth error entries, as for the croc banks

logic [DataWidth-1:0] macro_data;

// Signals driven by the march controller
logic [AddrWidth-1:0] march_addr;
logic [DataWidth-1:0] march_wdata;
logic [DataWidth-1:0] march_bitmask;
logic                 march_memen;
logic                 march_memwen;
logic                 march_memren;
logic                 march_bisten;

march_bist_controller #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .FifoDepth (FifoDepth)
) u_bist_controller (
    .tclk_i            (clk_i),
    .trst_ni           (rst_ni),
    .start_i           (mbist_start_i),
    .resume_or_reset_i (mbist_resume_i),
    .erraddr_rd_i      (mbist_erraddrread_i),
    .status_o          (mbist_status_o),
    .bist_en_o         (march_bisten),
    .rdata_i           (macro_data),
    .memaddr_o         (march_addr),
    .wdata_o           (march_wdata),
    .memen_o           (march_memen),
    .memren_o          (march_memren),
    .memwen_o          (march_memwen),
    .membm_o           (march_bitmask),
    .mbist_erraddr_o   (mbist_erraddr_o)
);

RM_IHPSG13_1P_512x32_c2_bm_bist u_frame_sram (
    .A_CLK       (clk_i),
    .A_MEN       (mem_enable_i),
    .A_WEN       (write_enable_i),
    .A_REN       (read_enable_i),
    .A_ADDR      (addr_i),
    .A_DIN       ({16'b0, data_i}),
    .A_DLY       (1'b0),
    .A_DOUT      (macro_data),
    .A_BM        (32'h0000ffff),
    .A_BIST_CLK  (clk_i),
    .A_BIST_EN   (march_bisten),
    .A_BIST_MEN  (march_memen),
    .A_BIST_WEN  (march_memwen),
    .A_BIST_REN  (march_memren),
    .A_BIST_ADDR (march_addr),
    .A_BIST_DIN  (march_wdata),
    .A_BIST_BM   (march_bitmask)
);

assign data_o = macro_data[15:0];

endmodule
