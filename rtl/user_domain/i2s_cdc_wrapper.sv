`include "common_cells/assertions.svh"

module i2s_cdc_wrapper #(
    parameter int CLK_DIV_FACTOR = 16,
    parameter int FRAME_SIZE     = 320
    )(
    input   logic   clk_sys_i,
    input   logic   rst_sys_ni,

    //connection to Microphone
    output  logic   i2s_sclk_o,
    output  logic   i2s_wsel_o,
    input   logic   i2s_sdat_i,

    //vad datapath
    output  logic               vad_wakeup_o,
    output  logic               active_read_bank_o,
    input   logic [$clog2(FRAME_SIZE)-1:0] vad_read_addr_i,
    output  logic [15:0]                 vad_read_data_o,

    // Observability: SRAM debug access (see ping_pong_buffer)
    input   logic        dbg_en_i,
    input   logic        dbg_bank_i,
    input   logic [8:0]  dbg_addr_i,
    input   logic [15:0] dbg_wdata_i,
    input   logic        dbg_we_i,
    input   logic        dbg_re_i,
    input   logic        dbg_kick_i,
    output  logic [15:0] dbg_rdata_o,
    output  logic        write_bank_o,
    output  logic [$clog2(FRAME_SIZE)-1:0] write_addr_o,

    // MBIST of the two frame SRAMs, index 0 = bank 0, 1 = bank 1 (see vad_frame_sram)
    input   logic [1:0]       mbist_start_i,
    input   logic [1:0]       mbist_resume_i,
    input   logic [1:0]       mbist_erraddrread_i,
    output  logic [1:0][3:0]  mbist_status_o,
    output  logic [1:0][8:0]  mbist_erraddr_o
);

typedef logic [$clog2(CLK_DIV_FACTOR)-1:0] div_count_t;
div_count_t div_counter;
logic slow_audio_clk;

//reducing the clock frequency
always_ff @( posedge clk_sys_i or negedge rst_sys_ni ) begin
    if (!rst_sys_ni) begin
        div_counter <= '0;
        slow_audio_clk <= 1'b0;
    end else begin
        if (div_counter == div_count_t'((CLK_DIV_FACTOR / 2) - 1)) begin
            slow_audio_clk <= ~slow_audio_clk;
            div_counter <= '0;
        end else begin
            div_counter <= div_counter + div_count_t'(1);
        end
    end
    
end

logic current_channel;

//Reset inversion
logic rst_sys_high;
assign rst_sys_high = ~rst_sys_ni;

//Connection I2s -> FIFO
logic [15:0] raw_audio_data;
logic        raw_audio_valid;

//Connection FIFO -> Ping-Pong Buffer
logic [15:0] fifo_audio_data;
logic        fifo_audio_valid;

//instatiate i2s receiver

i2s_top_rx u_i2s_rx(
    .clk_i      (slow_audio_clk),
    .rst_i     (rst_sys_high),
    .data_o     (raw_audio_data),
    .lr_chnl_o  (current_channel),
    .write_o    (raw_audio_valid),
    .sclk_o     (i2s_sclk_o),
    .wsel_o     (i2s_wsel_o),
    .sdat_i     (i2s_sdat_i)
);

logic left_channel_valid;
assign left_channel_valid = raw_audio_valid & (current_channel == 1'b0);

//instatiating the fifo
cdc_fifo_gray #(
    .T(logic [15:0]),
    .LOG_DEPTH(2)
) u_cdc_fifo(
    //write side
    .src_clk_i  (slow_audio_clk),
    .src_rst_ni (rst_sys_ni),
    .src_data_i (raw_audio_data),
    .src_valid_i (left_channel_valid),
    .src_ready_o (),

    //Read Side
    .dst_clk_i  (clk_sys_i),
    .dst_rst_ni (rst_sys_ni),
    .dst_data_o (fifo_audio_data),
    .dst_valid_o (fifo_audio_valid),
    .dst_ready_i (1'b1)
);

ping_pong_buffer #(
    .FRAME_SIZE(FRAME_SIZE),
    .WORD_WIDTH(16)
) u_ping_pong(
    .clk_sys_i      (clk_sys_i),
    .rst_sys_ni     (rst_sys_ni),

    .audio_data_i   (fifo_audio_data),
    .audio_valid_i  (fifo_audio_valid),

    .vad_wakeup_o   (vad_wakeup_o),
    .active_read_bank_o (active_read_bank_o),
    .vad_read_addr_i (vad_read_addr_i),
    .vad_read_data_o (vad_read_data_o),

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
`ASSERT_INIT(ClockDivisor, CLK_DIV_FACTOR >= 4 && (CLK_DIV_FACTOR % 2) == 0,
             "CLK_DIV_FACTOR must be even and at least four")

endmodule
