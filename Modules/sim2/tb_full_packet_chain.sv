`timescale 1ns/1ps

module tb_full_packet_chain;

    // -------------------------------------------------------------------------
    // Clock/reset
    // -------------------------------------------------------------------------

    logic clk;
    logic rst_n;
    logic rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100 MHz
    end

    assign rst = ~rst_n;

    // -------------------------------------------------------------------------
    // Packet TX inputs
    // -------------------------------------------------------------------------

    logic        start_tx;
    logic [7:0]  msg_type_in;
    logic [47:0] tod_sec_in;
    logic [31:0] tod_nsec_in;
    logic [15:0] tod_frac_in;

    // -------------------------------------------------------------------------
    // AXI interfaces
    // -------------------------------------------------------------------------

    axi_stream_if #(64) axis_packet    (clk);
    axi_stream_if #(64) axis_framed    (clk);
    axi_stream_if #(64) axis_crc_tx    (clk);

    axi_stream_if #(64) axis_pcs       (clk);
    axi_stream_if #(64) axis_crc_check (clk);
    axi_stream_if #(64) axis_payload   (clk);

    // -------------------------------------------------------------------------
    // Symbol / encode / decode path
    // -------------------------------------------------------------------------

    sym_stream_if sym_tx_serial(clk);

    logic [63:0] packed_data;
    logic [7:0]  packed_is_k;
    logic        packed_valid;

    logic [63:0] mux_data;
    logic [7:0]  mux_is_k;
    logic        mux_valid;

    logic [79:0] code80;
    logic        code80_valid;
    logic        enc_err;

    logic [63:0] dec_data;
    logic [7:0]  dec_is_k;
    logic        dec_valid;
    logic [7:0]  dec_code_err;
    logic [7:0]  dec_rd_err;
    logic        dec_any_err;

    // -------------------------------------------------------------------------
    // Status/debug signals
    // -------------------------------------------------------------------------

    logic        tx_busy;
    logic        tx_done;
    logic [15:0] seq_id_out;

    logic        fr_busy;
    logic        fr_done;

    logic        crc_append_busy;
    logic        crc_append_done;

    logic        pcs_in_frame;
    logic        pcs_sof;
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

    // -------------------------------------------------------------------------
    // DUT chain
    // -------------------------------------------------------------------------

    packet_tx u_packet_tx (
        .clk        (clk),
        .rst_n      (rst_n),

        .start_tx   (start_tx),
        .msg_type   (msg_type_in),

        .tod_sec    (tod_sec_in),
        .tod_nsec   (tod_nsec_in),
        .tod_frac   (tod_frac_in),

        .m_axis     (axis_packet.master),

        .tx_busy    (tx_busy),
        .tx_done    (tx_done),
        .seq_id_out (seq_id_out)
    );

    tx_framer u_tx_framer (
        .clk        (clk),
        .rst_n      (rst_n),

        .dst_mac    (48'hFF_FF_FF_FF_FF_FF),
        .src_mac    (48'h02_00_00_00_00_01),
        .ether_type (16'h88B5),

        .s_axis     (axis_packet.slave),
        .m_axis     (axis_framed.master),

        .fr_busy    (fr_busy),
        .fr_done    (fr_done)
    );

    crc_append_axis u_crc_append_axis (
        .clk      (clk),
        .rst_n    (rst_n),

        .s_axis   (axis_framed.slave),
        .m_axis   (axis_crc_tx.master),

        .crc_busy (crc_append_busy),
        .crc_done (crc_append_done)
    );

    axis64_to_sym8 u_axis64_to_sym8 (
        .clk    (clk),
        .rst_n  (rst_n),

        .s_axis (axis_crc_tx.slave),
        .sym    (sym_tx_serial.source)
    );

    sym8_to_parallel64 u_sym8_to_parallel64 (
        .clk       (clk),
        .rst_n     (rst_n),

        .sym       (sym_tx_serial.sink),

        .data_out  (packed_data),
        .is_k_out  (packed_is_k),
        .valid_out (packed_valid)
    );

    sym64_idle_mux u_sym64_idle_mux (
        .clk       (clk),
        .rst_n     (rst_n),

        .data_in   (packed_data),
        .is_k_in   (packed_is_k),
        .valid_in  (packed_valid),

        .data_out  (mux_data),
        .is_k_out  (mux_is_k),
        .valid_out (mux_valid)
    );

    enc_64b80b u_enc_64b80b (
        .clk        (clk),
        .rst        (rst),

        .data_in    (mux_data),
        .is_k_in    (mux_is_k),
        .valid_in   (mux_valid),

        .code80_out (code80),
        .valid_out  (code80_valid),
        .enc_err    (enc_err)
    );

    dec_80b64b u_dec_80b64b (
        .clk       (clk),
        .rst       (rst),

        .code80_in (code80),
        .valid_in  (code80_valid),

        .data_out  (dec_data),
        .is_k_out  (dec_is_k),
        .valid_out (dec_valid),

        .code_err  (dec_code_err),
        .rd_err    (dec_rd_err),
        .any_err   (dec_any_err)
    );

    pcs_rx64 u_pcs_rx64 (
        .clk           (clk),
        .rst_n         (rst_n),

        .sym_data      (dec_data),
        .sym_is_k      (dec_is_k),
        .sym_valid     (dec_valid),
        .sym_err_in    (dec_any_err),

        .m_axis        (axis_pcs.master),

        .in_frame      (pcs_in_frame),
        .rx_sof_strobe (pcs_sof),
        .frame_done    (pcs_frame_done),
        .frame_err     (pcs_frame_err),
        .ctrl_err      (pcs_ctrl_err),
        .sym_err       (pcs_sym_err)
    );

    crc32_check u_crc32_check (
        .clk      (clk),
        .rst_n    (rst_n),

        .s_axis   (axis_pcs.slave),
        .m_axis   (axis_crc_check.master),

        .crc_busy (crc_check_busy),
        .crc_ok   (crc_ok),
        .crc_fail (crc_fail),
        .len_err  (crc_len_err)
    );

    rx_deframer #(
        .EXPECTED_ETYPE(16'h88B5)
    ) u_rx_deframer (
        .clk            (clk),
        .rst_n          (rst_n),

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

    packet_rx u_packet_rx (
        .clk       (clk),
        .rst_n     (rst_n),

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

    // -------------------------------------------------------------------------
    // Test bookkeeping
    // -------------------------------------------------------------------------

    int error_count;
    int packet_count;
    int crc_ok_count;
    int crc_fail_count;
    int pcs_frame_done_count;
    int df_done_count;

    bit test_done;

    // -------------------------------------------------------------------------
    // Error/status monitor
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            crc_ok_count          = 0;
            crc_fail_count        = 0;
            pcs_frame_done_count  = 0;
            df_done_count         = 0;
        end else begin
            #1;

            if (enc_err) begin
                $error("[%0t] Encoder error asserted", $time);
                error_count++;
            end

            if (dec_valid && dec_any_err) begin
                $error("[%0t] Decoder error: code_err=%02h rd_err=%02h",
                       $time, dec_code_err, dec_rd_err);
                error_count++;
            end

            if (pcs_frame_err) begin
                $error("[%0t] PCS frame_err asserted", $time);
                error_count++;
            end

            if (pcs_ctrl_err) begin
                $error("[%0t] PCS ctrl_err asserted", $time);
                error_count++;
            end

            if (pcs_sym_err) begin
                $error("[%0t] PCS sym_err asserted", $time);
                error_count++;
            end

            if (crc_fail) begin
                $error("[%0t] CRC check failed", $time);
                crc_fail_count++;
                error_count++;
            end

            if (crc_len_err) begin
                $error("[%0t] CRC length error", $time);
                error_count++;
            end

            if (etype_err) begin
                $error("[%0t] EtherType error: got=%04h expected=88B5",
                       $time, ether_type_out);
                error_count++;
            end

            if (df_len_err) begin
                $error("[%0t] Deframer length error", $time);
                error_count++;
            end

            if (pkt_len_err) begin
                $error("[%0t] Packet RX length error", $time);
                error_count++;
            end

            if (pcs_sof) begin
                $display("[%0t] PCS SOF detected", $time);
            end

            if (pcs_frame_done) begin
                $display("[%0t] PCS frame_done", $time);
                pcs_frame_done_count++;
            end

            if (crc_ok) begin
                $display("[%0t] CRC OK", $time);
                crc_ok_count++;
            end

            if (df_done) begin
                $display("[%0t] Deframer done", $time);
                df_done_count++;
            end

            if (pkt_valid) begin
                $display("[%0t] Packet valid: msg_type=%02h seq=%0d sec=%012h nsec=%08h frac=%04h",
                         $time, rx_msg_type, rx_seq_id, rx_tod_sec, rx_tod_nsec, rx_tod_frac);
                packet_count++;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    task automatic idle_inputs();
        begin
            start_tx    <= 1'b0;
            msg_type_in <= 8'h00;
            tod_sec_in  <= 48'd0;
            tod_nsec_in <= 32'd0;
            tod_frac_in <= 16'd0;
        end
    endtask

    task automatic send_packet(
        input logic [7:0]  exp_msg_type,
        input logic [47:0] exp_sec,
        input logic [31:0] exp_nsec,
        input logic [15:0] exp_frac
    );
        begin
            @(posedge clk);
            #1;

            msg_type_in <= exp_msg_type;
            tod_sec_in  <= exp_sec;
            tod_nsec_in <= exp_nsec;
            tod_frac_in <= exp_frac;

            @(posedge clk);
            #1;
            start_tx <= 1'b1;

            @(posedge clk);
            #1;
            start_tx <= 1'b0;

            $display("[%0t] Started packet: msg_type=%02h sec=%012h nsec=%08h frac=%04h",
                     $time, exp_msg_type, exp_sec, exp_nsec, exp_frac);
        end
    endtask

    task automatic wait_and_check_packet(
        input logic [7:0]  exp_msg_type,
        input logic [7:0]  exp_version,
        input logic [15:0] exp_seq,
        input logic [7:0]  exp_flags,
        input logic [23:0] exp_reserved,
        input logic [47:0] exp_sec,
        input logic [31:0] exp_nsec,
        input logic [15:0] exp_frac
    );
        int timeout;
        bit seen;
        begin
            timeout = 0;
            seen    = 1'b0;

            while (!seen && timeout < 5000) begin
                @(posedge clk);
                #1;

                if (pkt_valid) begin
                    seen = 1'b1;

                    if (rx_msg_type !== exp_msg_type) begin
                        $error("msg_type mismatch: expected=%02h got=%02h",
                               exp_msg_type, rx_msg_type);
                        error_count++;
                    end

                    if (rx_version !== exp_version) begin
                        $error("version mismatch: expected=%02h got=%02h",
                               exp_version, rx_version);
                        error_count++;
                    end

                    if (rx_seq_id !== exp_seq) begin
                        $error("seq_id mismatch: expected=%04h got=%04h",
                               exp_seq, rx_seq_id);
                        error_count++;
                    end

                    if (rx_flags !== exp_flags) begin
                        $error("flags mismatch: expected=%02h got=%02h",
                               exp_flags, rx_flags);
                        error_count++;
                    end

                    if (rx_reserved !== exp_reserved) begin
                        $error("reserved mismatch: expected=%06h got=%06h",
                               exp_reserved, rx_reserved);
                        error_count++;
                    end

                    if (rx_tod_sec !== exp_sec) begin
                        $error("tod_sec mismatch: expected=%012h got=%012h",
                               exp_sec, rx_tod_sec);
                        error_count++;
                    end

                    if (rx_tod_nsec !== exp_nsec) begin
                        $error("tod_nsec mismatch: expected=%08h got=%08h",
                               exp_nsec, rx_tod_nsec);
                        error_count++;
                    end

                    if (rx_tod_frac !== exp_frac) begin
                        $error("tod_frac mismatch: expected=%04h got=%04h",
                               exp_frac, rx_tod_frac);
                        error_count++;
                    end

                    if (!pkt_done) begin
                        $error("pkt_valid asserted without pkt_done");
                        error_count++;
                    end

                    if (dst_mac_out !== 48'hFF_FF_FF_FF_FF_FF) begin
                        $error("dst_mac mismatch: expected=FFFFFFFFFFFF got=%012h",
                               dst_mac_out);
                        error_count++;
                    end

                    if (src_mac_out !== 48'h02_00_00_00_00_01) begin
                        $error("src_mac mismatch: expected=020000000001 got=%012h",
                               src_mac_out);
                        error_count++;
                    end

                    if (ether_type_out !== 16'h88B5) begin
                        $error("ether_type mismatch: expected=88B5 got=%04h",
                               ether_type_out);
                        error_count++;
                    end
                end

                timeout++;
            end

            if (!seen) begin
                $error("Timeout waiting for packet seq=%0d", exp_seq);
                error_count++;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Timeout
    // -------------------------------------------------------------------------

    initial begin
        test_done = 1'b0;

        #5_000_000;

        if (!test_done) begin
            $error("TIMEOUT: simulation did not complete");
            $finish;
        end
    end

    // -------------------------------------------------------------------------
    // Main test
    // -------------------------------------------------------------------------

    initial begin
        error_count = 0;
        packet_count = 0;
        crc_ok_count = 0;
        crc_fail_count = 0;
        pcs_frame_done_count = 0;
        df_done_count = 0;

        rst_n = 1'b0;
        idle_inputs();

        repeat (20) @(posedge clk);
        rst_n = 1'b1;

        repeat (50) @(posedge clk);

        // Packet 0
        send_packet(
            8'h11,
            48'h0000_0000_1234,
            32'h0000_5678,
            16'h9ABC
        );

        wait_and_check_packet(
            8'h11,              // msg_type
            8'h01,              // version
            16'h0000,            // seq_id
            8'h00,              // flags
            24'h000000,          // reserved
            48'h0000_0000_1234,
            32'h0000_5678,
            16'h9ABC
        );

        repeat (100) @(posedge clk);

        // Packet 1
        send_packet(
            8'h22,
            48'h0000_0000_ABCD,
            32'h0001_0203,
            16'h0405
        );

        wait_and_check_packet(
            8'h22,
            8'h01,
            16'h0001,
            8'h00,
            24'h000000,
            48'h0000_0000_ABCD,
            32'h0001_0203,
            16'h0405
        );

        repeat (100) @(posedge clk);

        // Packet 2
        send_packet(
            8'h33,
            48'h0000_1111_2222,
            32'h3333_4444,
            16'h5555
        );

        wait_and_check_packet(
            8'h33,
            8'h01,
            16'h0002,
            8'h00,
            24'h000000,
            48'h0000_1111_2222,
            32'h3333_4444,
            16'h5555
        );

        repeat (200) @(posedge clk);

        $display("----------------------------------------------------");
        $display("Packet count          = %0d", packet_count);
        $display("PCS frame_done count  = %0d", pcs_frame_done_count);
        $display("CRC OK count          = %0d", crc_ok_count);
        $display("CRC fail count        = %0d", crc_fail_count);
        $display("Deframer done count   = %0d", df_done_count);
        $display("Error count           = %0d", error_count);
        $display("----------------------------------------------------");

        if (packet_count !== 3) begin
            $error("Packet count mismatch: expected=3 got=%0d", packet_count);
            error_count++;
        end

        if (pcs_frame_done_count !== 3) begin
            $error("PCS frame_done count mismatch: expected=3 got=%0d",
                   pcs_frame_done_count);
            error_count++;
        end

        if (crc_ok_count !== 3) begin
            $error("CRC OK count mismatch: expected=3 got=%0d", crc_ok_count);
            error_count++;
        end

        if (crc_fail_count !== 0) begin
            $error("CRC fail count mismatch: expected=0 got=%0d", crc_fail_count);
            error_count++;
        end

        if (df_done_count !== 3) begin
            $error("Deframer done count mismatch: expected=3 got=%0d", df_done_count);
            error_count++;
        end

        if (error_count == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED with %0d errors", error_count);
        end

        test_done = 1'b1;
        $finish;
    end

endmodule
