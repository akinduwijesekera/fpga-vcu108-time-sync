`timescale 1ns/1ps

module tb_sync_loopback_top;

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

    logic [47:0] tx_tod_sec;
    logic [31:0] tx_tod_nsec;
    logic [15:0] tx_tod_frac;

    logic [47:0] rx_local_sec;
    logic [31:0] rx_local_nsec;
    logic [15:0] rx_local_frac;

    // ------------------------------------------------------------
    // DUT outputs
    // ------------------------------------------------------------
    logic        tx_done;
    logic [15:0] seq_id_out;

    logic        pkt_valid;
    logic [15:0] rx_seq_id;

    logic        diff_valid;
    logic [47:0] diff_sec;
    logic [31:0] diff_nsec;
    logic [15:0] diff_frac;
    logic        underflow;

    logic        enc_err;
    logic        dec_any_err;
    logic        rx_frame_err;
    logic        rx_crc_fail;
    logic        pkt_err;

    // ------------------------------------------------------------
    // Test parameters
    // ------------------------------------------------------------
    localparam int NUM_PKTS = 5;

    logic [47:0] exp_sec  [0:NUM_PKTS-1];
    logic [31:0] exp_nsec [0:NUM_PKTS-1];
    logic [15:0] exp_frac [0:NUM_PKTS-1];
    logic [7:0]  exp_msg  [0:NUM_PKTS-1];

    int tx_done_count;
    int pkt_valid_count;
    int diff_valid_count;

    int start_cycle;
    int tx_done_cycle;
    int pkt_valid_cycle;
    int diff_valid_cycle;

    int cycle_count;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    sync_loopback_top u_dut (
        .clk            (clk),
        .rst_n          (rst_n),

        .start_tx       (start_tx),
        .msg_type       (msg_type),

        .dst_mac        (dst_mac),
        .src_mac        (src_mac),
        .ether_type     (ether_type),

        .tx_tod_sec     (tx_tod_sec),
        .tx_tod_nsec    (tx_tod_nsec),
        .tx_tod_frac    (tx_tod_frac),

        .rx_local_sec   (rx_local_sec),
        .rx_local_nsec  (rx_local_nsec),
        .rx_local_frac  (rx_local_frac),

        .tx_done        (tx_done),
        .seq_id_out     (seq_id_out),

        .pkt_valid      (pkt_valid),
        .rx_seq_id      (rx_seq_id),

        .diff_valid     (diff_valid),
        .diff_sec       (diff_sec),
        .diff_nsec      (diff_nsec),
        .diff_frac      (diff_frac),
        .underflow      (underflow),

        .enc_err        (enc_err),
        .dec_any_err    (dec_any_err),
        .rx_frame_err   (rx_frame_err),
        .rx_crc_fail    (rx_crc_fail),
        .pkt_err        (pkt_err)
    );

    // ------------------------------------------------------------
    // Cycle counter
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    // ------------------------------------------------------------
    // Output/event counters
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_done_count    <= 0;
            pkt_valid_count  <= 0;
            diff_valid_count <= 0;
        end else begin
            if (tx_done) begin
                tx_done_count <= tx_done_count + 1;
            end

            if (pkt_valid) begin
                pkt_valid_count <= pkt_valid_count + 1;
            end

            if (diff_valid) begin
                diff_valid_count <= diff_valid_count + 1;
            end
        end
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
                $fatal(1, "Decoder error asserted");
            end

            if (rx_frame_err) begin
                $fatal(1, "RX frame error asserted");
            end

            if (rx_crc_fail) begin
                $fatal(1, "RX CRC failed");
            end

            if (pkt_err) begin
                $fatal(1, "Packet parser error asserted");
            end

            if (diff_valid && underflow) begin
                $fatal(1, "Timestamp difference underflow asserted");
            end
        end
    end

    // ------------------------------------------------------------
    // Send one packet through the final top-level
    // ------------------------------------------------------------
    task automatic send_packet(input int pkt_idx);
        begin
            msg_type    = exp_msg[pkt_idx];

            tx_tod_sec  = exp_sec[pkt_idx];
            tx_tod_nsec = exp_nsec[pkt_idx];
            tx_tod_frac = exp_frac[pkt_idx];

            // RX local timestamp is intentionally later than TX timestamp
            rx_local_sec  = exp_sec[pkt_idx];
            rx_local_nsec = exp_nsec[pkt_idx] + 32'd10;
            rx_local_frac = exp_frac[pkt_idx] + 16'h0010;

            repeat (2) @(posedge clk);

            start_cycle = cycle_count;

            start_tx <= 1'b1;
            @(posedge clk);
            start_tx <= 1'b0;

            // Wait for tx_done
            wait (tx_done);
            tx_done_cycle = cycle_count;

            // Wait for packet parser output
            wait (pkt_valid);
            pkt_valid_cycle = cycle_count;
            #1;

            if (rx_seq_id !== pkt_idx[15:0]) begin
                $fatal(1,
                    "Packet %0d rx_seq_id mismatch. Got %04h expected %04h",
                    pkt_idx,
                    rx_seq_id,
                    pkt_idx[15:0]
                );
            end

            // Wait for timestamp difference output
            wait (diff_valid);
            diff_valid_cycle = cycle_count;
            #1;

            if (diff_sec !== 48'd0) begin
                $fatal(1,
                    "Packet %0d diff_sec mismatch. Got %0d expected 0",
                    pkt_idx,
                    diff_sec
                );
            end

            if (diff_nsec !== 32'd10) begin
                $fatal(1,
                    "Packet %0d diff_nsec mismatch. Got %0d expected 10",
                    pkt_idx,
                    diff_nsec
                );
            end

            if (diff_frac !== 16'h0010) begin
                $fatal(1,
                    "Packet %0d diff_frac mismatch. Got %04h expected 0010",
                    pkt_idx,
                    diff_frac
                );
            end

            $display("[%0t] Packet %0d PASSED", $time, pkt_idx);
            $display("  rx_seq_id        = %04h", rx_seq_id);
            $display("  diff_sec         = %0d", diff_sec);
            $display("  diff_nsec        = %0d", diff_nsec);
            $display("  diff_frac        = %04h", diff_frac);
            $display("  start->tx_done   = %0d cycles", tx_done_cycle - start_cycle);
            $display("  start->pkt_valid = %0d cycles", pkt_valid_cycle - start_cycle);
            $display("  start->diff_valid= %0d cycles", diff_valid_cycle - start_cycle);
            $display("--------------------------------------------------");

            repeat (20) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin
        // Initial values
        rst_n = 1'b0;

        start_tx = 1'b0;
        msg_type = 8'd0;

        dst_mac    = 48'hDA_02_03_04_05_06;
        src_mac    = 48'h5A_02_03_04_05_06;
        ether_type = 16'h88F7;

        tx_tod_sec  = 48'd0;
        tx_tod_nsec = 32'd0;
        tx_tod_frac = 16'd0;

        rx_local_sec  = 48'd0;
        rx_local_nsec = 32'd0;
        rx_local_frac = 16'd0;

        // Expected packet fields
        exp_msg[0] = 8'h00;
        exp_msg[1] = 8'h01;
        exp_msg[2] = 8'h02;
        exp_msg[3] = 8'h03;
        exp_msg[4] = 8'h04;

        exp_sec[0] = 48'h0000_0000_1000;
        exp_sec[1] = 48'h0000_0000_1001;
        exp_sec[2] = 48'h0000_0000_1002;
        exp_sec[3] = 48'h0000_0000_1003;
        exp_sec[4] = 48'h0000_0000_1004;

        exp_nsec[0] = 32'd100_000_000;
        exp_nsec[1] = 32'd200_000_000;
        exp_nsec[2] = 32'd300_000_000;
        exp_nsec[3] = 32'd400_000_000;
        exp_nsec[4] = 32'd500_000_000;

        exp_frac[0] = 16'h0001;
        exp_frac[1] = 16'h0011;
        exp_frac[2] = 16'h0021;
        exp_frac[3] = 16'h0031;
        exp_frac[4] = 16'h0041;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        $display("Starting tb_sync_loopback_top...");
        $display("Testing final timing-closed sync_loopback_top directly");
        $display("--------------------------------------------------");

        for (int p = 0; p < NUM_PKTS; p++) begin
            send_packet(p);
        end

        repeat (50) @(posedge clk);

        // Final count checks
        if (tx_done_count !== NUM_PKTS) begin
            $fatal(1,
                "tx_done_count mismatch. Got %0d expected %0d",
                tx_done_count,
                NUM_PKTS
            );
        end

        if (pkt_valid_count !== NUM_PKTS) begin
            $fatal(1,
                "pkt_valid_count mismatch. Got %0d expected %0d",
                pkt_valid_count,
                NUM_PKTS
            );
        end

        if (diff_valid_count !== NUM_PKTS) begin
            $fatal(1,
                "diff_valid_count mismatch. Got %0d expected %0d",
                diff_valid_count,
                NUM_PKTS
            );
        end

        if (seq_id_out !== NUM_PKTS[15:0]) begin
            $fatal(1,
                "Final seq_id_out mismatch. Got %04h expected %04h",
                seq_id_out,
                NUM_PKTS[15:0]
            );
        end

        $display("==================================================");
        $display("tb_sync_loopback_top PASSED");
        $display("Packets sent/received: %0d", NUM_PKTS);
        $display("tx_done_count         = %0d", tx_done_count);
        $display("pkt_valid_count       = %0d", pkt_valid_count);
        $display("diff_valid_count      = %0d", diff_valid_count);
        $display("final seq_id_out      = %04h", seq_id_out);
        $display("==================================================");

        $finish;
    end

    // ------------------------------------------------------------
    // Timeout
    // ------------------------------------------------------------
    initial begin
        #10_000_000;
        $fatal(1, "Timeout: tb_sync_loopback_top did not complete");
    end

endmodule