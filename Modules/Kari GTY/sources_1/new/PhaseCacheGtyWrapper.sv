`timescale 1ns / 1ps
// @module PhaseCacheGty
//
// @date 12.02.2025
//
// @brief Links the phase caching circuitry out to transceivers
//
// @file PhaseCacheGtyWrapper.sv
//
// @author Kari Clark (Salisen), University College London


module PhaseCacheGtyWrapper (
        // Differential reference clock inputs
        input  logic       mgtrefclk0_p_in              ,
        input  logic       mgtrefclk0_n_in              ,
        // Serial data ports for phase cache transciever
        input  logic       ch0_gtyrxn_in                ,
        input  logic       ch0_gtyrxp_in                ,
        output logic       ch0_gtytxn_out               ,
        output logic       ch0_gtytxp_out               ,
        input  logic       ch1_gtyrxn_in                ,
        input  logic       ch1_gtyrxp_in                ,
        output logic       ch1_gtytxn_out               ,
        output logic       ch1_gtytxp_out               ,
        input  logic       ch2_gtyrxn_in                ,
        input  logic       ch2_gtyrxp_in                ,
        output logic       ch2_gtytxn_out               ,
        output logic       ch2_gtytxp_out               ,
        input  logic       ch3_gtyrxn_in                ,
        input  logic       ch3_gtyrxp_in                ,
        output logic       ch3_gtytxn_out               ,
        output logic       ch3_gtytxp_out               ,
        // User-provided ports for reset helper block(s)
        input  logic       hb_gtwiz_reset_clk_freerun_in,
        input  logic       hb_gtwiz_reset_all_in        //,
        // Delta-sigma sequence signals

    );


    // Instantiate signals passed between GTY transceivers and modules implemented in the parallel domain

    logic [3:0] tx_usrclk2_int;
    logic [3:0] rx_usrclk2_int;

    logic [3:0] tx_init_done_int;
    logic [3:0] rx_init_done_int;

    logic [3:0] tx_inhibit_int;
    logic [3:0] rx_inhibit_int;

    logic [79:0] ch0_tx_par_data_int;
    logic [79:0] ch0_rx_par_data_int;
    logic [79:0] ch1_tx_par_data_int;
    logic [79:0] ch1_rx_par_data_int;
    logic [79:0] ch2_tx_par_data_int;
    logic [79:0] ch2_rx_par_data_int;
    logic [79:0] ch3_tx_par_data_int;
    logic [79:0] ch3_rx_par_data_int;


    // Instantiation of the GTY Wizard block

    GtyQuad i_GtyQuad (
        // Reference clock input
        .mgtrefclk0_p_in              (mgtrefclk0_p_in              ),
        .mgtrefclk0_n_in              (mgtrefclk0_n_in              ),
        // Serial receiver and transmitter signals entering and leaving FPGA
        .ch0_gtyrxn_in                (ch0_gtyrxn_in                ),
        .ch0_gtyrxp_in                (ch0_gtyrxp_in                ),
        .ch0_gtytxn_out               (ch0_gtytxn_out               ),
        .ch0_gtytxp_out               (ch0_gtytxp_out               ),
        .ch1_gtyrxn_in                (ch1_gtyrxn_in                ),
        .ch1_gtyrxp_in                (ch1_gtyrxp_in                ),
        .ch1_gtytxn_out               (ch1_gtytxn_out               ),
        .ch1_gtytxp_out               (ch1_gtytxp_out               ),
        .ch2_gtyrxn_in                (ch2_gtyrxn_in                ),
        .ch2_gtyrxp_in                (ch2_gtyrxp_in                ),
        .ch2_gtytxn_out               (ch2_gtytxn_out               ),
        .ch2_gtytxp_out               (ch2_gtytxp_out               ),
        .ch3_gtyrxn_in                (ch3_gtyrxn_in                ),
        .ch3_gtyrxp_in                (ch3_gtyrxp_in                ),
        .ch3_gtytxn_out               (ch3_gtytxn_out               ),
        .ch3_gtytxp_out               (ch3_gtytxp_out               ),
        // Parallel transmitter and receiver clocks (for each channel)
        .tx_usrclk2_out               (tx_usrclk2_int               ),
        .rx_usrclk2_out               (rx_usrclk2_int               ),
        // Signal to indicate parallel transmitter and receiver are ready (for each channel)
        //   -> Use the inverse of this as a synchronous reset
        .tx_init_done_out             (tx_init_done_int             ),
        .rx_init_done_out             (rx_init_done_int             ),
        // Signal used to inhibit operation of circuitry (for each channel, optional)
        .tx_inhibit_out               (tx_inhibit_int               ),
        .rx_inhibit_out               (rx_inhibit_int               ),
        // Parallel transmitter and receiver data buses (for each channel)
        .ch0_rx_par_data_out          (ch0_rx_par_data_int          ),
        .ch0_tx_par_data_in           (ch0_tx_par_data_int          ),
        .ch1_rx_par_data_out          (ch1_rx_par_data_int          ),
        .ch1_tx_par_data_in           (ch1_tx_par_data_int          ),
        .ch2_rx_par_data_out          (ch2_rx_par_data_int          ),
        .ch2_tx_par_data_in           (ch2_tx_par_data_int          ),
        .ch3_rx_par_data_out          (ch3_rx_par_data_int          ),
        .ch3_tx_par_data_in           (ch3_tx_par_data_int          ),
        // Free-running clock and reset to configure and startup serial transceiver
        .hb_gtwiz_reset_clk_freerun_in(hb_gtwiz_reset_clk_freerun_in),
        .hb_gtwiz_reset_all_in        (hb_gtwiz_reset_all_in        ),
        .hb_gtwiz_reset_all_comb_out  (hb_gtwiz_reset_all_comb_int  )
    );

    // Example circuitry to drive each channel's transmitter with a repeating 01 sequence
    // and receive the data from each channel's receiver with an integrated logic analyser (ILA)

    // ============================================================================
    // Channel 0: Time synchronisation core
    // ============================================================================

    logic ch0_tx_par_reset;
    logic ch0_tx_par_clk;

    logic ch0_rx_par_reset;
    logic ch0_rx_par_clk;

    assign ch0_tx_par_reset = ~tx_init_done_int[0];
    assign ch0_tx_par_clk   = tx_usrclk2_int[0];

    assign ch0_rx_par_reset = ~rx_init_done_int[0];
    assign ch0_rx_par_clk   = rx_usrclk2_int[0];

    time_sync_ch0_core u_time_sync_ch0_core (
        .tx_clk      (ch0_tx_par_clk),
        .tx_rst      (ch0_tx_par_reset),
        .gty_tx_data (ch0_tx_par_data_int),

        .rx_clk      (ch0_rx_par_clk),
        .rx_rst      (ch0_rx_par_reset),
        .gty_rx_data (ch0_rx_par_data_int),

        // leave debug outputs unconnected for now
        .dbg_start_tx        (),
        .dbg_tx_done         (),
        .dbg_tx_seq_id       (),
        .dbg_enc_valid       (),
        .dbg_enc_err         (),

        .dbg_pcs_sof         (),
        .dbg_pcs_frame_done  (),
        .dbg_pcs_frame_err   (),
        .dbg_pcs_ctrl_err    (),
        .dbg_pcs_sym_err     (),

        .dbg_crc_ok          (),
        .dbg_crc_fail        (),
        .dbg_crc_len_err     (),

        .dbg_df_done         (),
        .dbg_etype_ok        (),
        .dbg_etype_err       (),
        .dbg_df_len_err      (),

        .dbg_pkt_valid       (),
        .dbg_pkt_done        (),
        .dbg_pkt_len_err     (),
        .dbg_rx_msg_type     (),
        .dbg_rx_seq_id       (),
        .dbg_rx_tod_sec      (),
        .dbg_rx_tod_nsec     (),
        .dbg_rx_tod_frac     ()
    );

    // Keep ILA on raw channel 0 RX parallel data for link/debug
    ila_gty_trx ch0_ila_gty_rx (
        .clk    (ch0_rx_par_clk),
        .probe0 (ch0_rx_par_data_int)
    );

    // Channel 1

    logic ch1_tx_par_reset;
    logic ch1_tx_par_clk;

    assign ch1_tx_par_reset = ~tx_init_done_int[1];
    assign ch1_tx_par_clk   = tx_usrclk2_int[1];

    always_ff @(posedge ch1_tx_par_clk) begin : proc_ch1_data_gen
        if(ch1_tx_par_reset) begin
            ch1_tx_par_data_int <= 80'd0;
        end else begin
            ch1_tx_par_data_int <= {40{2'b01}};
        end
    end

    logic ch1_rx_par_reset;
    logic ch1_rx_par_clk;

    assign ch1_rx_par_reset = ~rx_init_done_int[1];
    assign ch1_rx_par_clk   = rx_usrclk2_int[1];

    ila_gty_trx ch1_ila_gty_rx (
        .clk   (ch1_rx_par_clk     ),
        .probe0(ch1_rx_par_data_int)
    );

    // Channel 2

    logic ch2_tx_par_reset;
    logic ch2_tx_par_clk;

    assign ch2_tx_par_reset = ~tx_init_done_int[2];
    assign ch2_tx_par_clk   = tx_usrclk2_int[2];

    always_ff @(posedge ch2_tx_par_clk) begin : proc_ch2_data_gen
        if(ch2_tx_par_reset) begin
            ch2_tx_par_data_int <= 80'd0;
        end else begin
            ch2_tx_par_data_int <= {40{2'b01}};
        end
    end

    logic ch2_rx_par_reset;
    logic ch2_rx_par_clk;

    assign ch2_rx_par_reset = ~rx_init_done_int[2];
    assign ch2_rx_par_clk   = rx_usrclk2_int[2];

    ila_gty_trx ch2_ila_gty_rx (
        .clk   (ch2_rx_par_clk     ),
        .probe0(ch2_rx_par_data_int)
    );

    // Channel 3

    logic ch3_tx_par_reset;
    logic ch3_tx_par_clk;

    assign ch3_tx_par_reset = ~tx_init_done_int[3];
    assign ch3_tx_par_clk   = tx_usrclk2_int[3];

    always_ff @(posedge ch3_tx_par_clk) begin : proc_ch3_data_gen
        if(ch3_tx_par_reset) begin
            ch3_tx_par_data_int <= 80'd0;
        end else begin
            ch3_tx_par_data_int <= {40{2'b01}};
        end
    end

    logic ch3_rx_par_reset;
    logic ch3_rx_par_clk;

    assign ch3_rx_par_reset = ~rx_init_done_int[3];
    assign ch3_rx_par_clk   = rx_usrclk2_int[3];

    ila_gty_trx ch3_ila_gty_rx (
        .clk   (ch3_rx_par_clk     ),
        .probe0(ch3_rx_par_data_int)
    );


endmodule
