module SRAM_1P_behavioral_bm_bist (
    A_ADDR,
    A_DIN,
    A_BM,
    A_MEN,
    A_WEN,
    A_REN,
    A_CLK,
    A_DLY,
    A_DOUT,

    A_BIST_EN,
    A_BIST_ADDR,
    A_BIST_DIN,
    A_BIST_BM,
    A_BIST_MEN,
    A_BIST_WEN,
    A_BIST_REN,
    A_BIST_CLK
);

parameter DataWidth = 24;
parameter AddrWidth = 8;
localparam MEM_DEPTH   = 2**(AddrWidth);

parameter EN_FAULT_INJECTION = 1'b0;

parameter [DataWidth-1:0] MASK_SAF_0  [0:MEM_DEPTH-1] = '{default: '0};
parameter [DataWidth-1:0] MASK_SAF_1  [0:MEM_DEPTH-1] = '{default: '0};
parameter [DataWidth-1:0] MASK_TF_01  [0:MEM_DEPTH-1] = '{default: '0};
parameter [DataWidth-1:0] MASK_TF_10  [0:MEM_DEPTH-1] = '{default: '0};
parameter [DataWidth-1:0] MASK_RDF    [0:MEM_DEPTH-1] = '{default: '0};
parameter [DataWidth-1:0] MASK_IRF    [0:MEM_DEPTH-1] = '{default: '0};
parameter [DataWidth-1:0] MASK_DRDF   [0:MEM_DEPTH-1] = '{default: '0};
parameter [DataWidth-1:0] MASK_WDF    [0:MEM_DEPTH-1] = '{default: '0};

parameter [DataWidth-1:0] MASK_CF_WRITE [0:MEM_DEPTH-1][0:MEM_DEPTH-1] = '{default: '{default: '0}};
parameter [DataWidth-1:0] MASK_CF_READ  [0:MEM_DEPTH-1][0:MEM_DEPTH-1] = '{default: '{default: '0}};

input wire  [AddrWidth-1:0]  A_ADDR;
input wire  [DataWidth-1:0]  A_DIN;
input wire  [DataWidth-1:0]  A_BM;
input wire                   A_MEN;
input wire                   A_WEN;
input wire                   A_REN;
input wire                   A_CLK;
input wire                   A_DLY;
output wire [DataWidth-1:0]  A_DOUT;

input wire                   A_BIST_EN;
input wire  [AddrWidth-1:0]  A_BIST_ADDR;
input wire  [DataWidth-1:0]  A_BIST_DIN;
input wire  [DataWidth-1:0]  A_BIST_BM;
input wire                   A_BIST_MEN;
input wire                   A_BIST_WEN;
input wire                   A_BIST_REN;
input wire                   A_BIST_CLK;

reg [DataWidth-1:0] memory [0:MEM_DEPTH-1];
reg [DataWidth-1:0] dr_r;

wire [AddrWidth-1:0] ADDR_MUX;
wire [DataWidth-1:0] DIN_MUX;
wire [DataWidth-1:0] BM_MUX;
wire                 MEN_MUX;
wire                 WEN_MUX;
wire                 REN_MUX;
wire                 CLK_MUX;

assign ADDR_MUX = (A_BIST_EN == 1'b1) ? A_BIST_ADDR : A_ADDR;
assign DIN_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_DIN  : A_DIN;
assign BM_MUX   = (A_BIST_EN == 1'b1) ? A_BIST_BM   : A_BM;
assign MEN_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_MEN  : A_MEN;
assign WEN_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_WEN  : A_WEN;
assign REN_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_REN  : A_REN;
assign CLK_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_CLK  : A_CLK;

reg [DataWidth-1:0] write_data;
reg [DataWidth-1:0] current_mem;
integer i, v_addr;

always @(posedge CLK_MUX) begin
    if (MEN_MUX == 1'b1) begin
        if (WEN_MUX == 1'b1) begin
            current_mem = memory[ADDR_MUX];
            write_data = (current_mem & ~BM_MUX) | (DIN_MUX & BM_MUX);

            if (EN_FAULT_INJECTION) begin
                for (i = 0; i < DataWidth; i = i + 1) begin
                    if (BM_MUX[i]) begin
                        if (MASK_TF_01[ADDR_MUX][i] && !current_mem[i] && DIN_MUX[i]) begin
                            write_data[i] = 1'b0; 
                        end
                        if (MASK_TF_10[ADDR_MUX][i] && current_mem[i] && !DIN_MUX[i]) begin
                            write_data[i] = 1'b1; 
                        end
                        if (MASK_WDF[ADDR_MUX][i]) begin
                            write_data[i] = ~write_data[i];
                        end
                    end
                end

                for (v_addr = 0; v_addr < MEM_DEPTH; v_addr = v_addr + 1) begin
                    if (MASK_CF_WRITE[ADDR_MUX][v_addr] != '0) begin
                        memory[v_addr] = memory[v_addr] ^ MASK_CF_WRITE[ADDR_MUX][v_addr];
                    end
                end
            end

            memory[ADDR_MUX] = write_data;

            if (REN_MUX == 1'b1) begin
                dr_r <= write_data;
            end
        end

        else if (REN_MUX == 1'b1) begin
            dr_r <= memory[ADDR_MUX];

            if (EN_FAULT_INJECTION) begin
                if (MASK_IRF[ADDR_MUX] != '0) begin
                    dr_r <= memory[ADDR_MUX] ^ MASK_IRF[ADDR_MUX];
                end

                if (MASK_RDF[ADDR_MUX] != '0) begin
                    dr_r             <= memory[ADDR_MUX] ^ MASK_RDF[ADDR_MUX];
                    memory[ADDR_MUX] = memory[ADDR_MUX] ^ MASK_RDF[ADDR_MUX];
                end

                if (MASK_DRDF[ADDR_MUX] != '0) begin
                    dr_r             <= memory[ADDR_MUX];
                    memory[ADDR_MUX] = memory[ADDR_MUX] ^ MASK_DRDF[ADDR_MUX];
                end

                for (v_addr = 0; v_addr < MEM_DEPTH; v_addr = v_addr + 1) begin
                    if (MASK_CF_READ[ADDR_MUX][v_addr] != '0) begin
                        memory[v_addr] = memory[v_addr] ^ MASK_CF_READ[ADDR_MUX][v_addr];
                    end
                end
            end
        end

        if (EN_FAULT_INJECTION) begin
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                if (MASK_SAF_0[i] != '0 || MASK_SAF_1[i] != '0) begin
                    memory[i] = (memory[i] & ~MASK_SAF_0[i]) | MASK_SAF_1[i];
                end
            end
        end

    end
end

assign A_DOUT = dr_r;

endmodule














// ////////////////////////////////////////////////////////////////////////
// //
// // Extended SRAM Behavioral Model with Multi-Address & Bit-Masked Faults
// //
// ////////////////////////////////////////////////////////////////////////

// module SRAM_1P_behavioral_bm_bist (
//     A_ADDR,
//     A_DIN,
//     A_BM,
//     A_MEN,    // Memory enable input
//     A_WEN,    // Common write enable input
//     A_REN,    // Read enable input
//     A_CLK,    // Clock input
//     A_DLY,    // Delay selection signals
//     A_DOUT,

//     A_BIST_EN,
//     A_BIST_ADDR,
//     A_BIST_DIN,
//     A_BIST_BM,
//     A_BIST_MEN,
//     A_BIST_WEN,
//     A_BIST_REN,
//     A_BIST_CLK
// );

// // Basic Parameters
// parameter DataWidth = 24;
// parameter AddrWidth = 14;
// localparam MEM_DEPTH   = 2**(AddrWidth);

// // ---------------------------------------------------------------------
// // Fault Injection Control Parameters
// // ---------------------------------------------------------------------
// parameter EN_FAULT_INJECTION = 1'b0; // Master Enable

// // Bitmask Arrays across Memory Depth [0 : MEM_DEPTH-1]
// // For any address, setting bit 'i' to 1 enables the fault for bit 'i'
// parameter [DataWidth-1:0] MASK_SAF_0  [0:MEM_DEPTH-1] = '{default: '0}; // Stuck-At 0 Mask
// parameter [DataWidth-1:0] MASK_SAF_1  [0:MEM_DEPTH-1] = '{default: '0}; // Stuck-At 1 Mask
// parameter [DataWidth-1:0] MASK_TF_01  [0:MEM_DEPTH-1] = '{default: '0}; // Transition Fault (Fails 0->1)
// parameter [DataWidth-1:0] MASK_TF_10  [0:MEM_DEPTH-1] = '{default: '0}; // Transition Fault (Fails 1->0)
// parameter [DataWidth-1:0] MASK_RDF    [0:MEM_DEPTH-1] = '{default: '0}; // Read Destructive Fault Mask
// parameter [DataWidth-1:0] MASK_IRF    [0:MEM_DEPTH-1] = '{default: '0}; // Incorrect Read Fault Mask
// parameter [DataWidth-1:0] MASK_DRDF   [0:MEM_DEPTH-1] = '{default: '0}; // Deceptive Read Destructive Fault Mask
// parameter [DataWidth-1:0] MASK_WDF    [0:MEM_DEPTH-1] = '{default: '0}; // Write Destructive Fault Mask

// // Coupling Fault Matrix: [Aggressor_Addr][Victim_Addr] -> Bitmask of victim bits flipped
// parameter [DataWidth-1:0] MASK_CF_WRITE [0:MEM_DEPTH-1][0:MEM_DEPTH-1] = '{default: '{default: '0}};
// parameter [DataWidth-1:0] MASK_CF_READ  [0:MEM_DEPTH-1][0:MEM_DEPTH-1] = '{default: '{default: '0}};

// // Ports
// input wire  [AddrWidth-1:0]  A_ADDR;
// input wire  [DataWidth-1:0]  A_DIN;
// input wire  [DataWidth-1:0]  A_BM;
// input wire                      A_MEN;
// input wire                      A_WEN;
// input wire                      A_REN;
// input wire                      A_CLK;
// input wire                      A_DLY;
// output wire [DataWidth-1:0]  A_DOUT;

// input wire                      A_BIST_EN;
// input wire  [AddrWidth-1:0]  A_BIST_ADDR;
// input wire  [DataWidth-1:0]  A_BIST_DIN;
// input wire  [DataWidth-1:0]  A_BIST_BM;
// input wire                      A_BIST_MEN;
// input wire                      A_BIST_WEN;
// input wire                      A_BIST_REN;
// input wire                      A_BIST_CLK;

// // Internal Registers & Signals
// reg [DataWidth-1:0] memory [0:MEM_DEPTH-1];
// reg [DataWidth-1:0] dr_r;

// wire [AddrWidth-1:0] ADDR_MUX;
// wire [DataWidth-1:0] DIN_MUX;
// wire [DataWidth-1:0] BM_MUX;
// wire                    MEN_MUX;
// wire                    WEN_MUX;
// wire                    REN_MUX;
// wire                    CLK_MUX;

// // BIST Multiplexers
// assign ADDR_MUX = (A_BIST_EN == 1'b1) ? A_BIST_ADDR : A_ADDR;
// assign DIN_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_DIN  : A_DIN;
// assign BM_MUX   = (A_BIST_EN == 1'b1) ? A_BIST_BM   : A_BM;
// assign MEN_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_MEN  : A_MEN;
// assign WEN_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_WEN  : A_WEN;
// assign REN_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_REN  : A_REN;
// assign CLK_MUX  = (A_BIST_EN == 1'b1) ? A_BIST_CLK  : A_CLK;

// // Internal helper variables
// reg [DataWidth-1:0] write_data;
// reg [DataWidth-1:0] current_mem;
// integer i, v_addr;

// always @(posedge CLK_MUX) begin
//     if (MEN_MUX == 1'b1) begin
        
//         // -----------------------------------------------------------------
//         // WRITE OPERATION
//         // -----------------------------------------------------------------
//         if (WEN_MUX == 1'b1) begin
//             current_mem = memory[ADDR_MUX];
            
//             // Base byte-masked write calculation
//             write_data = (current_mem & ~BM_MUX) | (DIN_MUX & BM_MUX);

//             if (EN_FAULT_INJECTION) begin
//                 for (i = 0; i < DataWidth; i = i + 1) begin
//                     if (BM_MUX[i]) begin
//                         // Transition Fault 0 -> 1 (TF_01)
//                         if (MASK_TF_01[ADDR_MUX][i] && !current_mem[i] && DIN_MUX[i]) begin
//                             write_data[i] = 1'b0; 
//                         end
//                         // Transition Fault 1 -> 0 (TF_10)
//                         if (MASK_TF_10[ADDR_MUX][i] && current_mem[i] && !DIN_MUX[i]) begin
//                             write_data[i] = 1'b1; 
//                         end
//                         // Write Destructive Fault (WDF)
//                         if (MASK_WDF[ADDR_MUX][i]) begin
//                             write_data[i] = ~write_data[i];
//                         end
//                     end
//                 end

//                 // Trigger Coupling Faults caused by Write on victim addresses
//                 for (v_addr = 0; v_addr < MEM_DEPTH; v_addr = v_addr + 1) begin
//                     if (MASK_CF_WRITE[ADDR_MUX][v_addr] != '0) begin
//                         memory[v_addr] <= memory[v_addr] ^ MASK_CF_WRITE[ADDR_MUX][v_addr];
//                     end
//                 end
//             end

//             // Apply Write Data to Memory
//             memory[ADDR_MUX] <= write_data;

//             // Concurrent Write-Through Read
//             if (REN_MUX == 1'b1) begin
//                 dr_r <= write_data;
//             end
//         end

//         // -----------------------------------------------------------------
//         // READ OPERATION
//         // -----------------------------------------------------------------
//         else if (REN_MUX == 1'b1) begin
//             dr_r <= memory[ADDR_MUX];

//             if (EN_FAULT_INJECTION) begin
//                 // Incorrect Read Fault (IRF): Read output inverted on masked bits, cell unchanged
//                 if (MASK_IRF[ADDR_MUX] != '0) begin
//                     dr_r <= memory[ADDR_MUX] ^ MASK_IRF[ADDR_MUX];
//                 end

//                 // Read Destructive Fault (RDF): Cell flips and wrong data is read out
//                 if (MASK_RDF[ADDR_MUX] != '0) begin
//                     memory[ADDR_MUX] <= memory[ADDR_MUX] ^ MASK_RDF[ADDR_MUX];
//                     dr_r             <= memory[ADDR_MUX] ^ MASK_RDF[ADDR_MUX];
//                 end

//                 // Deceptive Read Destructive Fault (DRDF): Correct data read out, cell flips after
//                 if (MASK_DRDF[ADDR_MUX] != '0) begin
//                     memory[ADDR_MUX] <= memory[ADDR_MUX] ^ MASK_DRDF[ADDR_MUX];
//                     dr_r             <= memory[ADDR_MUX];
//                 end

//                 // Trigger Coupling Faults caused by Read on victim addresses
//                 for (v_addr = 0; v_addr < MEM_DEPTH; v_addr = v_addr + 1) begin
//                     if (MASK_CF_READ[ADDR_MUX][v_addr] != '0) begin
//                         memory[v_addr] <= memory[v_addr] ^ MASK_CF_READ[ADDR_MUX][v_addr];
//                     end
//                 end
//             end
//         end

//         // -----------------------------------------------------------------
//         // CONTINUOUS STUCK-AT FAULT OVERRIDE (SAF_0 and SAF_1)
//         // -----------------------------------------------------------------
//         if (EN_FAULT_INJECTION) begin
//             for (i = 0; i < MEM_DEPTH; i = i + 1) begin
//                 if (MASK_SAF_0[i] != '0 || MASK_SAF_1[i] != '0) begin
//                     memory[i] <= (memory[i] & ~MASK_SAF_0[i]) | MASK_SAF_1[i];
//                 end
//             end
//         end

//     end
// end

// assign A_DOUT = dr_r;

// endmodule























