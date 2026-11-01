// Blackbox views of SRAM macros that have no Liberty file in ../technology/lib.
// Loaded by scripts/init_tech.tcl so read_slang can instantiate them as cells.
// Ports copied from ../technology/verilog/<macro>.v.

// VAD frame buffer (rtl/user_domain/vad_frame_sram.sv)
(* blackbox *)
module RM_IHPSG13_1P_512x32_c2_bm_bist (
    input         A_CLK,
    input         A_MEN,
    input         A_WEN,
    input         A_REN,
    input  [8:0]  A_ADDR,
    input  [31:0] A_DIN,
    input         A_DLY,
    output [31:0] A_DOUT,
    input  [31:0] A_BM,
    input         A_BIST_CLK,
    input         A_BIST_EN,
    input         A_BIST_MEN,
    input         A_BIST_WEN,
    input         A_BIST_REN,
    input  [8:0]  A_BIST_ADDR,
    input  [31:0] A_BIST_DIN,
    input  [31:0] A_BIST_BM
);
endmodule
