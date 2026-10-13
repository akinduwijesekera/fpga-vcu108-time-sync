`timescale 1ns/1ps

module enc_dec_vio_test_top (
    input logic clk,
    input logic rst    // active-high reset
);

    // =========================================================================
    // VIO-driven TX inputs
    // =========================================================================

    logic [63:0] vio_tx_data;
    logic [7:0]  vio_tx_is_k;
    logic        vio_tx_valid;
    logic        vio_clear_errors;

    // =========================================================================
    // Useful constants for manual VIO entry
    // =========================================================================
    // K_IDLE  = 8'hBC  // K28.5
    // K_START = 8'hFB  // K27.7
    // K_END   = 8'hFD  // K29.7
    //
    // Example VIO test values:
    //
    // 1) All data:
    //    vio_tx_data  = 64'h0706_0504_0302_0100
    //    vio_tx_is_k  = 8'h00
    //    vio_tx_valid = 1
    //
    // 2) All IDLE:
    //    vio_tx_data  = 64'hBCBC_BCBC_BCBC_BCBC
    //    vio_tx_is_k  = 8'hFF
    //    vio_tx_valid = 1
    //
    // 3) START, data, END, IDLE:
    //    byte0 = K_START, byte5 = K_END, byte6/7 = K_IDLE
    //    vio_tx_data  = 64'hBCBC_FD33_2211_00FB
    //    vio_tx_is_k  = 8'b1110_0001
    //    vio_tx_valid = 1
    // =========================================================================

    // =========================================================================
    // Encoder
    // =========================================================================

    logic [79:0] code80;
    logic        enc_valid;
    logic        enc_err;

    enc_64b80b u_enc_64b80b (
        .clk        (clk),
        .rst        (rst),

        .data_in    (vio_tx_data),
        .is_k_in    (vio_tx_is_k),
        .valid_in   (vio_tx_valid),

        .code80_out (code80),
        .valid_out  (enc_valid),
        .enc_err    (enc_err)
    );

    // =========================================================================
    // Decoder
    // =========================================================================

    logic [63:0] dec_data;
    logic [7:0]  dec_is_k;
    logic        dec_valid;
    logic [7:0]  dec_code_err;
    logic [7:0]  dec_rd_err;
    logic        dec_any_err;

    dec_80b64b u_dec_80b64b (
        .clk       (clk),
        .rst       (rst),

        .code80_in (code80),
        .valid_in  (enc_valid),

        .data_out  (dec_data),
        .is_k_out  (dec_is_k),
        .valid_out (dec_valid),

        .code_err  (dec_code_err),
        .rd_err    (dec_rd_err),
        .any_err   (dec_any_err)
    );

    // =========================================================================
    // Expected-data delay alignment
    // =========================================================================
    // Encoder has internal input register + output register.
    // Decoder has internal input register + output register.
    //
    // Practical alignment from VIO input to decoder output is 3 clocks
    // for comparison against the original TX input.
    // =========================================================================

    logic [63:0] tx_data_d0;
    logic [63:0] tx_data_d1;
    logic [63:0] tx_data_d2;

    logic [7:0] tx_is_k_d0;
    logic [7:0] tx_is_k_d1;
    logic [7:0] tx_is_k_d2;

    logic tx_valid_d0;
    logic tx_valid_d1;
    logic tx_valid_d2;

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_data_d0  <= 64'd0;
            tx_data_d1  <= 64'd0;
            tx_data_d2  <= 64'd0;

            tx_is_k_d0  <= 8'd0;
            tx_is_k_d1  <= 8'd0;
            tx_is_k_d2  <= 8'd0;

            tx_valid_d0 <= 1'b0;
            tx_valid_d1 <= 1'b0;
            tx_valid_d2 <= 1'b0;
        end else begin
            tx_data_d0  <= vio_tx_data;
            tx_data_d1  <= tx_data_d0;
            tx_data_d2  <= tx_data_d1;

            tx_is_k_d0  <= vio_tx_is_k;
            tx_is_k_d1  <= tx_is_k_d0;
            tx_is_k_d2  <= tx_is_k_d1;

            tx_valid_d0 <= vio_tx_valid;
            tx_valid_d1 <= tx_valid_d0;
            tx_valid_d2 <= tx_valid_d1;
        end
    end

    // =========================================================================
    // Comparator
    // =========================================================================

    logic data_match;
    logic is_k_match;
    logic test_pass;
    logic test_fail;

    logic [31:0] test_count;
    logic [31:0] error_count;

    assign data_match = (dec_data == tx_data_d2);
    assign is_k_match = (dec_is_k == tx_is_k_d2);

    assign test_pass = dec_valid &&
                       tx_valid_d2 &&
                       data_match &&
                       is_k_match &&
                       !enc_err &&
                       !dec_any_err;

    assign test_fail = dec_valid &&
                       tx_valid_d2 &&
                       (
                           !data_match ||
                           !is_k_match ||
                           enc_err ||
                           dec_any_err
                       );

    always_ff @(posedge clk) begin
        if (rst || vio_clear_errors) begin
            test_count  <= 32'd0;
            error_count <= 32'd0;
        end else begin
            if (dec_valid && tx_valid_d2) begin
                test_count <= test_count + 32'd1;
            end

            if (test_fail) begin
                error_count <= error_count + 32'd1;
            end
        end
    end

    // =========================================================================
    // VIO instance
    // =========================================================================
    // Create this VIO IP in Vivado with:
    //
    // probe_out0 = 64 bits  -> vio_tx_data
    // probe_out1 = 8 bits   -> vio_tx_is_k
    // probe_out2 = 1 bit    -> vio_tx_valid
    // probe_out3 = 1 bit    -> vio_clear_errors
    //
    // probe_in0  = 64 bits
    // probe_in1  = 8 bits
    // probe_in2  = 1 bit
    // probe_in3  = 80 bits
    // probe_in4  = 1 bit
    // probe_in5  = 1 bit
    // probe_in6  = 64 bits
    // probe_in7  = 8 bits
    // probe_in8  = 1 bit
    // probe_in9  = 8 bits
    // probe_in10 = 8 bits
    // probe_in11 = 1 bit
    // probe_in12 = 1 bit
    // probe_in13 = 1 bit
    // probe_in14 = 1 bit
    // probe_in15 = 1 bit
    // probe_in16 = 32 bits
    // probe_in17 = 32 bits
    // =========================================================================

    vio_enc_dec_test u_vio_enc_dec_test (
        .clk        (clk),

        // VIO-controlled inputs
        .probe_out0 (vio_tx_data),
        .probe_out1 (vio_tx_is_k),
        .probe_out2 (vio_tx_valid),
        .probe_out3 (vio_clear_errors),

        // Observed TX side
        .probe_in0  (vio_tx_data),
        .probe_in1  (vio_tx_is_k),
        .probe_in2  (vio_tx_valid),

        // Encoder outputs
        .probe_in3  (code80),
        .probe_in4  (enc_valid),
        .probe_in5  (enc_err),

        // Decoder outputs
        .probe_in6  (dec_data),
        .probe_in7  (dec_is_k),
        .probe_in8  (dec_valid),
        .probe_in9  (dec_code_err),
        .probe_in10 (dec_rd_err),
        .probe_in11 (dec_any_err),

        // Comparator/debug
        .probe_in12 (data_match),
        .probe_in13 (is_k_match),
        .probe_in14 (test_pass),
        .probe_in15 (test_fail),
        .probe_in16 (test_count),
        .probe_in17 (error_count)
    );

endmodule
