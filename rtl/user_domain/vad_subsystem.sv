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

    output  logic       speech_detected_o,

    // Observability: last frame result (see vad_core)
    input   logic        last_energy_lo_we_i,
    input   logic        last_energy_hi_we_i,
    input   logic        last_zcr_we_i,
    input   logic [31:0] last_wdata_i,
    input   logic        eval_i,
    output  logic [47:0] last_energy_o,
    output  logic [15:0] last_zcr_o,

    // Observability: SRAM debug access (see ping_pong_buffer)
    input   logic        dbg_en_i,
    input   logic        dbg_bank_i,
    input   logic [8:0]  dbg_addr_i,
    input   logic [15:0] dbg_wdata_i,
    input   logic        dbg_we_i,
    input   logic        dbg_re_i,
    input   logic        dbg_kick_i,
    output  logic [15:0] dbg_rdata_o,
    output  logic        read_bank_o,
    output  logic        write_bank_o,
    output  logic [$clog2(FRAME_SIZE)-1:0] write_addr_o,

    // MBIST of the two frame SRAMs, index 0 = bank 0, 1 = bank 1 (see vad_frame_sram)
    input   logic [1:0]       mbist_start_i,
    input   logic [1:0]       mbist_resume_i,
    input   logic [1:0]       mbist_erraddrread_i,
    output  logic [1:0][3:0]  mbist_status_o,
    output  logic [1:0][8:0]  mbist_erraddr_o
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
    .active_read_bank_o (read_bank_o),
    .vad_read_addr_i (sram_addr),
    .vad_read_data_o (sram_data),

    .dbg_en_i       (dbg_en_i),
    .dbg_bank_i     (dbg_bank_i),
    .dbg_addr_i     (dbg_addr_i),
    .dbg_wdata_i    (dbg_wdata_i),
    .dbg_we_i       (dbg_we_i),
    .dbg_re_i       (dbg_re_i),
    .dbg_kick_i     (dbg_kick_i),
    .dbg_rdata_o    (dbg_rdata_o),
    .write_bank_o   (write_bank_o),
    .write_addr_o   (write_addr_o),
    .mbist_start_i       (mbist_start_i),
    .mbist_resume_i      (mbist_resume_i),
    .mbist_erraddrread_i (mbist_erraddrread_i),
    .mbist_status_o      (mbist_status_o),
    .mbist_erraddr_o     (mbist_erraddr_o)
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

    .speech_detected_o (speech_detected_o),

    .last_energy_lo_we_i (last_energy_lo_we_i),
    .last_energy_hi_we_i (last_energy_hi_we_i),
    .last_zcr_we_i       (last_zcr_we_i),
    .last_wdata_i        (last_wdata_i),
    .eval_i              (eval_i),
    .last_energy_o       (last_energy_o),
    .last_zcr_o          (last_zcr_o)
);



endmodule
