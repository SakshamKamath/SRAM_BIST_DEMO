

module march_bist_controller #(
    parameter DataWidth      = 32,
    parameter AddrWidth      = 10,
    parameter FifoDepth      = 2,   // (2^FifoDepth) is the actual depth,

    //Derived Parameters -- Do not override
    parameter NumWords         = 1 << AddrWidth
)   
    (
        //JTAG Related Signals
        input  tdi_i,
        input  tms_i,
        input  tclk_i, 
        input  trst_ni,           
        output tdo_o,

        //Control Signals
        input  start_i,
        input  resume_or_reset_i,
        input  erraddr_rd_i,
        output busy_o,
        output done_o,
        output fail_o,

        //Memory Related Signals
        input  [DataWidth -1:0] rdata_i,
        output [AddrWidth -1:0] memaddr_o,
        output [DataWidth -1:0] wdata_o,
        output                  memen_o,
        output                  memren_o,
        output                  memwen_o,
        output [DataWidth -1:0] membm_o,

        //MBIST erroneous address output
        output [AddrWidth -1:0] mbist_erraddr_o

    );

// ####################  March-MSS Algorithm FSM #####################

// Stage 0: ↕(w0)
// Stage 1: ⇑(r0, r0, w1, w1)
// Stage 2: ⇑(r1, r1, w0, w0)
// Stage 3: ⇓(r0, r0, w1, w1)
// Stage 4: ⇓(r1, r1, w0, w0)
// Stage 5: ↕(r0)

import march_pkg::*;
// typedef enum logic [3:0] {
//     St_Idle,
//     St_Stage0,
//     St_Stage1,
//     St_Stage2,
//     St_Stage3,
//     St_Stage4,
//     St_Stage5,
//     St_Done,
//     ERR_ABORT
// } seq_e;



// Expected read data patterns
localparam logic [DataWidth-1:0] DATA_ZERO = {DataWidth{1'b0}};
localparam logic [DataWidth-1:0] DATA_ONE  = {DataWidth{1'b1}};


// Registers for the algorithm
seq_e       seq_d, seq_q;
logic       err_d, err_q;
logic [1:0] sub_op_d, sub_op_q;
logic       ren, wen;
logic       is_first_addr, is_last_addr;
logic       read_error;

// Address and data registers
logic [DataWidth-1:0] wdata;
logic [AddrWidth-1:0] addr_d, addr_q;
logic [AddrWidth-1:0] mbist_erraddr;

// To check for the first and last address
assign is_first_addr  = (addr_q == '0); 
assign is_last_addr   = (addr_q == NumWords - 1); 

// FIFO related signals
logic fifo_wren, fifo_rden;
logic fifo_full, fifo_empty;

// Prevent duplicate FIFO writes for the same address
logic read_logged_d, read_logged_q;

// Registers for resumption after repair
seq_e                    recov_seq_d, recov_seq_q;

logic is_recov_downward;
assign is_recov_downward = (recov_seq_q == St_Stage3) || (recov_seq_q == St_Stage4);

always_comb begin
        seq_d         = seq_q;
        addr_d        = addr_q;
        sub_op_d      = sub_op_q;
        err_d         = err_q;
        wen           = 1'b0;
        ren           = 1'b0;
        wdata         = DATA_ZERO;
        fifo_wren     = 1'b0;
        fifo_rden     = erraddr_rd_i;
        read_error    = 1'b0;
        read_logged_d = read_logged_q;

        recov_seq_d    = recov_seq_q;

    if (fifo_full && (seq_q != St_Idle) && (seq_q != St_RepairWait)) begin
        seq_d = St_RepairWait;
        recov_seq_d    = seq_q;
    end else begin
        unique case(seq_q)
            St_Idle:    begin
                            if(start_i) begin
                                seq_d         = St_Stage0;
                                sub_op_d      = 2'b0;
                                err_d         = 1'b0;
                                read_logged_d = 1'b0;
                            end
                        end

            // Stage 0: ↕(w0)
            St_Stage0:  begin
                            wen    = 1'b1;
                            wdata  = DATA_ZERO;

                            if (is_last_addr) begin
                                seq_d  = St_Stage1;
                                addr_d = '0;
                            end else begin
                                addr_d = addr_q + 1'b1;
                            end
                        end

            // Stage 1: ⇑(r0, r0, w1, w1)
            St_Stage1:  begin
                            case (sub_op_q)

                                2'd0: begin ren = 1'b1; sub_op_d = 2'd1; end // Read 0
                                2'd1: begin // Verify Read 0 & Perform second Read 0
                                    if (rdata_i != DATA_ZERO) begin 
                                        read_error = 1'b1;
                                    end
                                    ren      = 1'b1;
                                    sub_op_d = 2'd2;
                                end
                                2'd2: begin // Verify Read 0 & Write 1
                                    if (rdata_i != DATA_ZERO) begin 
                                        read_error = 1'b1;
                                    end
                                    wen      = 1'b1;
                                    wdata    = DATA_ONE;
                                    sub_op_d = 2'd3;
                                end
                                2'd3: begin // Write 1 again
                                    wen      = 1'b1;
                                    wdata    = DATA_ONE;
                                    sub_op_d = 2'd0;
                                    read_logged_d = 1'b0;
                                    if (is_last_addr) begin
                                        seq_d  = St_Stage2;
                                        addr_d = '0;
                                    end else begin
                                        addr_d = addr_q + 1'b1;
                                    end
                                end
                            endcase
                        end

            // Stage 2: ⇑(r1, r1, w0, w0)
            St_Stage2:  begin
                            case (sub_op_q)
                                2'd0: begin ren = 1'b1; sub_op_d = 2'd1; end // Read 1
                                2'd1: begin // Verify Read 1 & second Read 1
                                    if (rdata_i != DATA_ONE) begin 
                                        read_error = 1'b1;
                                    end
                                    ren      = 1'b1;
                                    sub_op_d = 2'd2;
                                end
                                2'd2: begin // Verify Read 1 & Write 0
                                    if (rdata_i != DATA_ONE) begin
                                        read_error = 1'b1;
                                    end
                                    wen      = 1'b1;
                                    wdata    = DATA_ZERO;
                                    sub_op_d = 2'd3;
                                end
                                2'd3: begin // Write 0 again
                                    wen      = 1'b1;
                                    wdata    = DATA_ZERO;
                                    sub_op_d = 2'd0;
                                    read_logged_d = 1'b0;
                                    if (is_last_addr) begin
                                        seq_d  = St_Stage3;
                                        addr_d = NumWords - 1; // Prepare Downwards sweep
                                    end else begin
                                        addr_d = addr_q + 1'b1;
                                    end
                                end
                            endcase
                        end

            // Stage 3: ⇓(r0, r0, w1, w1)
            St_Stage3:  begin
                            case (sub_op_q)
                                2'd0: begin ren = 1'b1; sub_op_d = 2'd1; end
                                2'd1: begin
                                    if (rdata_i != DATA_ZERO) begin
                                        read_error = 1'b1;
                                    end
                                    ren      = 1'b1;
                                    sub_op_d = 2'd2;
                                end
                                2'd2: begin
                                    if (rdata_i != DATA_ZERO) begin
                                        read_error = 1'b1;
                                    end
                                    wen      = 1'b1;
                                    wdata    = DATA_ONE;
                                    sub_op_d = 2'd3;
                                end
                                2'd3: begin
                                    wen           = 1'b1;
                                    wdata         = DATA_ONE;
                                    sub_op_d      = 2'd0;
                                    read_logged_d = 1'b0;
                                    if (is_first_addr) begin
                                        seq_d  = St_Stage4;
                                        addr_d = NumWords - 1; // Downwards sweep continuation
                                    end else begin
                                        addr_d = addr_q - 1'b1;
                                    end
                                end
                            endcase
                        end

            // Stage 4: ⇓(r1, r1, w0, w0)
            St_Stage4:  begin
                            case (sub_op_q)
                                2'd0: begin ren = 1'b1; sub_op_d = 2'd1; end
                                2'd1: begin
                                    if (rdata_i != DATA_ONE) begin 
                                        read_error = 1'b1;
                                    end
                                    ren      = 1'b1;
                                    sub_op_d = 2'd2;
                                end
                                2'd2: begin
                                    if (rdata_i != DATA_ONE) begin
                                        read_error = 1'b1;
                                    end
                                    wen      = 1'b1;
                                    wdata    = DATA_ZERO;
                                    sub_op_d = 2'd3;
                                end
                                2'd3: begin
                                    wen      = 1'b1;
                                    wdata    = DATA_ZERO;
                                    sub_op_d = 2'd0;
                                    read_logged_d = 1'b0;
                                    if (is_first_addr) begin
                                        seq_d  = St_Stage5;
                                        addr_d = '0;
                                    end else begin
                                        addr_d = addr_q - 1'b1;
                                    end
                                end
                            endcase
                        end

            // Stage 5: ↕(r0)
            St_Stage5:  begin
                            case (sub_op_q)
                                2'd0: begin
                                    ren      = 1'b1;
                                    sub_op_d = 2'd1;
                                end
                                2'd1: begin
                                    if (rdata_i != DATA_ZERO) begin
                                        read_error = 1'b1;
                                    end
                                    sub_op_d = 2'd0;
                                    read_logged_d = 1'b0;
                                    if (is_last_addr) begin
                                        seq_d = St_Done;
                                    end else begin
                                        addr_d = addr_q + 1'b1;
                                    end
                                end
                                default: sub_op_d = 2'd0;
                            endcase
                        end


            St_Done:        begin
                                if(resume_or_reset_i) begin
                                    seq_d = St_Idle;
                                end
                            end

            St_RepairWait:  begin
                                if (resume_or_reset_i) begin
                                    sub_op_d      = 2'd0; // Reset sub-op to start fresh at the next address
                                    read_logged_d = 1'b0;

                                    if (is_recov_downward) begin
                                        if (addr_q == '0) begin // Downward boundary check
                                            seq_d  = (recov_seq_q == St_Stage3) ? St_Stage4 : St_Stage5;
                                            addr_d = (recov_seq_q == St_Stage3) ? (NumWords - 1) : '0;
                                        end else begin
                                            seq_d  = recov_seq_q;
                                            addr_d = addr_q - 1'b1;
                                        end
                                    end else begin
                                        if (addr_q == NumWords - 1) begin // Upward boundary check
                                            seq_d  = (recov_seq_q == St_Stage0) ? St_Stage1 :
                                                     (recov_seq_q == St_Stage1) ? St_Stage2 :
                                                     (recov_seq_q == St_Stage2) ? St_Stage3 : St_Done;
                                            addr_d = (recov_seq_q == St_Stage2) ? (NumWords - 1) : '0;
                                        end else begin
                                            seq_d  = recov_seq_q;
                                            addr_d = addr_q + 1'b1;
                                        end
                                    end
                                end
                            end

            default: seq_d = St_Idle;

        endcase
        if (read_error) begin
            err_d = 1'b1;
            if (!read_logged_q && !fifo_full) begin
                fifo_wren     = 1'b1;
                read_logged_d = 1'b1;
            end
        end
    end
end


// To log the correct address
logic [AddrWidth-1:0] err_addr_d, err_addr_q;

// Capture the address when issuing a read command
always_comb begin
    err_addr_d = err_addr_q;
    if (ren) begin
        err_addr_d = addr_q;
    end
end

always_ff @(posedge tclk_i) begin
    if (!trst_ni) begin
        err_addr_q <= '0;
    end else begin
        err_addr_q <= err_addr_d;
    end
end


generate 
    if (FifoDepth > 0) begin : gen_fifo_enabled
        fifo #(
            .FifoDepth(FifoDepth),
            .FifoWidth(AddrWidth)
        ) u_err_fifo (
            .clk_i(tclk_i),
            .rst_ni(trst_ni),
            .wen_i(fifo_wren),
            .ren_i(fifo_rden),
            .data_i(err_addr_q),
            .data_o(mbist_erraddr_o),
            .full_o(fifo_full),
            .empty_o(fifo_empty)
        );
    end else begin : gen_fifo_disabled
        assign fifo_full  = err_q;
        assign fifo_empty = !err_q;
    end

endgenerate

always_ff @(posedge tclk_i) begin
if (!trst_ni) begin
        seq_q         <= St_Idle;
        addr_q        <= '0;
        sub_op_q      <= '0;
        err_q         <= 1'b0;
        read_logged_q <= 1'b0;
        recov_seq_q   <= St_Idle;
    end else begin
        seq_q         <= seq_d;
        addr_q        <= addr_d;
        sub_op_q      <= sub_op_d;
        err_q         <= err_d;
        read_logged_q <= read_logged_d;
        recov_seq_q   <= recov_seq_d;
    end
end


// Output Assignments
assign tdo_o     = tdi_i;
assign done_o = (seq_q == St_Done);
assign memaddr_o = addr_q;
assign busy_o    = (seq_q != St_Idle) && (seq_q != St_Done);
assign wdata_o   = wdata;
assign memwen_o  = wen;
assign memren_o  = ren;
assign memen_o   = busy_o;
assign membm_o   = '1;
assign fail_o    = !fifo_empty; 

endmodule
