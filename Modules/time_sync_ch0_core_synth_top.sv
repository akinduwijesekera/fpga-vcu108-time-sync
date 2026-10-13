module time_sync_ch0_core_synth_top (
    input  logic clk,
    input  logic rst,
    output logic [79:0] gty_tx_data,
    input  logic [79:0] gty_rx_data
);

    time_sync_ch0_core u_core (
        .tx_clk      (clk),
        .tx_rst      (rst),
        .gty_tx_data (gty_tx_data),

        .rx_clk      (clk),
        .rx_rst      (rst),
        .gty_rx_data (gty_rx_data),

        .dbg_start_tx       (),
        .dbg_tx_done        (),
        .dbg_tx_seq_id      (),
        .dbg_enc_valid      (),
        .dbg_enc_err        (),

        .dbg_pcs_sof        (),
        .dbg_pcs_frame_done (),
        .dbg_pcs_frame_err  (),
        .dbg_pcs_ctrl_err   (),
        .dbg_pcs_sym_err    (),

        .dbg_crc_ok         (),
        .dbg_crc_fail       (),
        .dbg_crc_len_err    (),

        .dbg_df_done        (),
        .dbg_etype_ok       (),
        .dbg_etype_err      (),
        .dbg_df_len_err     (),

        .dbg_pkt_valid      (),
        .dbg_pkt_done       (),
        .dbg_pkt_len_err    (),
        .dbg_rx_msg_type    (),
        .dbg_rx_seq_id      (),
        .dbg_rx_tod_sec     (),
        .dbg_rx_tod_nsec    (),
        .dbg_rx_tod_frac    ()
    );

endmodule
