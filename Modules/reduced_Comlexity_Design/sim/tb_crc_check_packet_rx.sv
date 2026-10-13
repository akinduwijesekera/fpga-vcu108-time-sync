`timescale 1ns/1ps

module tb_crc_check_packet_rx;

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
    axi_stream_if #(64) axis_crc_to_packet(clk);

    // ------------------------------------------------------------
    // crc32_check outputs
    // ------------------------------------------------------------
    logic crc_busy;
    logic crc_ok;
    logic crc_fail;
    logic crc_len_err;

    // ------------------------------------------------------------
    // packet_rx outputs
    // ------------------------------------------------------------
    logic [47:0] dst_mac;
    logic [47:0] src_mac;
    logic [15:0] ether_type;

    logic [7:0]  msg_type;
    logic [7:0]  version;
    logic [15:0] seq_id;
    logic [7:0]  flags;
    logic [7:0]  reserved;

    logic [47:0] tx_tod_sec;
    logic [31:0] tx_tod_nsec;
    logic [15:0] tx_tod_frac;

    logic pkt_valid;
    logic pkt_done;
    logic pkt_len_err;
    logic ether_type_err;
    logic version_err;
    logic pkt_err;
    logic pr_busy;

    // ------------------------------------------------------------
    // DUTs
    // ------------------------------------------------------------
    crc32_check #(
        .OUT_FRAME_BYTES(32),
        .FCS_BYTES      (4)
    ) u_crc32_check (
        .clk      (clk),
        .rst_n    (rst_n),

        .s_axis   (axis_in.slave),
        .m_axis   (axis_crc_to_packet.master),

        .crc_busy (crc_busy),
        .crc_ok   (crc_ok),
        .crc_fail (crc_fail),
        .len_err  (crc_len_err)
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

        .dst_mac        (dst_mac),
        .src_mac        (src_mac),
        .ether_type     (ether_type),

        .msg_type       (msg_type),
        .version        (version),
        .seq_id         (seq_id),
        .flags          (flags),
        .reserved       (reserved),

        .tx_tod_sec     (tx_tod_sec),
        .tx_tod_nsec    (tx_tod_nsec),
        .tx_tod_frac    (tx_tod_frac),

        .pkt_valid      (pkt_valid),
        .pkt_done       (pkt_done),
        .len_err        (pkt_len_err),
        .ether_type_err (ether_type_err),
        .version_err    (version_err),
        .pkt_err        (pkt_err),

        .pr_busy        (pr_busy)
    );

    // ------------------------------------------------------------
    // Expected 36-byte input frame including FCS
    //
    // This is the same frame already verified:
    //
    // 32-byte frame:
    //   DA 02 03 04 05 06
    //   5A 02 03 04 05 06
    //   88 F7
    //   00 01 00 00 00 00
    //   00 00 00 00 12 34
    //   07 5B CD 15
    //   AB CD
    //
    // FCS:
    //   CRC = 0x7199D0AE
    //   stream order = AE D0 99 71
    // ------------------------------------------------------------
    localparam int IN_FRAME_BYTES  = 36;
    localparam int OUT_FRAME_BYTES = 32;

    logic [7:0] frame_with_crc [0:IN_FRAME_BYTES-1];
    logic [7:0] crc_output_bytes [0:OUT_FRAME_BYTES-1];

    int crc_output_count;
    int crc_output_beats;

    task automatic build_input_frame;
        begin
            frame_with_crc[0]  = 8'hDA;
            frame_with_crc[1]  = 8'h02;
            frame_with_crc[2]  = 8'h03;
            frame_with_crc[3]  = 8'h04;
            frame_with_crc[4]  = 8'h05;
            frame_with_crc[5]  = 8'h06;

            frame_with_crc[6]  = 8'h5A;
            frame_with_crc[7]  = 8'h02;
            frame_with_crc[8]  = 8'h03;
            frame_with_crc[9]  = 8'h04;
            frame_with_crc[10] = 8'h05;
            frame_with_crc[11] = 8'h06;

            frame_with_crc[12] = 8'h88;
            frame_with_crc[13] = 8'hF7;

            frame_with_crc[14] = 8'h00; // msg_type
            frame_with_crc[15] = 8'h01; // version

            frame_with_crc[16] = 8'h00; // seq_id[15:8]
            frame_with_crc[17] = 8'h00; // seq_id[7:0]

            frame_with_crc[18] = 8'h00; // flags
            frame_with_crc[19] = 8'h00; // reserved

            frame_with_crc[20] = 8'h00;
            frame_with_crc[21] = 8'h00;
            frame_with_crc[22] = 8'h00;
            frame_with_crc[23] = 8'h00;
            frame_with_crc[24] = 8'h12;
            frame_with_crc[25] = 8'h34;

            frame_with_crc[26] = 8'h07;
            frame_with_crc[27] = 8'h5B;
            frame_with_crc[28] = 8'hCD;
            frame_with_crc[29] = 8'h15;

            frame_with_crc[30] = 8'hAB;
            frame_with_crc[31] = 8'hCD;

            // FCS, LSB-first on stream
            frame_with_crc[32] = 8'hAE;
            frame_with_crc[33] = 8'hD0;
            frame_with_crc[34] = 8'h99;
            frame_with_crc[35] = 8'h71;
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
                    frame_with_crc[0], frame_with_crc[1], frame_with_crc[2], frame_with_crc[3],
                    frame_with_crc[4], frame_with_crc[5], frame_with_crc[6], frame_with_crc[7]
                ),
                8'hFF,
                1'b0
            );

            drive_axi_beat(
                pack8(
                    frame_with_crc[8], frame_with_crc[9], frame_with_crc[10], frame_with_crc[11],
                    frame_with_crc[12], frame_with_crc[13], frame_with_crc[14], frame_with_crc[15]
                ),
                8'hFF,
                1'b0
            );

            drive_axi_beat(
                pack8(
                    frame_with_crc[16], frame_with_crc[17], frame_with_crc[18], frame_with_crc[19],
                    frame_with_crc[20], frame_with_crc[21], frame_with_crc[22], frame_with_crc[23]
                ),
                8'hFF,
                1'b0
            );

            drive_axi_beat(
                pack8(
                    frame_with_crc[24], frame_with_crc[25], frame_with_crc[26], frame_with_crc[27],
                    frame_with_crc[28], frame_with_crc[29], frame_with_crc[30], frame_with_crc[31]
                ),
                8'hFF,
                1'b0
            );

            drive_axi_beat(
                pack8(
                    frame_with_crc[32], frame_with_crc[33], frame_with_crc[34], frame_with_crc[35],
                    8'h00, 8'h00, 8'h00, 8'h00
                ),
                8'h0F,
                1'b1
            );
        end
    endtask

    // ------------------------------------------------------------
    // Monitor crc32_check output before packet_rx consumes it
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_output_count <= 0;
            crc_output_beats <= 0;
        end else begin
            if (axis_crc_to_packet.tvalid && axis_crc_to_packet.tready) begin
                int next_count;

                next_count = crc_output_count;
                crc_output_beats <= crc_output_beats + 1;

                for (int lane = 0; lane < 8; lane++) begin
                    if (axis_crc_to_packet.tkeep[lane]) begin
                        if (next_count < OUT_FRAME_BYTES) begin
                            crc_output_bytes[next_count] <= axis_crc_to_packet.tdata[8*lane +: 8];
                            next_count++;
                        end else begin
                            $fatal(1, "crc32_check output more than expected %0d bytes", OUT_FRAME_BYTES);
                        end
                    end
                end

                crc_output_count <= next_count;

                $display("[%0t] CRC output beat %0d: data=%016h keep=%02h last=%0b",
                         $time,
                         crc_output_beats,
                         axis_crc_to_packet.tdata,
                         axis_crc_to_packet.tkeep,
                         axis_crc_to_packet.tlast);
            end
        end
    end

    // ------------------------------------------------------------
    // Error monitors
    // ------------------------------------------------------------
    logic crc_ok_seen;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_ok_seen <= 1'b0;
        end else begin
            if (crc_ok) begin
                crc_ok_seen <= 1'b1;
            end

            if (crc_fail) begin
                $fatal(1, "crc32_check reported CRC failure");
            end

            if (crc_len_err) begin
                $fatal(1, "crc32_check reported length error");
            end

            if (pkt_len_err) begin
                $fatal(1, "packet_rx reported length error");
            end

            if (ether_type_err) begin
                $fatal(1, "packet_rx reported EtherType error");
            end

            if (version_err) begin
                $fatal(1, "packet_rx reported version error");
            end

            if (pkt_err) begin
                $fatal(1, "packet_rx reported packet error");
            end
        end
    end

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin
        rst_n = 1'b0;

        axis_in.tvalid = 1'b0;
        axis_in.tdata  = 64'd0;
        axis_in.tkeep  = 8'd0;
        axis_in.tlast  = 1'b0;

        build_input_frame();

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("Starting crc32_check + packet_rx test...");

        drive_frame_36_bytes();

        // Wait for packet_rx to parse packet
        wait (pkt_done);
        #1;

        // --------------------------------------------------------
        // Checks
        // --------------------------------------------------------
        if (!crc_ok_seen) begin
            $fatal(1, "crc_ok was never seen");
        end

        if (!pkt_valid) begin
            $fatal(1, "pkt_done occurred but pkt_valid was not high");
        end

        if (crc_output_count !== OUT_FRAME_BYTES) begin
            $fatal(1, "Wrong crc32_check output byte count. Got %0d, expected %0d",
                   crc_output_count, OUT_FRAME_BYTES);
        end

        if (crc_output_beats !== 4) begin
            $fatal(1, "Wrong crc32_check output beat count. Got %0d, expected 4",
                   crc_output_beats);
        end

        // Check crc32_check output is exactly the original frame without FCS
        for (int i = 0; i < OUT_FRAME_BYTES; i++) begin
            if (crc_output_bytes[i] !== frame_with_crc[i]) begin
                $fatal(1,
                    "crc32_check output byte mismatch at byte %0d. Got 0x%02h, expected 0x%02h",
                    i,
                    crc_output_bytes[i],
                    frame_with_crc[i]
                );
            end
        end

        // Check parsed header
        if (dst_mac !== 48'hDA_02_03_04_05_06) begin
            $fatal(1, "dst_mac mismatch. Got %012h", dst_mac);
        end

        if (src_mac !== 48'h5A_02_03_04_05_06) begin
            $fatal(1, "src_mac mismatch. Got %012h", src_mac);
        end

        if (ether_type !== 16'h88F7) begin
            $fatal(1, "ether_type mismatch. Got %04h", ether_type);
        end

        // Check parsed PTP-lite fields
        if (msg_type !== 8'h00) begin
            $fatal(1, "msg_type mismatch. Got %02h", msg_type);
        end

        if (version !== 8'h01) begin
            $fatal(1, "version mismatch. Got %02h", version);
        end

        if (seq_id !== 16'h0000) begin
            $fatal(1, "seq_id mismatch. Got %04h", seq_id);
        end

        if (flags !== 8'h00) begin
            $fatal(1, "flags mismatch. Got %02h", flags);
        end

        if (reserved !== 8'h00) begin
            $fatal(1, "reserved mismatch. Got %02h", reserved);
        end

        if (tx_tod_sec !== 48'h0000_0000_1234) begin
            $fatal(1, "tx_tod_sec mismatch. Got %012h", tx_tod_sec);
        end

        if (tx_tod_nsec !== 32'd123_456_789) begin
            $fatal(1, "tx_tod_nsec mismatch. Got %0d", tx_tod_nsec);
        end

        if (tx_tod_frac !== 16'hABCD) begin
            $fatal(1, "tx_tod_frac mismatch. Got %04h", tx_tod_frac);
        end

        $display("--------------------------------------------------");
        $display("tb_crc_check_packet_rx PASSED");
        $display("crc32_check output %0d bytes over %0d beats", crc_output_count, crc_output_beats);
        $display("Parsed:");
        $display("  dst_mac    = %012h", dst_mac);
        $display("  src_mac    = %012h", src_mac);
        $display("  ether_type = %04h", ether_type);
        $display("  msg_type   = %02h", msg_type);
        $display("  version    = %02h", version);
        $display("  seq_id     = %04h", seq_id);
        $display("  tx_sec     = %012h", tx_tod_sec);
        $display("  tx_nsec    = %0d", tx_tod_nsec);
        $display("  tx_frac    = %04h", tx_tod_frac);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
