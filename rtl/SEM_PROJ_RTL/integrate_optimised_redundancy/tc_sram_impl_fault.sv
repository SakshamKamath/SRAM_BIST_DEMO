// Fault-injection variant of tc_sram_impl_mod.sv, compiled instead of it with
// `run_vsim.sh --mbist-fault`. Same module name and ports, so croc_domain is unchanged.
//
// Differences from tc_sram_impl_mod.sv:
// - Only the configuration Croc uses (512 x 32 bit, 1 port, latency 1) is supported.
// - The SRAM core is the fault model (rtl/RM_IHPSG13_1P_core_behavioral_bm_bist_fault_model.v)
//   instantiated directly instead of the RM_IHPSG13_1P_256x64_c2_bm_bist wrapper, so the
//   fault masks from mbist_fault_cfg_pkg can be passed in.
// - Faults are enabled only in bank mbist_fault_cfg_pkg::FaultBank.

module tc_sram_impl #(
  parameter int unsigned NumWords     = 32'd1024,
  parameter int unsigned DataWidth    = 32'd128,
  parameter int unsigned ByteWidth    = 32'd8,
  parameter int unsigned NumPorts     = 32'd2,
  parameter int unsigned Latency      = 32'd1,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  parameter              ImplKey      = "none",
  parameter type         impl_in_t    = logic,
  parameter type         impl_out_t   = logic,
  parameter impl_out_t   ImplOutSim   = '0,
  parameter int unsigned FifoDepth    = 32'd2,  // Depth is 2**FifoDepth
  parameter bit          BistEnable   = 1'b1,
  parameter int unsigned BankIdx      = 32'd0,  // SRAM bank index, selects the faulty bank
  // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
  parameter int unsigned AddrWidth    = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth      = (DataWidth + ByteWidth - 32'd1) / ByteWidth,
  parameter type         addr_t       = logic [AddrWidth-1:0],
  parameter type         data_t       = logic [DataWidth-1:0],
  parameter type         be_t         = logic [BeWidth-1:0]
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  impl_in_t             impl_i,
  output impl_out_t            impl_o,

  input  logic  [NumPorts-1:0] req_i,
  input  logic  [NumPorts-1:0] we_i,
  input  addr_t [NumPorts-1:0] addr_i,
  input  data_t [NumPorts-1:0] wdata_i,
  input  be_t   [NumPorts-1:0] be_i,

  output data_t [NumPorts-1:0] rdata_o,

  input  logic                 mbist_start_i,
  input  logic                 mbist_resume_i,
  input  logic                 mbist_erraddrread_i,
  output logic  [3:0]          mbist_status_o,

  output addr_t                mbist_erraddr_o
);

  localparam P1L1    = (NumPorts == 1 & Latency == 1);
  localparam bit EnFault = (BankIdx == mbist_fault_cfg_pkg::FaultBank);

  // Assemble bit mask
  data_t [NumPorts-1:0] bm;

  for (genvar p = 0; p < NumPorts; ++p) begin : gen_bm_ports
      for (genvar b = 0; b < DataWidth; ++b) begin : gen_bm_bits
        assign bm[p][b] = be_i[p][b/ByteWidth];
      end
  end

  assign impl_o = ImplOutSim;

  //----------------- BIST Related Modules ------------------------
  logic [AddrWidth-1:0] march_addr;
  logic [DataWidth-1:0] march_wdata;
  logic [DataWidth-1:0] march_bitmask;
  logic                 march_memen;
  logic                 march_memwen;
  logic                 march_memren;
  logic [3:0]           march_status;
  logic                 march_bisten;

  logic [DataWidth-1:0] march_rdata;
  assign march_rdata    = rdata_o;
  assign mbist_status_o = march_status;

  march_bist_controller #(
     .DataWidth(DataWidth),
     .AddrWidth(AddrWidth),
     .FifoDepth(FifoDepth)
  ) u_bist_controller (
    .tclk_i           (clk_i),
    .trst_ni          (rst_ni),
    .start_i          (mbist_start_i       ),
    .resume_or_reset_i(mbist_resume_i      ),
    .erraddr_rd_i     (mbist_erraddrread_i ),
    .status_o         (march_status       ),
    .bist_en_o        (march_bisten       ),
    .rdata_i          (march_rdata        ),
    .memaddr_o        (march_addr         ),
    .wdata_o          (march_wdata        ),
    .memen_o          (march_memen        ),
    .memren_o         (march_memren       ),
    .memwen_o         (march_memwen       ),
    .membm_o          (march_bitmask      ),
    .mbist_erraddr_o  (mbist_erraddr_o    )
  );

  if (NumWords == 512 && DataWidth == 32 && P1L1) begin: gen_512x32xBx1
    logic [63:0] wdata64, rdata64, bm64;
    logic [63:0] wdata64_bist, bm64_bist;
    logic sel_d, sel_q;

    // muxing neighboring bits instead of upper/lower 32bit reduces routing
    always_comb begin : gen_bit_interleaving
      for (int i = 0; i < 32; i++) begin
          wdata64[2*i]   = wdata_i[0][i]; // even bits (active if addr LSB is 0)
          bm64[2*i]      = bm[0][i] & ~addr_i[0][0];
          wdata64[2*i+1] = wdata_i[0][i]; // odd bits  (active if addr LSB is 1)
          bm64[2*i+1]    = bm[0][i] & addr_i[0][0];

          wdata64_bist[2*i]   = march_wdata[i];
          bm64_bist[2*i]      = march_bitmask[i] & ~march_addr[0];
          wdata64_bist[2*i+1] = march_wdata[i];
          bm64_bist[2*i+1]    = march_bitmask[i] & march_addr[0];

          if(~sel_q) begin
            rdata_o[0][i] = rdata64[2*i];   // even bits
          end else begin
            rdata_o[0][i] = rdata64[2*i+1]; // odd bits
          end
      end
    end

    // LSB needed for read in next cycle
    assign sel_d = march_bisten ? march_addr[0]: addr_i[0][0];

    logic sel_en;
    assign sel_en = march_bisten ? march_memren : (req_i & ~we_i);

    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_mem_sel_q
      if(~rst_ni)      sel_q <= '0;
      else if (sel_en) sel_q <= sel_d;
    end

    SRAM_1P_behavioral_bm_bist #(
      .P_DATA_WIDTH       ( 64 ),
      .P_ADDR_WIDTH       ( 8  ),
      .EN_FAULT_INJECTION ( EnFault                        ),
      .MASK_SAF_0         ( mbist_fault_cfg_pkg::MASK_SAF_0 ),
      .MASK_SAF_1         ( mbist_fault_cfg_pkg::MASK_SAF_1 ),
      .MASK_TF_01         ( mbist_fault_cfg_pkg::MASK_TF_01 ),
      .MASK_TF_10         ( mbist_fault_cfg_pkg::MASK_TF_10 ),
      .MASK_RDF           ( mbist_fault_cfg_pkg::MASK_RDF   ),
      .MASK_IRF           ( mbist_fault_cfg_pkg::MASK_IRF   ),
      .MASK_DRDF          ( mbist_fault_cfg_pkg::MASK_DRDF  ),
      .MASK_WDF           ( mbist_fault_cfg_pkg::MASK_WDF   )
    ) i_cut (
      .A_CLK        ( clk_i            ),
      .A_DLY        ( impl_i           ),
      .A_ADDR       ( addr_i [0][8:1]  ),
      .A_BM         ( bm64             ),
      .A_MEN        ( req_i            ),
      .A_WEN        ( we_i             ),
      .A_REN        ( ~we_i            ),
      .A_DIN        ( wdata64          ),
      .A_DOUT       ( rdata64          ),
      .A_BIST_CLK   ( clk_i            ),
      .A_BIST_ADDR  ( march_addr[8:1]  ),
      .A_BIST_DIN   ( wdata64_bist     ),
      .A_BIST_BM    ( bm64_bist        ),
      .A_BIST_MEN   ( march_memen      ),
      .A_BIST_WEN   ( march_memwen     ),
      .A_BIST_REN   ( march_memren     ),
      .A_BIST_EN    ( march_bisten     )
    );

    initial if (EnFault) $display("[MBIST-FAULT] %m: fault injection ENABLED (bank %0d)", BankIdx);

  end else begin : gen_unsupported
    initial $fatal(1, "tc_sram_impl_fault %m: only 512x32, 1 port, latency 1 is supported (got %0dx%0d)",
                   NumWords, DataWidth);
  end

endmodule
