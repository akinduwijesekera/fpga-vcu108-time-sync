`timescale 1ns/1ps

module tb_pcs_rx_full_chain;

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
    // Interfaces
    // -------------------------------------------------------------------------

    axi_stream_if #(64) axis_in(clk);
    axi_stream_if #(64) axis_out(clk);

    sym_stream_if sym_tx_serial(clk);

    // -------------------------------------------------------------------------
    // TX encode path signals
    // -------------------------------------------------------------------------

    logic [63:0] packed_data;
    logic [7:0]  packed_is_k;
    logic        packed_valid;

    logic [63:0] mux_data;
    logic [7:0]  mux_is_k;
    logic        mux_valid;

    logic [79:0] code80;
    logic        code80_valid;
    logic        enc_err;

    // -------------------------------------------------------------------------
    // RX decode path signals
    // -------------------------------------------------------------------------

    logic [63:0] dec_data;
    logic [7:0]  dec_is_k;
    logic        dec_valid;
    logic [7:0]  dec_code_err;
    logic [7:0]  dec_rd_err;
    logic        dec_any_err;

    // -------------------------------------------------------------------------
    // PCS RX64 status
    // -------------------------------------------------------------------------

    logic pcs_in_frame;
    logic pcs_sof;
    logic pcs_frame_done;
    logic pcs_frame_err;
    logic pcs_ctrl_err;
    logic pcs_sym_err;

    // -------------------------------------------------------------------------
    // DUT chain
    // -------------------------------------------------------------------------

    axis64_to_sym8 u_axis64_to_sym8 (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_axis (axis_in.slave),
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

        .m_axis        (axis_out.master),

        .in_frame      (pcs_in_frame),
        .rx_sof_strobe (pcs_sof),
        .frame_done    (pcs_frame_done),
        .frame_err     (pcs_frame_err),
        .ctrl_err      (pcs_ctrl_err),
        .sym_err       (pcs_sym_err)
    );

    assign axis_out.tready = 1'b1;

    // -------------------------------------------------------------------------
    // Test bookkeeping
    // -------------------------------------------------------------------------

    typedef struct packed {
        logic [63:0] data;
        logic [7:0]  keep;
        logic        last;
    } axi_beat_t;

    axi_beat_t expected_q[$];

    int error_count;
    int checked_beats;
    int expected_frames;
    int frame_done_count;
    bit test_done;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    task automatic axi_idle();
        begin
            axis_in.tvalid <= 1'b0;
            axis_in.tdata  <= 64'd0;
            axis_in.tkeep  <= 8'd0;
            axis_in.tlast  <= 1'b0;
        end
    endtask

    task automatic push_expected_axi(
        input logic [63:0] data,
        input logic [7:0]  keep,
        input logic        last
    );
        axi_beat_t item;
        begin
            item.data = data;
            item.keep = keep;
            item.last = last;
            expected_q.push_back(item);
        end
    endtask

    task automatic send_axi_beat(
        input logic [63:0] data,
        input logic [7:0]  keep,
        input logic        last
    );
        begin
            @(posedge clk);

            axis_in.tdata  <= data;
            axis_in.tkeep  <= keep;
            axis_in.tlast  <= last;
            axis_in.tvalid <= 1'b1;

            while (!(axis_in.tvalid && axis_in.tready)) begin
                @(posedge clk);
            end

            @(posedge clk);

            axis_in.tvalid <= 1'b0;
            axis_in.tdata  <= 64'd0;
            axis_in.tkeep  <= 8'd0;
            axis_in.tlast  <= 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Frame stimulus
    // -------------------------------------------------------------------------

    task automatic send_frame_20_bytes_with_gaps();
        logic [63:0] beat0;
        logic [63:0] beat1;
        logic [63:0] beat2;
        begin
            $display("[%0t] Sending 20-byte frame with gaps", $time);

            beat0 = {
                8'h07, 8'h06, 8'h05, 8'h04,
                8'h03, 8'h02, 8'h01, 8'h00
            };

            beat1 = {
                8'h0F, 8'h0E, 8'h0D, 8'h0C,
                8'h0B, 8'h0A, 8'h09, 8'h08
            };

            beat2 = {
                8'h00, 8'h00, 8'h00, 8'h00,
                8'h13, 8'h12, 8'h11, 8'h10
            };

            push_expected_axi(beat0, 8'hFF, 1'b0);
            push_expected_axi(beat1, 8'hFF, 1'b0);
            push_expected_axi(64'h0000_0000_1312_1110, 8'h0F, 1'b1);

            expected_frames++;

            send_axi_beat(beat0, 8'hFF, 1'b0);
            repeat (5) @(posedge clk);

            send_axi_beat(beat1, 8'hFF, 1'b0);
            repeat (3) @(posedge clk);

            send_axi_beat(beat2, 8'h0F, 1'b1);
        end
    endtask

    task automatic send_frame_1_byte();
        logic [63:0] beat0;
        begin
            $display("[%0t] Sending 1-byte frame", $time);

            beat0 = 64'h0000_0000_0000_00A5;

            push_expected_axi(beat0, 8'h01, 1'b1);
            expected_frames++;

            send_axi_beat(beat0, 8'h01, 1'b1);
        end
    endtask

    task automatic send_frame_8_bytes_exact();
        logic [63:0] beat0;
        begin
            $display("[%0t] Sending exact 8-byte frame", $time);

            beat0 = {
                8'h88, 8'h77, 8'h66, 8'h55,
                8'h44, 8'h33, 8'h22, 8'h11
            };

            push_expected_axi(beat0, 8'hFF, 1'b1);
            expected_frames++;

            send_axi_beat(beat0, 8'hFF, 1'b1);
        end
    endtask

    task automatic send_frame_16_bytes_exact();
        logic [63:0] beat0;
        logic [63:0] beat1;
        begin
            $display("[%0t] Sending exact 16-byte frame", $time);

            beat0 = 64'h8877_6655_4433_2211;
            beat1 = 64'h00FF_EEDD_CCAA_9988;

            push_expected_axi(beat0, 8'hFF, 1'b0);
            push_expected_axi(beat1, 8'hFF, 1'b1);
            expected_frames++;

            send_axi_beat(beat0, 8'hFF, 1'b0);
            repeat (2) @(posedge clk);
            send_axi_beat(beat1, 8'hFF, 1'b1);
        end
    endtask

    // -------------------------------------------------------------------------
    // Output monitor / checker
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            checked_beats    = 0;
            frame_done_count = 0;
        end else begin
            if (enc_err) begin
                $error("[%0t] Encoder error asserted", $time);
                error_count = error_count + 1;
            end

            if (dec_any_err) begin
                $error("[%0t] Decoder error: code_err=%02h rd_err=%02h",
                       $time, dec_code_err, dec_rd_err);
                error_count = error_count + 1;
            end

            if (pcs_frame_err) begin
                $error("[%0t] PCS frame_err asserted", $time);
                error_count = error_count + 1;
            end

            if (pcs_ctrl_err) begin
                $error("[%0t] PCS ctrl_err asserted", $time);
                error_count = error_count + 1;
            end

            if (pcs_sym_err) begin
                $error("[%0t] PCS sym_err asserted", $time);
                error_count = error_count + 1;
            end

            if (pcs_sof) begin
                $display("[%0t] PCS SOF detected", $time);
            end

            if (pcs_frame_done) begin
                $display("[%0t] PCS frame_done", $time);
                frame_done_count = frame_done_count + 1;
            end

            if (axis_out.tvalid && axis_out.tready) begin
                axi_beat_t exp;

                if (expected_q.size() == 0) begin
                    $error("[%0t] Unexpected AXI output: data=%016h keep=%02h last=%0b",
                           $time, axis_out.tdata, axis_out.tkeep, axis_out.tlast);
                    error_count = error_count + 1;
                end else begin
                    exp = expected_q.pop_front();

                    if (axis_out.tdata !== exp.data) begin
                        $error("[%0t] AXI data mismatch: expected=%016h got=%016h",
                               $time, exp.data, axis_out.tdata);
                        error_count = error_count + 1;
                    end

                    if (axis_out.tkeep !== exp.keep) begin
                        $error("[%0t] AXI keep mismatch: expected=%02h got=%02h",
                               $time, exp.keep, axis_out.tkeep);
                        error_count = error_count + 1;
                    end

                    if (axis_out.tlast !== exp.last) begin
                        $error("[%0t] AXI last mismatch: expected=%0b got=%0b",
                               $time, exp.last, axis_out.tlast);
                        error_count = error_count + 1;
                    end

                    checked_beats = checked_beats + 1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Timeout
    // -------------------------------------------------------------------------

    initial begin
        test_done = 1'b0;

        #2_000_000;

        if (!test_done) begin
            $error("TIMEOUT: simulation did not complete");
            $finish;
        end
    end

    // -------------------------------------------------------------------------
    // Main test
    // -------------------------------------------------------------------------

    initial begin
        error_count      = 0;
        checked_beats    = 0;
        expected_frames  = 0;
        frame_done_count = 0;

        rst_n = 1'b0;
        axi_idle();

        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        repeat (30) @(posedge clk);

        send_frame_20_bytes_with_gaps();

        repeat (120) @(posedge clk);

        send_frame_1_byte();

        repeat (120) @(posedge clk);

        send_frame_8_bytes_exact();

        repeat (120) @(posedge clk);

        send_frame_16_bytes_exact();

        repeat (700) @(posedge clk);

        $display("----------------------------------------------------");
        $display("Expected frames       = %0d", expected_frames);
        $display("PCS frame_done count  = %0d", frame_done_count);
        $display("Checked AXI beats     = %0d", checked_beats);
        $display("Remaining expected_q  = %0d", expected_q.size());
        $display("Error count           = %0d", error_count);
        $display("----------------------------------------------------");

        if (frame_done_count !== expected_frames) begin
            $error("Frame done count mismatch: expected=%0d got=%0d",
                   expected_frames, frame_done_count);
            error_count = error_count + 1;
        end

        if (checked_beats !== 7) begin
            $error("Checked beat count mismatch: expected=7 got=%0d", checked_beats);
            error_count = error_count + 1;
        end

        if (expected_q.size() != 0) begin
            $error("Expected AXI queue not empty at end");
            error_count = error_count + 1;
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
