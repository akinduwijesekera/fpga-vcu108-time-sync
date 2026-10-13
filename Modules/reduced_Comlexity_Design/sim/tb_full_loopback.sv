`timescale 1ns/1ps

module tb_full_loopback;

    // ------------------------------------------------------------
    // Clock/reset
    // ------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #2.5 clk = ~clk; // 200 MHz

    // ------------------------------------------------------------
    // TX stimulus
    // ------------------------------------------------------------
    logic        start_tx;
    logic [7:0]  msg_type;

    logic [47:0] dst_mac;
    logic [47:0] src_mac;
    logic [15:0] ether_type;

    logic [47:0] tx_tod_sec_in;
    logic [31:0] tx_tod_nsec_in;
    logic [15:0] tx_tod_frac_in;

    logic tx_busy;
    logic tx_done;
    logic [15:0] seq_id_out;

    // ------------------------------------------------------------
    // RX local timestamp for timestamp_diff
    // Choose this to be later than TX timestamp by a known amount.
    // Expected diff = 10 ns + 0x0010 fractional ns.
    // ------------------------------------------------------------
    logic [47:0] rx_local_sec;
    logic [31:0] rx_local_nsec;
    logic [15:0] rx_local_frac;

    // ------------------------------------------------------------
    // AXI interfaces
    // ------------------------------------------------------------
    axi_stream_if #(64) axis_tx_to_crc(clk);
    axi_stream_if #(64) axis_crc_to_pcs(clk);
    axi_stream_if #(64) axis_rxpcs_to_crc(clk);
    axi_stream_if #(64) axis_crc_to_packet(clk);

    // ------------------------------------------------------------
    // PCS / encoder / decoder signals
    // ------------------------------------------------------------
    logic [63:0] tx_sym_data;
    logic [7:0]  tx_sym_is_k;
    logic        tx_sym_valid;
    logic        tx_sym_ready;

    logic [79:0] code80;
    logic        code80_valid;
    logic        code80_ready;
    logic        enc_err;

    logic [63:0] rx_sym_data;
    logic [7:0]  rx_sym_is_k;
    logic        rx_sym_valid;
    logic        rx_sym_ready;

    logic [7:0]  dec_code_err;
    logic [7:0]  dec_rd_err;
    logic        dec_any_err;

    // ------------------------------------------------------------
    // Status/debug signals
    // ------------------------------------------------------------
    logic tx_crc_busy;
    logic tx_crc_done;

    logic tx_pcs_busy;
    logic tx_pcs_done;
    logic tx_pcs_overflow;

    logic rx_in_frame;
    logic rx_sof_strobe;
    logic rx_frame_done;
    logic rx_frame_err;
    logic rx_ctrl_err;
    logic rx_sym_err;

    logic rx_crc_busy;
    logic rx_crc_ok;
    logic rx_crc_fail;
    logic rx_crc_len_err;

    // ------------------------------------------------------------
    // Packet RX outputs
    // ------------------------------------------------------------
    logic [47:0] rx_dst_mac;
    logic [47:0] rx_src_mac;
    logic [15:0] rx_ether_type;

    logic [7:0]  rx_msg_type;
    logic [7:0]  rx_version;
    logic [15:0] rx_seq_id;
    logic [7:0]  rx_flags;
    logic [7:0]  rx_reserved;

    logic [47:0] rx_tx_tod_sec;
    logic [31:0] rx_tx_tod_nsec;
    logic [15:0] rx_tx_tod_frac;

    logic pkt_valid;
    logic pkt_done;
    logic pkt_len_err;
    logic ether_type_err;
    logic version_err;
    logic pkt_err;
    logic pr_busy;

    // ------------------------------------------------------------
    // Timestamp diff outputs
    // ------------------------------------------------------------
    logic        diff_valid;
    logic [47:0] diff_sec;
    logic [31:0] diff_nsec;
    logic [15:0] diff_frac;
    logic        underflow;

    // ------------------------------------------------------------
    // DUT chain
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

        .tod_sec    (tx_tod_sec_in),
        .tod_nsec   (tx_tod_nsec_in),
        .tod_frac   (tx_tod_frac_in),

        .m_axis     (axis_tx_to_crc.master),

        .tx_busy    (tx_busy),
        .tx_done    (tx_done),
        .seq_id_out (seq_id_out)
    );

    crc_append_axis u_crc_append_axis (
        .clk      (clk),
        .rst_n    (rst_n),

        .s_axis   (axis_tx_to_crc.slave),
        .m_axis   (axis_crc_to_pcs.master),

        .crc_busy (tx_crc_busy),
        .crc_done (tx_crc_done)
    );

    tx_pcs #(
        .MAX_FRAME_BYTES(64)
    ) u_tx_pcs (
        .clk                  (clk),
        .rst_n                (rst_n),

        .s_axis               (axis_crc_to_pcs.slave),

        .sym_data             (tx_sym_data),
        .sym_is_k             (tx_sym_is_k),
        .sym_valid            (tx_sym_valid),
        .sym_ready            (tx_sym_ready),

        .pcs_busy             (tx_pcs_busy),
        .pcs_done             (tx_pcs_done),
        .frame_overflow_error (tx_pcs_overflow)
    );

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

        .m_axis        (axis_rxpcs_to_crc.master),

        .in_frame      (rx_in_frame),
        .rx_sof_strobe (rx_sof_strobe),
        .frame_done    (rx_frame_done),
        .frame_err     (rx_frame_err),
        .ctrl_err      (rx_ctrl_err),
        .sym_err       (rx_sym_err)
    );

    crc32_check #(
        .OUT_FRAME_BYTES(32),
        .FCS_BYTES      (4)
    ) u_crc32_check (
        .clk      (clk),
        .rst_n    (rst_n),

        .s_axis   (axis_rxpcs_to_crc.slave),
        .m_axis   (axis_crc_to_packet.master),

        .crc_busy (rx_crc_busy),
        .crc_ok   (rx_crc_ok),
        .crc_fail (rx_crc_fail),
        .len_err  (rx_crc_len_err)
    );

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

    // ------------------------------------------------------------
    // Error monitors
    // ------------------------------------------------------------
    logic tx_done_seen;
    logic tx_crc_done_seen;
    logic tx_pcs_done_seen;
    logic rx_frame_done_seen;
    logic rx_crc_ok_seen;
    logic pkt_valid_seen;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_done_seen       <= 1'b0;
            tx_crc_done_seen   <= 1'b0;
            tx_pcs_done_seen   <= 1'b0;
            rx_frame_done_seen <= 1'b0;
            rx_crc_ok_seen     <= 1'b0;
            pkt_valid_seen     <= 1'b0;
        end else begin
            if (tx_done)       tx_done_seen       <= 1'b1;
            if (tx_crc_done)   tx_crc_done_seen   <= 1'b1;
            if (tx_pcs_done)   tx_pcs_done_seen   <= 1'b1;
            if (rx_frame_done) rx_frame_done_seen <= 1'b1;
            if (rx_crc_ok)     rx_crc_ok_seen     <= 1'b1;
            if (pkt_valid)     pkt_valid_seen     <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (enc_err) begin
                $fatal(1, "Encoder error asserted");
            end

            if (dec_any_err) begin
                $fatal(1, "Decoder error asserted. code_err=%02h rd_err=%02h",
                       dec_code_err, dec_rd_err);
            end

            if (tx_pcs_overflow) begin
                $fatal(1, "TX PCS overflow");
            end

            if (rx_frame_err || rx_ctrl_err || rx_sym_err) begin
                $fatal(1, "RX PCS error. frame_err=%0b ctrl_err=%0b sym_err=%0b",
                       rx_frame_err, rx_ctrl_err, rx_sym_err);
            end

            if (rx_crc_fail) begin
                $fatal(1, "RX CRC failed");
            end

            if (rx_crc_len_err) begin
                $fatal(1, "RX CRC length error");
            end

            if (pkt_len_err) begin
                $fatal(1, "packet_rx length error");
            end

            if (ether_type_err) begin
                $fatal(1, "packet_rx EtherType error");
            end

            if (version_err) begin
                $fatal(1, "packet_rx version error");
            end

            if (pkt_err) begin
                $fatal(1, "packet_rx packet error");
            end
        end
    end

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin
        rst_n    = 1'b0;
        start_tx = 1'b0;

        msg_type   = 8'h00;
        dst_mac    = 48'hDA_02_03_04_05_06;
        src_mac    = 48'h5A_02_03_04_05_06;
        ether_type = 16'h88F7;

        tx_tod_sec_in  = 48'h0000_0000_1234;
        tx_tod_nsec_in = 32'd123_456_789;
        tx_tod_frac_in = 16'hABCD;

        // RX local timestamp = TX timestamp + 10 ns + 0x0010 frac
        rx_local_sec  = 48'h0000_0000_1234;
        rx_local_nsec = 32'd123_456_799;
        rx_local_frac = 16'hABDD;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("Starting full end-to-end loopback test...");

        @(posedge clk);
        start_tx <= 1'b1;

        @(posedge clk);
        start_tx <= 1'b0;

        // Wait for final timestamp diff
        wait (diff_valid);
        #1;

        // --------------------------------------------------------
        // Checks
        // --------------------------------------------------------
        if (!tx_done_seen) begin
            $fatal(1, "tx_done was never seen");
        end

        if (!tx_crc_done_seen) begin
            $fatal(1, "tx_crc_done was never seen");
        end

        if (!tx_pcs_done_seen) begin
            $fatal(1, "tx_pcs_done was never seen");
        end

        if (!rx_frame_done_seen) begin
            $fatal(1, "rx_frame_done was never seen");
        end

        if (!rx_crc_ok_seen) begin
            $fatal(1, "rx_crc_ok was never seen");
        end

        if (!pkt_valid_seen) begin
            $fatal(1, "pkt_valid was never seen");
        end

        if (seq_id_out !== 16'd1) begin
            $fatal(1, "seq_id_out mismatch. Got %04h, expected 0001", seq_id_out);
        end

        if (rx_dst_mac !== 48'hDA_02_03_04_05_06) begin
            $fatal(1, "dst_mac mismatch. Got %012h", rx_dst_mac);
        end

        if (rx_src_mac !== 48'h5A_02_03_04_05_06) begin
            $fatal(1, "src_mac mismatch. Got %012h", rx_src_mac);
        end

        if (rx_ether_type !== 16'h88F7) begin
            $fatal(1, "ether_type mismatch. Got %04h", rx_ether_type);
        end

        if (rx_msg_type !== 8'h00) begin
            $fatal(1, "msg_type mismatch. Got %02h", rx_msg_type);
        end

        if (rx_version !== 8'h01) begin
            $fatal(1, "version mismatch. Got %02h", rx_version);
        end

        if (rx_seq_id !== 16'h0000) begin
            $fatal(1, "rx_seq_id mismatch. Got %04h, expected 0000", rx_seq_id);
        end

        if (rx_flags !== 8'h00) begin
            $fatal(1, "flags mismatch. Got %02h", rx_flags);
        end

        if (rx_reserved !== 8'h00) begin
            $fatal(1, "reserved mismatch. Got %02h", rx_reserved);
        end

        if (rx_tx_tod_sec !== tx_tod_sec_in) begin
            $fatal(1, "tx timestamp seconds mismatch. Got %012h expected %012h",
                   rx_tx_tod_sec, tx_tod_sec_in);
        end

        if (rx_tx_tod_nsec !== tx_tod_nsec_in) begin
            $fatal(1, "tx timestamp nsec mismatch. Got %0d expected %0d",
                   rx_tx_tod_nsec, tx_tod_nsec_in);
        end

        if (rx_tx_tod_frac !== tx_tod_frac_in) begin
            $fatal(1, "tx timestamp frac mismatch. Got %04h expected %04h",
                   rx_tx_tod_frac, tx_tod_frac_in);
        end

        if (underflow) begin
            $fatal(1, "timestamp_diff underflow asserted");
        end

        if (diff_sec !== 48'd0) begin
            $fatal(1, "diff_sec mismatch. Got %0d expected 0", diff_sec);
        end

        if (diff_nsec !== 32'd10) begin
            $fatal(1, "diff_nsec mismatch. Got %0d expected 10", diff_nsec);
        end

        if (diff_frac !== 16'h0010) begin
            $fatal(1, "diff_frac mismatch. Got %04h expected 0010", diff_frac);
        end

        $display("--------------------------------------------------");
        $display("tb_full_loopback PASSED");
        $display("Parsed packet:");
        $display("  dst_mac    = %012h", rx_dst_mac);
        $display("  src_mac    = %012h", rx_src_mac);
        $display("  ether_type = %04h", rx_ether_type);
        $display("  msg_type   = %02h", rx_msg_type);
        $display("  version    = %02h", rx_version);
        $display("  seq_id     = %04h", rx_seq_id);
        $display("  tx_sec     = %012h", rx_tx_tod_sec);
        $display("  tx_nsec    = %0d", rx_tx_tod_nsec);
        $display("  tx_frac    = %04h", rx_tx_tod_frac);
        $display("Timestamp difference:");
        $display("  diff_sec   = %0d", diff_sec);
        $display("  diff_nsec  = %0d", diff_nsec);
        $display("  diff_frac  = %04h", diff_frac);
        $display("--------------------------------------------------");

        $finish;
    end

    // ------------------------------------------------------------
    // Timeout
    // ------------------------------------------------------------
    initial begin
        #2_000_000;
        $fatal(1, "Timeout: full loopback test did not complete");
    end

endmodule
