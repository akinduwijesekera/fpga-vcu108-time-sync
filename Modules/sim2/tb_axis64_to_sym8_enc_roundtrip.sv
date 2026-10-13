`timescale 1ns/1ps

module tb_axis64_to_sym8_enc_roundtrip;

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
    // Constants
    // -------------------------------------------------------------------------

    localparam logic [7:0] K_IDLE  = 8'hBC; // K28.5
    localparam logic [7:0] K_START = 8'hFB; // K27.7
    localparam logic [7:0] K_END   = 8'hFD; // K29.7

    // -------------------------------------------------------------------------
    // Interfaces
    // -------------------------------------------------------------------------

    axi_stream_if #(64) axis_in(clk);
    sym_stream_if       sym_serial(clk);

    // -------------------------------------------------------------------------
    // DUT chain signals
    // -------------------------------------------------------------------------

    logic [63:0] packed_data;
    logic [7:0]  packed_is_k;
    logic        packed_valid;

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
    // DUT instances
    // -------------------------------------------------------------------------

    axis64_to_sym8 u_axis64_to_sym8 (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_axis (axis_in.slave),
        .sym    (sym_serial.source)
    );

    sym8_to_parallel64 u_sym8_to_parallel64 (
        .clk       (clk),
        .rst_n     (rst_n),
        .sym       (sym_serial.sink),

        .data_out  (packed_data),
        .is_k_out  (packed_is_k),
        .valid_out (packed_valid)
    );

    enc_64b80b u_enc_64b80b (
        .clk        (clk),
        .rst        (rst),

        .data_in    (packed_data),
        .is_k_in    (packed_is_k),
        .valid_in   (packed_valid),

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

    // -------------------------------------------------------------------------
    // Testbench bookkeeping
    // -------------------------------------------------------------------------

    logic [7:0] expected_q[$];

    int expected_frame_count;
    int received_frame_count;
    int total_checked_bytes;
    int error_count;

    typedef enum logic [1:0] {
        MON_WAIT_START,
        MON_DATA
    } mon_state_t;

    mon_state_t mon_state;

    bit test_done;

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------

    task automatic push_expected_byte(input logic [7:0] b);
        begin
            expected_q.push_back(b);
        end
    endtask

    task automatic axi_idle();
        begin
            axis_in.tvalid <= 1'b0;
            axis_in.tdata  <= 64'd0;
            axis_in.tkeep  <= 8'd0;
            axis_in.tlast  <= 1'b0;
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
    // Frame generators
    // -------------------------------------------------------------------------

    task automatic send_frame_20_bytes();
        logic [63:0] beat0;
        logic [63:0] beat1;
        logic [63:0] beat2;
        begin
            $display("[%0t] Sending 20-byte frame", $time);

            // Byte 0 is tdata[7:0], byte 1 is tdata[15:8], etc.
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

            // Expected decoded data sequence:
            // 00 01 02 ... 13
            for (int i = 0; i < 20; i++) begin
                push_expected_byte(8'(i));
            end

            expected_frame_count = expected_frame_count + 1;

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

            push_expected_byte(8'hA5);
            expected_frame_count = expected_frame_count + 1;

            send_axi_beat(beat0, 8'h01, 1'b1);
        end
    endtask

    task automatic send_frame_8_bytes();
        logic [63:0] beat0;
        begin
            $display("[%0t] Sending 8-byte frame", $time);

            beat0 = {
                8'h88, 8'h77, 8'h66, 8'h55,
                8'h44, 8'h33, 8'h22, 8'h11
            };

            push_expected_byte(8'h11);
            push_expected_byte(8'h22);
            push_expected_byte(8'h33);
            push_expected_byte(8'h44);
            push_expected_byte(8'h55);
            push_expected_byte(8'h66);
            push_expected_byte(8'h77);
            push_expected_byte(8'h88);

            expected_frame_count = expected_frame_count + 1;

            send_axi_beat(beat0, 8'hFF, 1'b1);
        end
    endtask

    // -------------------------------------------------------------------------
    // Self-checking decoded symbol monitor
    // -------------------------------------------------------------------------

    task automatic check_decoded_symbol(
        input logic [7:0] data,
        input logic       is_k
    );
        logic [7:0] exp;
        begin
            unique case (mon_state)

                MON_WAIT_START: begin
                    if (is_k && data == K_IDLE) begin
                        // Normal idle before frame.
                    end else if (is_k && data == K_START) begin
                        $display("[%0t] Monitor: K_START detected", $time);
                        mon_state = MON_DATA;
                    end else begin
                        $error("[%0t] Unexpected symbol while waiting for K_START: data=%02h is_k=%0b",
                               $time, data, is_k);
                        error_count = error_count + 1;
                    end
                end

                MON_DATA: begin
                    if (is_k && data == K_END) begin
                        $display("[%0t] Monitor: K_END detected", $time);
                        received_frame_count = received_frame_count + 1;
                        mon_state = MON_WAIT_START;
                    end else if (is_k && data == K_IDLE) begin
                        // IDLEs inside frame are allowed here because axis64_to_sym8
                        // may emit IDLEs while waiting for the next AXI beat.
                        $display("[%0t] Monitor: IDLE inside frame gap", $time);
                    end else if (!is_k) begin
                        if (expected_q.size() == 0) begin
                            $error("[%0t] Received extra data byte %02h but expected queue is empty",
                                   $time, data);
                            error_count = error_count + 1;
                        end else begin
                            exp = expected_q.pop_front();

                            if (data !== exp) begin
                                $error("[%0t] Data mismatch: expected %02h, got %02h",
                                       $time, exp, data);
                                error_count = error_count + 1;
                            end else begin
                                total_checked_bytes = total_checked_bytes + 1;
                            end
                        end
                    end else begin
                        $error("[%0t] Unexpected K symbol inside frame: data=%02h", $time, data);
                        error_count = error_count + 1;
                    end
                end

                default: begin
                    mon_state = MON_WAIT_START;
                end

            endcase
        end
    endtask

    // -------------------------------------------------------------------------
    // Decoder output monitor
    // -------------------------------------------------------------------------
    // Plain always block, not always_ff, because this is testbench code and these
    // variables are also initialised/checked in initial blocks.
    // -------------------------------------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            mon_state = MON_WAIT_START;
        end else begin
            if (code80_valid && enc_err) begin
                $error("[%0t] Encoder reported enc_err", $time);
                error_count = error_count + 1;
            end

            if (dec_valid) begin
                if (dec_any_err) begin
                    $error("[%0t] Decoder error: code_err=%02h rd_err=%02h",
                           $time, dec_code_err, dec_rd_err);
                    error_count = error_count + 1;
                end

                for (int n = 0; n < 8; n++) begin
                    check_decoded_symbol(
                        dec_data[n*8 +: 8],
                        dec_is_k[n]
                    );
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
    // Main stimulus
    // -------------------------------------------------------------------------

    initial begin
        expected_frame_count = 0;
        received_frame_count = 0;
        total_checked_bytes  = 0;
        error_count          = 0;
        mon_state            = MON_WAIT_START;

        rst_n = 1'b0;
        axi_idle();

        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        repeat (20) @(posedge clk);

        send_frame_20_bytes();

        repeat (100) @(posedge clk);

        send_frame_1_byte();

        repeat (100) @(posedge clk);

        send_frame_8_bytes();

        repeat (500) @(posedge clk);

        $display("----------------------------------------------------");
        $display("Expected frames       = %0d", expected_frame_count);
        $display("Received frames       = %0d", received_frame_count);
        $display("Checked data bytes    = %0d", total_checked_bytes);
        $display("Remaining expected_q  = %0d", expected_q.size());
        $display("Error count           = %0d", error_count);
        $display("----------------------------------------------------");

        if (received_frame_count !== expected_frame_count) begin
            $error("Frame count mismatch: expected %0d, received %0d",
                   expected_frame_count, received_frame_count);
            error_count = error_count + 1;
        end

        if (expected_q.size() != 0) begin
            $error("Expected queue not empty at end of test");
            error_count = error_count + 1;
        end

        if (total_checked_bytes !== 29) begin
            $error("Checked byte count mismatch: expected 29, got %0d",
                   total_checked_bytes);
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
