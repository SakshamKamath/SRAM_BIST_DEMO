module fifo #(
    parameter FifoDepth = 2,
    parameter FifoWidth = 32

) 
    (
        input                  clk_i,
        input                  rst_ni,
        input                  wen_i,
        input                  ren_i,
        input  [FifoWidth-1:0] data_i,
        output [FifoWidth-1:0] data_o,
        output                 full_o,
        output                 empty_o
    );

    localparam MemDepth = 1 << FifoDepth;

    logic [MemDepth-1:0][FifoWidth-1:0]memfifo;
    logic [FifoDepth:0]wr_ptr_d, wr_ptr_q, rd_ptr_d, rd_ptr_q;

    logic [FifoWidth-1:0]rd_data;

    always_ff @(posedge clk_i) begin
        if(!rst_ni) begin
            wr_ptr_q  <= '0;
            rd_ptr_q  <= '0;
        end else begin
            wr_ptr_q <= wr_ptr_d;
            rd_ptr_q <= rd_ptr_d;
        end
    end
    
    always_comb begin
        wr_ptr_d = wr_ptr_q;
        if (wen_i && !full_o) begin
            wr_ptr_d = wr_ptr_q + 1'b1;
        end
    end

    always_comb begin
        rd_ptr_d = rd_ptr_q;
        if (ren_i && !empty_o) begin
            rd_ptr_d = rd_ptr_q + 1'b1;
        end
    end    

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            memfifo <= '0;
        end else begin
            if (wen_i && !full_o) begin
                memfifo[wr_ptr_q[FifoDepth-1:0]] <= data_i;
            end
        end
    end

    // ---------------------------------------------------------------------------
    // Memory Read Operation
    // ---------------------------------------------------------------------------
    assign rd_data = memfifo[rd_ptr_q[FifoDepth-1:0]];




    // Output Assignments
    assign empty_o = (wr_ptr_q == rd_ptr_q);

    assign full_o  = (wr_ptr_q[FifoDepth-1:0] == rd_ptr_q[FifoDepth-1:0]) && 
                     (wr_ptr_q[FifoDepth]     != rd_ptr_q[FifoDepth]);

    assign data_o = rd_data; 

endmodule
