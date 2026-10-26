`include "common_cells/assertions.svh"

module vad_core #(
    parameter int FRAME_SIZE = 320
    //parameter logic [31:0] ENERGY_THRESHOLD = 32'd22_317_440, // Scaled Python threshold
    //parameter logic [15:0] ZCR_THRESHOLD = 16'd20 // Set to 40 to allow for consonants
)(
    input logic        clk_sys_i,
    input logic        rst_sys_ni,

    input logic        vad_wakeup_i,

    output logic [$clog2(FRAME_SIZE)-1:0] sram_addr_o,
    input  logic [15:0]                   sram_data_i, 

    output logic        speech_detected_o,

    input logic vad_enable_i,

    input logic [31:0] energy_threshold_i, 
    input logic [15:0] zcr_threshold_i
);

typedef enum logic [1:0] {  
    IDLE,
    READ_WAIT,
    PROCESS,
    DECIDE
} state_e;

state_e state_q, state_d;

typedef logic [$clog2(FRAME_SIZE)-1:0] frame_addr_t;

frame_addr_t addr_q, addr_d;
logic [47:0] energy_acc_q, energy_acc_d;
logic [15:0] zcr_acc_q, zcr_acc_d;
logic        prev_sign_q, prev_sign_d;

logic signed [15:0] current_sample;
logic signed [31:0] squared_sample;
logic signed [31:0] sample_32;

// --- THE FIX ---
// The I2S wrapper has a 1-bit alignment error. 
// Bit 15 is random noise, and the TRUE sign bit is at Bit 14.
// We reconstruct the true sample by duplicating the true sign bit 
// and dropping the noise bit.
assign current_sample = {sram_data_i[14], sram_data_i[14:0]};

assign sample_32 = {{16{current_sample[15]}}, current_sample};
assign squared_sample = sample_32 * sample_32; // True 32-bit math

always_comb begin
    //default
    state_d      = state_q;
    addr_d       = addr_q;
    energy_acc_d = energy_acc_q;
    zcr_acc_d    = zcr_acc_q;
    prev_sign_d  = prev_sign_q;
    speech_detected_o = 1'b0;

    case(state_q)
        IDLE: begin
            addr_d       = '0;
            energy_acc_d = '0;
            zcr_acc_d    = '0;
            prev_sign_d  = 1'b0;

            if (vad_wakeup_i) begin
                state_d = READ_WAIT;
            end
        end

        READ_WAIT: begin
            //wait for 1 cycle for sram to output data
            state_d = PROCESS;
        end

        PROCESS: begin
            //add up energy
            // The square is nonnegative; extend it without changing its value.
            energy_acc_d = energy_acc_q + {16'b0, squared_sample};

            //add up zero-crossing rate    
            // Because we fixed the MSB noise, we can use the standard logic again
            if (addr_q > 0 && (current_sample[15] != prev_sign_q)) begin
                zcr_acc_d = zcr_acc_q + 1;
            end
            
            // Store current sign
            prev_sign_d = current_sample[15];

            if(addr_q == frame_addr_t'(FRAME_SIZE - 1)) begin
                state_d = DECIDE;
            end else begin
                addr_d = addr_q + frame_addr_t'(1);
                state_d = READ_WAIT;
            end
        end

        DECIDE: begin
            // Changed to <= to ensure it triggers if ZCR equals the threshold exactly
            if(vad_enable_i && (energy_acc_q > {16'b0, energy_threshold_i}) && (zcr_acc_q <= zcr_threshold_i)) begin
                speech_detected_o = 1'b1;
            end 

            // Reset accumulators immediately to prevent old frame data from lingering
            addr_d       = '0;
            energy_acc_d = '0;
            zcr_acc_d    = '0;
            prev_sign_d  = 1'b0;

            state_d = IDLE;
        end

        default: state_d = IDLE;

    endcase
end 

always_ff @(posedge clk_sys_i or negedge rst_sys_ni) begin
    if(!rst_sys_ni) begin
        state_q    <= IDLE;
        addr_q     <= '0;
        energy_acc_q <= '0;
        zcr_acc_q   <= '0;
        prev_sign_q <= 1'b0;
    end else begin
        state_q     <= state_d;
        addr_q      <= addr_d;
        energy_acc_q <= energy_acc_d;
        zcr_acc_q   <= zcr_acc_d;
        prev_sign_q <= prev_sign_d;
    end
end

assign sram_addr_o = addr_q;

`ASSERT_INIT(FrameSize, FRAME_SIZE >= 2 && FRAME_SIZE <= 512,
             "FRAME_SIZE must be between 2 and 512 samples")
// Incoming samples must be at least four system cycles apart. A frame arriving
// before processing completes is unsupported by the baseline ping-pong protocol.
`ASSERT(FrameProcessingComplete, vad_wakeup_i |-> state_q == IDLE,
        clk_sys_i, !rst_sys_ni, "A completed frame arrived while the VAD core was busy")

endmodule
