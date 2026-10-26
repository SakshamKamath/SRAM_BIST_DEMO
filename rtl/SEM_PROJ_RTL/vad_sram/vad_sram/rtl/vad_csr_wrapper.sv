module vad_csr_wrapper import croc_pkg::*; import user_pkg::*; (
    input   logic   clk_i,
    input   logic   rst_ni,

    input   sbr_obi_req_t obi_req_i,
    output  sbr_obi_rsp_t obi_rsp_o,

    output  logic   i2s_sclk_o,
    output  logic   i2s_wsel_o,
    input   logic   i2s_sdat_i,

    output  logic   vad_wakeup_event_o
);

logic           reg_vad_enable;
logic [31:0]    reg_energy_thresh;
logic [15:0]    reg_zcr_thresh;

vad_subsystem #(
    .CLK_DIV_FACTOR(16),
    .FRAME_SIZE(320)
) u_vad_subsystem (
    .clk_sys_i          (clk_i),
    .rst_sys_ni         (rst_ni),

    .vad_enable_i       (reg_vad_enable),
    .energy_threshold_i (reg_energy_thresh),
    .zcr_threshold_i    (reg_zcr_thresh),

    .i2s_sclk_o         (i2s_sclk_o),
    .i2s_wsel_o         (i2s_wsel_o),
    .i2s_sdat_i         (i2s_sdat_i),

    .speech_detected_o  (vad_wakeup_event_o)
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
    end else begin
        rvalid_q <= obi_req_i.req;
        rdata_q  <= 32'h0;

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
                        default: rdata_q <= 32'h0;
                    endcase 
                end
            end
        end
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
