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
    output  logic [WORD_WIDTH-1:0]         vad_read_data_o
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

// There is no ownership handshake. Production samples must be separated by at
// least four system cycles so the core finishes a frame before the next wakeup.
// A bank becomes readable only after its final sample has been written.
assign bank_0_write = rst_sys_ni && audio_valid_i && (write_bank == 1'b0);
assign bank_1_write = rst_sys_ni && audio_valid_i && (write_bank == 1'b1);
assign bank_0_read = rst_sys_ni && read_bank_valid_q &&
                     (read_bank_q == 1'b0) && (write_bank != read_bank_q);
assign bank_1_read = rst_sys_ni && read_bank_valid_q &&
                     (read_bank_q == 1'b1) && (write_bank != read_bank_q);
assign bank_0_addr = (write_bank == 1'b0) ? 9'(write_addr) : 9'(vad_read_addr_i);
assign bank_1_addr = (write_bank == 1'b1) ? 9'(write_addr) : 9'(vad_read_addr_i);

// Both macros use the system clock directly; MEN qualifies every memory access.
vad_frame_sram u_bank_0 (
    .clk_i          (clk_sys_i),
    .mem_enable_i   (bank_0_write || bank_0_read),
    .write_enable_i (bank_0_write),
    .read_enable_i  (bank_0_read),
    .addr_i         (bank_0_addr),
    .data_i         (audio_data_i),
    .data_o         (bank_0_data)
);

vad_frame_sram u_bank_1 (
    .clk_i          (clk_sys_i),
    .mem_enable_i   (bank_1_write || bank_1_read),
    .write_enable_i (bank_1_write),
    .read_enable_i  (bank_1_read),
    .addr_i         (bank_1_addr),
    .data_i         (audio_data_i),
    .data_o         (bank_1_data)
);

always_ff @(posedge clk_sys_i or negedge rst_sys_ni) begin
    if (!rst_sys_ni) begin
        write_addr        <= '0;
        write_bank        <= 1'b0;
        read_bank_q       <= 1'b1;
        read_bank_valid_q <= 1'b0;
        vad_wakeup_o      <= 1'b0;
    end else begin
        vad_wakeup_o <= 1'b0;
        if (audio_valid_i) begin
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
assign vad_read_data_o = read_bank_q ? bank_1_data : bank_0_data;

`ASSERT_INIT(FrameSize, FRAME_SIZE >= 2 && FRAME_SIZE <= 512,
             "FRAME_SIZE must be between 2 and 512 samples")
`ASSERT_INIT(WordWidth, WORD_WIDTH == 16, "The frame SRAM supports 16-bit samples")

endmodule
