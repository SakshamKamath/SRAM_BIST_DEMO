// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

module croc_chip import croc_pkg::*; #() (
  input  wire clk_i,
  input  wire rst_ni,
  input  wire ref_clk_i,

  input  wire jtag_tck_i,
  input  wire jtag_trst_ni,
  input  wire jtag_tms_i,
  input  wire jtag_tdi_i,
  output wire jtag_tdo_o,

  input  wire uart_rx_i,
  output wire uart_tx_o,

  input  wire testmode_i,
  output wire status_o,

  inout  wire gpio0_io,
  inout  wire gpio1_io,
  inout  wire gpio2_io,
  inout  wire gpio3_io,
  inout  wire gpio4_io,
  inout  wire gpio5_io,
  inout  wire gpio6_io,
  inout  wire gpio7_io,
  inout  wire gpio8_io,
  inout  wire gpio9_io,
  inout  wire gpio10_io,
  inout  wire gpio11_io,
  inout  wire gpio12_io,
  inout  wire gpio13_io,
  inout  wire gpio14_io,
  inout  wire gpio15_io,
  inout  wire gpio16_io,
  inout  wire gpio17_io,
  inout  wire gpio18_io,
  inout  wire gpio19_io,
  inout  wire gpio20_io,
  inout  wire gpio21_io,
  inout  wire gpio22_io,
  inout  wire gpio23_io,
  inout  wire gpio24_io,
  inout  wire gpio25_io,
  inout  wire gpio26_io,
  inout  wire gpio27_io,
  inout  wire gpio28_io,
  inout  wire gpio29_io,
  inout  wire gpio30_io,
  inout  wire gpio31_io,
  output wire unused0_o,
  output wire unused1_o,
  output wire unused2_o,
  output wire unused3_o,

  inout wire VDD,
  inout wire VSS,
  inout wire VDDIO,
  inout wire VSSIO
);

    localparam int unsigned GpioCount     = 32;
    localparam int unsigned UnusedCount   = 4;
    localparam int unsigned SingleInputs  = 2; // uart_rx_i, testmode_i
    localparam int unsigned SingleOutputs = 2; // status_o, uart_tx_o

    // Direct inputs/outputs excluding power, dedicated JTAG pins, clk & reset
    localparam int unsigned BndScanPadCount = SingleInputs + SingleOutputs + GpioCount + UnusedCount;

    // Fixed slot ordering within the BndScanPadCount-wide vectors
    localparam int unsigned InOfs     = 0;
    localparam int unsigned OutOfs    = InOfs     + SingleInputs;   // 2
    localparam int unsigned UnusedOfs = OutOfs    + SingleOutputs;  // 4
    localparam int unsigned GpioOfs   = UnusedOfs + UnusedCount;    // 8
    // GpioOfs + GpioCount == BndScanPadCount  (8 + 32 = 40)


    logic soc_clk_i;
    logic soc_rst_ni;
    logic soc_ref_clk_i;
    logic soc_testmode_i;

    logic soc_uart_rx_i;
    logic core_uart_tx_o;

    logic soc_jtag_tck_i;
    logic soc_jtag_trst_ni;
    logic soc_jtag_tms_i;
    logic soc_jtag_tdi_i;
    logic soc_jtag_tdo_o;

    logic soc_status_o;
    logic core_status_o;

    logic [GpioCount-1:0] soc_gpio_i;
    logic [GpioCount-1:0] soc_gpio_o;
    logic [GpioCount-1:0] core_gpio_o;
    logic [GpioCount-1:0] core_gpio_out_en_o; // Output enable signal; 0 -> input, 1 -> output



    // Creating vector mappings and relevant bus mapping

    // Gpio Bus
    wire [GpioCount-1:0] gpio_io_bus = {
    gpio31_io, gpio30_io, gpio29_io, gpio28_io, gpio27_io, gpio26_io, gpio25_io, gpio24_io,
    gpio23_io, gpio22_io, gpio21_io, gpio20_io, gpio19_io, gpio18_io, gpio17_io, gpio16_io,
    gpio15_io, gpio14_io, gpio13_io, gpio12_io, gpio11_io, gpio10_io, gpio9_io,  gpio8_io,
    gpio7_io,  gpio6_io,  gpio5_io,  gpio4_io,  gpio3_io,  gpio2_io,  gpio1_io,  gpio0_io
    };

    wire [UnusedCount-1:0] unused_o_bus;

    pad_dir_t    [BndScanPadCount-1:0] pad_cfg;          // Static Direction configuration
    pad_signal_t [BndScanPadCount-1:0] pad_to_bndscan;   // Core outputs & Pad inputs -> BNDSCAN
    pad_signal_t [BndScanPadCount-1:0] pad_from_bndscan; // BNDSCAN outputs -> Pads & Core

    // To understand the type of IOPad (Not how it is configured)
    assign pad_cfg[InOfs     +: SingleInputs]  = '{SingleInputs{PAD_IN}};
    assign pad_cfg[OutOfs    +: SingleOutputs] = '{SingleOutputs{PAD_OUT}};
    assign pad_cfg[UnusedOfs +: UnusedCount]   = '{UnusedCount{PAD_OUT}};

    for (genvar i = 0; i < GpioCount; i++) begin
      assign pad_cfg[GpioOfs + i] = pad_dir_t'(core_gpio_out_en_o[i]);
    end

    // -- Single inputs (only p2c meaningful) --
    assign pad_to_bndscan[InOfs+0].p2c    = soc_uart_rx_i;
    assign pad_to_bndscan[InOfs+1].p2c    = soc_testmode_i;

    // -- Single outputs (only c2p meaningful) --
    assign pad_to_bndscan[OutOfs+0].c2p    = core_uart_tx_o;
    assign pad_to_bndscan[OutOfs+1].c2p    = core_status_o;

    // -- Unused outputs --
    for (genvar i = 0; i < UnusedCount; i++) begin : gen_unused_pack
      assign pad_to_bndscan[UnusedOfs+i].c2p    = core_status_o;
    end

    // -- GPIOs (bidirectional) --
    // pad_signal_t is a packed union (p2c and c2p are the same bit), so select the
    // direction at runtime from the output enable. (A generate-if on pad_cfg cannot work:
    // it depends on core_gpio_out_en_o.)
    for (genvar i = 0; i < GpioCount; i++) begin : gen_gpio_pack
      assign pad_to_bndscan[GpioOfs+i].c2p = core_gpio_out_en_o[i] ? core_gpio_o[i] : soc_gpio_i[i];
    end


    logic core_uart_rx_i, core_testmode_i;
    assign core_uart_rx_i  = pad_from_bndscan[InOfs+0].p2c;
    assign core_testmode_i = pad_from_bndscan[InOfs+1].p2c;
  
    assign soc_uart_tx_o = pad_from_bndscan[OutOfs+0].c2p;
    assign soc_status_o  = pad_from_bndscan[OutOfs+1].c2p;

    for (genvar i = 0; i < UnusedCount; i++) begin : gen_unused_unpack
      assign unused_o_bus[i] = pad_from_bndscan[UnusedOfs+i].c2p;
    end

    logic [GpioCount-1:0] core_gpio_i;
    // Both directions pass through; the pad's c2p_en (core_gpio_out_en_o) decides which is used.
    for (genvar i = 0; i < GpioCount; i++) begin : gen_gpio_unpack
      assign core_gpio_i[i]       = pad_from_bndscan[GpioOfs+i].p2c;
      assign soc_gpio_o[i]        = pad_from_bndscan[GpioOfs+i].c2p;
    end



    // Boundary Scan Chain
    logic daisy_scan_chain;  // To connect the bndscan chain for IOPads with Croc SoC

    bndscan_jtag_top #(
    .NumIOPads ( BndScanPadCount ),
    .IrWidth   ( 4               ),
    .PadType_t ( pad_signal_t    ),
    .PadDir_t  ( pad_dir_t       )
  ) i_bndscan_jtag_top (
    .clk_i      ( soc_clk_i         ),
    .rst_ni     ( soc_rst_ni        ),
    .testmode_i ( soc_testmode_i    ),

    // Standard Dedicated JTAG TAP connection directly from chip pins
    .trst_ni    ( soc_jtag_trst_ni  ),
    .tclk_i     ( soc_jtag_tck_i    ),
    .tdi_i      ( soc_jtag_tdi_i    ),
    .tms_i      ( soc_jtag_tms_i    ),
    .tdo_o      ( daisy_scan_chain  ),

    .PadCfg_i   ( pad_cfg           ),
    .PadCnct_i  ( pad_to_bndscan    ), // From Core out to physical Pads
    .PadCnct_o  ( pad_from_bndscan  )  // From Physical Pads back to Core
  );




    // Physical PADS



    sg13cmos5l_IOPadIn        pad_clk_i        (.pad(clk_i),        .p2c(soc_clk_i));
    sg13cmos5l_IOPadIn        pad_rst_ni       (.pad(rst_ni),       .p2c(soc_rst_ni));
    sg13cmos5l_IOPadIn        pad_ref_clk_i    (.pad(ref_clk_i),    .p2c(soc_ref_clk_i));
    sg13cmos5l_IOPadIn        pad_jtag_tck_i   (.pad(jtag_tck_i),   .p2c(soc_jtag_tck_i));
    sg13cmos5l_IOPadIn        pad_jtag_trst_ni (.pad(jtag_trst_ni), .p2c(soc_jtag_trst_ni));
    sg13cmos5l_IOPadIn        pad_jtag_tms_i   (.pad(jtag_tms_i),   .p2c(soc_jtag_tms_i));
    sg13cmos5l_IOPadIn        pad_jtag_tdi_i   (.pad(jtag_tdi_i),   .p2c(soc_jtag_tdi_i));
    sg13cmos5l_IOPadOut16mA   pad_jtag_tdo_o   (.pad(jtag_tdo_o),   .c2p(soc_jtag_tdo_o));

    sg13cmos5l_IOPadIn        pad_uart_rx_i    (.pad(uart_rx_i),  .p2c(soc_uart_rx_i));
    sg13cmos5l_IOPadOut16mA   pad_uart_tx_o    (.pad(uart_tx_o),  .c2p(soc_uart_tx_o));

    sg13cmos5l_IOPadIn        pad_testmode_i   (.pad(testmode_i), .p2c(soc_testmode_i));
    sg13cmos5l_IOPadOut16mA   pad_status_o     (.pad(status_o),   .c2p(soc_status_o));

    sg13cmos5l_IOPadInOut30mA pad_gpio0_io     (.pad(gpio0_io),  .c2p(soc_gpio_o[0]),  .p2c(soc_gpio_i[0]),  .c2p_en(core_gpio_out_en_o[0]));
    sg13cmos5l_IOPadInOut30mA pad_gpio1_io     (.pad(gpio1_io),  .c2p(soc_gpio_o[1]),  .p2c(soc_gpio_i[1]),  .c2p_en(core_gpio_out_en_o[1]));
    sg13cmos5l_IOPadInOut30mA pad_gpio2_io     (.pad(gpio2_io),  .c2p(soc_gpio_o[2]),  .p2c(soc_gpio_i[2]),  .c2p_en(core_gpio_out_en_o[2]));
    sg13cmos5l_IOPadInOut30mA pad_gpio3_io     (.pad(gpio3_io),  .c2p(soc_gpio_o[3]),  .p2c(soc_gpio_i[3]),  .c2p_en(core_gpio_out_en_o[3]));
    sg13cmos5l_IOPadInOut30mA pad_gpio4_io     (.pad(gpio4_io),  .c2p(soc_gpio_o[4]),  .p2c(soc_gpio_i[4]),  .c2p_en(core_gpio_out_en_o[4]));
    sg13cmos5l_IOPadInOut30mA pad_gpio5_io     (.pad(gpio5_io),  .c2p(soc_gpio_o[5]),  .p2c(soc_gpio_i[5]),  .c2p_en(core_gpio_out_en_o[5]));
    sg13cmos5l_IOPadInOut30mA pad_gpio6_io     (.pad(gpio6_io),  .c2p(soc_gpio_o[6]),  .p2c(soc_gpio_i[6]),  .c2p_en(core_gpio_out_en_o[6]));
    sg13cmos5l_IOPadInOut30mA pad_gpio7_io     (.pad(gpio7_io),  .c2p(soc_gpio_o[7]),  .p2c(soc_gpio_i[7]),  .c2p_en(core_gpio_out_en_o[7]));
    sg13cmos5l_IOPadInOut30mA pad_gpio8_io     (.pad(gpio8_io),  .c2p(soc_gpio_o[8]),  .p2c(soc_gpio_i[8]),  .c2p_en(core_gpio_out_en_o[8]));
    sg13cmos5l_IOPadInOut30mA pad_gpio9_io     (.pad(gpio9_io),  .c2p(soc_gpio_o[9]),  .p2c(soc_gpio_i[9]),  .c2p_en(core_gpio_out_en_o[9]));
    sg13cmos5l_IOPadInOut30mA pad_gpio10_io    (.pad(gpio10_io), .c2p(soc_gpio_o[10]), .p2c(soc_gpio_i[10]), .c2p_en(core_gpio_out_en_o[10]));
    sg13cmos5l_IOPadInOut30mA pad_gpio11_io    (.pad(gpio11_io), .c2p(soc_gpio_o[11]), .p2c(soc_gpio_i[11]), .c2p_en(core_gpio_out_en_o[11]));
    sg13cmos5l_IOPadInOut30mA pad_gpio12_io    (.pad(gpio12_io), .c2p(soc_gpio_o[12]), .p2c(soc_gpio_i[12]), .c2p_en(core_gpio_out_en_o[12]));
    sg13cmos5l_IOPadInOut30mA pad_gpio13_io    (.pad(gpio13_io), .c2p(soc_gpio_o[13]), .p2c(soc_gpio_i[13]), .c2p_en(core_gpio_out_en_o[13]));
    sg13cmos5l_IOPadInOut30mA pad_gpio14_io    (.pad(gpio14_io), .c2p(soc_gpio_o[14]), .p2c(soc_gpio_i[14]), .c2p_en(core_gpio_out_en_o[14]));
    sg13cmos5l_IOPadInOut30mA pad_gpio15_io    (.pad(gpio15_io), .c2p(soc_gpio_o[15]), .p2c(soc_gpio_i[15]), .c2p_en(core_gpio_out_en_o[15]));
    sg13cmos5l_IOPadInOut30mA pad_gpio16_io    (.pad(gpio16_io), .c2p(soc_gpio_o[16]), .p2c(soc_gpio_i[16]), .c2p_en(core_gpio_out_en_o[16]));
    sg13cmos5l_IOPadInOut30mA pad_gpio17_io    (.pad(gpio17_io), .c2p(soc_gpio_o[17]), .p2c(soc_gpio_i[17]), .c2p_en(core_gpio_out_en_o[17]));
    sg13cmos5l_IOPadInOut30mA pad_gpio18_io    (.pad(gpio18_io), .c2p(soc_gpio_o[18]), .p2c(soc_gpio_i[18]), .c2p_en(core_gpio_out_en_o[18]));
    sg13cmos5l_IOPadInOut30mA pad_gpio19_io    (.pad(gpio19_io), .c2p(soc_gpio_o[19]), .p2c(soc_gpio_i[19]), .c2p_en(core_gpio_out_en_o[19]));
    sg13cmos5l_IOPadInOut30mA pad_gpio20_io    (.pad(gpio20_io), .c2p(soc_gpio_o[20]), .p2c(soc_gpio_i[20]), .c2p_en(core_gpio_out_en_o[20]));
    sg13cmos5l_IOPadInOut30mA pad_gpio21_io    (.pad(gpio21_io), .c2p(soc_gpio_o[21]), .p2c(soc_gpio_i[21]), .c2p_en(core_gpio_out_en_o[21]));
    sg13cmos5l_IOPadInOut30mA pad_gpio22_io    (.pad(gpio22_io), .c2p(soc_gpio_o[22]), .p2c(soc_gpio_i[22]), .c2p_en(core_gpio_out_en_o[22]));
    sg13cmos5l_IOPadInOut30mA pad_gpio23_io    (.pad(gpio23_io), .c2p(soc_gpio_o[23]), .p2c(soc_gpio_i[23]), .c2p_en(core_gpio_out_en_o[23]));
    sg13cmos5l_IOPadInOut30mA pad_gpio24_io    (.pad(gpio24_io), .c2p(soc_gpio_o[24]), .p2c(soc_gpio_i[24]), .c2p_en(core_gpio_out_en_o[24]));
    sg13cmos5l_IOPadInOut30mA pad_gpio25_io    (.pad(gpio25_io), .c2p(soc_gpio_o[25]), .p2c(soc_gpio_i[25]), .c2p_en(core_gpio_out_en_o[25]));
    sg13cmos5l_IOPadInOut30mA pad_gpio26_io    (.pad(gpio26_io), .c2p(soc_gpio_o[26]), .p2c(soc_gpio_i[26]), .c2p_en(core_gpio_out_en_o[26]));
    sg13cmos5l_IOPadInOut30mA pad_gpio27_io    (.pad(gpio27_io), .c2p(soc_gpio_o[27]), .p2c(soc_gpio_i[27]), .c2p_en(core_gpio_out_en_o[27]));
    sg13cmos5l_IOPadInOut30mA pad_gpio28_io    (.pad(gpio28_io), .c2p(soc_gpio_o[28]), .p2c(soc_gpio_i[28]), .c2p_en(core_gpio_out_en_o[28]));
    sg13cmos5l_IOPadInOut30mA pad_gpio29_io    (.pad(gpio29_io), .c2p(soc_gpio_o[29]), .p2c(soc_gpio_i[29]), .c2p_en(core_gpio_out_en_o[29]));
    sg13cmos5l_IOPadInOut30mA pad_gpio30_io    (.pad(gpio30_io), .c2p(soc_gpio_o[30]), .p2c(soc_gpio_i[30]), .c2p_en(core_gpio_out_en_o[30]));
    sg13cmos5l_IOPadInOut30mA pad_gpio31_io    (.pad(gpio31_io), .c2p(soc_gpio_o[31]), .p2c(soc_gpio_i[31]), .c2p_en(core_gpio_out_en_o[31]));
    // sg13cmos5l_IOPadOut16mA   pad_unused0_o    (.pad(unused0_o), .c2p(soc_status_o));
    // sg13cmos5l_IOPadOut16mA   pad_unused1_o    (.pad(unused1_o), .c2p(soc_status_o));
    // sg13cmos5l_IOPadOut16mA   pad_unused2_o    (.pad(unused2_o), .c2p(soc_status_o));
    // sg13cmos5l_IOPadOut16mA   pad_unused3_o    (.pad(unused3_o), .c2p(soc_status_o));
    sg13cmos5l_IOPadOut16mA   pad_unused0_o    (.pad(unused0_o), .c2p(unused_o_bus[0]));
    sg13cmos5l_IOPadOut16mA   pad_unused1_o    (.pad(unused1_o), .c2p(unused_o_bus[1]));
    sg13cmos5l_IOPadOut16mA   pad_unused2_o    (.pad(unused2_o), .c2p(unused_o_bus[2]));
    sg13cmos5l_IOPadOut16mA   pad_unused3_o    (.pad(unused3_o), .c2p(unused_o_bus[3]));

    (* dont_touch = "true" *)sg13cmos5l_IOPadVdd pad_vdd0();
    (* dont_touch = "true" *)sg13cmos5l_IOPadVdd pad_vdd1();
    (* dont_touch = "true" *)sg13cmos5l_IOPadVdd pad_vdd2();
    (* dont_touch = "true" *)sg13cmos5l_IOPadVdd pad_vdd3();

    (* dont_touch = "true" *)sg13cmos5l_IOPadVss pad_vss0();
    (* dont_touch = "true" *)sg13cmos5l_IOPadVss pad_vss1();
    (* dont_touch = "true" *)sg13cmos5l_IOPadVss pad_vss2();
    (* dont_touch = "true" *)sg13cmos5l_IOPadVss pad_vss3();

    (* dont_touch = "true" *)sg13cmos5l_IOPadIOVdd pad_vddio0();
    (* dont_touch = "true" *)sg13cmos5l_IOPadIOVdd pad_vddio1();
    (* dont_touch = "true" *)sg13cmos5l_IOPadIOVdd pad_vddio2();
    (* dont_touch = "true" *)sg13cmos5l_IOPadIOVdd pad_vddio3();

    (* dont_touch = "true" *)sg13cmos5l_IOPadIOVss pad_vssio0();
    (* dont_touch = "true" *)sg13cmos5l_IOPadIOVss pad_vssio1();
    (* dont_touch = "true" *)sg13cmos5l_IOPadIOVss pad_vssio2();
    (* dont_touch = "true" *)sg13cmos5l_IOPadIOVss pad_vssio3();

  croc_soc #(
    .GpioCount( GpioCount )
  )
  i_croc_soc (
    .clk_i          ( soc_clk_i      ),
    .rst_ni         ( soc_rst_ni     ),
    .ref_clk_i      ( soc_ref_clk_i  ),
    .testmode_i     ( soc_testmode_i ),
    .status_o       ( core_status_o  ),

    .jtag_tck_i     ( soc_jtag_tck_i   ),
    .jtag_tdi_i     ( daisy_scan_chain ),
    .jtag_tdo_o     ( soc_jtag_tdo_o   ),
    .jtag_tms_i     ( soc_jtag_tms_i   ),
    .jtag_trst_ni   ( soc_jtag_trst_ni ),

    .uart_rx_i      ( core_uart_rx_i ),
    .uart_tx_o      ( core_uart_tx_o ),

    .gpio_i         ( core_gpio_i        ),
    .gpio_o         ( core_gpio_o        ),
    .gpio_out_en_o  ( core_gpio_out_en_o ),

    // TODO: VAD I2S pins have no pads yet; data tied low until a pad is assigned
    .vad_i2s_sclk_o (                    ),
    .vad_i2s_wsel_o (                    ),
    .vad_i2s_sdat_i ( 1'b0               )
  );

endmodule
