`include "common_cells/assertions.svh"

module ping_pong_buffer #(
    parameter int FRAME_SIZE = 320,
    parameter int WORD_WIDTH = 16
)(
    input   logic                  clk_sys_i,
    input   logic                  rst_sys_ni,
    input   logic [WORD_WIDTH-1:0] audio_data_i,
    input   logic                  audio_valid_i,
    output  logic                  vad_wakeup_o,
    output  logic                  active_read_bank_o,
    input   logic [$clog2(FRAME_SIZE)-1:0] vad_read_addr_i,
    output  logic [WORD_WIDTH-1:0]         vad_read_data_o,

    // Observability: CPU debug access to the frame SRAMs
    input   logic                  dbg_en_i,
    input   logic                  dbg_bank_i,
    input   logic [8:0]            dbg_addr_i,
    input   logic [WORD_WIDTH-1:0] dbg_wdata_i,
    input   logic                  dbg_we_i,
    input   logic                  dbg_re_i,
    input   logic                  dbg_kick_i,
    output  logic [WORD_WIDTH-1:0] dbg_rdata_o,

    // Observability: audio writer state for SRAM_STATUS
    output  logic                  write_bank_o,
    output  logic [$clog2(FRAME_SIZE)-1:0] write_addr_o,

    // MBIST of the two frame SRAMs, index 0 = bank 0, 1 = bank 1 (see vad_frame_sram)
    input   logic [1:0]       mbist_start_i,
    input   logic [1:0]       mbist_resume_i,
    input   logic [1:0]       mbist_erraddrread_i,
    output  logic [1:0][3:0]  mbist_status_o,
    output  logic [1:0][8:0]  mbist_erraddr_o
);

typedef logic [$clog2(FRAME_SIZE)-1:0] frame_addr_t;

frame_addr_t write_addr;
logic write_bank;
logic read_bank_q;
logic read_bank_valid_q;

logic bank_0_write, bank_1_write;
logic bank_0_read, bank_1_read;
logic [8:0] bank_0_addr, bank_1_addr;
logic [15:0] bank_0_data, bank_1_data;

// Observability: debug-mode SRAM access
logic audio_write;
logic cpu_access;
logic [WORD_WIDTH-1:0] bank_wdata;

// There is no ownership handshake. Production samples must be separated by at
// least four system cycles so the core finishes a frame before the next wakeup.
// A bank becomes readable only after its final sample has been written.
assign audio_write = rst_sys_ni && audio_valid_i && !dbg_en_i;
assign cpu_access  = dbg_en_i && (dbg_we_i || dbg_re_i);

// Observability: SRAM port mux, CPU in debug mode
always_comb begin
    if (dbg_en_i) begin
        bank_0_write = rst_sys_ni && dbg_we_i && (dbg_bank_i == 1'b0);
        bank_1_write = rst_sys_ni && dbg_we_i && (dbg_bank_i == 1'b1);
        bank_0_read  = rst_sys_ni && !dbg_we_i && (dbg_bank_i == 1'b0);
        bank_1_read  = rst_sys_ni && !dbg_we_i && (dbg_bank_i == 1'b1);
        bank_0_addr  = cpu_access ? dbg_addr_i : 9'(vad_read_addr_i);
        bank_1_addr  = cpu_access ? dbg_addr_i : 9'(vad_read_addr_i);
        bank_wdata   = dbg_wdata_i;
    end else begin
        bank_0_write = audio_write && (write_bank == 1'b0);
        bank_1_write = audio_write && (write_bank == 1'b1);
        bank_0_read  = rst_sys_ni && read_bank_valid_q &&
                       (read_bank_q == 1'b0) && (write_bank != read_bank_q);
        bank_1_read  = rst_sys_ni && read_bank_valid_q &&
                       (read_bank_q == 1'b1) && (write_bank != read_bank_q);
        bank_0_addr  = (write_bank == 1'b0) ? 9'(write_addr) : 9'(vad_read_addr_i);
        bank_1_addr  = (write_bank == 1'b1) ? 9'(write_addr) : 9'(vad_read_addr_i);
        bank_wdata   = audio_data_i;
    end
end

// Both macros use the system clock directly; MEN qualifies every memory access.
vad_frame_sram u_bank_0 (
    .clk_i          (clk_sys_i),
    .rst_ni         (rst_sys_ni),
    .mem_enable_i   (bank_0_write || bank_0_read),
    .write_enable_i (bank_0_write),
    .read_enable_i  (bank_0_read),
    .addr_i         (bank_0_addr),
    .data_i         (bank_wdata),
    .data_o         (bank_0_data),

    .mbist_start_i       (mbist_start_i[0]),
    .mbist_resume_i      (mbist_resume_i[0]),
    .mbist_erraddrread_i (mbist_erraddrread_i[0]),
    .mbist_status_o      (mbist_status_o[0]),
    .mbist_erraddr_o     (mbist_erraddr_o[0])
);

vad_frame_sram u_bank_1 (
    .clk_i          (clk_sys_i),
    .rst_ni         (rst_sys_ni),
    .mem_enable_i   (bank_1_write || bank_1_read),
    .write_enable_i (bank_1_write),
    .read_enable_i  (bank_1_read),
    .addr_i         (bank_1_addr),
    .data_i         (bank_wdata),
    .data_o         (bank_1_data),

    .mbist_start_i       (mbist_start_i[1]),
    .mbist_resume_i      (mbist_resume_i[1]),
    .mbist_erraddrread_i (mbist_erraddrread_i[1]),
    .mbist_status_o      (mbist_status_o[1]),
    .mbist_erraddr_o     (mbist_erraddr_o[1])
);

always_ff @(posedge clk_sys_i or negedge rst_sys_ni) begin
    if (!rst_sys_ni) begin
        write_addr        <= '0;
        write_bank        <= 1'b0;
        read_bank_q       <= 1'b1;
        read_bank_valid_q <= 1'b0;
        vad_wakeup_o      <= 1'b0;
    end else begin
        // Observability: KICK
        vad_wakeup_o <= dbg_en_i && dbg_kick_i;
        if (audio_valid_i && !dbg_en_i) begin
            if (write_addr == frame_addr_t'(FRAME_SIZE - 1)) begin
                read_bank_q       <= write_bank;
                read_bank_valid_q <= 1'b1;
                write_bank        <= ~write_bank;
                write_addr        <= '0;
                vad_wakeup_o      <= 1'b1;
            end else begin
                write_addr <= write_addr + frame_addr_t'(1);
            end
        end
    end
end

assign active_read_bank_o = read_bank_q;
// Observability: in debug mode the core reads the CPU-selected bank
assign vad_read_data_o = (dbg_en_i ? dbg_bank_i : read_bank_q) ? bank_1_data : bank_0_data;

// Observability: debug read data and audio writer state
assign dbg_rdata_o  = dbg_bank_i ? bank_1_data : bank_0_data;
assign write_bank_o = write_bank;
assign write_addr_o = write_addr;

`ASSERT_INIT(FrameSize, FRAME_SIZE >= 2 && FRAME_SIZE <= 512,
             "FRAME_SIZE must be between 2 and 512 samples")
`ASSERT_INIT(WordWidth, WORD_WIDTH == 16, "The frame SRAM supports 16-bit samples")

endmodule
