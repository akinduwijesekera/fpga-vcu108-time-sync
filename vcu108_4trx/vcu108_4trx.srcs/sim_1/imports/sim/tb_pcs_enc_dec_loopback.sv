`timescale 1ns/1ps

module tb_pcs_enc_dec_loopback;

    // ------------------------------------------------------------
    // Clock/reset
    // ------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #2.5 clk = ~clk; // 200 MHz

    // ------------------------------------------------------------
    // AXI interfaces
    // ------------------------------------------------------------
    axi_stream_if #(64) axis_in(clk);
    axi_stream_if #(64) axis_out(clk);

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

    logic tx_pcs_busy;
    logic tx_pcs_done;
    logic tx_pcs_overflow;

    logic rx_in_frame;
    logic rx_sof_strobe;
    logic rx_frame_done;
    logic rx_frame_err;
    logic rx_ctrl_err;
    logic rx_sym_err;

    // ------------------------------------------------------------
    // DUTs
    // ------------------------------------------------------------
    tx_pcs #(
        .MAX_FRAME_BYTES(64)
    ) u_tx_pcs (
        .clk                 (clk),
        .rst_n               (rst_n),

        .s_axis              (axis_in.slave),

        .sym_data            (tx_sym_data),
        .sym_is_k            (tx_sym_is_k),
        .sym_valid           (tx_sym_valid),
        .sym_ready           (tx_sym_ready),

        .pcs_busy            (tx_pcs_busy),
        .pcs_done            (tx_pcs_done),
        .frame_overflow_error(tx_pcs_overflow)
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
        .clk          (clk),
        .rst_n        (rst_n),

        .sym_data     (rx_sym_data),
        .sym_is_k     (rx_sym_is_k),
        .sym_valid    (rx_sym_valid),
        .sym_ready    (rx_sym_ready),

        .code_err_in  (dec_code_err),
        .rd_err_in    (dec_rd_err),
        .any_err_in   (dec_any_err),

        .m_axis       (axis_out.master),

        .in_frame     (rx_in_frame),
        .rx_sof_strobe(rx_sof_strobe),
        .frame_done   (rx_frame_done),
        .frame_err    (rx_frame_err),
        .ctrl_err     (rx_ctrl_err),
        .sym_err      (rx_sym_err)
    );

    // ------------------------------------------------------------
    // Expected 36-byte frame
    //
    // This is the same frame that passed your tx_packet_framer_crc test:
    //
    // DA 02 03 04 05 06
    // 5A 02 03 04 05 06
    // 88 F7
    // 00 01
    // 00 00
    // 00 00
    // 00 00 00 00 12 34
    // 07 5B CD 15
    // AB CD
    // AE D0 99 71
    // ------------------------------------------------------------
    localparam int FRAME_BYTES = 36;

    logic [7:0] expected_bytes [0:FRAME_BYTES-1];
    logic [7:0] captured_bytes [0:FRAME_BYTES-1];

    int captured_count;
    int beat_count;

    task automatic build_expected_frame;
        begin
            expected_bytes[0]  = 8'hDA;
            expected_bytes[1]  = 8'h02;
            expected_bytes[2]  = 8'h03;
            expected_bytes[3]  = 8'h04;
            expected_bytes[4]  = 8'h05;
            expected_bytes[5]  = 8'h06;

            expected_bytes[6]  = 8'h5A;
            expected_bytes[7]  = 8'h02;
            expected_bytes[8]  = 8'h03;
            expected_bytes[9]  = 8'h04;
            expected_bytes[10] = 8'h05;
            expected_bytes[11] = 8'h06;

            expected_bytes[12] = 8'h88;
            expected_bytes[13] = 8'hF7;

            expected_bytes[14] = 8'h00; // msg_type
            expected_bytes[15] = 8'h01; // version

            expected_bytes[16] = 8'h00; // seq_id[15:8]
            expected_bytes[17] = 8'h00; // seq_id[7:0]

            expected_bytes[18] = 8'h00; // flags
            expected_bytes[19] = 8'h00; // reserved

            expected_bytes[20] = 8'h00;
            expected_bytes[21] = 8'h00;
            expected_bytes[22] = 8'h00;
            expected_bytes[23] = 8'h00;
            expected_bytes[24] = 8'h12;
            expected_bytes[25] = 8'h34;

            expected_bytes[26] = 8'h07;
            expected_bytes[27] = 8'h5B;
            expected_bytes[28] = 8'hCD;
            expected_bytes[29] = 8'h15;

            expected_bytes[30] = 8'hAB;
            expected_bytes[31] = 8'hCD;

            // FCS from previous passing test: CRC = 0x7199D0AE
            // AXI/FCS byte order = LSB first
            expected_bytes[32] = 8'hAE;
            expected_bytes[33] = 8'hD0;
            expected_bytes[34] = 8'h99;
            expected_bytes[35] = 8'h71;
        end
    endtask

    // ------------------------------------------------------------
    // Byte packing helper
    // b0 goes to tdata[7:0]
    // ------------------------------------------------------------
    function automatic logic [63:0] pack8(
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3,
        input logic [7:0] b4,
        input logic [7:0] b5,
        input logic [7:0] b6,
        input logic [7:0] b7
    );
        begin
            pack8 = {b7, b6, b5, b4, b3, b2, b1, b0};
        end
    endfunction

    // ------------------------------------------------------------
    // AXI input driver
    // ------------------------------------------------------------
    task automatic drive_axi_beat(
        input logic [63:0] data,
        input logic [7:0]  keep,
        input logic        last
    );
        begin
            axis_in.tdata  <= data;
            axis_in.tkeep  <= keep;
            axis_in.tlast  <= last;
            axis_in.tvalid <= 1'b1;

            do begin
                @(posedge clk);
            end while (!axis_in.tready);

            axis_in.tvalid <= 1'b0;
            axis_in.tdata  <= 64'd0;
            axis_in.tkeep  <= 8'd0;
            axis_in.tlast  <= 1'b0;

            @(posedge clk);
        end
    endtask

    task automatic drive_frame_36_bytes;
        begin
            drive_axi_beat(
                pack8(
                    expected_bytes[0], expected_bytes[1], expected_bytes[2], expected_bytes[3],
                    expected_bytes[4], expected_bytes[5], expected_bytes[6], expected_bytes[7]
                ),
                8'hFF,
                1'b0
            );

            drive_axi_beat(
                pack8(
                    expected_bytes[8], expected_bytes[9], expected_bytes[10], expected_bytes[11],
                    expected_bytes[12], expected_bytes[13], expected_bytes[14], expected_bytes[15]
                ),
                8'hFF,
                1'b0
            );

            drive_axi_beat(
                pack8(
                    expected_bytes[16], expected_bytes[17], expected_bytes[18], expected_bytes[19],
                    expected_bytes[20], expected_bytes[21], expected_bytes[22], expected_bytes[23]
                ),
                8'hFF,
                1'b0
            );

            drive_axi_beat(
                pack8(
                    expected_bytes[24], expected_bytes[25], expected_bytes[26], expected_bytes[27],
                    expected_bytes[28], expected_bytes[29], expected_bytes[30], expected_bytes[31]
                ),
                8'hFF,
                1'b0
            );

            drive_axi_beat(
                pack8(
                    expected_bytes[32], expected_bytes[33], expected_bytes[34], expected_bytes[35],
                    8'h00, 8'h00, 8'h00, 8'h00
                ),
                8'h0F,
                1'b1
            );
        end
    endtask

    // ------------------------------------------------------------
    // AXI output monitor
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_count <= 0;
            beat_count     <= 0;
        end else begin
            if (axis_out.tvalid && axis_out.tready) begin
                int next_count;

                next_count = captured_count;
                beat_count <= beat_count + 1;

                for (int lane = 0; lane < 8; lane++) begin
                    if (axis_out.tkeep[lane]) begin
                        if (next_count < FRAME_BYTES) begin
                            captured_bytes[next_count] <= axis_out.tdata[8*lane +: 8];
                            next_count++;
                        end else begin
                            $fatal(1, "Captured more than expected %0d bytes", FRAME_BYTES);
                        end
                    end
                end

                captured_count <= next_count;

                $display("[%0t] RX beat %0d: data=%016h keep=%02h last=%0b",
                         $time,
                         beat_count,
                         axis_out.tdata,
                         axis_out.tkeep,
                         axis_out.tlast);

                if (axis_out.tlast) begin
                    if (axis_out.tkeep !== 8'h0F) begin
                        $fatal(1, "Final RX beat tkeep wrong. Got %02h, expected 0F",
                               axis_out.tkeep);
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Optional back-pressure control
    // ------------------------------------------------------------
    initial begin
        axis_out.tready = 1'b1;
    end

    // ------------------------------------------------------------
    // Error monitors
    // ------------------------------------------------------------
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
        end
    end

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin
        // Initial values
        rst_n = 1'b0;

        axis_in.tvalid = 1'b0;
        axis_in.tdata  = 64'd0;
        axis_in.tkeep  = 8'd0;
        axis_in.tlast  = 1'b0;

        build_expected_frame();

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("Starting PCS + enc/dec loopback test...");

        drive_frame_36_bytes();

        // Wait for RX frame to complete
        wait (rx_frame_done);
        repeat (10) @(posedge clk);

        // --------------------------------------------------------
        // Checks
        // --------------------------------------------------------
        if (captured_count !== FRAME_BYTES) begin
            $fatal(1, "Wrong captured byte count. Got %0d, expected %0d",
                   captured_count, FRAME_BYTES);
        end

        if (beat_count !== 5) begin
            $fatal(1, "Wrong RX beat count. Got %0d, expected 5", beat_count);
        end

        for (int i = 0; i < FRAME_BYTES; i++) begin
            if (captured_bytes[i] !== expected_bytes[i]) begin
                $fatal(1,
                    "Byte mismatch at byte %0d. Got 0x%02h, expected 0x%02h",
                    i,
                    captured_bytes[i],
                    expected_bytes[i]
                );
            end
        end

        $display("--------------------------------------------------");
        $display("tb_pcs_enc_dec_loopback PASSED");
        $display("Captured %0d bytes over %0d beats", captured_count, beat_count);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
