`timescale 1ns / 1ps
// @module GtyQuad
//
// @date 12.03.2018
// 
// @brief Instantiation of GTY Quad with four transceivers.  Contains all necessary clock management interfaces,
//     reset control, basic debug VIO control, etc.
//
// @file GtyQuad.sv
//
// @author Kari Clark (Salisen), University College London

//------------------------------------------------------------------------------
//  (c) Copyright 2013-2015 Xilinx, Inc. All rights reserved.
//
//  This file contains confidential and proprietary information
//  of Xilinx, Inc. and is protected under U.S. and
//  international copyright and other intellectual property
//  laws.
//
//  DISCLAIMER
//  This disclaimer is not a license and does not grant any
//  rights to the materials distributed herewith. Except as
//  otherwise provided in a valid license issued to you by
//  Xilinx, and to the maximum extent permitted by applicable
//  law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
//  WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
//  AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
//  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
//  INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
//  (2) Xilinx shall not be liable (whether in contract or tort,
//  including negligence, or under any other theory of
//  liability) for any loss or damage of any kind or nature
//  related to, arising under or in connection with these
//  materials, including for any direct, or any indirect,
//  special, incidental, or consequential loss or damage
//  (including loss of data, profits, goodwill, or any type of
//  loss or damage suffered as a result of any action brought
//  by a third party) even if such damage or loss was
//  reasonably foreseeable or Xilinx had been advised of the
//  possibility of the same.
//
//  CRITICAL APPLICATIONS
//  Xilinx products are not designed or intended to be fail-
//  safe, or for use in any application requiring fail-safe
//  performance, such as life-support or safety devices or
//  systems, Class III medical devices, nuclear facilities,
//  applications related to the deployment of airbags, or any
//  other applications that could lead to death, personal
//  injury, or severe property or environmental damage
//  (individually and collectively, "Critical
//  Applications"). Customer assumes the sole risk and
//  liability of any use of Xilinx products in Critical
//  Applications, subject only to applicable laws and
//  regulations governing limitations on product liability.
//
//  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
//  PART OF THIS FILE AT ALL TIMES.
//------------------------------------------------------------------------------

// =====================================================================================================================
// This example design top module instantiates the example design wrapper; slices vectored ports for per-channel
// assignment; and instantiates example resources such as buffers, pattern generators, and pattern checkers for core
// demonstration purposes
// =====================================================================================================================

module GtyQuad (
		// Differential reference clock inputs
		input  logic        mgtrefclk0_p_in              ,
		input  logic        mgtrefclk0_n_in              ,
		// Quad parallel data parallel clocks and done signals
		output logic [ 3:0] tx_usrclk2_out               ,
		output logic [ 3:0] rx_usrclk2_out               ,
		output logic [ 3:0] tx_init_done_out             ,
		output logic [ 3:0] rx_init_done_out             ,
		// Quad parallel inhibit signals for Tx and Rx
		output logic [ 3:0] tx_inhibit_out               ,
		output logic [ 3:0] rx_inhibit_out               ,
		// External reset for JTAG to AXI master with its clock
        output logic        JtagAxiMstExtResetn_out      ,
        input  logic        aclk_in                      ,
		// Serial data ports for transceiver channel 0
		input  logic        ch0_gtyrxn_in                ,
		input  logic        ch0_gtyrxp_in                ,
		output logic        ch0_gtytxn_out               ,
		output logic        ch0_gtytxp_out               ,
		// Parallel data ports for phase cache transciever
		output logic [79:0] ch0_rx_par_data_out          ,
		input  logic [79:0] ch0_tx_par_data_in           ,
		// Serial data ports for transceiver channel 1
		input  logic        ch1_gtyrxn_in                ,
		input  logic        ch1_gtyrxp_in                ,
		output logic        ch1_gtytxn_out               ,
		output logic        ch1_gtytxp_out               ,
		// Parallel data ports for phase cache transciever
		output logic [79:0] ch1_rx_par_data_out          ,
		input  logic [79:0] ch1_tx_par_data_in           ,
		// Serial data ports for transceiver channel 2
		input  logic        ch2_gtyrxn_in                ,
		input  logic        ch2_gtyrxp_in                ,
		output logic        ch2_gtytxn_out               ,
		output logic        ch2_gtytxp_out               ,
		// Parallel data ports for phase cache transciever
		output logic [79:0] ch2_rx_par_data_out          ,
		input  logic [79:0] ch2_tx_par_data_in           ,
		// Serial data ports for transceiver channel 3
		input  logic        ch3_gtyrxn_in                ,
		input  logic        ch3_gtyrxp_in                ,
		output logic        ch3_gtytxn_out               ,
		output logic        ch3_gtytxp_out               ,
		// Parallel data ports for phase cache transciever
		output logic [79:0] ch3_rx_par_data_out          ,
		input  logic [79:0] ch3_tx_par_data_in           ,
		// User-provided ports for reset helper block(s)
		input  logic        hb_gtwiz_reset_clk_freerun_in,
		input  logic        hb_gtwiz_reset_all_in        ,
		output logic 		hb_gtwiz_reset_all_comb_out  ,
		// Receiver phase output
		output logic [ 6:0] ch0_rx_cdr_phase_out         ,
		output logic [ 6:0] ch1_rx_cdr_phase_out         ,
		output logic [ 6:0] ch2_rx_cdr_phase_out         ,
		output logic [ 6:0] ch3_rx_cdr_phase_out         ,
		// TX 0 PiPPM control signals
		input  logic        ch0_txpippmen_in             ,
		input  logic        ch0_txpippmovrden_in         ,
		input  logic        ch0_txpippmsel_in            ,
		input  logic [ 4:0] ch0_txpippmstepsize_in       ,
		// RX 0 CDR override signals
		input  logic        ch0_rxcdrovrden_in           ,
		// TX 1 PiPPM control signals
		input  logic        ch1_txpippmen_in             ,
		input  logic        ch1_txpippmovrden_in         ,
		input  logic        ch1_txpippmsel_in            ,
		input  logic [ 4:0] ch1_txpippmstepsize_in       ,
		// RX 1 CDR override signals
		input  logic        ch1_rxcdrovrden_in           ,
		// TX 2 PiPPM control signals
		input  logic        ch2_txpippmen_in             ,
		input  logic        ch2_txpippmovrden_in         ,
		input  logic        ch2_txpippmsel_in            ,
		input  logic [ 4:0] ch2_txpippmstepsize_in       ,
		// RX 2 CDR override signals
		input  logic        ch2_rxcdrovrden_in           ,
		// TX 3 PiPPM control signals
		input  logic        ch3_txpippmen_in             ,
		input  logic        ch3_txpippmovrden_in         ,
		input  logic        ch3_txpippmsel_in            ,
		input  logic [ 4:0] ch3_txpippmstepsize_in       ,
		// RX 3 CDR override signals
		input  logic        ch3_rxcdrovrden_in           ,
		// Set which TX is used to generate the scope trigger signal
		output logic [ 1:0] ScopeTriggerSrc_out
	);


	// ===================================================================================================================
	// PER-CHANNEL SIGNAL ASSIGNMENTS
	// ===================================================================================================================

	// The core and example design wrapper vectorize ports across all enabled transceiver channel and common instances for
	// simplicity and compactness. This example design top module assigns slices of each vector to individual, per-channel
	// signal vectors for use if desired. Signals which connect to helper blocks are prefixed "hb#", signals which connect
	// to transceiver common primitives are prefixed "cm#", and signals which connect to transceiver channel primitives
	// are prefixed "ch#", where "#" is the sequential resource number.

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtyrxn_int;
	assign gtyrxn_int[0:0] = ch0_gtyrxn_in;
	assign gtyrxn_int[1:1] = ch1_gtyrxn_in;
	assign gtyrxn_int[2:2] = ch2_gtyrxn_in;
	assign gtyrxn_int[3:3] = ch3_gtyrxn_in;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtyrxp_int;
	assign gtyrxp_int[0:0] = ch0_gtyrxp_in;
	assign gtyrxp_int[1:1] = ch1_gtyrxp_in;
	assign gtyrxp_int[2:2] = ch2_gtyrxp_in;
	assign gtyrxp_int[3:3] = ch3_gtyrxp_in;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtytxn_int;
	assign ch0_gtytxn_out = gtytxn_int[0:0];
	assign ch1_gtytxn_out = gtytxn_int[1:1];
	assign ch2_gtytxn_out = gtytxn_int[2:2];
	assign ch3_gtytxn_out = gtytxn_int[3:3];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtytxp_int;
	assign ch0_gtytxp_out = gtytxp_int[0:0];
	assign ch1_gtytxp_out = gtytxp_int[1:1];
	assign ch2_gtytxp_out = gtytxp_int[2:2];
	assign ch3_gtytxp_out = gtytxp_int[3:3];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_tx_reset_int    ;
	logic [3:0] hb0_gtwiz_userclk_tx_reset_int;
	assign gtwiz_userclk_tx_reset_int[3:0] = hb0_gtwiz_userclk_tx_reset_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_tx_srcclk_int    ;
	logic [3:0] hb0_gtwiz_userclk_tx_srcclk_int;
	assign hb0_gtwiz_userclk_tx_srcclk_int = gtwiz_userclk_tx_srcclk_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_tx_usrclk_int    ;
	logic [3:0] hb0_gtwiz_userclk_tx_usrclk_int;
	assign hb0_gtwiz_userclk_tx_usrclk_int = gtwiz_userclk_tx_usrclk_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_tx_usrclk2_int    ;
	logic [3:0] hb0_gtwiz_userclk_tx_usrclk2_int;
	assign hb0_gtwiz_userclk_tx_usrclk2_int = gtwiz_userclk_tx_usrclk2_int[3:0];
	assign tx_usrclk2_out = hb0_gtwiz_userclk_tx_usrclk2_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_tx_active_int    ;
	logic [3:0] hb0_gtwiz_userclk_tx_active_int;
	assign hb0_gtwiz_userclk_tx_active_int = gtwiz_userclk_tx_active_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_rx_reset_int    ;
	logic [3:0] hb0_gtwiz_userclk_rx_reset_int;
	assign gtwiz_userclk_rx_reset_int[3:0] = hb0_gtwiz_userclk_rx_reset_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_rx_srcclk_int    ;
	logic [3:0] hb0_gtwiz_userclk_rx_srcclk_int;
	assign hb0_gtwiz_userclk_rx_srcclk_int = gtwiz_userclk_rx_srcclk_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_rx_usrclk_int    ;
	logic [3:0] hb0_gtwiz_userclk_rx_usrclk_int;
	assign hb0_gtwiz_userclk_rx_usrclk_int = gtwiz_userclk_rx_usrclk_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_rx_usrclk2_int    ;
	logic [3:0] hb0_gtwiz_userclk_rx_usrclk2_int;
	assign hb0_gtwiz_userclk_rx_usrclk2_int = gtwiz_userclk_rx_usrclk2_int[3:0];
	assign rx_usrclk2_out = hb0_gtwiz_userclk_rx_usrclk2_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_userclk_rx_active_int    ;
	logic [3:0] hb0_gtwiz_userclk_rx_active_int;
	assign hb0_gtwiz_userclk_rx_active_int = gtwiz_userclk_rx_active_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_buffbypass_rx_reset_int    ;
	logic [3:0] hb0_gtwiz_buffbypass_rx_reset_int;
	assign gtwiz_buffbypass_rx_reset_int[3:0] = hb0_gtwiz_buffbypass_rx_reset_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_buffbypass_rx_start_user_int           ;
	logic [3:0] hb0_gtwiz_buffbypass_rx_start_user_int = 1'b0;
	assign gtwiz_buffbypass_rx_start_user_int[3:0] = hb0_gtwiz_buffbypass_rx_start_user_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_buffbypass_rx_done_int    ;
	logic [3:0] hb0_gtwiz_buffbypass_rx_done_int;
	assign hb0_gtwiz_buffbypass_rx_done_int = gtwiz_buffbypass_rx_done_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_buffbypass_rx_error_int    ;
	logic [3:0] hb0_gtwiz_buffbypass_rx_error_int;
	assign hb0_gtwiz_buffbypass_rx_error_int = gtwiz_buffbypass_rx_error_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] gtwiz_reset_clk_freerun_int           ;
	logic [0:0] hb0_gtwiz_reset_clk_freerun_int = 1'b0;
	assign gtwiz_reset_clk_freerun_int[0:0] = hb0_gtwiz_reset_clk_freerun_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] gtwiz_reset_all_int           ;
	logic [0:0] hb0_gtwiz_reset_all_int = 1'b0;
	assign gtwiz_reset_all_int[0:0] = hb0_gtwiz_reset_all_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] gtwiz_reset_tx_pll_and_datapath_int    ;
	logic [0:0] hb0_gtwiz_reset_tx_pll_and_datapath_int;
	assign gtwiz_reset_tx_pll_and_datapath_int[0:0] = hb0_gtwiz_reset_tx_pll_and_datapath_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] gtwiz_reset_tx_datapath_int    ;
	logic [0:0] hb0_gtwiz_reset_tx_datapath_int;
	assign gtwiz_reset_tx_datapath_int[0:0] = hb0_gtwiz_reset_tx_datapath_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] gtwiz_reset_rx_pll_and_datapath_int           ;
	logic [0:0] hb0_gtwiz_reset_rx_pll_and_datapath_int = 1'b0;
	assign gtwiz_reset_rx_pll_and_datapath_int[0:0] = hb0_gtwiz_reset_rx_pll_and_datapath_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] gtwiz_reset_rx_datapath_int           ;
	logic [0:0] hb0_gtwiz_reset_rx_datapath_int = 1'b0;
	assign gtwiz_reset_rx_datapath_int[0:0] = hb0_gtwiz_reset_rx_datapath_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] gtwiz_reset_rx_cdr_stable_int    ;
	logic [0:0] hb0_gtwiz_reset_rx_cdr_stable_int;
	assign hb0_gtwiz_reset_rx_cdr_stable_int = gtwiz_reset_rx_cdr_stable_int[0:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_reset_tx_done_int    ;
	logic [3:0] hb0_gtwiz_reset_tx_done_int;
	assign hb0_gtwiz_reset_tx_done_int = gtwiz_reset_tx_done_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtwiz_reset_rx_done_int    ;
	logic [3:0] hb0_gtwiz_reset_rx_done_int;
	assign hb0_gtwiz_reset_rx_done_int = gtwiz_reset_rx_done_int[3:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [319:0] gtwiz_userdata_tx_int    ;
	logic [ 79:0] hb0_gtwiz_userdata_tx_int;
	logic [ 79:0] hb1_gtwiz_userdata_tx_int;
	logic [ 79:0] hb2_gtwiz_userdata_tx_int;
	logic [ 79:0] hb3_gtwiz_userdata_tx_int;
	assign gtwiz_userdata_tx_int[79:0]    = hb0_gtwiz_userdata_tx_int;
	assign gtwiz_userdata_tx_int[159:80]  = hb1_gtwiz_userdata_tx_int;
	assign gtwiz_userdata_tx_int[239:160] = hb2_gtwiz_userdata_tx_int;
	assign gtwiz_userdata_tx_int[319:240] = hb3_gtwiz_userdata_tx_int;
	assign hb0_gtwiz_userdata_tx_int = ch0_tx_par_data_in;
	assign hb1_gtwiz_userdata_tx_int = ch1_tx_par_data_in;
	assign hb2_gtwiz_userdata_tx_int = ch2_tx_par_data_in;
	assign hb3_gtwiz_userdata_tx_int = ch3_tx_par_data_in;

	//--------------------------------------------------------------------------------------------------------------------
	logic [319:0] gtwiz_userdata_rx_int    ;
	logic [ 79:0] hb0_gtwiz_userdata_rx_int;
	logic [ 79:0] hb1_gtwiz_userdata_rx_int;
	logic [ 79:0] hb2_gtwiz_userdata_rx_int;
	logic [ 79:0] hb3_gtwiz_userdata_rx_int;
	assign hb0_gtwiz_userdata_rx_int = gtwiz_userdata_rx_int[79:0];
	assign hb1_gtwiz_userdata_rx_int = gtwiz_userdata_rx_int[159:80];
	assign hb2_gtwiz_userdata_rx_int = gtwiz_userdata_rx_int[239:160];
	assign hb3_gtwiz_userdata_rx_int = gtwiz_userdata_rx_int[319:240];
	assign ch0_rx_par_data_out = hb0_gtwiz_userdata_rx_int;
	assign ch1_rx_par_data_out = hb1_gtwiz_userdata_rx_int;
	assign ch2_rx_par_data_out = hb2_gtwiz_userdata_rx_int;
	assign ch3_rx_par_data_out = hb3_gtwiz_userdata_rx_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] gtrefclk00_int    ;
	logic [0:0] cm0_gtrefclk00_int;
	assign gtrefclk00_int[0:0] = cm0_gtrefclk00_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] qpll0outclk_int    ;
	logic [0:0] cm0_qpll0outclk_int;
	assign cm0_qpll0outclk_int = qpll0outclk_int[0:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] qpll0outrefclk_int    ;
	logic [0:0] cm0_qpll0outrefclk_int;
	assign cm0_qpll0outrefclk_int = qpll0outrefclk_int[0:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [0:0] qpll0locked_int    ;
	logic [0:0] cm0_qpll0locked_int;
	assign cm0_qpll0locked_int = qpll0locked_int[0:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] dmonitorclk_int    ;
	logic [0:0] ch0_dmonitorclk_int;
	logic [0:0] ch1_dmonitorclk_int;
	logic [0:0] ch2_dmonitorclk_int;
	logic [0:0] ch3_dmonitorclk_int;
	assign dmonitorclk_int[0:0] = ch0_dmonitorclk_int;
	assign dmonitorclk_int[1:1] = ch1_dmonitorclk_int;
	assign dmonitorclk_int[2:2] = ch2_dmonitorclk_int;
	assign dmonitorclk_int[3:3] = ch3_dmonitorclk_int;
	// Digital monitor clk is set to point to the various rx_usrclk2 clocks so that receiver phase can be extracted
	assign ch0_dmonitorclk_int = hb0_gtwiz_userclk_rx_usrclk2_int[0];
	assign ch1_dmonitorclk_int = hb0_gtwiz_userclk_rx_usrclk2_int[1];
	assign ch2_dmonitorclk_int = hb0_gtwiz_userclk_rx_usrclk2_int[2];
	assign ch3_dmonitorclk_int = hb0_gtwiz_userclk_rx_usrclk2_int[3];

	//--------------------------------------------------------------------------------------------------------------------
	logic [39:0] drpaddr_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] drpclk_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [63:0] drpdi_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] drpen_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] drpwe_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] eyescanreset_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] rxcdrhold_int           ;
	logic [0:0] ch0_rxcdrhold_int = 1'b0;
	logic [0:0] ch1_rxcdrhold_int = 1'b0;
	logic [0:0] ch2_rxcdrhold_int = 1'b0;
	logic [0:0] ch3_rxcdrhold_int = 1'b0;
	assign rxcdrhold_int[0:0] = ch0_rxcdrhold_int;
	assign rxcdrhold_int[1:1] = ch1_rxcdrhold_int;
	assign rxcdrhold_int[2:2] = ch2_rxcdrhold_int;
	assign rxcdrhold_int[3:3] = ch3_rxcdrhold_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] rxcdrovrden_int                         ;
	logic [0:0] ch0_rxcdrovrden_int = ch0_rxcdrovrden_in;
	logic [0:0] ch1_rxcdrovrden_int = ch1_rxcdrovrden_in;
	logic [0:0] ch2_rxcdrovrden_int = ch2_rxcdrovrden_in;
	logic [0:0] ch3_rxcdrovrden_int = ch3_rxcdrovrden_in;
	assign rxcdrovrden_int[0:0] = ch0_rxcdrovrden_int;
	assign rxcdrovrden_int[1:1] = ch1_rxcdrovrden_int;
	assign rxcdrovrden_int[2:2] = ch2_rxcdrovrden_int;
	assign rxcdrovrden_int[3:3] = ch3_rxcdrovrden_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] rxinhibit_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] rxdfelpmreset_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] rxlpmen_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [11:0] rxrate_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [19:0] txdiffctrl_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] txinhibit_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [11:0] txrate_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] txpippmen_int                       ;
	logic [0:0] ch0_txpippmen_int = ch0_txpippmen_in;
	logic [0:0] ch1_txpippmen_int = ch1_txpippmen_in;
	logic [0:0] ch2_txpippmen_int = ch2_txpippmen_in;
	logic [0:0] ch3_txpippmen_int = ch3_txpippmen_in;
	assign txpippmen_int[0:0] = ch0_txpippmen_int;
	assign txpippmen_int[1:1] = ch1_txpippmen_int;
	assign txpippmen_int[2:2] = ch2_txpippmen_int;
	assign txpippmen_int[3:3] = ch3_txpippmen_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] txpippmovrden_int                           ;
	logic [0:0] ch0_txpippmovrden_int = ch0_txpippmovrden_in;
	logic [0:0] ch1_txpippmovrden_int = ch1_txpippmovrden_in;
	logic [0:0] ch2_txpippmovrden_int = ch2_txpippmovrden_in;
	logic [0:0] ch3_txpippmovrden_int = ch3_txpippmovrden_in;
	assign txpippmovrden_int[0:0] = ch0_txpippmovrden_int;
	assign txpippmovrden_int[1:1] = ch1_txpippmovrden_int;
	assign txpippmovrden_int[2:2] = ch2_txpippmovrden_int;
	assign txpippmovrden_int[3:3] = ch3_txpippmovrden_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] txpippmpd_int           ;
	logic [0:0] ch0_txpippmpd_int = 1'b0;
	logic [0:0] ch1_txpippmpd_int = 1'b0;
	logic [0:0] ch2_txpippmpd_int = 1'b0;
	logic [0:0] ch3_txpippmpd_int = 1'b0;
	assign txpippmpd_int[0:0] = ch0_txpippmpd_int;
	assign txpippmpd_int[1:1] = ch1_txpippmpd_int;
	assign txpippmpd_int[2:2] = ch2_txpippmpd_int;
	assign txpippmpd_int[3:3] = ch3_txpippmpd_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] txpippmsel_int                        ;
	logic [0:0] ch0_txpippmsel_int = ch0_txpippmsel_in;
	logic [0:0] ch1_txpippmsel_int = ch1_txpippmsel_in;
	logic [0:0] ch2_txpippmsel_int = ch2_txpippmsel_in;
	logic [0:0] ch3_txpippmsel_int = ch3_txpippmsel_in;
	assign txpippmsel_int[0:0] = ch0_txpippmsel_int;
	assign txpippmsel_int[1:1] = ch1_txpippmsel_int;
	assign txpippmsel_int[2:2] = ch2_txpippmsel_int;
	assign txpippmsel_int[3:3] = ch3_txpippmsel_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [19:0] txpippmstepsize_int                             ;
	logic [ 4:0] ch0_txpippmstepsize_int = ch0_txpippmstepsize_in;
	logic [ 4:0] ch1_txpippmstepsize_int = ch1_txpippmstepsize_in;
	logic [ 4:0] ch2_txpippmstepsize_int = ch2_txpippmstepsize_in;
	logic [ 4:0] ch3_txpippmstepsize_int = ch3_txpippmstepsize_in;
	assign txpippmstepsize_int[4:0]   = ch0_txpippmstepsize_int;
	assign txpippmstepsize_int[9:5]   = ch1_txpippmstepsize_int;
	assign txpippmstepsize_int[14:10] = ch2_txpippmstepsize_int;
	assign txpippmstepsize_int[19:15] = ch3_txpippmstepsize_int;

	//--------------------------------------------------------------------------------------------------------------------
	logic [19:0] txpostcursor_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [15:0] txprbssel_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [19:0] txprecursor_int;
	// This vector is not sliced because it is directly assigned in a debug core instance below

	//--------------------------------------------------------------------------------------------------------------------
	logic [67:0] dmonitorout_int    ;
	logic [16:0] ch0_dmonitorout_int;
	logic [16:0] ch1_dmonitorout_int;
	logic [16:0] ch2_dmonitorout_int;
	logic [16:0] ch3_dmonitorout_int;
	assign ch0_dmonitorout_int = dmonitorout_int[16:0];
	assign ch1_dmonitorout_int = dmonitorout_int[33:17];
	assign ch2_dmonitorout_int = dmonitorout_int[50:34];
	assign ch3_dmonitorout_int = dmonitorout_int[67:51];
	// Output of dmonitor is the current receiver phase value
	assign ch0_rx_cdr_phase_out = ch0_dmonitorout_int[6:0];
	assign ch1_rx_cdr_phase_out = ch1_dmonitorout_int[6:0];
	assign ch2_rx_cdr_phase_out = ch2_dmonitorout_int[6:0];
	assign ch3_rx_cdr_phase_out = ch3_dmonitorout_int[6:0];

	//--------------------------------------------------------------------------------------------------------------------
	logic [63:0] drpdo_int    ;
	logic [15:0] ch0_drpdo_int;
	logic [15:0] ch1_drpdo_int;
	logic [15:0] ch2_drpdo_int;
	logic [15:0] ch3_drpdo_int;
	assign ch0_drpdo_int = drpdo_int[15:0];
	assign ch1_drpdo_int = drpdo_int[31:16];
	assign ch2_drpdo_int = drpdo_int[47:32];
	assign ch3_drpdo_int = drpdo_int[63:48];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] drprdy_int    ;
	logic [0:0] ch0_drprdy_int;
	logic [0:0] ch1_drprdy_int;
	logic [0:0] ch2_drprdy_int;
	logic [0:0] ch3_drprdy_int;
	assign ch0_drprdy_int = drprdy_int[0:0];
	assign ch1_drprdy_int = drprdy_int[1:1];
	assign ch2_drprdy_int = drprdy_int[2:2];
	assign ch3_drprdy_int = drprdy_int[3:3];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] gtpowergood_int    ;
	logic [0:0] ch0_gtpowergood_int;
	logic [0:0] ch1_gtpowergood_int;
	logic [0:0] ch2_gtpowergood_int;
	logic [0:0] ch3_gtpowergood_int;
	assign ch0_gtpowergood_int = gtpowergood_int[0:0];
	assign ch1_gtpowergood_int = gtpowergood_int[1:1];
	assign ch2_gtpowergood_int = gtpowergood_int[2:2];
	assign ch3_gtpowergood_int = gtpowergood_int[3:3];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] rxpmaresetdone_int    ;
	logic [0:0] ch0_rxpmaresetdone_int;
	logic [0:0] ch1_rxpmaresetdone_int;
	logic [0:0] ch2_rxpmaresetdone_int;
	logic [0:0] ch3_rxpmaresetdone_int;
	assign ch0_rxpmaresetdone_int = rxpmaresetdone_int[0:0];
	assign ch1_rxpmaresetdone_int = rxpmaresetdone_int[1:1];
	assign ch2_rxpmaresetdone_int = rxpmaresetdone_int[2:2];
	assign ch3_rxpmaresetdone_int = rxpmaresetdone_int[3:3];

	//--------------------------------------------------------------------------------------------------------------------
	logic [3:0] txpmaresetdone_int    ;
	logic [0:0] ch0_txpmaresetdone_int;
	logic [0:0] ch1_txpmaresetdone_int;
	logic [0:0] ch2_txpmaresetdone_int;
	logic [0:0] ch3_txpmaresetdone_int;
	assign ch0_txpmaresetdone_int = txpmaresetdone_int[0:0];
	assign ch1_txpmaresetdone_int = txpmaresetdone_int[1:1];
	assign ch2_txpmaresetdone_int = txpmaresetdone_int[2:2];
	assign ch3_txpmaresetdone_int = txpmaresetdone_int[3:3];

	//--------------------------------------------------------------------------------------------------------------------
	logic [1:0] ScopeTriggerSrc_int;
	assign ScopeTriggerSrc_out = ScopeTriggerSrc_int;

	// ===================================================================================================================
	// BUFFERS
	// ===================================================================================================================

	// Buffer the hb_gtwiz_reset_all_in input and logically combine it with the internal signal from the example
	// initialization block as well as the VIO-sourced reset
	logic hb_gtwiz_reset_all_vio_int ;
	logic hb_gtwiz_reset_all_init_int;
	logic hb_gtwiz_reset_all_int     ;

	assign hb_gtwiz_reset_all_int = hb_gtwiz_reset_all_in || hb_gtwiz_reset_all_init_int || hb_gtwiz_reset_all_vio_int;

	assign hb_gtwiz_reset_all_comb_out = hb_gtwiz_reset_all_int;

	// Globally buffer the free-running input clock
	logic hb_gtwiz_reset_clk_freerun_buf_int;

	BUFG bufg_clk_freerun_inst (
		.I(hb_gtwiz_reset_clk_freerun_in     ),
		.O(hb_gtwiz_reset_clk_freerun_buf_int)
	);

	// Instantiate a differential reference clock buffer for each reference clock differential pair in this configuration,
	// and assign the single-ended output of each differential reference clock buffer to the appropriate PLL input signal

	// Differential reference clock buffer for MGTREFCLK0_X0Y2
	logic mgtrefclk0_x0y2_int;

	IBUFDS_GTE3 #(
		.REFCLK_EN_TX_PATH (1'b0 ),
		.REFCLK_HROW_CK_SEL(2'b00),
		.REFCLK_ICNTL_RX   (2'b00)
	) IBUFDS_GTE3_MGTREFCLK0_X0Y2_INST (
		.I    (mgtrefclk0_p_in    ),
		.IB   (mgtrefclk0_n_in    ),
		.CEB  (1'b0               ),
		.O    (mgtrefclk0_x0y2_int),
		.ODIV2(                   )
	);

	assign cm0_gtrefclk00_int = mgtrefclk0_x0y2_int;

	// ===================================================================================================================
	// USER CLOCKING RESETS
	// ===================================================================================================================

	// The TX user clocking helper block should be held in reset until the clock source of that block is known to be
	// stable. The following assignment is an example of how that stability can be determined, based on the selected TX
	// user clock source. Replace the assignment with the appropriate signal or logic to achieve that behavior as needed.
	assign hb0_gtwiz_userclk_tx_reset_int = ~txpmaresetdone_int;

	// The RX user clocking helper block should be held in reset until the clock source of that block is known to be
	// stable. The following assignment is an example of how that stability can be determined, based on the selected RX
	// user clock source. Replace the assignment with the appropriate signal or logic to achieve that behavior as needed.
	assign hb0_gtwiz_userclk_rx_reset_int = ~rxpmaresetdone_int;

	// ===================================================================================================================
	// BUFFER BYPASS CONTROLLER RESETS
	// ===================================================================================================================

	// The RX buffer bypass controller helper blocks should be held in reset until the RX user clocking network helper
	// block which drives it is active

	genvar gi_ch_rx_usrclk2;
	generate 
		for (gi_ch_rx_usrclk2 = 0; gi_ch_rx_usrclk2 < 4; gi_ch_rx_usrclk2 = gi_ch_rx_usrclk2 + 1) begin : gen_ch_rx_usrclk2
			(* DONT_TOUCH = "TRUE" *)
			ResetSynchroniser reset_synchronizer_gtwiz_buffbypass_rx_reset_inst (
				.clk_in   (hb0_gtwiz_userclk_rx_usrclk2_int[gi_ch_rx_usrclk2] ),
				.reset_in (~hb0_gtwiz_userclk_rx_active_int[gi_ch_rx_usrclk2] ),
				.reset_out(hb0_gtwiz_buffbypass_rx_reset_int[gi_ch_rx_usrclk2])
			);
		end
	endgenerate

	// ===================================================================================================================
	// INITIALIZATION
	// ===================================================================================================================

	// Declare the receiver reset signals that interface to the reset controller helper block. For this configuration,
	// which uses the same PLL type for transmitter and receiver, the "reset RX PLL and datapath" feature is not used.
	logic hb_gtwiz_reset_rx_pll_and_datapath_int = 1'b0;
	logic hb_gtwiz_reset_rx_datapath_int               ;

	// Declare signals which connect the VIO instance to the initialization module for debug purposes
	logic       init_done_int     ;
	logic [3:0] init_retry_ctr_int;

	// Combine the receiver reset signals form the initialization module and the VIO to drive the appropriate reset
	// controller helper block reset input
	logic hb_gtwiz_reset_rx_pll_and_datapath_vio_int;
	logic hb_gtwiz_reset_rx_datapath_vio_int        ;
	logic hb_gtwiz_reset_rx_datapath_init_int       ;

	assign hb_gtwiz_reset_rx_datapath_int = hb_gtwiz_reset_rx_datapath_init_int || hb_gtwiz_reset_rx_datapath_vio_int;

	genvar gi_ch_tx_usrclk2_2;
	generate 
		for (gi_ch_tx_usrclk2_2 = 0; gi_ch_tx_usrclk2_2 < 4; gi_ch_tx_usrclk2_2 = gi_ch_tx_usrclk2_2 + 1) begin : gen_ch_tx_usrclk2_2
		    // TX Done signals (registered to ease timing)
		    always_ff @(posedge tx_usrclk2_out[gi_ch_tx_usrclk2_2]) begin
		        tx_init_done_out[gi_ch_tx_usrclk2_2] <= gtwiz_reset_tx_done_int[gi_ch_tx_usrclk2_2];
			end
        end
	endgenerate


	// gtwiz_reset_rx_done_int needs to be synchronised into the rx clock domains
	logic [3:0] gtwiz_reset_rx_done_int_rx_usrclk2;

	genvar gi_ch_rx_usrclk2_2;
	generate 
		for (gi_ch_rx_usrclk2_2 = 0; gi_ch_rx_usrclk2_2 < 4; gi_ch_rx_usrclk2_2 = gi_ch_rx_usrclk2_2 + 1) begin : gen_ch_rx_usrclk2_2
		    // RX Done signals (registered to ease timing)
		    always_ff @(posedge rx_usrclk2_out[gi_ch_rx_usrclk2_2]) begin
			   rx_init_done_out[gi_ch_rx_usrclk2_2] <= gtwiz_reset_rx_done_int[gi_ch_rx_usrclk2_2] 
			                                            && gtwiz_buffbypass_rx_done_int[gi_ch_rx_usrclk2_2];
			end
        end
	endgenerate

	// The example initialization module interacts with the reset controller helper block and other example design logic
	// to retry failed reset attempts in order to mitigate bring-up issues such as initially-unavilable reference clocks
	// or data connections. It also resets the receiver in the event of link loss in an attempt to regain link, so please
	// note the possibility that this behavior can have the effect of overriding or disturbing user-provided inputs that
	// destabilize the data stream. It is a demonstration only and can be modified to suit your system needs.
	GtWizardInit i_GtWizardInit (
		.clk_freerun_in (hb_gtwiz_reset_clk_freerun_buf_int                           ),
		.reset_all_in   (hb_gtwiz_reset_all_int                                       ),
		.tx_init_done_in((&gtwiz_reset_tx_done_int)                                   ),
		.rx_init_done_in((&gtwiz_reset_rx_done_int) && (&gtwiz_buffbypass_rx_done_int)),
		.rx_data_good_in(1'b1                                                         ),
		.reset_all_out  (hb_gtwiz_reset_all_init_int                                  ),
		.reset_rx_out   (hb_gtwiz_reset_rx_datapath_init_int                          ),
		.init_done_out  (init_done_int                                                ),
		.retry_ctr_out  (init_retry_ctr_int                                           )
	);

	// ===================================================================================================================
	// VIO FOR HARDWARE BRING-UP AND DEBUG
	// ===================================================================================================================

	// Synchronize gtpowergood into the free-running clock domain for VIO usage
	logic [3:0] gtpowergood_vio_sync;

	(* DONT_TOUCH = "TRUE" *)
	Synchroniser #(.WIDTH('d4)) bus_synchronizer_vio_gtpowergood_inst (
		.clk_in(hb_gtwiz_reset_clk_freerun_buf_int),
		.i_in  (gtpowergood_int                   ),
		.o_out (gtpowergood_vio_sync              )
	);

	// Synchronize txpmaresetdone into the free-running clock domain for VIO usage
	logic [3:0] txpmaresetdone_vio_sync;

	(* DONT_TOUCH = "TRUE" *)
	Synchroniser #(.WIDTH('d4)) bus_synchronizer_vio_txpmaresetdone_0_inst (
		.clk_in(hb_gtwiz_reset_clk_freerun_buf_int),
		.i_in  (txpmaresetdone_int                ),
		.o_out (txpmaresetdone_vio_sync           )
	);

	// Synchronize rxpmaresetdone into the free-running clock domain for VIO usage
	logic [3:0] rxpmaresetdone_vio_sync;

	(* DONT_TOUCH = "TRUE" *)
	Synchroniser #(.WIDTH('d4)) bus_synchronizer_vio_rxpmaresetdone_inst (
		.clk_in(hb_gtwiz_reset_clk_freerun_buf_int),
		.i_in  (rxpmaresetdone_int                ),
		.o_out (rxpmaresetdone_vio_sync           )
	);

	// Synchronize gtwiz_reset_tx_done into the free-running clock domain for VIO usage
	logic [0:0] gtwiz_reset_tx_done_vio_sync;

	(* DONT_TOUCH = "TRUE" *)
	Synchroniser bit_synchronizer_vio_gtwiz_reset_tx_done_0_inst (
		.clk_in(hb_gtwiz_reset_clk_freerun_buf_int),
		.i_in  (gtwiz_reset_tx_done_int[0]        ),
		.o_out (gtwiz_reset_tx_done_vio_sync[0]   )
	);

	// Synchronize gtwiz_reset_rx_done into the free-running clock domain for VIO usage
	logic [0:0] gtwiz_reset_rx_done_vio_sync;

	(* DONT_TOUCH = "TRUE" *)
	Synchroniser bit_synchronizer_vio_gtwiz_reset_rx_done_0_inst (
		.clk_in(hb_gtwiz_reset_clk_freerun_buf_int),
		.i_in  (gtwiz_reset_rx_done_int[0]        ),
		.o_out (gtwiz_reset_rx_done_vio_sync[0]   )
	);

	// Synchronize cm0_qpll0locked into the free-running clock domain for VIO usage
	logic [0:0] cm0_qpll0locked_vio_sync;

	(* DONT_TOUCH = "TRUE" *)
	Synchroniser bit_synchronizer_vio_cm0_qpll0locked_0_inst (
		.clk_in(hb_gtwiz_reset_clk_freerun_buf_int),
		.i_in  (cm0_qpll0locked_int[0]            ),
		.o_out (cm0_qpll0locked_vio_sync[0]       )
	);

	// Synchronize gtwiz_buffbypass_rx_done into the free-running clock domain for VIO usage
	logic [3:0] gtwiz_buffbypass_rx_done_vio_sync;

	(* DONT_TOUCH = "TRUE" *)
	Synchroniser #(.WIDTH('d4)) bus_synchronizer_vio_gtwiz_buffbypass_rx_done_0_inst (
		.clk_in(hb_gtwiz_reset_clk_freerun_buf_int),
		.i_in  (gtwiz_buffbypass_rx_done_int      ),
		.o_out (gtwiz_buffbypass_rx_done_vio_sync )
	);

	// Synchronize gtwiz_buffbypass_rx_error into the free-running clock domain for VIO usage
	logic [3:0] gtwiz_buffbypass_rx_error_vio_sync;

	(* DONT_TOUCH = "TRUE" *)
	Synchroniser #(.WIDTH('d4)) bus_synchronizer_vio_gtwiz_buffbypass_rx_error_0_inst (
		.clk_in(hb_gtwiz_reset_clk_freerun_buf_int),
		.i_in  (gtwiz_buffbypass_rx_error_int     ),
		.o_out (gtwiz_buffbypass_rx_error_vio_sync)
	);

	// Synchronize txprbssel into the TXUSRCLK2 clock domain from VIO usage
	logic [15:0] txprbssel_vio_async;

	genvar gn_txprbssel_vio;
	generate
		for (gn_txprbssel_vio = 0; gn_txprbssel_vio < 4; gn_txprbssel_vio = gn_txprbssel_vio + 1)
			(* DONT_TOUCH = "TRUE" *)
			Synchroniser #(.WIDTH('d4)) bus_synchronizer_vio_txprbssel_inst (
				.clk_in(hb0_gtwiz_userclk_tx_usrclk2_int[gn_txprbssel_vio]          ),
				.i_in  (txprbssel_vio_async[gn_txprbssel_vio*4+3:gn_txprbssel_vio*4]),
				.o_out (txprbssel_int[gn_txprbssel_vio*4+3:gn_txprbssel_vio*4]      )
			);
	endgenerate

	// Synchronize txinhibit into the TXUSRCLK2 clock domains from VIO usage
	logic [3:0] txinhibit_vio_async;

	genvar gn_txinhibit_vio;
	generate
		for (gn_txinhibit_vio = 0; gn_txinhibit_vio < 4; gn_txinhibit_vio = gn_txinhibit_vio + 1) begin
			(* DONT_TOUCH = "TRUE" *)
			Synchroniser #(.WIDTH('d1)) bit_synchronizer_vio_txinhibit_inst (
				.clk_in(hb0_gtwiz_userclk_tx_usrclk2_int[gn_txinhibit_vio]),
				.i_in  (txinhibit_vio_async[gn_txinhibit_vio]             ),
				.o_out (txinhibit_int[gn_txinhibit_vio]                   )
			);
			assign tx_inhibit_out[gn_txinhibit_vio] = txinhibit_int[gn_txinhibit_vio];
		end
	endgenerate

	// Synchronize txrate into the TXUSRCLK2 clock domains from VIO usage
	logic [11:0] txrate_vio_async;

	genvar gn_txrate_vio;
	generate
		for (gn_txrate_vio = 0; gn_txrate_vio < 4; gn_txrate_vio = gn_txrate_vio + 1) begin
			(* DONT_TOUCH = "TRUE" *)
			Synchroniser #(.WIDTH('d3)) bus_synchronizer_vio_txrate_inst (
				.clk_in(hb0_gtwiz_userclk_tx_usrclk2_int[gn_txrate_vio]    ),
				.i_in  (txrate_vio_async[gn_txrate_vio*3+2:gn_txrate_vio*3]),
				.o_out (txrate_int[gn_txrate_vio*3+2:gn_txrate_vio*3]      )
			);
		end
	endgenerate

	// Synchronize rxinhibit into the TXUSRCLK2 clock domains from VIO usage
	logic [3:0] rxinhibit_vio_async;

	genvar gn_rxinhibit_vio;
	generate
		for (gn_rxinhibit_vio = 0; gn_rxinhibit_vio < 4; gn_rxinhibit_vio = gn_rxinhibit_vio + 1) begin
			(* DONT_TOUCH = "TRUE" *)
			Synchroniser #(.WIDTH('d1)) bit_synchronizer_vio_rxinhibit_inst (
				.clk_in(hb0_gtwiz_userclk_rx_usrclk2_int[gn_rxinhibit_vio]),
				.i_in  (rxinhibit_vio_async[gn_rxinhibit_vio]             ),
				.o_out (rxinhibit_int[gn_rxinhibit_vio]                   )
			);
			assign rx_inhibit_out[gn_rxinhibit_vio] = rxinhibit_int[gn_rxinhibit_vio];
		end
	endgenerate

	// Synchronize rxinhibit into the TXUSRCLK2 clock domains from VIO usage
	logic JtagAxiMstExtReset_vio_async;
	logic JtagAxiMstExtReset_int;

	(* DONT_TOUCH = "TRUE" *)
	ResetSynchroniser reset_synchronizer_vio_JtagAxiMstExtResetn_inst (
		.clk_in   (aclk_in                     ),
		.reset_in (JtagAxiMstExtReset_vio_async),
		.reset_out(JtagAxiMstExtReset_int      )
	);

	assign JtagAxiMstExtResetn_out = ~JtagAxiMstExtReset_int;

	// rxrate doesn't need synchronisation as its on the same clock domain as the IBERT, which it goes through first
	logic [11:0] rxrate_vio_async;

	// Instantiate the VIO IP core for hardware bring-up and debug purposes, connecting relevant debug and analysis
	// signals which have been enabled during Wizard IP customization. This initial set of connected signals is
	// provided as a convenience and example, but more or fewer ports can be used as needed; simply re-customize and
	// re-generate the VIO instance, then connect any exposed signals that are needed. Signals which are synchronous to
	// clocks other than the free-running clock will require synchronization. For usage, refer to Vivado Design Suite
	// User Guide: Programming and Debugging (UG908)
	GtWizardVio i_GtWizardVio (
		.clk        (hb_gtwiz_reset_clk_freerun_buf_int        ),
		.probe_in0  (init_done_int                             ),
		.probe_in1  (init_retry_ctr_int                        ),
		.probe_in2  (gtpowergood_vio_sync                      ),
		.probe_in3  (txpmaresetdone_vio_sync                   ),
		.probe_in4  (rxpmaresetdone_vio_sync                   ),
		.probe_in5  (gtwiz_reset_tx_done_vio_sync              ),
		.probe_in6  (gtwiz_reset_rx_done_vio_sync              ),
		.probe_in7  (gtwiz_buffbypass_rx_done_vio_sync         ),
		.probe_in8  (gtwiz_buffbypass_rx_error_vio_sync        ),
		.probe_in9  (cm0_qpll0locked_vio_sync                  ),
		.probe_out0 (hb_gtwiz_reset_all_vio_int                ),
		.probe_out1 (hb0_gtwiz_reset_tx_pll_and_datapath_int   ),
		.probe_out2 (hb0_gtwiz_reset_tx_datapath_int           ),
		.probe_out3 (hb_gtwiz_reset_rx_pll_and_datapath_vio_int),
		.probe_out4 (hb_gtwiz_reset_rx_datapath_vio_int        ),
		.probe_out5 (rxdfelpmreset_int                         ),
		.probe_out6 (txinhibit_vio_async                       ),
		.probe_out7 (txprbssel_vio_async                       ),
		.probe_out8 (rxinhibit_vio_async                       ),
		.probe_out9 (JtagAxiMstExtReset_vio_async              ),
		.probe_out10(ScopeTriggerSrc_int                       ),
		.probe_out11(txrate_vio_async                          ),
		.probe_out12(rxrate_vio_async                          )
	);

	// ===================================================================================================================
	// IN-SYSTEM IBERT FOR HARDWARE BRING-UP AND LINK ANALYSIS
	// ===================================================================================================================

	// Instantiate the In-System IBERT IP core for hardware bring-up and link analysis purposes. For usage, refer to
	// Vivado Design Suite User Guide: Programming and Debugging (UG908)
	// In-System IBERT IP instance property dictionary is as follows:
	// CONFIG.C_GT_TYPE {GTY} CONFIG.C_GTS_USED {X0Y8 X0Y9 X0Y10 X0Y11} CONFIG.C_ENABLE_INPUT_PORTS {true}
	in_system_ibert_0 i_in_system_ibert_0 (
		.drpclk_o      (drpclk_int                             ),
		.gt0_drpen_o   (drpen_int[0:0]                         ),
		.gt0_drpwe_o   (drpwe_int[0:0]                         ),
		.gt0_drpaddr_o (drpaddr_int[9:0]                       ),
		.gt0_drpdi_o   (drpdi_int[15:0]                        ),
		.gt0_drprdy_i  (drprdy_int[0:0]                        ),
		.gt0_drpdo_i   (drpdo_int[15:0]                        ),
		.gt1_drpen_o   (drpen_int[1:1]                         ),
		.gt1_drpwe_o   (drpwe_int[1:1]                         ),
		.gt1_drpaddr_o (drpaddr_int[19:10]                     ),
		.gt1_drpdi_o   (drpdi_int[31:16]                       ),
		.gt1_drprdy_i  (drprdy_int[1:1]                        ),
		.gt1_drpdo_i   (drpdo_int[31:16]                       ),
		.gt2_drpen_o   (drpen_int[2:2]                         ),
		.gt2_drpwe_o   (drpwe_int[2:2]                         ),
		.gt2_drpaddr_o (drpaddr_int[29:20]                     ),
		.gt2_drpdi_o   (drpdi_int[47:32]                       ),
		.gt2_drprdy_i  (drprdy_int[2:2]                        ),
		.gt2_drpdo_i   (drpdo_int[47:32]                       ),
		.gt3_drpen_o   (drpen_int[3:3]                         ),
		.gt3_drpwe_o   (drpwe_int[3:3]                         ),
		.gt3_drpaddr_o (drpaddr_int[39:30]                     ),
		.gt3_drpdi_o   (drpdi_int[63:48]                       ),
		.gt3_drprdy_i  (drprdy_int[3:3]                        ),
		.gt3_drpdo_i   (drpdo_int[63:48]                       ),
		.eyescanreset_o(eyescanreset_int                       ),
		.rxrate_o      (rxrate_int                             ),
		.txdiffctrl_o  (txdiffctrl_int                         ),
		.txprecursor_o (txprecursor_int                        ),
		.txpostcursor_o(txpostcursor_int                       ),
		.rxlpmen_o     (rxlpmen_int                            ),
		.rxrate_i      (rxrate_vio_async                       ),
		.txdiffctrl_i  ({4{5'b01110}}                          ),
		.txprecursor_i ({4{5'b00001}}                          ),
		.txpostcursor_i({4{5'b10100}}                          ),
		.rxlpmen_i     ({4{1'b1}}                              ),
		.rxoutclk_i    (hb0_gtwiz_userclk_rx_usrclk2_int[3:0]  ),
		.drpclk_i      ({4{hb_gtwiz_reset_clk_freerun_buf_int}}),
		.clk           (hb_gtwiz_reset_clk_freerun_buf_int     )
	);

	// ===================================================================================================================
	// EXAMPLE WRAPPER INSTANCE
	// ===================================================================================================================

	// Instantiate the example design wrapper, mapping its enabled ports to per-channel internal signals and example
	// resources as appropriate
	GtyWrapper GtyWrapper_inst (
		.gtyrxn_in                         (gtyrxn_int                                 ),
		.gtyrxp_in                         (gtyrxp_int                                 ),
		.gtytxn_out                        (gtytxn_int                                 ),
		.gtytxp_out                        (gtytxp_int                                 ),
		.gtwiz_userclk_tx_reset_in         (gtwiz_userclk_tx_reset_int                 ),
		.gtwiz_userclk_tx_srcclk_out       (gtwiz_userclk_tx_srcclk_int                ),
		.gtwiz_userclk_tx_usrclk_out       (gtwiz_userclk_tx_usrclk_int                ),
		.gtwiz_userclk_tx_usrclk2_out      (gtwiz_userclk_tx_usrclk2_int               ),
		.gtwiz_userclk_tx_active_out       (gtwiz_userclk_tx_active_int                ),
		.gtwiz_userclk_rx_reset_in         (gtwiz_userclk_rx_reset_int                 ),
		.gtwiz_userclk_rx_srcclk_out       (gtwiz_userclk_rx_srcclk_int                ),
		.gtwiz_userclk_rx_usrclk_out       (gtwiz_userclk_rx_usrclk_int                ),
		.gtwiz_userclk_rx_usrclk2_out      (gtwiz_userclk_rx_usrclk2_int               ),
		.gtwiz_userclk_rx_active_out       (gtwiz_userclk_rx_active_int                ),
		.gtwiz_buffbypass_rx_reset_in      (gtwiz_buffbypass_rx_reset_int              ),
		.gtwiz_buffbypass_rx_start_user_in (gtwiz_buffbypass_rx_start_user_int         ),
		.gtwiz_buffbypass_rx_done_out      (gtwiz_buffbypass_rx_done_int               ),
		.gtwiz_buffbypass_rx_error_out     (gtwiz_buffbypass_rx_error_int              ),
		.gtwiz_reset_clk_freerun_in        ({1{hb_gtwiz_reset_clk_freerun_buf_int}}    ),
		.gtwiz_reset_all_in                ({1{hb_gtwiz_reset_all_int}}                ),
		.gtwiz_reset_tx_pll_and_datapath_in(gtwiz_reset_tx_pll_and_datapath_int        ),
		.gtwiz_reset_tx_datapath_in        (gtwiz_reset_tx_datapath_int                ),
		.gtwiz_reset_rx_pll_and_datapath_in({1{hb_gtwiz_reset_rx_pll_and_datapath_int}}),
		.gtwiz_reset_rx_datapath_in        ({1{hb_gtwiz_reset_rx_datapath_int}}        ),
		.gtwiz_reset_rx_cdr_stable_out     (gtwiz_reset_rx_cdr_stable_int              ),
		.gtwiz_reset_tx_done_out           (gtwiz_reset_tx_done_int                    ),
		.gtwiz_reset_rx_done_out           (gtwiz_reset_rx_done_int                    ),
		.gtwiz_userdata_tx_in              (gtwiz_userdata_tx_int                      ),
		.gtwiz_userdata_rx_out             (gtwiz_userdata_rx_int                      ),
		.gtrefclk00_in                     (gtrefclk00_int                             ),
		.qpll0outclk_out                   (qpll0outclk_int                            ),
		.qpll0outrefclk_out                (qpll0outrefclk_int                         ),
		.qpll0locked_out                   (qpll0locked_int                            ),
		.dmonitorclk_in                    (dmonitorclk_int                            ),
		.drpaddr_in                        (drpaddr_int                                ),
		.drpclk_in                         (drpclk_int                                 ),
		.drpdi_in                          (drpdi_int                                  ),
		.drpen_in                          (drpen_int                                  ),
		.drpwe_in                          (drpwe_int                                  ),
		.eyescanreset_in                   (eyescanreset_int                           ),
		.rxcdrhold_in                      (rxcdrhold_int                              ),
		.rxcdrovrden_in                    (rxcdrovrden_int                            ),
		.rxdfelpmreset_in                  (rxdfelpmreset_int                          ),
		.rxlpmen_in                        (rxlpmen_int                                ),
		.rxrate_in                         (rxrate_int                                 ),
		.txdiffctrl_in                     (txdiffctrl_int                             ),
		.txinhibit_in                      (txinhibit_int                              ),
		.txpippmen_in                      (txpippmen_int                              ),
		.txpippmovrden_in                  (txpippmovrden_int                          ),
		.txpippmpd_in                      (txpippmpd_int                              ),
		.txpippmsel_in                     (txpippmsel_int                             ),
		.txpippmstepsize_in                (txpippmstepsize_int                        ),
		.txpostcursor_in                   (txpostcursor_int                           ),
		.txprbssel_in                      (txprbssel_int                              ),
		.txprecursor_in                    (txprecursor_int                            ),
		.txrate_in                         (txrate_int                                 ),
		.dmonitorout_out                   (dmonitorout_int                            ),
		.drpdo_out                         (drpdo_int                                  ),
		.drprdy_out                        (drprdy_int                                 ),
		.gtpowergood_out                   (gtpowergood_int                            ),
		.rxpmaresetdone_out                (rxpmaresetdone_int                         ),
		.txpmaresetdone_out                (txpmaresetdone_int                         )
	);

endmodule
