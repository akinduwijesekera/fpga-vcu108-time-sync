`timescale 1ns/1ps

module tb_tx_packet_framer_crc;

    // ------------------------------------------------------------
    // Clock/reset
    // ------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #2.5 clk = ~clk; // 200 MHz

    // ------------------------------------------------------------
    // DUT inputs
    // ------------------------------------------------------------
    logic        start_tx;
    logic [7:0]  msg_type;

    logic [47:0] dst_mac;
    logic [47:0] src_mac;
    logic [15:0] ether_type;

    logic [47:0] tod_sec;
    logic [31:0] tod_nsec;
    logic [15:0] tod_frac;

    logic tx_busy;
    logic tx_done;
    logic [15:0] seq_id_out;

    logic crc_busy;
    logic crc_done;

    // ------------------------------------------------------------
    // AXI stream interfaces
    // ------------------------------------------------------------
    axi_stream_if #(64) axis_framer_to_crc(clk);
    axi_stream_if #(64) axis_crc_out(clk);

    // ------------------------------------------------------------
    // DUTs
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

        .tod_sec    (tod_sec),
        .tod_nsec   (tod_nsec),
        .tod_frac   (tod_frac),

        .m_axis     (axis_framer_to_crc.master),

        .tx_busy    (tx_busy),
        .tx_done    (tx_done),
        .seq_id_out (seq_id_out)
    );

    crc_append_axis u_crc_append_axis (
        .clk      (clk),
        .rst_n    (rst_n),

        .s_axis   (axis_framer_to_crc.slave),
        .m_axis   (axis_crc_out.master),

        .crc_busy (crc_busy),
        .crc_done (crc_done)
    );

    // ------------------------------------------------------------
    // Testbench output ready
    // ------------------------------------------------------------
    initial begin
        axis_crc_out.tready = 1'b1;
    end

    // ------------------------------------------------------------
    // Captured output bytes
    // ------------------------------------------------------------
    localparam int EXPECT_NO_CRC_BYTES   = 32;
    localparam int EXPECT_WITH_CRC_BYTES = 36;

    logic [7:0] captured_bytes [0:EXPECT_WITH_CRC_BYTES-1];
    int captured_count;
    int beat_count;

    // ------------------------------------------------------------
    // Expected frame bytes before CRC
    // ------------------------------------------------------------
    logic [7:0] expected_no_crc [0:EXPECT_NO_CRC_BYTES-1];

    task automatic build_expected_no_crc;
        begin
            // Ethernet-style header
            expected_no_crc[0]  = dst_mac[47:40];
            expected_no_crc[1]  = dst_mac[39:32];
            expected_no_crc[2]  = dst_mac[31:24];
            expected_no_crc[3]  = dst_mac[23:16];
            expected_no_crc[4]  = dst_mac[15:8];
            expected_no_crc[5]  = dst_mac[7:0];

            expected_no_crc[6]  = src_mac[47:40];
            expected_no_crc[7]  = src_mac[39:32];
            expected_no_crc[8]  = src_mac[31:24];
            expected_no_crc[9]  = src_mac[23:16];
            expected_no_crc[10] = src_mac[15:8];
            expected_no_crc[11] = src_mac[7:0];

            expected_no_crc[12] = ether_type[15:8];
            expected_no_crc[13] = ether_type[7:0];

            // PTP-lite payload, 18 bytes
            expected_no_crc[14] = msg_type;
            expected_no_crc[15] = 8'h01;       // version

            expected_no_crc[16] = 8'h00;       // seq_id[15:8], first packet = 0
            expected_no_crc[17] = 8'h00;       // seq_id[7:0]

            expected_no_crc[18] = 8'h00;       // flags
            expected_no_crc[19] = 8'h00;       // reserved

            expected_no_crc[20] = tod_sec[47:40];
            expected_no_crc[21] = tod_sec[39:32];
            expected_no_crc[22] = tod_sec[31:24];
            expected_no_crc[23] = tod_sec[23:16];
            expected_no_crc[24] = tod_sec[15:8];
            expected_no_crc[25] = tod_sec[7:0];

            expected_no_crc[26] = tod_nsec[31:24];
            expected_no_crc[27] = tod_nsec[23:16];
            expected_no_crc[28] = tod_nsec[15:8];
            expected_no_crc[29] = tod_nsec[7:0];

            expected_no_crc[30] = tod_frac[15:8];
            expected_no_crc[31] = tod_frac[7:0];
        end
    endtask

    // ------------------------------------------------------------
    // Golden CRC model
    // Must match crc_append_axis reflected CRC
    // ------------------------------------------------------------
    localparam logic [31:0] POLY_R = 32'hEDB88320;
    localparam logic [31:0] INIT   = 32'hFFFF_FFFF;
    localparam logic [31:0] XOROUT = 32'hFFFF_FFFF;

    function automatic logic [31:0] crc_step_byte(
        input logic [31:0] c,
        input logic [7:0]  d
    );
        logic [31:0] tmp;
        int i;
        begin
            tmp = c ^ {24'h0, d};

            for (i = 0; i < 8; i++) begin
                if (tmp[0]) begin
                    tmp = (tmp >> 1) ^ POLY_R;
                end else begin
                    tmp = tmp >> 1;
                end
            end

            return tmp;
        end
    endfunction

    function automatic logic [31:0] crc32_bytes_32;
        logic [31:0] c;
        int i;
        begin
            c = INIT;

            for (i = 0; i < EXPECT_NO_CRC_BYTES; i++) begin
                c = crc_step_byte(c, expected_no_crc[i]);
            end

            crc32_bytes_32 = c ^ XOROUT;
        end
    endfunction

    // ------------------------------------------------------------
    // AXI output monitor
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_count <= 0;
            beat_count     <= 0;
        end else begin
            if (axis_crc_out.tvalid && axis_crc_out.tready) begin
                int next_count;

                next_count = captured_count;

                beat_count <= beat_count + 1;

                for (int lane = 0; lane < 8; lane++) begin
                    if (axis_crc_out.tkeep[lane]) begin
                        if (next_count < EXPECT_WITH_CRC_BYTES) begin
                            captured_bytes[next_count] <= axis_crc_out.tdata[8*lane +: 8];
                            next_count++;
                        end else begin
                            $fatal(1, "Captured more than expected %0d bytes", EXPECT_WITH_CRC_BYTES);
                        end
                    end
                end

                captured_count <= next_count;

                $display("[%0t] beat %0d: data=%016h keep=%02h last=%0b",
                         $time,
                         beat_count,
                         axis_crc_out.tdata,
                         axis_crc_out.tkeep,
                         axis_crc_out.tlast);

                if (axis_crc_out.tlast) begin
                    if (axis_crc_out.tkeep !== 8'h0F) begin
                        $fatal(1, "Final CRC beat tkeep wrong. Got %02h, expected 0F",
                               axis_crc_out.tkeep);
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    logic [31:0] expected_crc;
    logic [31:0] captured_crc;

    initial begin
        // Initial values
        rst_n     = 1'b0;
        start_tx  = 1'b0;

        msg_type   = 8'h00; // e.g. SYNC
        dst_mac    = 48'hDA_02_03_04_05_06;
        src_mac    = 48'h5A_02_03_04_05_06;
        ether_type = 16'h88F7;

        tod_sec  = 48'h0000_0000_1234;
        tod_nsec = 32'd123_456_789;
        tod_frac = 16'hABCD;

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        build_expected_no_crc();
        expected_crc = crc32_bytes_32();

        $display("Expected CRC = 0x%08h", expected_crc);

        // Start frame
        @(posedge clk);
        start_tx <= 1'b1;

        @(posedge clk);
        start_tx <= 1'b0;

        // Wait until CRC output completes
        wait (crc_done);
        repeat (3) @(posedge clk);

        // --------------------------------------------------------
        // Checks
        // --------------------------------------------------------
        if (captured_count !== EXPECT_WITH_CRC_BYTES) begin
            $fatal(1, "Wrong captured byte count. Got %0d, expected %0d",
                   captured_count, EXPECT_WITH_CRC_BYTES);
        end

        if (beat_count !== 5) begin
            $fatal(1, "Wrong output beat count. Got %0d, expected 5", beat_count);
        end

        // Check first 32 bytes
        for (int i = 0; i < EXPECT_NO_CRC_BYTES; i++) begin
            if (captured_bytes[i] !== expected_no_crc[i]) begin
                $fatal(1,
                    "Frame byte mismatch at byte %0d. Got 0x%02h, expected 0x%02h",
                    i,
                    captured_bytes[i],
                    expected_no_crc[i]
                );
            end
        end

        // Check CRC byte order:
        // crc_append_axis sends:
        // byte 32 = crc[7:0]
        // byte 33 = crc[15:8]
        // byte 34 = crc[23:16]
        // byte 35 = crc[31:24]
        captured_crc = {
            captured_bytes[35],
            captured_bytes[34],
            captured_bytes[33],
            captured_bytes[32]
        };

        if (captured_crc !== expected_crc) begin
            $fatal(1, "CRC mismatch. Got 0x%08h, expected 0x%08h",
                   captured_crc, expected_crc);
        end

        if (seq_id_out !== 16'd1) begin
            $fatal(1, "seq_id_out wrong after first frame. Got %0d, expected 1",
                   seq_id_out);
        end

        $display("--------------------------------------------------");
        $display("tb_tx_packet_framer_crc PASSED");
        $display("Captured %0d bytes over %0d beats", captured_count, beat_count);
        $display("CRC = 0x%08h", captured_crc);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
