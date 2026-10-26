// Physical frame storage: one sample occupies the low half of a 32-bit SRAM word.
// Reads are registered by the macro. SRAM contents have no reset or initialization.
module vad_frame_sram (
    input  logic        clk_i,
    input  logic        mem_enable_i,
    input  logic        write_enable_i,
    input  logic        read_enable_i,
    input  logic [8:0]  addr_i,
    input  logic [15:0] data_i,
    output logic [15:0] data_o
);

logic [31:0] macro_data;

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
    .A_BIST_CLK  (1'b0),
    .A_BIST_EN   (1'b0),
    .A_BIST_MEN  (1'b0),
    .A_BIST_WEN  (1'b0),
    .A_BIST_REN  (1'b0),
    .A_BIST_ADDR (9'b0),
    .A_BIST_DIN  (32'b0),
    .A_BIST_BM   (32'b0)
);

assign data_o = macro_data[15:0];

endmodule
