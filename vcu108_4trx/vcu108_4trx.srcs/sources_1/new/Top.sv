`timescale 1ns / 1ps
// @module Top
//
// @date 12.03.2018
// 
// @brief Top level file for Phase Caching design.  Designed to contain IOBUFs and a clock
//    wizard only.  The phase caching module and MicroBlaze are instantiated here.
//
// @file Top.sv
//
// @author Kari Clark (Salisen), University College London

module Top (
		// GT top level ports
		output        ch0_gtytxn_out    ,
		output        ch0_gtytxp_out    ,
		input         ch0_gtyrxn_in     ,
		input         ch0_gtyrxp_in     ,
		output        ch1_gtytxn_out    ,
		output        ch1_gtytxp_out    ,
		input         ch1_gtyrxn_in     ,
		input         ch1_gtyrxp_in     ,
		output        ch2_gtytxn_out    ,
		output        ch2_gtytxp_out    ,
		input         ch2_gtyrxn_in     ,
		input         ch2_gtyrxp_in     ,
		output        ch3_gtytxn_out    ,
		output        ch3_gtytxp_out    ,
		input         ch3_gtyrxn_in     ,
		input         ch3_gtyrxp_in     ,
		input         SysClk_clk_p      ,
		input         SysClk_clk_n      ,
		input         CpuReset_in       ,
		input         mgtrefclk0_p_in   ,
		input         mgtrefclk0_n_in
	);

    // Sysclk signals
	logic SysClkRst;
	logic SysClk   ;
	logic locked   ;

	// Generation of SysClk

	sysclk_mmcm i_sysclk_mmcm (
		.clk_in1_p(SysClk_clk_p),
		.clk_in1_n(SysClk_clk_n),
		.reset    (CpuReset_in ),
		.clk_out1 (SysClk      ),
		.locked   (locked      )
	);

	assign SysClkRst = ~locked;

	//
	// Phase cache GTY instantiation
	//
	
	PhaseCacheGtyWrapper i_PhaseCacheGtyWrapper (
		.mgtrefclk0_p_in              (mgtrefclk0_p_in),
		.mgtrefclk0_n_in              (mgtrefclk0_n_in),
		.ch0_gtyrxn_in                (ch0_gtyrxn_in  ),
		.ch0_gtyrxp_in                (ch0_gtyrxp_in  ),
		.ch0_gtytxn_out               (ch0_gtytxn_out ),
		.ch0_gtytxp_out               (ch0_gtytxp_out ),
		.ch1_gtyrxn_in                (ch1_gtyrxn_in  ),
		.ch1_gtyrxp_in                (ch1_gtyrxp_in  ),
		.ch1_gtytxn_out               (ch1_gtytxn_out ),
		.ch1_gtytxp_out               (ch1_gtytxp_out ),
		.ch2_gtyrxn_in                (ch2_gtyrxn_in  ),
		.ch2_gtyrxp_in                (ch2_gtyrxp_in  ),
		.ch2_gtytxn_out               (ch2_gtytxn_out ),
		.ch2_gtytxp_out               (ch2_gtytxp_out ),
		.ch3_gtyrxn_in                (ch3_gtyrxn_in  ),
		.ch3_gtyrxp_in                (ch3_gtyrxp_in  ),
		.ch3_gtytxn_out               (ch3_gtytxn_out ),
		.ch3_gtytxp_out               (ch3_gtytxp_out ),
		.hb_gtwiz_reset_clk_freerun_in(SysClk         ),
		.hb_gtwiz_reset_all_in        (SysClkRst      )
	);

endmodule
