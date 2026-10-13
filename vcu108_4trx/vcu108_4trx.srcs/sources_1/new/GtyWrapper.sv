//------------------------------------------------------------------------------
//  (c) Copyright 2023 Advanced Micro Devices, Inc. All rights reserved.
//
//  This file contains confidential and proprietary information
//  of AMD, Inc. and is protected under U.S. and
//  international copyright and other intellectual property
//  laws.
//
//  DISCLAIMER
//  This disclaimer is not a license and does not grant any
//  rights to the materials distributed herewith. Except as
//  otherwise provided in a valid license issued to you by
//  AMD, and to the maximum extent permitted by applicable
//  law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
//  WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
//  AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
//  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
//  INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
//  (2) AMD shall not be liable (whether in contract or tort,
//  including negligence, or under any other theory of
//  liability) for any loss or damage of any kind or nature
//  related to, arising under or in connection with these
//  materials, including for any direct, or any indirect,
//  special, incidental, or consequential loss or damage
//  (including loss of data, profits, goodwill, or any type of
//  loss or damage suffered as a result of any action brought
//  by a third party) even if such damage or loss was
//  reasonably foreseeable or AMD had been advised of the
//  possibility of the same.
//
//  CRITICAL APPLICATIONS
//  AMD products are not designed or intended to be fail-
//  safe, or for use in any application requiring fail-safe
//  performance, such as life-support or safety devices or
//  systems, Class III medical devices, nuclear facilities,
//  applications related to the deployment of airbags, or any
//  other applications that could lead to death, personal
//  injury, or severe property or environmental damage
//  (individually and collectively, "Critical
//  Applications"). Customer assumes the sole risk and
//  liability of any use of AMD products in Critical
//  Applications, subject only to applicable laws and
//  regulations governing limitations on product liability.
//
//  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
//  PART OF THIS FILE AT ALL TIMES.
//------------------------------------------------------------------------------


`timescale 1ps/1ps

// =====================================================================================================================
// This example design wrapper module instantiates the core and any helper blocks which the user chose to exclude from
// the core, connects them as appropriate, and maps enabled ports
// =====================================================================================================================

module GtyWrapper (
  input  logic [  3:0] gtyrxn_in                         ,
  input  logic [  3:0] gtyrxp_in                         ,
  output logic [  3:0] gtytxn_out                        ,
  output logic [  3:0] gtytxp_out                        ,
  input  logic [  3:0] gtwiz_userclk_tx_reset_in         ,
  output logic [  3:0] gtwiz_userclk_tx_srcclk_out       ,
  output logic [  3:0] gtwiz_userclk_tx_usrclk_out       ,
  output logic [  3:0] gtwiz_userclk_tx_usrclk2_out      ,
  output logic [  3:0] gtwiz_userclk_tx_active_out       ,
  input  logic [  3:0] gtwiz_userclk_rx_reset_in         ,
  output logic [  3:0] gtwiz_userclk_rx_srcclk_out       ,
  output logic [  3:0] gtwiz_userclk_rx_usrclk_out       ,
  output logic [  3:0] gtwiz_userclk_rx_usrclk2_out      ,
  output logic [  3:0] gtwiz_userclk_rx_active_out       ,
  input  logic [  3:0] gtwiz_buffbypass_rx_reset_in      ,
  input  logic [  3:0] gtwiz_buffbypass_rx_start_user_in ,
  output logic [  3:0] gtwiz_buffbypass_rx_done_out      ,
  output logic [  3:0] gtwiz_buffbypass_rx_error_out     ,
  input  logic [  0:0] gtwiz_reset_clk_freerun_in        ,
  input  logic [  0:0] gtwiz_reset_all_in                ,
  input  logic [  0:0] gtwiz_reset_tx_pll_and_datapath_in,
  input  logic [  0:0] gtwiz_reset_tx_datapath_in        ,
  input  logic [  0:0] gtwiz_reset_rx_pll_and_datapath_in,
  input  logic [  0:0] gtwiz_reset_rx_datapath_in        ,
  output logic [  0:0] gtwiz_reset_rx_cdr_stable_out     ,
  output logic [  3:0] gtwiz_reset_tx_done_out           ,
  output logic [  3:0] gtwiz_reset_rx_done_out           ,
  input  logic [319:0] gtwiz_userdata_tx_in              ,
  output logic [319:0] gtwiz_userdata_rx_out             ,
  input  logic [  0:0] gtrefclk00_in                     ,
  output logic [  0:0] qpll0outclk_out                   ,
  output logic [  0:0] qpll0outrefclk_out                ,
  output logic [  0:0] qpll0locked_out                   ,
  output logic [  0:0] qpll1outclk_out                   ,
  output logic [  0:0] qpll1outrefclk_out                ,
  output logic [  0:0] qpll1locked_out                   ,
  input  logic [  3:0] dmonitorclk_in                    ,
  input  logic [ 39:0] drpaddr_in                        ,
  input  logic [  3:0] drpclk_in                         ,
  input  logic [ 63:0] drpdi_in                          ,
  input  logic [  3:0] drpen_in                          ,
  input  logic [  3:0] drpwe_in                          ,
  input  logic [  3:0] eyescanreset_in                   ,
  input  logic [  3:0] rxcdrhold_in                      ,
  input  logic [  3:0] rxcdrovrden_in                    ,
  input  logic [  3:0] rxdfelpmreset_in                  ,
  input  logic [  3:0] rxlpmen_in                        ,
  input  logic [ 11:0] rxrate_in                         ,
  input  logic [ 19:0] txdiffctrl_in                     ,
  input  logic [  3:0] txinhibit_in                      ,
  input  logic [  3:0] txpippmen_in                      ,
  input  logic [  3:0] txpippmovrden_in                  ,
  input  logic [  3:0] txpippmpd_in                      ,
  input  logic [  3:0] txpippmsel_in                     ,
  input  logic [ 19:0] txpippmstepsize_in                ,
  input  logic [ 19:0] txpostcursor_in                   ,
  input  logic [ 15:0] txprbssel_in                      ,
  input  logic [ 19:0] txprecursor_in                    ,
  input  logic [ 11:0] txrate_in                         ,
  output logic [ 67:0] dmonitorout_out                   ,
  output logic [ 63:0] drpdo_out                         ,
  output logic [  3:0] drprdy_out                        ,
  output logic [  3:0] gtpowergood_out                   ,
  output logic [  3:0] rxpmaresetdone_out                ,
  output logic [  3:0] txpmaresetdone_out
);


  // ===================================================================================================================
  // PARAMETERS AND FUNCTIONS
  // ===================================================================================================================

  // Declare and initialize local parameters and functions used for HDL generation
  localparam [191:0] P_CHANNEL_ENABLE = 192'h000000000000000000000000000000F00;
  `include "GtyWrapperFunctions.sv"
  localparam integer P_TX_MASTER_CH_PACKED_IDX = f_calc_pk_mc_idx(8);
  localparam integer P_RX_MASTER_CH_PACKED_IDX = f_calc_pk_mc_idx(8);


  // ===================================================================================================================
  // HELPER BLOCKS
  // ===================================================================================================================

  // Any helper blocks which the user chose to exclude from the core will appear below. In addition, some signal
  // assignments related to optionally-enabled ports may appear below.

  // -------------------------------------------------------------------------------------------------------------------
  // Transmitter user clocking network helper block
  // -------------------------------------------------------------------------------------------------------------------

  /*logic [3:0] txusrclk_int ;
  logic [3:0] txusrclk2_int;
  logic [3:0] txoutclk_int ;

  // Generate a single module instance which is driven by a clock source associated with the master transmitter channel,
  // and which drives TXUSRCLK and TXUSRCLK2 for all channels

  // The source clock is TXOUTCLK from the master transmitter channel
  assign gtwiz_userclk_tx_srcclk_out = txoutclk_int[P_TX_MASTER_CH_PACKED_IDX];

  // Instantiate a single instance of the transmitter user clocking network helper block
  GtyUserclkTx GtyUserclkTx_inst (
    .gtwiz_userclk_tx_srcclk_in  (gtwiz_userclk_tx_srcclk_out ),
    .gtwiz_userclk_tx_reset_in   (gtwiz_userclk_tx_reset_in   ),
    .gtwiz_userclk_tx_usrclk_out (gtwiz_userclk_tx_usrclk_out ),
    .gtwiz_userclk_tx_usrclk2_out(gtwiz_userclk_tx_usrclk2_out),
    .gtwiz_userclk_tx_active_out (gtwiz_userclk_tx_active_out )
  );

  // Drive TXUSRCLK and TXUSRCLK2 for all channels with the respective helper block outputs
  assign txusrclk_int  = {4{gtwiz_userclk_tx_usrclk_out}};
  assign txusrclk2_int = {4{gtwiz_userclk_tx_usrclk2_out}};*/

  logic [3:0] txusrclk_int ;
  logic [3:0] txusrclk2_int;
  logic [3:0] txoutclk_int ;

  // For each channel, generate one module instance which is driven by a clock source associated with that channel, and
  // which drives TXUSRCLK and TXUSRCLK2 for that same channel

  // Instantiate one instance of the receiver user clocking network helper block for each channel
  genvar gi_hb_txclk;
  generate 
    for (gi_hb_txclk = 0; gi_hb_txclk < 4; gi_hb_txclk = gi_hb_txclk + 1) begin : gen_gtwiz_userclk_tx

      // The source clock for a given instance is TXOUTCLK from the associated channel
      assign gtwiz_userclk_tx_srcclk_out[gi_hb_txclk] = txoutclk_int[gi_hb_txclk];

      GtyUserclkTx GtyUserclkTx_inst (
        .gtwiz_userclk_tx_srcclk_in  (gtwiz_userclk_tx_srcclk_out  [gi_hb_txclk]),
        .gtwiz_userclk_tx_reset_in   (gtwiz_userclk_tx_reset_in    [gi_hb_txclk]),
        .gtwiz_userclk_tx_usrclk_out (gtwiz_userclk_tx_usrclk_out  [gi_hb_txclk]),
        .gtwiz_userclk_tx_usrclk2_out(gtwiz_userclk_tx_usrclk2_out [gi_hb_txclk]),
        .gtwiz_userclk_tx_active_out (gtwiz_userclk_tx_active_out  [gi_hb_txclk])
      );
    end
  endgenerate

  // Drive TXUSRCLK and TXUSRCLK2 for all channels with the respective helper block outputs
  assign txusrclk_int  = gtwiz_userclk_tx_usrclk_out;
  assign txusrclk2_int = gtwiz_userclk_tx_usrclk2_out;

  // -------------------------------------------------------------------------------------------------------------------
  // Receiver user clocking network helper block
  // -------------------------------------------------------------------------------------------------------------------

  logic [3:0] rxusrclk_int ;
  logic [3:0] rxusrclk2_int;
  logic [3:0] rxoutclk_int ;

  // For each channel, generate one module instance which is driven by a clock source associated with that channel, and
  // which drives RXUSRCLK and RXUSRCLK2 for that same channel

  // Instantiate one instance of the receiver user clocking network helper block for each channel
  genvar gi_hb_rxclk;
  generate 
    for (gi_hb_rxclk = 0; gi_hb_rxclk < 4; gi_hb_rxclk = gi_hb_rxclk + 1) begin : gen_gtwiz_userclk_rx

      // The source clock for a given instance is RXOUTCLK from the associated channel
      assign gtwiz_userclk_rx_srcclk_out[gi_hb_rxclk] = rxoutclk_int[gi_hb_rxclk];

      GtyUserclkRx GtyUserclkRx_inst (
        .gtwiz_userclk_rx_srcclk_in  (gtwiz_userclk_rx_srcclk_out  [gi_hb_rxclk]),
        .gtwiz_userclk_rx_reset_in   (gtwiz_userclk_rx_reset_in    [gi_hb_rxclk]),
        .gtwiz_userclk_rx_usrclk_out (gtwiz_userclk_rx_usrclk_out  [gi_hb_rxclk]),
        .gtwiz_userclk_rx_usrclk2_out(gtwiz_userclk_rx_usrclk2_out [gi_hb_rxclk]),
        .gtwiz_userclk_rx_active_out (gtwiz_userclk_rx_active_out  [gi_hb_rxclk])
      );
    end
  endgenerate

  // Drive RXUSRCLK and RXUSRCLK2 for each channel with the respective outputs of the associated helper block
  assign rxusrclk_int  = gtwiz_userclk_rx_usrclk_out;
  assign rxusrclk2_int = gtwiz_userclk_rx_usrclk2_out;

  // -------------------------------------------------------------------------------------------------------------------
  // Receiver buffer bypass controller helper block
  // -------------------------------------------------------------------------------------------------------------------

  logic [3:0] rxphaligndone_int  ;
  logic [3:0] rxdlysresetdone_int;
  logic [3:0] rxsyncout_int      ;
  logic [3:0] rxsyncdone_int     ;
  logic [3:0] rxphdlyreset_int   ;
  logic [3:0] rxphalign_int      ;
  logic [3:0] rxphalignen_int    ;
  logic [3:0] rxphdlypd_int      ;
  logic [3:0] rxphovrden_int     ;
  logic [3:0] rxdlysreset_int    ;
  logic [3:0] rxdlybypass_int    ;
  logic [3:0] rxdlyen_int        ;
  logic [3:0] rxdlyovrden_int    ;
  logic [3:0] rxsyncmode_int     ;
  logic [3:0] rxsyncallin_int    ;
  logic [3:0] rxsyncin_int       ;

  // Generate one module instance per channel to implement single-lane receive buffer bypass for each lane
  // independently, treating each lane as a master

  // Depending on the number of reset controller helper blocks, either use the single reset done indicator or the
  // logical combination of per-channel reset done indicators as the reset done indicator for use in this block
  logic [3:0] gtwiz_buffbypass_rx_resetdone_int;

  assign gtwiz_buffbypass_rx_resetdone_int = {4{gtwiz_reset_rx_done_out}};

  genvar gi_hb_rxbb;
  generate 
    for (gi_hb_rxbb = 0; gi_hb_rxbb < 4; gi_hb_rxbb = gi_hb_rxbb + 1) begin : gen_gtwiz_buffbypass_rx
      (* DONT_TOUCH = "TRUE" *)
      GtyBuffbypassRx #(
        .P_TOTAL_NUMBER_OF_CHANNELS(1),
        .P_MASTER_CHANNEL_POINTER  (0)
      ) GtyBuffbypassRx_inst (
        .gtwiz_buffbypass_rx_clk_in       (gtwiz_userclk_rx_usrclk2_out      [gi_hb_rxbb]),
        .gtwiz_buffbypass_rx_reset_in     (gtwiz_buffbypass_rx_reset_in      [gi_hb_rxbb]),
        .gtwiz_buffbypass_rx_start_user_in(gtwiz_buffbypass_rx_start_user_in [gi_hb_rxbb]),
        .gtwiz_buffbypass_rx_resetdone_in (gtwiz_buffbypass_rx_resetdone_int [gi_hb_rxbb]),
        .gtwiz_buffbypass_rx_done_out     (gtwiz_buffbypass_rx_done_out      [gi_hb_rxbb]),
        .gtwiz_buffbypass_rx_error_out    (gtwiz_buffbypass_rx_error_out     [gi_hb_rxbb]),
        .rxphaligndone_in                 (rxphaligndone_int                 [gi_hb_rxbb]),
        .rxdlysresetdone_in               (rxdlysresetdone_int               [gi_hb_rxbb]),
        .rxsyncout_in                     (rxsyncout_int                     [gi_hb_rxbb]),
        .rxsyncdone_in                    (rxsyncdone_int                    [gi_hb_rxbb]),
        .rxphdlyreset_out                 (rxphdlyreset_int                  [gi_hb_rxbb]),
        .rxphalign_out                    (rxphalign_int                     [gi_hb_rxbb]),
        .rxphalignen_out                  (rxphalignen_int                   [gi_hb_rxbb]),
        .rxphdlypd_out                    (rxphdlypd_int                     [gi_hb_rxbb]),
        .rxphovrden_out                   (rxphovrden_int                    [gi_hb_rxbb]),
        .rxdlysreset_out                  (rxdlysreset_int                   [gi_hb_rxbb]),
        .rxdlybypass_out                  (rxdlybypass_int                   [gi_hb_rxbb]),
        .rxdlyen_out                      (rxdlyen_int                       [gi_hb_rxbb]),
        .rxdlyovrden_out                  (rxdlyovrden_int                   [gi_hb_rxbb]),
        .rxsyncmode_out                   (rxsyncmode_int                    [gi_hb_rxbb]),
        .rxsyncallin_out                  (rxsyncallin_int                   [gi_hb_rxbb]),
        .rxsyncin_out                     (rxsyncin_int                      [gi_hb_rxbb])
      );
    end
  endgenerate

  // -------------------------------------------------------------------------------------------------------------------
  // Reset controller helper block
  // -------------------------------------------------------------------------------------------------------------------

  // Generate a single module instance which controls all PLLs and all channels within the core

  // Depending on the number of user clocking network helper blocks, either use the single user clock active indicator
  // or a logical combination of per-channel user clock active indicators as the user clock active indicator for use in
  // this block
  logic gtwiz_reset_userclk_tx_active_int;
  logic gtwiz_reset_userclk_rx_active_int;

  // When each channel has an independent transmitter user clock, synchronize each transmitter user clock active
  // indicator independently before combining them
  logic [3:0] gtwiz_userclk_tx_active_sync;

  genvar gi_ch_txclk1;
  generate 
    for (gi_ch_txclk1 = 0; gi_ch_txclk1 < 4; gi_ch_txclk1 = gi_ch_txclk1 + 1) begin : gen_ch_txclk1
      (* DONT_TOUCH = "TRUE" *)
      ResetSynchroniser bit_synchronizer_gtwiz_reset_userclk_rx_active_inst (
        .clk_in   (gtwiz_reset_clk_freerun_in                ),
        .reset_in (gtwiz_userclk_tx_active_out[gi_ch_txclk1] ),
        .reset_out(gtwiz_userclk_tx_active_sync[gi_ch_txclk1])
      );
    end
  endgenerate
  assign gtwiz_reset_userclk_tx_active_int = &gtwiz_userclk_tx_active_sync;

  // When each channel has an independent receiver user clock, synchronize each receiver user clock active
  // indicator independently before combining them
  logic [3:0] gtwiz_userclk_rx_active_sync;

  genvar gi_ch_rxclk1;
  generate 
    for (gi_ch_rxclk1 = 0; gi_ch_rxclk1 < 4; gi_ch_rxclk1 = gi_ch_rxclk1 + 1) begin : gen_ch_rxclk1
      (* DONT_TOUCH = "TRUE" *)
      ResetSynchroniser bit_synchronizer_gtwiz_reset_userclk_rx_active_inst (
        .clk_in   (gtwiz_reset_clk_freerun_in                ),
        .reset_in (gtwiz_userclk_rx_active_out[gi_ch_rxclk1] ),
        .reset_out(gtwiz_userclk_rx_active_sync[gi_ch_rxclk1])
      );
    end
  endgenerate
  assign gtwiz_reset_userclk_rx_active_int = &gtwiz_userclk_rx_active_sync;

  // Combine the appropriate PLL lock signals such that the reset controller can sense when all PLLs which clock each
  // data direction are locked, regardless of what PLL source is used
  logic gtwiz_reset_plllock_tx_int;
  logic gtwiz_reset_plllock_rx_int;

  logic [0:0] qpll0lock_int;

  assign gtwiz_reset_plllock_tx_int = &qpll0lock_int;
  assign gtwiz_reset_plllock_rx_int = &qpll0lock_int;

  assign qpll0locked_out = qpll0lock_int;

  // Combine the power good, reset done, and CDR lock indicators across all channels, per data direction
  logic [3:0] gtpowergood_int            ;
  logic [3:0] rxcdrlock_int              ;
  logic [3:0] txresetdone_int            ;
  logic [3:0] rxresetdone_int            ;
  logic       gtwiz_reset_gtpowergood_int;
  logic       gtwiz_reset_rxcdrlock_int  ;
  logic       gtwiz_reset_txresetdone_int;
  logic       gtwiz_reset_rxresetdone_int;

  assign gtwiz_reset_gtpowergood_int = &gtpowergood_int;
  assign gtwiz_reset_rxcdrlock_int   = &rxcdrlock_int;

  logic [3:0] txresetdone_sync;
  logic [3:0] rxresetdone_sync;
  genvar gi_ch_xrd;
  generate 
    for (gi_ch_xrd = 0; gi_ch_xrd < 4; gi_ch_xrd = gi_ch_xrd + 1) begin : gen_ch_xrd
      (* DONT_TOUCH = "TRUE" *)
      Synchroniser bit_synchronizer_txresetdone_inst (
        .clk_in(gtwiz_reset_clk_freerun_in ),
        .i_in  (txresetdone_int[gi_ch_xrd] ),
        .o_out (txresetdone_sync[gi_ch_xrd])
      );
      (* DONT_TOUCH = "TRUE" *)
      Synchroniser bit_synchronizer_rxresetdone_inst (
        .clk_in(gtwiz_reset_clk_freerun_in ),
        .i_in  (rxresetdone_int[gi_ch_xrd] ),
        .o_out (rxresetdone_sync[gi_ch_xrd])
      );
    end
  endgenerate
  assign gtwiz_reset_txresetdone_int = &txresetdone_sync;
  assign gtwiz_reset_rxresetdone_int = &rxresetdone_sync;

  logic gtwiz_reset_pllreset_tx_int   ;
  logic gtwiz_reset_txprogdivreset_int;
  logic gtwiz_reset_gttxreset_int     ;
  logic gtwiz_reset_txuserrdy_int     ;
  logic gtwiz_reset_pllreset_rx_int   ;
  logic gtwiz_reset_rxprogdivreset_int;
  logic gtwiz_reset_gtrxreset_int     ;
  logic gtwiz_reset_rxuserrdy_int     ;

  // Instantiate the single reset controller
  (* DONT_TOUCH = "TRUE" *)
  GtyReset GtyReset_inst (
    .gtwiz_reset_clk_freerun_in        (gtwiz_reset_clk_freerun_in        ),
    .gtwiz_reset_all_in                (gtwiz_reset_all_in                ),
    .gtwiz_reset_tx_pll_and_datapath_in(gtwiz_reset_tx_pll_and_datapath_in),
    .gtwiz_reset_tx_datapath_in        (gtwiz_reset_tx_datapath_in        ),
    .gtwiz_reset_rx_pll_and_datapath_in(gtwiz_reset_rx_pll_and_datapath_in),
    .gtwiz_reset_rx_datapath_in        (gtwiz_reset_rx_datapath_in        ),
    .gtwiz_reset_rx_cdr_stable_out     (gtwiz_reset_rx_cdr_stable_out     ),
    .gtwiz_reset_tx_done_out           (gtwiz_reset_tx_done_out           ),
    .gtwiz_reset_rx_done_out           (gtwiz_reset_rx_done_out           ),
    .gtwiz_reset_userclk_tx_active_in  (gtwiz_reset_userclk_tx_active_int ),
    .gtwiz_reset_userclk_rx_active_in  (gtwiz_reset_userclk_rx_active_int ),
    .gtpowergood_in                    (gtwiz_reset_gtpowergood_int       ),
    .txusrclk2_in                      (gtwiz_userclk_tx_usrclk2_out      ),
    .plllock_tx_in                     (gtwiz_reset_plllock_tx_int        ),
    .txresetdone_in                    (gtwiz_reset_txresetdone_int       ),
    .rxusrclk2_in                      (gtwiz_userclk_rx_usrclk2_out      ),
    .plllock_rx_in                     (gtwiz_reset_plllock_rx_int        ),
    .rxcdrlock_in                      (gtwiz_reset_rxcdrlock_int         ),
    .rxresetdone_in                    (gtwiz_reset_rxresetdone_int       ),
    .pllreset_tx_out                   (gtwiz_reset_pllreset_tx_int       ),
    .txprogdivreset_out                (gtwiz_reset_txprogdivreset_int    ),
    .gttxreset_out                     (gtwiz_reset_gttxreset_int         ),
    .txuserrdy_out                     (gtwiz_reset_txuserrdy_int         ),
    .pllreset_rx_out                   (gtwiz_reset_pllreset_rx_int       ),
    .rxprogdivreset_out                (gtwiz_reset_rxprogdivreset_int    ),
    .gtrxreset_out                     (gtwiz_reset_gtrxreset_int         ),
    .rxuserrdy_out                     (gtwiz_reset_rxuserrdy_int         ),
    .tx_enabled_tie_in                 (1'b1                              ),
    .rx_enabled_tie_in                 (1'b1                              ),
    .shared_pll_tie_in                 (1'b1                              )
  );

  // Drive the internal PLL reset inputs with the appropriate PLL reset signals produced by the reset controller. The
  // single reset controller instance generates independent transmit PLL reset and receive PLL reset outputs, which are
  // used across all such PLLs in the core.
  logic [0:0] qpll0reset_int;

  assign qpll0reset_int = {1{gtwiz_reset_pllreset_tx_int || gtwiz_reset_pllreset_rx_int}};

  // Fan out appropriate reset controller outputs to all transceiver channels
  logic [3:0] txprogdivreset_int;
  logic [3:0] gttxreset_int     ;
  logic [3:0] txuserrdy_int     ;
  logic [3:0] rxprogdivreset_int;
  logic [3:0] gtrxreset_int     ;
  logic [3:0] rxuserrdy_int     ;

  assign txprogdivreset_int = {4{gtwiz_reset_txprogdivreset_int}};
  assign gttxreset_int      = {4{gtwiz_reset_gttxreset_int}};
  assign txuserrdy_int      = {4{gtwiz_reset_txuserrdy_int}};
  assign rxprogdivreset_int = {4{gtwiz_reset_rxprogdivreset_int}};
  assign gtrxreset_int      = {4{gtwiz_reset_gtrxreset_int}};
  assign rxuserrdy_int      = {4{gtwiz_reset_rxuserrdy_int}};

  // Required assignment to expose the GTPOWERGOOD port per user request
  assign gtpowergood_out = gtpowergood_int;

  // ----------------------------------------------------------------------------------------------------------------
  // Transmitter user data width sizing helper block
  // ----------------------------------------------------------------------------------------------------------------

  // Declare vectors for the helper block to drive transceiver-facing TXDATA port; and in configurations where
  // transmitter data encoding is raw and user data width is modulus 10, also for TXCTRL0 and TXCTRL1 ports
  logic [511:0] txdata_int;
  logic [63 :0] txctrl0_int;
  logic [63 :0] txctrl1_int;

  GtyUserdataTx GtyUserdataTx_inst (
    .gtwiz_userdata_tx_in(gtwiz_userdata_tx_in),
    .txdata_out          (txdata_int          ),
    .txctrl0_out         (txctrl0_int         ),
    .txctrl1_out         (txctrl1_int         ) 
  );

  // ----------------------------------------------------------------------------------------------------------------
  // Receiver user data width sizing helper block
  // ----------------------------------------------------------------------------------------------------------------

  // Declare vectors for the helper block to be driven by transceiver-facing RXDATA port; and in configurations where
  // receiver data decoding is raw and user data width is modulus 10, also for RXCTRL0 and RXCTRL1 ports
  logic [511:0] rxdata_int;
  logic [63 :0] rxctrl0_int;
  logic [63 :0] rxctrl1_int;

  GtyUserdataRx GtyUserdataRx_inst (
    .rxdata_in            (rxdata_int           ),
    .rxctrl0_in           (rxctrl0_int          ),
    .rxctrl1_in           (rxctrl1_int          ),
    .gtwiz_userdata_rx_out(gtwiz_userdata_rx_out)
  );

  // ===================================================================================================================
  // TRANSCEIVER COMMON BLOCK
  // ===================================================================================================================

  logic [0:0] gtrefclk00_int ;
  logic [3:0] qpll0clk_int   ;
  logic [3:0] qpll0refclk_int;

  // When QPLL0 is used, the following assignments support the use of the transceiver COMMON block in the example design
  assign gtrefclk00_int = gtrefclk00_in;
  genvar gi_ch_to_cm0;
  generate 
    for (gi_ch_to_cm0 = 0; gi_ch_to_cm0 < 4; gi_ch_to_cm0 = gi_ch_to_cm0 + 1) begin : gen_ch_to_cm0
      assign qpll0clk_int[gi_ch_to_cm0]    = qpll0outclk_out    [f_idx_cm(gi_ch_to_cm0)];
      assign qpll0refclk_int[gi_ch_to_cm0] = qpll0outrefclk_out [f_idx_cm(gi_ch_to_cm0)];
    end
  endgenerate

  logic [0:0] gtrefclk01_int ;
  logic [3:0] qpll1clk_int   ;
  logic [3:0] qpll1refclk_int;
  logic [0:0] qpll1reset_int ;
  logic [0:0] qpll1lock_int  ;

  // When QPLL1 is not used, the following assignments tie off QPLL1-related inputs as appropriate
  assign gtrefclk01_int  = {1{1'b0}};
  assign qpll1clk_int    = {4{1'b0}};
  assign qpll1refclk_int = {4{1'b0}};
  assign qpll1reset_int  = {1{1'b1}};
  assign qpll1locked_out = {1{1'b0}};

  localparam [47:0] P_COMMON_ENABLE = f_pop_cm_en(0);

  // The following HDL generate loop iterates across each possible transceiver quad, instantiating only the enabled
  // transceiver COMMON blocks, each within a configuration-specific parameterization wrapper
  genvar cm;
  generate
    for (cm = 0; cm < 48; cm = cm + 1) begin : gen_common_container
      if (P_COMMON_ENABLE[cm] == 1'b1) begin : gen_enabled_common

        gtwizard_ultrascale_0_gtye3_common_wrapper gtye3_common_wrapper_inst (
          .GTYE3_COMMON_BGBYPASSB        (1'b1                                                        ),
          .GTYE3_COMMON_BGMONITORENB     (1'b1                                                        ),
          .GTYE3_COMMON_BGPDB            (1'b1                                                        ),
          .GTYE3_COMMON_BGRCALOVRD       (5'b10000                                                    ),
          .GTYE3_COMMON_BGRCALOVRDENB    (1'b1                                                        ),
          .GTYE3_COMMON_DRPADDR          (10'b0000000000                                              ),
          .GTYE3_COMMON_DRPCLK           (1'b0                                                        ),
          .GTYE3_COMMON_DRPDI            (16'b0000000000000000                                        ),
          .GTYE3_COMMON_DRPEN            (1'b0                                                        ),
          .GTYE3_COMMON_DRPWE            (1'b0                                                        ),
          .GTYE3_COMMON_GTGREFCLK0       (1'b0                                                        ),
          .GTYE3_COMMON_GTGREFCLK1       (1'b0                                                        ),
          .GTYE3_COMMON_GTNORTHREFCLK00  (1'b0                                                        ),
          .GTYE3_COMMON_GTNORTHREFCLK01  (1'b0                                                        ),
          .GTYE3_COMMON_GTNORTHREFCLK10  (1'b0                                                        ),
          .GTYE3_COMMON_GTNORTHREFCLK11  (1'b0                                                        ),
          .GTYE3_COMMON_GTREFCLK00       (gtrefclk00_int [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]    ),
          .GTYE3_COMMON_GTREFCLK01       (gtrefclk01_int [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]    ),
          .GTYE3_COMMON_GTREFCLK10       (1'b0                                                        ),
          .GTYE3_COMMON_GTREFCLK11       (1'b0                                                        ),
          .GTYE3_COMMON_GTSOUTHREFCLK00  (1'b0                                                        ),
          .GTYE3_COMMON_GTSOUTHREFCLK01  (1'b0                                                        ),
          .GTYE3_COMMON_GTSOUTHREFCLK10  (1'b0                                                        ),
          .GTYE3_COMMON_GTSOUTHREFCLK11  (1'b0                                                        ),
          .GTYE3_COMMON_PMARSVD0         (8'b00000000                                                 ),
          .GTYE3_COMMON_PMARSVD1         (8'b00000000                                                 ),
          .GTYE3_COMMON_QPLL0CLKRSVD0    (1'b0                                                        ),
          .GTYE3_COMMON_QPLL0LOCKDETCLK  (1'b0                                                        ),
          .GTYE3_COMMON_QPLL0LOCKEN      (1'b1                                                        ),
          .GTYE3_COMMON_QPLL0PD          (1'b0                                                        ),
          .GTYE3_COMMON_QPLL0REFCLKSEL   (3'b001                                                      ),
          .GTYE3_COMMON_QPLL0RESET       (qpll0reset_int [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]    ),
          .GTYE3_COMMON_QPLL1CLKRSVD0    (1'b0                                                        ),
          .GTYE3_COMMON_QPLL1LOCKDETCLK  (1'b0                                                        ),
          .GTYE3_COMMON_QPLL1LOCKEN      (1'b0                                                        ),
          .GTYE3_COMMON_QPLL1PD          (1'b1                                                        ),
          .GTYE3_COMMON_QPLL1REFCLKSEL   (3'b001                                                      ),
          .GTYE3_COMMON_QPLL1RESET       (qpll1reset_int [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]    ),
          .GTYE3_COMMON_QPLLRSVD1        (8'b00000000                                                 ),
          .GTYE3_COMMON_QPLLRSVD2        (5'b00000                                                    ),
          .GTYE3_COMMON_QPLLRSVD3        (5'b00000                                                    ),
          .GTYE3_COMMON_QPLLRSVD4        (8'b00000000                                                 ),
          .GTYE3_COMMON_RCALENB          (1'b1                                                        ),
          .GTYE3_COMMON_SDM0DATA         (25'b0000000000000000000000000                               ),
          .GTYE3_COMMON_SDM0RESET        (1'b0                                                        ),
          .GTYE3_COMMON_SDM0WIDTH        (2'b00                                                       ),
          .GTYE3_COMMON_SDM1DATA         (25'b0000000000000000000000000                               ),
          .GTYE3_COMMON_SDM1RESET        (1'b0                                                        ),
          .GTYE3_COMMON_SDM1WIDTH        (2'b00                                                       ),
          .GTYE3_COMMON_DRPDO            (                                                            ),
          .GTYE3_COMMON_DRPRDY           (                                                            ),
          .GTYE3_COMMON_PMARSVDOUT0      (                                                            ),
          .GTYE3_COMMON_PMARSVDOUT1      (                                                            ),
          .GTYE3_COMMON_QPLL0FBCLKLOST   (                                                            ),
          .GTYE3_COMMON_QPLL0LOCK        (qpll0lock_int      [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
          .GTYE3_COMMON_QPLL0OUTCLK      (qpll0outclk_out    [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
          .GTYE3_COMMON_QPLL0OUTREFCLK   (qpll0outrefclk_out [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
          .GTYE3_COMMON_QPLL0REFCLKLOST  (                                                            ),
          .GTYE3_COMMON_QPLL1FBCLKLOST   (                                                            ),
          .GTYE3_COMMON_QPLL1LOCK        (qpll1lock_int      [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
          .GTYE3_COMMON_QPLL1OUTCLK      (qpll1outclk_out    [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
          .GTYE3_COMMON_QPLL1OUTREFCLK   (qpll1outrefclk_out [f_ub_cm( 1,(4*cm)+3) : f_lb_cm( 1,4*cm)]),
          .GTYE3_COMMON_QPLL1REFCLKLOST  (                                                            ),
          .GTYE3_COMMON_QPLLDMONITOR0    (                                                            ),
          .GTYE3_COMMON_QPLLDMONITOR1    (                                                            ),
          .GTYE3_COMMON_REFCLKOUTMONITOR0(                                                            ),
          .GTYE3_COMMON_REFCLKOUTMONITOR1(                                                            ),
          .GTYE3_COMMON_RXRECCLK0_SEL    (                                                            ),
          .GTYE3_COMMON_RXRECCLK1_SEL    (                                                            ),
          .GTYE3_COMMON_SDM0FINALOUT     (                                                            ),
          .GTYE3_COMMON_SDM0TESTDATA     (                                                            ),
          .GTYE3_COMMON_SDM1FINALOUT     (                                                            ),
          .GTYE3_COMMON_SDM1TESTDATA     (                                                            )
        );

      end
    end
  endgenerate


  // ===================================================================================================================
  // CORE INSTANCE
  // ===================================================================================================================

  // Instantiate the core, mapping its enabled ports to example design ports and helper blocks as appropriate
  gtwizard_ultrascale_0 gtwizard_ultrascale_0_inst (
    .gtyrxn_in                 (gtyrxn_in                  ),
    .gtyrxp_in                 (gtyrxp_in                  ),
    .gtytxn_out                (gtytxn_out                 ),
    .gtytxp_out                (gtytxp_out                 ),
    .gtwiz_userclk_tx_active_in(gtwiz_userclk_tx_active_out),
    .gtwiz_userclk_rx_active_in(gtwiz_userclk_rx_active_out),
    .gtwiz_reset_tx_done_in    (gtwiz_reset_tx_done_out    ),
    .gtwiz_reset_rx_done_in    (gtwiz_reset_rx_done_out    ),
    .dmonitorclk_in            (dmonitorclk_in             ),
    .drpaddr_in                (drpaddr_in                 ),
    .drpclk_in                 (drpclk_in                  ),
    .drpdi_in                  (drpdi_in                   ),
    .drpen_in                  (drpen_in                   ),
    .drpwe_in                  (drpwe_in                   ),
    .eyescanreset_in           (eyescanreset_in            ),
    .gtrxreset_in              (gtrxreset_int              ),
    .gttxreset_in              (gttxreset_int              ),
    .qpll0clk_in               (qpll0clk_int               ),
    .qpll0refclk_in            (qpll0refclk_int            ),
    .qpll1clk_in               (qpll1clk_int               ),
    .qpll1refclk_in            (qpll1refclk_int            ),
    .rxcdrhold_in              (rxcdrhold_in               ),
    .rxcdrovrden_in            (rxcdrovrden_in             ),
    .rxdfelpmreset_in          (rxdfelpmreset_in           ),
    .rxdlybypass_in            (rxdlybypass_int            ),
    .rxdlyen_in                (rxdlyen_int                ),
    .rxdlyovrden_in            (rxdlyovrden_int            ),
    .rxdlysreset_in            (rxdlysreset_int            ),
    .rxlpmen_in                (rxlpmen_in                 ),
    .rxphalign_in              (rxphalign_int              ),
    .rxphalignen_in            (rxphalignen_int            ),
    .rxphdlypd_in              (rxphdlypd_int              ),
    .rxphdlyreset_in           (rxphdlyreset_int           ),
    .rxphovrden_in             (rxphovrden_int             ),
    .rxprogdivreset_in         (rxprogdivreset_int         ),
    .rxrate_in                 (rxrate_in                  ),
    .rxsyncallin_in            (rxsyncallin_int            ),
    .rxsyncin_in               (rxsyncin_int               ),
    .rxsyncmode_in             (rxsyncmode_int             ),
    .rxuserrdy_in              (rxuserrdy_int              ),
    .rxusrclk_in               (rxusrclk_int               ),
    .rxusrclk2_in              (rxusrclk2_int              ),
    .txdata_in                 (txdata_int                 ),
    .txctrl0_in                (txctrl0_int                ),
    .txctrl1_in                (txctrl1_int                ),
    .txdiffctrl_in             (txdiffctrl_in              ),
    .txinhibit_in              (txinhibit_in               ),
    .txpippmen_in              (txpippmen_in               ),
    .txpippmovrden_in          (txpippmovrden_in           ),
    .txpippmpd_in              (txpippmpd_in               ),
    .txpippmsel_in             (txpippmsel_in              ),
    .txpippmstepsize_in        (txpippmstepsize_in         ),
    .txpostcursor_in           (txpostcursor_in            ),
    .txprbssel_in              (txprbssel_in               ),
    .txprecursor_in            (txprecursor_in             ),
    .txrate_in                 (txrate_in                  ),
    .txprogdivreset_in         (txprogdivreset_int         ),
    .txuserrdy_in              (txuserrdy_int              ),
    .txusrclk_in               (txusrclk_int               ),
    .txusrclk2_in              (txusrclk2_int              ),
    .dmonitorout_out           (dmonitorout_out            ),
    .drpdo_out                 (drpdo_out                  ),
    .drprdy_out                (drprdy_out                 ),
    .gtpowergood_out           (gtpowergood_int            ),
    .rxcdrlock_out             (rxcdrlock_int              ),
    .rxdata_out                (rxdata_int                 ),
    .rxctrl0_out               (rxctrl0_int                ),
    .rxctrl1_out               (rxctrl1_int                ),
    .rxdlysresetdone_out       (rxdlysresetdone_int        ),
    .rxoutclk_out              (rxoutclk_int               ),
    .rxphaligndone_out         (rxphaligndone_int          ),
    .rxpmaresetdone_out        (rxpmaresetdone_out         ),
    .rxresetdone_out           (rxresetdone_int            ),
    .rxsyncdone_out            (rxsyncdone_int             ),
    .rxsyncout_out             (rxsyncout_int              ),
    .txoutclk_out              (txoutclk_int               ),
    .txpmaresetdone_out        (txpmaresetdone_out         ),
    .txresetdone_out           (txresetdone_int            )
  );

endmodule
