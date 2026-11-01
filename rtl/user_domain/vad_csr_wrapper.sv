module vad_csr_wrapper import croc_pkg::*; import user_pkg::*; (
    input   logic   clk_i,
    input   logic   rst_ni,

    input   sbr_obi_req_t obi_req_i,
    output  sbr_obi_rsp_t obi_rsp_o,

    output  logic   i2s_sclk_o,
    output  logic   i2s_wsel_o,
    input   logic   i2s_sdat_i,

    output  logic   vad_wakeup_event_o, // single-cycle pulse per detection
    output  logic   vad_irq_o,          // Observability: level interrupt, SPEECH flag & IRQ_EN

    // MBIST of the frame SRAMs, controlled from soc_ctrl_regs (index = bank)
    input   logic [1:0]       mbist_start_i,
    input   logic [1:0]       mbist_resume_i,
    input   logic [1:0]       mbist_erraddrread_i,
    output  logic [1:0][3:0]  mbist_status_o,
    output  logic [1:0][8:0]  mbist_erraddr_o
);

// Register map (offsets in addr[7:0]):
//   0x00-0x1C  RO  student names
//   0x20       RW  VAD_ENABLE   [0]
//   0x24       RW  ENERGY_THRESH
//   0x28       RW  ZCR_THRESH   [15:0]
//   Observability registers (0x2C-0x4C):
//   0x2C       RW  SRAM_CTRL    [0] DBG_EN: CPU owns the frame SRAMs, audio is dropped
//                               [1] BANK_SEL: bank accessed by CPU and read by the VAD core
//                               [2] AUTO_INC: SRAM_ADDR += 1 after each WRITE/READ command
//                               [3] IRQ_EN: vad_irq_o follows SRAM_STATUS.SPEECH
//   0x30       RW  SRAM_ADDR    [8:0]
//   0x34       RW  SRAM_WDATA   [15:0]
//   0x38       WO  SRAM_CMD     [0] WRITE: SRAM[BANK_SEL][SRAM_ADDR] <= SRAM_WDATA
//                               [1] READ:  SRAM_RDATA <= SRAM[BANK_SEL][SRAM_ADDR]
//                               [2] KICK:  run the VAD core on BANK_SEL
//                               [3] EVAL:  run the speech decision on LAST_ENERGY/LAST_ZCR;
//                                          sets SPEECH like a frame would. Ignored while
//                                          the core is busy.
//                               [4] IRQ_TRIG: set SPEECH as if a frame had detected speech,
//                                          to test the interrupt path without audio.
//                               WRITE/READ/KICK/EVAL only take effect while DBG_EN is set;
//                               IRQ_TRIG works in normal operation too.
//   0x3C       RO  SRAM_RDATA   [15:0]
//   0x40       RO  SRAM_STATUS  [0] SPEECH: sticky speech-detected flag, write 1 to clear
//                               [1] READ_BANK, [2] WRITE_BANK, [3] READ_PENDING,
//                               [12:4] WRITE_ADDR (next sample slot of the audio writer)
//                               [13] IRQ: current level of vad_irq_o
//   0x44       RW  LAST_ENERGY_LO  energy of the last processed frame [31:0]
//   0x48       RW  LAST_ENERGY_HI  [15:0] = energy [47:32]
//   0x4C       RW  LAST_ZCR        [15:0] zero crossings of the last processed frame
//                               Updated when a frame is decided; a frame ending in the
//                               same cycle as a software write wins.
localparam int unsigned FRAME_SIZE = 320;

logic           reg_vad_enable;
logic [31:0]    reg_energy_thresh;
logic [15:0]    reg_zcr_thresh;

// Observability: SRAM_CTRL, SRAM debug access and sticky SPEECH flag
logic           reg_sram_dbg_en;
logic           reg_sram_bank;
logic           reg_sram_auto_inc;
logic           reg_irq_en;
logic [8:0]     reg_sram_addr;
logic [15:0]    reg_sram_wdata;
logic [15:0]    reg_sram_rdata;
logic           sram_rd_pending_q;
logic           speech_sticky_q;

// Observability: SRAM_CMD strobes and SRAM_STATUS sources
logic           sram_cmd_valid;
logic           sram_we, sram_re, sram_kick, sram_eval, irq_trig;
logic [15:0]    sram_dbg_rdata;
logic           speech_detected;
logic           read_bank, write_bank;
logic [$clog2(FRAME_SIZE)-1:0] write_addr;

// Observability: last frame result (the flops are in vad_core)
logic [47:0]    last_energy;
logic [15:0]    last_zcr;
logic           last_energy_lo_we, last_energy_hi_we, last_zcr_we;
logic [31:0]    last_wdata;
logic [31:0]    last_old;
logic [31:0]    be_mask;

// Observability: SRAM_CMD strobes, issued in the same cycle as the OBI write
assign sram_cmd_valid = obi_req_i.req && obi_req_i.a.we &&
                        (obi_req_i.a.addr[7:0] == 8'h38) && obi_req_i.a.be[0];
assign sram_we   = sram_cmd_valid && obi_req_i.a.wdata[0];
assign sram_re   = sram_cmd_valid && obi_req_i.a.wdata[1];
assign sram_kick = sram_cmd_valid && obi_req_i.a.wdata[2];
assign sram_eval = sram_cmd_valid && obi_req_i.a.wdata[3] && reg_sram_dbg_en;
assign irq_trig  = sram_cmd_valid && obi_req_i.a.wdata[4];   // not gated by DBG_EN

// Observability: write enables for the last frame result
assign last_energy_lo_we = obi_req_i.req && obi_req_i.a.we && (obi_req_i.a.addr[7:0] == 8'h44);
assign last_energy_hi_we = obi_req_i.req && obi_req_i.a.we && (obi_req_i.a.addr[7:0] == 8'h48);
assign last_zcr_we       = obi_req_i.req && obi_req_i.a.we && (obi_req_i.a.addr[7:0] == 8'h4C);

// Observability: byte-enable merge of the last frame result write data
assign be_mask    = {{8{obi_req_i.a.be[3]}}, {8{obi_req_i.a.be[2]}},
                     {8{obi_req_i.a.be[1]}}, {8{obi_req_i.a.be[0]}}};
assign last_old   = last_energy_lo_we ? last_energy[31:0] :
                    last_energy_hi_we ? {16'h0, last_energy[47:32]} : {16'h0, last_zcr};
assign last_wdata = (last_old & ~be_mask) | (obi_req_i.a.wdata & be_mask);

assign vad_wakeup_event_o = speech_detected;
// Observability: level interrupt from the sticky SPEECH flag
assign vad_irq_o          = speech_sticky_q & reg_irq_en;

vad_subsystem #(
    .CLK_DIV_FACTOR(16),
    .FRAME_SIZE(FRAME_SIZE)
) u_vad_subsystem (
    .clk_sys_i          (clk_i),
    .rst_sys_ni         (rst_ni),

    .vad_enable_i       (reg_vad_enable),
    .energy_threshold_i (reg_energy_thresh),
    .zcr_threshold_i    (reg_zcr_thresh),

    .i2s_sclk_o         (i2s_sclk_o),
    .i2s_wsel_o         (i2s_wsel_o),
    .i2s_sdat_i         (i2s_sdat_i),

    .speech_detected_o  (speech_detected),

    // Observability
    .last_energy_lo_we_i (last_energy_lo_we),
    .last_energy_hi_we_i (last_energy_hi_we),
    .last_zcr_we_i       (last_zcr_we),
    .last_wdata_i        (last_wdata),
    .eval_i              (sram_eval),
    .last_energy_o       (last_energy),
    .last_zcr_o          (last_zcr),

    .dbg_en_i           (reg_sram_dbg_en),
    .dbg_bank_i         (reg_sram_bank),
    .dbg_addr_i         (reg_sram_addr),
    .dbg_wdata_i        (reg_sram_wdata),
    .dbg_we_i           (sram_we),
    .dbg_re_i           (sram_re),
    .dbg_kick_i         (sram_kick),
    .dbg_rdata_o        (sram_dbg_rdata),
    .read_bank_o        (read_bank),
    .write_bank_o       (write_bank),
    .write_addr_o       (write_addr),

    .mbist_start_i       (mbist_start_i),
    .mbist_resume_i      (mbist_resume_i),
    .mbist_erraddrread_i (mbist_erraddrread_i),
    .mbist_status_o      (mbist_status_o),
    .mbist_erraddr_o     (mbist_erraddr_o)
);

localparam int unsigned NAME_LEN = 32;
localparam byte STUDENT_NAMES [0:NAME_LEN-1] = '{
        "A", "n", "n", "a", " ", "L", "u", "b", "b", 
        "e", "r", "s", " ", "&", " ", "O", "l",
        "e", "g", " ", "T", "s", "y", "p", "l",
        "a", "k", "o", "v", 0, 0, 0
    };

logic rvalid_q;
logic [31:0] rdata_q;
logic [SbrObiCfg.IdWidth-1:0] rid_q;


always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        reg_vad_enable      <= 1'b1;
        reg_energy_thresh   <= 32'd17_435;
        reg_zcr_thresh      <= 16'd20;
        rvalid_q            <= 1'b0;
        rdata_q             <= 32'h0;
        rid_q               <= '0;
        reg_sram_dbg_en     <= 1'b0;
        reg_sram_bank       <= 1'b0;
        reg_sram_auto_inc   <= 1'b0;
        reg_irq_en          <= 1'b0;
        reg_sram_addr       <= '0;
        reg_sram_wdata      <= '0;
        reg_sram_rdata      <= '0;
        sram_rd_pending_q   <= 1'b0;
        speech_sticky_q     <= 1'b0;   // Observability registers above
    end else begin
        rvalid_q <= obi_req_i.req;
        rdata_q  <= 32'h0;

        // Observability: SRAM read capture
        sram_rd_pending_q <= sram_re && reg_sram_dbg_en;
        if (sram_rd_pending_q) reg_sram_rdata <= sram_dbg_rdata;

        // Observability: SRAM_ADDR auto-increment
        if ((sram_we || sram_re) && reg_sram_dbg_en && reg_sram_auto_inc)
            reg_sram_addr <= reg_sram_addr + 9'd1;

        if (obi_req_i.req) begin
            rid_q <= obi_req_i.a.aid;
            if (obi_req_i.a.we) begin
                case(obi_req_i.a.addr[7:0])
                    8'h20: if (obi_req_i.a.be[0]) reg_vad_enable <= obi_req_i.a.wdata[0];
                    8'h24: begin //ENERGY_Thresh
                        if(obi_req_i.a.be[0]) reg_energy_thresh[7:0]    <= obi_req_i.a.wdata[7:0];
                        if(obi_req_i.a.be[1]) reg_energy_thresh[15:8]   <= obi_req_i.a.wdata[15:8];
                        if(obi_req_i.a.be[2]) reg_energy_thresh[23:16]  <= obi_req_i.a.wdata[23:16];
                        if(obi_req_i.a.be[3]) reg_energy_thresh[31:24]  <= obi_req_i.a.wdata[31:24];
                    end
                    8'h28: begin
                        if(obi_req_i.a.be[0]) reg_zcr_thresh[7:0]     <= obi_req_i.a.wdata[7:0];
                        if(obi_req_i.a.be[1]) reg_zcr_thresh[15:8]    <= obi_req_i.a.wdata[15:8];
                    end
                    8'h2C: if (obi_req_i.a.be[0]) begin // Observability: SRAM_CTRL
                        reg_sram_dbg_en   <= obi_req_i.a.wdata[0];
                        reg_sram_bank     <= obi_req_i.a.wdata[1];
                        reg_sram_auto_inc <= obi_req_i.a.wdata[2];
                        reg_irq_en        <= obi_req_i.a.wdata[3];
                    end
                    8'h30: begin // Observability: SRAM_ADDR
                        if(obi_req_i.a.be[0]) reg_sram_addr[7:0]  <= obi_req_i.a.wdata[7:0];
                        if(obi_req_i.a.be[1]) reg_sram_addr[8]    <= obi_req_i.a.wdata[8];
                    end
                    8'h34: begin // Observability: SRAM_WDATA
                        if(obi_req_i.a.be[0]) reg_sram_wdata[7:0]  <= obi_req_i.a.wdata[7:0];
                        if(obi_req_i.a.be[1]) reg_sram_wdata[15:8] <= obi_req_i.a.wdata[15:8];
                    end
                    default: ;
                endcase
            end else begin
                if (obi_req_i.a.addr[7:0] < 8'h20) begin
                    rdata_q <= {
                        STUDENT_NAMES[ {obi_req_i.a.addr[4:2], 2'b11}],
                        STUDENT_NAMES[ {obi_req_i.a.addr[4:2], 2'b10}],
                        STUDENT_NAMES[ {obi_req_i.a.addr[4:2], 2'b01}],
                        STUDENT_NAMES[ {obi_req_i.a.addr[4:2], 2'b00}]
                    };
                end else begin
                    case (obi_req_i.a.addr[7:0])
                        8'h20: rdata_q <= {31'h0, reg_vad_enable};
                        8'h24: rdata_q <= reg_energy_thresh;
                        8'h28: rdata_q <= {16'h0, reg_zcr_thresh};
                        // Observability registers
                        8'h2C: rdata_q <= {28'h0, reg_irq_en, reg_sram_auto_inc, reg_sram_bank, reg_sram_dbg_en};
                        8'h30: rdata_q <= {23'h0, reg_sram_addr};
                        8'h34: rdata_q <= {16'h0, reg_sram_wdata};
                        8'h3C: rdata_q <= {16'h0, sram_rd_pending_q ? sram_dbg_rdata : reg_sram_rdata};
                        8'h40: rdata_q <= {18'h0, vad_irq_o, 9'(write_addr), sram_rd_pending_q,
                                           write_bank, read_bank, speech_sticky_q};
                        8'h44: rdata_q <= last_energy[31:0];
                        8'h48: rdata_q <= {16'h0, last_energy[47:32]};
                        8'h4C: rdata_q <= {16'h0, last_zcr};
                        default: rdata_q <= 32'h0;
                    endcase 
                end
            end
        end

        // Observability: sticky SPEECH flag, write 1 to clear
        if (obi_req_i.req && obi_req_i.a.we && (obi_req_i.a.addr[7:0] == 8'h40) &&
            obi_req_i.a.be[0] && obi_req_i.a.wdata[0])
            speech_sticky_q <= 1'b0;
        if (speech_detected || irq_trig) speech_sticky_q <= 1'b1;
    end
end

always_comb begin
    obi_rsp_o         = '0;
    obi_rsp_o.gnt     = 1'b1;
    obi_rsp_o.rvalid  = rvalid_q;
    obi_rsp_o.r.rdata = rdata_q;
    obi_rsp_o.r.rid   = rid_q;
end

endmodule
