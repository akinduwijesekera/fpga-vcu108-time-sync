`timescale 1ns/1ps

module sync_loopback_top (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start_tx,
    input  logic [7:0]  msg_type,

    input  logic [47:0] dst_mac,
    input  logic [47:0] src_mac,
    input  logic [15:0] ether_type,

    input  logic [47:0] tx_tod_sec,
    input  logic [31:0] tx_tod_nsec,
    input  logic [15:0] tx_tod_frac,

    input  logic [47:0] rx_local_sec,
    input  logic [31:0] rx_local_nsec,
    input  logic [15:0] rx_local_frac,

    output logic        tx_done,
    output logic [15:0] seq_id_out,

    output logic        pkt_valid,
    output logic [15:0] rx_seq_id,

    output logic        diff_valid,
    output logic [47:0] diff_sec,
    output logic [31:0] diff_nsec,
    output logic [15:0] diff_frac,
    output logic        underflow,

    output logic        enc_err,
    output logic        dec_any_err,
    output logic        rx_frame_err,
    output logic        rx_crc_fail,
    output logic        pkt_err
);

    // ------------------------------------------------------------
    // AXI stream interfaces
    // ------------------------------------------------------------
    axi_stream_if #(64) axis_tx_to_crc(clk);

    // TX CRC to TX PCS now has a register slice between them
    axi_stream_if #(64) axis_crc_to_tx_slice(clk);
    axi_stream_if #(64) axis_tx_slice_to_pcs(clk);

    // RX PCS to RX CRC has a register slice between them
    axi_stream_if #(64) axis_rxpcs_to_slice(clk);
    axi_stream_if #(64) axis_slice_to_crc(clk);

    axi_stream_if #(64) axis_crc_to_packet(clk);

    // ------------------------------------------------------------
    // TX CRC status
    // ------------------------------------------------------------
    logic tx_crc_busy;
    logic tx_crc_done;

    // ------------------------------------------------------------
    // TX PCS / encoder signals
    // ------------------------------------------------------------
    logic [63:0] tx_sym_data;
    logic [7:0]  tx_sym_is_k;
    logic        tx_sym_valid;
    logic        tx_sym_ready;

    logic [79:0] code80;
    logic        code80_valid;
    logic        code80_ready;

    logic tx_pcs_busy;
    logic tx_pcs_done;
    logic tx_pcs_overflow;

    // ------------------------------------------------------------
    // Decoder / RX PCS signals
    // ------------------------------------------------------------
    logic [63:0] rx_sym_data;
    logic [7:0]  rx_sym_is_k;
    logic        rx_sym_valid;
    logic        rx_sym_ready;

    logic [7:0]  dec_code_err;
    logic [7:0]  dec_rd_err;

    logic rx_in_frame;
    logic rx_sof_strobe;
    logic rx_frame_done;
    logic rx_ctrl_err;
    logic rx_sym_err;

    // ------------------------------------------------------------
    // RX CRC status
    // ------------------------------------------------------------
    logic rx_crc_busy;
    logic rx_crc_ok;
    logic rx_crc_len_err;

    // ------------------------------------------------------------
    // Packet RX outputs
    // ------------------------------------------------------------
    logic [47:0] rx_dst_mac;
    logic [47:0] rx_src_mac;
    logic [15:0] rx_ether_type;

    logic [7:0]  rx_msg_type;
    logic [7:0]  rx_version;
    logic [7:0]  rx_flags;
    logic [7:0]  rx_reserved;

    logic [47:0] rx_tx_tod_sec;
    logic [31:0] rx_tx_tod_nsec;
    logic [15:0] rx_tx_tod_frac;

    logic pkt_done;
    logic pkt_len_err;
    logic ether_type_err;
    logic version_err;
    logic pr_busy;

    // ------------------------------------------------------------
    // TX packet/framer
    // ------------------------------------------------------------
    tx_packet_framer #(
        .PTP_LITE_VERSION   (8'h01),
        .DEFAULT_FLAGS      (8'h00),
        .DEFAULT_RESERVED   (8'h00),
        .DEFAULT_DST_MAC    (48'hDA_02_03_04_05_06),
        .DEFAULT_SRC_MAC    (48'h5A_02_03_04_05_06),
        .DEFAULT_ETHER_TYPE (16'h88F7)
    ) u_tx_packet_framer (
        .clk        (clk),
        .rst_n      (rst_n),

        .start_tx   (start_tx),
        .msg_type   (msg_type),

        .dst_mac    (dst_mac),
        .src_mac    (src_mac),
        .ether_type (ether_type),

        .tod_sec    (tx_tod_sec),
        .tod_nsec   (tx_tod_nsec),
        .tod_frac   (tx_tod_frac),

        .m_axis     (axis_tx_to_crc.master),

        .tx_busy    (),
        .tx_done    (tx_done),
        .seq_id_out (seq_id_out)
    );

    // ------------------------------------------------------------
    // Append TX CRC/FCS
    // ------------------------------------------------------------
    crc_append_axis u_crc_append_axis (
        .clk      (clk),
        .rst_n    (rst_n),

        .s_axis   (axis_tx_to_crc.slave),
        .m_axis   (axis_crc_to_tx_slice.master),

        .crc_busy (tx_crc_busy),
        .crc_done (tx_crc_done)
    );

    // ------------------------------------------------------------
    // AXI register slice between TX CRC append and TX PCS
    //
    // Breaks timing path:
    //   crc_append_axis output/tkeep/control -> tx_pcs frame memory/control
    // ------------------------------------------------------------
    axis_register_slice #(
        .WIDTH(64)
    ) u_axis_slice_crc_to_txpcs (
        .clk    (clk),
        .rst_n  (rst_n),

        .s_axis (axis_crc_to_tx_slice.slave),
        .m_axis (axis_tx_slice_to_pcs.master)
    );

    // ------------------------------------------------------------
    // TX PCS
    // ------------------------------------------------------------
    tx_pcs #(
        .MAX_FRAME_BYTES(64)
    ) u_tx_pcs (
        .clk                  (clk),
        .rst_n                (rst_n),

        .s_axis               (axis_tx_slice_to_pcs.slave),

        .sym_data             (tx_sym_data),
        .sym_is_k             (tx_sym_is_k),
        .sym_valid            (tx_sym_valid),
        .sym_ready            (tx_sym_ready),

        .pcs_busy             (tx_pcs_busy),
        .pcs_done             (tx_pcs_done),
        .frame_overflow_error (tx_pcs_overflow)
    );

    // ------------------------------------------------------------
    // 8b/10b encoder
    // ------------------------------------------------------------
    enc_64b80b u_enc_64b80b (
        .clk        (clk),
        .rst_n      (rst_n),

        .data_in    (tx_sym_data),
        .is_k_in    (tx_sym_is_k),
        .valid_in   (tx_sym_valid),
        .ready_in   (tx_sym_ready),

        .code80_out (code80),
        .valid_out  (code80_valid),
        .ready_out  (code80_ready),

        .enc_err    (enc_err)
    );

    // ------------------------------------------------------------
    // 8b/10b decoder
    // Digital loopback: encoder output directly feeds decoder input.
    // ------------------------------------------------------------
    dec_80b64b u_dec_80b64b (
        .clk        (clk),
        .rst_n      (rst_n),

        .code80_in  (code80),
        .valid_in   (code80_valid),
        .ready_in   (code80_ready),

        .data_out   (rx_sym_data),
        .is_k_out   (rx_sym_is_k),
        .valid_out  (rx_sym_valid),
        .ready_out  (rx_sym_ready),

        .code_err   (dec_code_err),
        .rd_err     (dec_rd_err),
        .any_err    (dec_any_err)
    );

    // ------------------------------------------------------------
    // RX PCS
    // ------------------------------------------------------------
    rx_pcs #(
        .FIFO_DEPTH(16)
    ) u_rx_pcs (
        .clk           (clk),
        .rst_n         (rst_n),

        .sym_data      (rx_sym_data),
        .sym_is_k      (rx_sym_is_k),
        .sym_valid     (rx_sym_valid),
        .sym_ready     (rx_sym_ready),

        .code_err_in   (dec_code_err),
        .rd_err_in     (dec_rd_err),
        .any_err_in    (dec_any_err),

        .m_axis        (axis_rxpcs_to_slice.master),

        .in_frame      (rx_in_frame),
        .rx_sof_strobe (rx_sof_strobe),
        .frame_done    (rx_frame_done),
        .frame_err     (rx_frame_err),
        .ctrl_err      (rx_ctrl_err),
        .sym_err       (rx_sym_err)
    );

    // ------------------------------------------------------------
    // AXI register slice between RX PCS and CRC checker
    //
    // Breaks timing path:
    //   rx_pcs FIFO read/control -> crc32_check frame buffer/control
    // ------------------------------------------------------------
    axis_register_slice #(
        .WIDTH(64)
    ) u_axis_slice_rxpcs_to_crc (
        .clk    (clk),
        .rst_n  (rst_n),

        .s_axis (axis_rxpcs_to_slice.slave),
        .m_axis (axis_slice_to_crc.master)
    );

    // ------------------------------------------------------------
    // RX CRC check
    // ------------------------------------------------------------
    crc32_check #(
        .OUT_FRAME_BYTES(32),
        .FCS_BYTES      (4)
    ) u_crc32_check (
        .clk      (clk),
        .rst_n    (rst_n),

        .s_axis   (axis_slice_to_crc.slave),
        .m_axis   (axis_crc_to_packet.master),

        .crc_busy (rx_crc_busy),
        .crc_ok   (rx_crc_ok),
        .crc_fail (rx_crc_fail),
        .len_err  (rx_crc_len_err)
    );

    // ------------------------------------------------------------
    // Packet parser
    // ------------------------------------------------------------
    packet_rx #(
        .EXPECTED_ETHER_TYPE(16'h88F7),
        .EXPECTED_VERSION   (8'h01),
        .CHECK_ETHER_TYPE   (1'b1),
        .CHECK_VERSION      (1'b1)
    ) u_packet_rx (
        .clk            (clk),
        .rst_n          (rst_n),

        .s_axis         (axis_crc_to_packet.slave),

        .dst_mac        (rx_dst_mac),
        .src_mac        (rx_src_mac),
        .ether_type     (rx_ether_type),

        .msg_type       (rx_msg_type),
        .version        (rx_version),
        .seq_id         (rx_seq_id),
        .flags          (rx_flags),
        .reserved       (rx_reserved),

        .tx_tod_sec     (rx_tx_tod_sec),
        .tx_tod_nsec    (rx_tx_tod_nsec),
        .tx_tod_frac    (rx_tx_tod_frac),

        .pkt_valid      (pkt_valid),
        .pkt_done       (pkt_done),
        .len_err        (pkt_len_err),
        .ether_type_err (ether_type_err),
        .version_err    (version_err),
        .pkt_err        (pkt_err),

        .pr_busy        (pr_busy)
    );

    // ------------------------------------------------------------
    // Timestamp difference
    // ------------------------------------------------------------
    timestamp_diff u_timestamp_diff (
        .clk            (clk),
        .rst_n          (rst_n),

        .valid_in       (pkt_valid),

        .rx_local_sec   (rx_local_sec),
        .rx_local_nsec  (rx_local_nsec),
        .rx_local_frac  (rx_local_frac),

        .tx_stamp_sec   (rx_tx_tod_sec),
        .tx_stamp_nsec  (rx_tx_tod_nsec),
        .tx_stamp_frac  (rx_tx_tod_frac),

        .diff_valid     (diff_valid),
        .diff_sec       (diff_sec),
        .diff_nsec      (diff_nsec),
        .diff_frac      (diff_frac),
        .underflow      (underflow)
    );

endmodule
