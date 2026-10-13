`timescale 1ns / 1ps

module time_sync_ch0_core (
    // TX GTY user domain
    input  logic        tx_clk,
    input  logic        tx_rst,       // active high
    output logic [79:0] gty_tx_data,

    // RX GTY user domain
    input  logic        rx_clk,
    input  logic        rx_rst,       // active high
    input  logic [79:0] gty_rx_data,

    // Optional debug/status outputs
    output logic        dbg_start_tx,
    output logic        dbg_tx_done,
    output logic [15:0] dbg_tx_seq_id,
    output logic        dbg_enc_valid,
    output logic        dbg_enc_err,

    output logic        dbg_pcs_sof,
    output logic        dbg_pcs_frame_done,
    output logic        dbg_pcs_frame_err,
    output logic        dbg_pcs_ctrl_err,
    output logic        dbg_pcs_sym_err,

    output logic        dbg_crc_ok,
    output logic        dbg_crc_fail,
    output logic        dbg_crc_len_err,

    output logic        dbg_df_done,
    output logic        dbg_etype_ok,
    output logic        dbg_etype_err,
    output logic        dbg_df_len_err,

    output logic        dbg_pkt_valid,
    output logic        dbg_pkt_done,
    output logic        dbg_pkt_len_err,
    output logic [7:0]  dbg_rx_msg_type,
    output logic [15:0] dbg_rx_seq_id,
    output logic [47:0] dbg_rx_tod_sec,
    output logic [31:0] dbg_rx_tod_nsec,
    output logic [15:0] dbg_rx_tod_frac,

    // Timestamp difference / latency debug
    output logic        dbg_latency_valid,
    output logic [47:0] dbg_latency_sec,
    output logic [31:0] dbg_latency_nsec,
    output logic [15:0] dbg_latency_frac,
    output logic        dbg_latency_underflow
);

    // =========================================================================
    // Reset polarity conversion
    // =========================================================================

    logic tx_rst_n;
    logic rx_rst_n;

    assign tx_rst_n = ~tx_rst;
    assign rx_rst_n = ~rx_rst;

    // =========================================================================
    // TX side signals/interfaces
    // =========================================================================

    logic [47:0] tod_sec_tx;
    logic [31:0] tod_nsec_tx;
    logic [15:0] tod_frac_tx;

    logic        start_tx;
    logic [31:0] start_counter;

    logic        tx_busy;
    logic        tx_done;
    logic [15:0] seq_id_out;

    logic        fr_busy;
    logic        fr_done;

    logic        crc_busy;
    logic        crc_done;

    axi_stream_if #(64) axis_packet (tx_clk);
    axi_stream_if #(64) axis_framed (tx_clk);
    axi_stream_if #(64) axis_crc    (tx_clk);

    sym_stream_if sym_tx_serial(tx_clk);

    logic [63:0] tx_pack_data64;
    logic [7:0]  tx_pack_is_k8;
    logic        tx_pack_valid;

    logic [63:0] tx_mux_data64;
    logic [7:0]  tx_mux_is_k8;
    logic        tx_mux_valid;

    logic [79:0] enc_code80;
    logic        enc_valid;
    logic        enc_err;

    // =========================================================================
    // Simple periodic packet trigger for bring-up
    // =========================================================================
    // One packet every 1,000,000 tx_clk cycles.
    // Later this can be replaced with VIO/button/software control.

    always_ff @(posedge tx_clk) begin
        if (tx_rst) begin
            start_counter <= 32'd0;
            start_tx      <= 1'b0;
        end else begin
            start_tx <= (start_counter == 32'd1_000_000);

            if (start_counter == 32'd1_000_000) begin
                start_counter <= 32'd0;
            end else begin
                start_counter <= start_counter + 32'd1;
            end
        end
    end

    // =========================================================================
    // TX local time counter
    // =========================================================================

    local_time_counter u_tx_time_counter (
        .clk           (tx_clk),
        .rst_n         (tx_rst_n),
        .enable        (1'b1),

        .freq_adj_ns   (16'sd0),
        .freq_adj_frac (16'sd0),

        .tod_sec       (tod_sec_tx),
        .tod_nsec      (tod_nsec_tx),
        .tod_frac      (tod_frac_tx)
    );

    // =========================================================================
    // Packet generation
    // =========================================================================

    packet_tx u_packet_tx (
        .clk        (tx_clk),
        .rst_n      (tx_rst_n),

        .start_tx   (start_tx),
        .msg_type   (8'h00),

        .tod_sec    (tod_sec_tx),
        .tod_nsec   (tod_nsec_tx),
        .tod_frac   (tod_frac_tx),

        .m_axis     (axis_packet.master),

        .tx_busy    (tx_busy),
        .tx_done    (tx_done),
        .seq_id_out (seq_id_out)
    );

    // =========================================================================
    // TX framer
    // =========================================================================

    tx_framer u_tx_framer (
        .clk        (tx_clk),
        .rst_n      (tx_rst_n),

        .dst_mac    (48'hFF_FF_FF_FF_FF_FF),
        .src_mac    (48'h02_00_00_00_00_01),
        .ether_type (16'h88B5),

        .s_axis     (axis_packet.slave),
        .m_axis     (axis_framed.master),

        .fr_busy    (fr_busy),
        .fr_done    (fr_done)
    );

    // =========================================================================
    // CRC append
    // =========================================================================

    crc_append_axis u_crc_append_axis (
        .clk      (tx_clk),
        .rst_n    (tx_rst_n),

        .s_axis   (axis_framed.slave),
        .m_axis   (axis_crc.master),

        .crc_busy (crc_busy),
        .crc_done (crc_done)
    );

    // =========================================================================
    // AXI64 to serial 8-bit symbol stream
    // =========================================================================

    axis64_to_sym8 u_axis64_to_sym8 (
        .clk    (tx_clk),
        .rst_n  (tx_rst_n),

        .s_axis (axis_crc.slave),
        .sym    (sym_tx_serial.source)
    );

    // =========================================================================
    // Serial symbols to packed 8-symbol word
    // =========================================================================

    sym8_to_parallel64 u_sym8_to_parallel64 (
        .clk       (tx_clk),
        .rst_n     (tx_rst_n),

        .sym       (sym_tx_serial.sink),

        .data_out  (tx_pack_data64),
        .is_k_out  (tx_pack_is_k8),
        .valid_out (tx_pack_valid)
    );

    // =========================================================================
    // Idle insertion before encoder
    // =========================================================================

    sym64_idle_mux u_sym64_idle_mux (
        .clk       (tx_clk),
        .rst_n     (tx_rst_n),

        .data_in   (tx_pack_data64),
        .is_k_in   (tx_pack_is_k8),
        .valid_in  (tx_pack_valid),

        .data_out  (tx_mux_data64),
        .is_k_out  (tx_mux_is_k8),
        .valid_out (tx_mux_valid)
    );

    // =========================================================================
    // 64b/80b encoder
    // =========================================================================

    enc_64b80b u_enc_64b80b (
        .clk        (tx_clk),
        .rst        (tx_rst),

        .data_in    (tx_mux_data64),
        .is_k_in    (tx_mux_is_k8),
        .valid_in   (tx_mux_valid),

        .code80_out (enc_code80),
        .valid_out  (enc_valid),
        .enc_err    (enc_err)
    );

    // =========================================================================
    // Drive GTY TX data
    // =========================================================================

    always_ff @(posedge tx_clk) begin
        if (tx_rst) begin
            gty_tx_data <= 80'd0;
        end else if (enc_valid) begin
            gty_tx_data <= enc_code80;
        end
    end

    // =========================================================================
    // RX side signals/interfaces
    // =========================================================================

    logic [47:0] tod_sec_rx_local;
    logic [31:0] tod_nsec_rx_local;
    logic [15:0] tod_frac_rx_local;

    logic [63:0] dec_data;
    logic [7:0]  dec_is_k;
    logic        dec_valid;
    logic [7:0]  dec_code_err;
    logic [7:0]  dec_rd_err;
    logic        dec_any_err;

    axi_stream_if #(64) axis_pcs       (rx_clk);
    axi_stream_if #(64) axis_crc_check (rx_clk);
    axi_stream_if #(64) axis_payload   (rx_clk);

    logic        pcs_in_frame;
    logic        pcs_rx_sof_strobe;
    logic        pcs_frame_done;
    logic        pcs_frame_err;
    logic        pcs_ctrl_err;
    logic        pcs_sym_err;

    logic        crc_check_busy;
    logic        crc_ok;
    logic        crc_fail;
    logic        crc_len_err;

    logic [47:0] dst_mac_out;
    logic [47:0] src_mac_out;
    logic [15:0] ether_type_out;

    logic        hdr_valid;
    logic        etype_ok;
    logic        etype_err;
    logic        df_len_err;
    logic        df_busy;
    logic        df_done;

    logic [7:0]  rx_msg_type;
    logic [7:0]  rx_version;
    logic [15:0] rx_seq_id;
    logic [7:0]  rx_flags;
    logic [23:0] rx_reserved;
    logic [47:0] rx_tod_sec;
    logic [31:0] rx_tod_nsec;
    logic [15:0] rx_tod_frac;

    logic        pkt_valid;
    logic        pkt_done;
    logic        pkt_len_err;
    logic        pr_busy;

    logic        pkt_valid_d;

    logic        latency_valid;
    logic [47:0] latency_sec;
    logic [31:0] latency_nsec;
    logic [15:0] latency_frac;
    logic        latency_underflow;

    // =========================================================================
    // RX local time counter
    // =========================================================================

    local_time_counter u_rx_time_counter (
        .clk           (rx_clk),
        .rst_n         (rx_rst_n),
        .enable        (1'b1),

        .freq_adj_ns   (16'sd0),
        .freq_adj_frac (16'sd0),

        .tod_sec       (tod_sec_rx_local),
        .tod_nsec      (tod_nsec_rx_local),
        .tod_frac      (tod_frac_rx_local)
    );

    // =========================================================================
    // 80b/64b decoder
    // =========================================================================

    dec_80b64b u_dec_80b64b (
        .clk       (rx_clk),
        .rst       (rx_rst),

        .code80_in (gty_rx_data),
        .valid_in  (1'b1),

        .data_out  (dec_data),
        .is_k_out  (dec_is_k),
        .valid_out (dec_valid),

        .code_err  (dec_code_err),
        .rd_err    (dec_rd_err),
        .any_err   (dec_any_err)
    );

    // =========================================================================
    // Parallel PCS RX
    // =========================================================================

    pcs_rx64 u_pcs_rx64 (
        .clk           (rx_clk),
        .rst_n         (rx_rst_n),

        .sym_data      (dec_data),
        .sym_is_k      (dec_is_k),
        .sym_valid     (dec_valid),
        .sym_err_in    (dec_any_err),

        .m_axis        (axis_pcs.master),

        .in_frame      (pcs_in_frame),
        .rx_sof_strobe (pcs_rx_sof_strobe),
        .frame_done    (pcs_frame_done),
        .frame_err     (pcs_frame_err),
        .ctrl_err      (pcs_ctrl_err),
        .sym_err       (pcs_sym_err)
    );

    // =========================================================================
    // CRC check
    // =========================================================================

    crc32_check u_crc32_check (
        .clk      (rx_clk),
        .rst_n    (rx_rst_n),

        .s_axis   (axis_pcs.slave),
        .m_axis   (axis_crc_check.master),

        .crc_busy (crc_check_busy),
        .crc_ok   (crc_ok),
        .crc_fail (crc_fail),
        .len_err  (crc_len_err)
    );

    // =========================================================================
    // RX deframer
    // =========================================================================

    rx_deframer #(
        .EXPECTED_ETYPE(16'h88B5)
    ) u_rx_deframer (
        .clk            (rx_clk),
        .rst_n          (rx_rst_n),

        .s_axis         (axis_crc_check.slave),
        .m_axis         (axis_payload.master),

        .dst_mac_out    (dst_mac_out),
        .src_mac_out    (src_mac_out),
        .ether_type_out (ether_type_out),

        .hdr_valid      (hdr_valid),
        .etype_ok       (etype_ok),
        .etype_err      (etype_err),
        .len_err        (df_len_err),
        .df_busy        (df_busy),
        .df_done        (df_done)
    );

    // =========================================================================
    // Packet RX
    // =========================================================================

    packet_rx u_packet_rx (
        .clk       (rx_clk),
        .rst_n     (rx_rst_n),

        .s_axis    (axis_payload.slave),

        .msg_type  (rx_msg_type),
        .version   (rx_version),
        .seq_id    (rx_seq_id),
        .flags     (rx_flags),
        .reserved  (rx_reserved),
        .tod_sec   (rx_tod_sec),
        .tod_nsec  (rx_tod_nsec),
        .tod_frac  (rx_tod_frac),

        .pkt_valid (pkt_valid),
        .pkt_done  (pkt_done),
        .len_err   (pkt_len_err),
        .pr_busy   (pr_busy)
    );

    // Delay pkt_valid by one cycle so timestamp_diff samples registered packet fields
    always_ff @(posedge rx_clk or negedge rx_rst_n) begin
        if (!rx_rst_n) begin
            pkt_valid_d <= 1'b0;
        end else begin
            pkt_valid_d <= pkt_valid;
        end
    end

    // =========================================================================
    // Timestamp difference / latency measurement
    // =========================================================================
    // latency = RX local time - timestamp carried in received packet

    timestamp_diff u_timestamp_diff (
        .clk           (rx_clk),
        .rst_n         (rx_rst_n),

        .valid_in      (pkt_valid_d),

        .rx_local_sec  (tod_sec_rx_local),
        .rx_local_nsec (tod_nsec_rx_local),
        .rx_local_frac (tod_frac_rx_local),

        .tx_stamp_sec  (rx_tod_sec),
        .tx_stamp_nsec (rx_tod_nsec),
        .tx_stamp_frac (rx_tod_frac),

        .diff_valid    (latency_valid),
        .diff_sec      (latency_sec),
        .diff_nsec     (latency_nsec),
        .diff_frac     (latency_frac),
        .underflow     (latency_underflow)
    );

    // =========================================================================
    // Debug output assignments
    // =========================================================================

    assign dbg_start_tx  = start_tx;
    assign dbg_tx_done   = tx_done;
    assign dbg_tx_seq_id = seq_id_out;
    assign dbg_enc_valid = enc_valid;
    assign dbg_enc_err   = enc_err;

    assign dbg_pcs_sof        = pcs_rx_sof_strobe;
    assign dbg_pcs_frame_done = pcs_frame_done;
    assign dbg_pcs_frame_err  = pcs_frame_err;
    assign dbg_pcs_ctrl_err   = pcs_ctrl_err;
    assign dbg_pcs_sym_err    = pcs_sym_err;

    assign dbg_crc_ok      = crc_ok;
    assign dbg_crc_fail    = crc_fail;
    assign dbg_crc_len_err = crc_len_err;

    assign dbg_df_done    = df_done;
    assign dbg_etype_ok   = etype_ok;
    assign dbg_etype_err  = etype_err;
    assign dbg_df_len_err = df_len_err;

    assign dbg_pkt_valid   = pkt_valid;
    assign dbg_pkt_done    = pkt_done;
    assign dbg_pkt_len_err = pkt_len_err;

    assign dbg_rx_msg_type = rx_msg_type;
    assign dbg_rx_seq_id   = rx_seq_id;
    assign dbg_rx_tod_sec  = rx_tod_sec;
    assign dbg_rx_tod_nsec = rx_tod_nsec;
    assign dbg_rx_tod_frac = rx_tod_frac;

    assign dbg_latency_valid     = latency_valid;
    assign dbg_latency_sec       = latency_sec;
    assign dbg_latency_nsec      = latency_nsec;
    assign dbg_latency_frac      = latency_frac;
    assign dbg_latency_underflow = latency_underflow;

endmodule
