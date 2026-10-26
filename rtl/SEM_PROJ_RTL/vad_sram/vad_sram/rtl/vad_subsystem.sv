module vad_subsystem #(
    parameter int CLK_DIV_FACTOR = 16,
    parameter int FRAME_SIZE     = 320
    //parameter logic [31:0]  ENERGY_THRESHOLD = 32'd30_000,
    //parameter logic [15:0]  ZCR_THRESHOLD    = 16'd150

)(
    input   logic       clk_sys_i,
    input   logic       rst_sys_ni,

    input   logic       vad_enable_i,
    input   logic [31:0] energy_threshold_i,
    input   logic [15:0] zcr_threshold_i,

    output  logic       i2s_sclk_o,
    output  logic       i2s_wsel_o,
    input   logic       i2s_sdat_i,

    output  logic       speech_detected_o
);

logic                          vad_wakeup;
logic [$clog2(FRAME_SIZE)-1:0] sram_addr;
logic [15:0]                   sram_data;

i2s_cdc_wrapper #(
    .CLK_DIV_FACTOR (CLK_DIV_FACTOR),
    .FRAME_SIZE     (FRAME_SIZE)
) u_i2s_ingestion (
    .clk_sys_i      (clk_sys_i),
    .rst_sys_ni     (rst_sys_ni),

    .i2s_sclk_o     (i2s_sclk_o),
    .i2s_wsel_o     (i2s_wsel_o),
    .i2s_sdat_i     (i2s_sdat_i),

    .vad_wakeup_o   (vad_wakeup),
    .active_read_bank_o (),
    .vad_read_addr_i (sram_addr),
    .vad_read_data_o (sram_data)
);

vad_core #(
    .FRAME_SIZE         (FRAME_SIZE)
    //.ENERGY_THRESHOLD   (ENERGY_THRESHOLD),
    //.ZCR_THRESHOLD      (ZCR_THRESHOLD)
) u_vad_dsp(
    .clk_sys_i      (clk_sys_i),
    .rst_sys_ni     (rst_sys_ni),

    .vad_enable_i   (vad_enable_i),
    .energy_threshold_i (energy_threshold_i),
    .zcr_threshold_i    (zcr_threshold_i),

    .vad_wakeup_i   (vad_wakeup),
    .sram_addr_o    (sram_addr),
    .sram_data_i    (sram_data),

    .speech_detected_o (speech_detected_o)
);



endmodule
