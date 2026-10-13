`timescale 1ns/1ps

module enc_dec_test_top (
    input  logic clk,
    input  logic rst,   // active-high reset

    // Debug outputs
    output logic [63:0] dbg_tx_data,
    output logic [7:0]  dbg_tx_is_k,
    output logic        dbg_tx_valid,

    output logic [79:0] dbg_code80,
    output logic        dbg_enc_valid,
    output logic        dbg_enc_err,

    output logic [63:0] dbg_rx_data,
    output logic [7:0]  dbg_rx_is_k,
    output logic        dbg_rx_valid,

    output logic [7:0]  dbg_code_err,
    output logic [7:0]  dbg_rd_err,
    output logic        dbg_dec_any_err,

    output logic        dbg_data_match,
    output logic        dbg_is_k_match,
    output logic        dbg_test_pass,
    output logic        dbg_test_fail,

    output logic [31:0] dbg_test_count,
    output logic [31:0] dbg_error_count
);

    // =========================================================================
    // Test pattern generator
    // =========================================================================

    logic [63:0] tx_data;
    logic [7:0]  tx_is_k;
    logic        tx_valid;

    logic [31:0] test_count;

    localparam logic [7:0] K_IDLE  = 8'hBC; // K28.5
    localparam logic [7:0] K_START = 8'hFB; // K27.7
    localparam logic [7:0] K_END   = 8'hFD; // K29.7

    always_ff @(posedge clk) begin
        if (rst) begin
            test_count <= 32'd0;
            tx_data    <= 64'd0;
            tx_is_k    <= 8'd0;
            tx_valid   <= 1'b0;
        end else begin
            test_count <= test_count + 32'd1;
            tx_valid   <= 1'b1;

            unique case (test_count[3:0])

                // All normal data bytes
                4'd0: begin
                    tx_data <= 64'h0706_0504_0302_0100;
                    tx_is_k <= 8'h00;
                end

                4'd1: begin
                    tx_data <= 64'h0F0E_0D0C_0B0A_0908;
                    tx_is_k <= 8'h00;
                end

                4'd2: begin
                    tx_data <= 64'h1716_1514_1312_1110;
                    tx_is_k <= 8'h00;
                end

                4'd3: begin
                    tx_data <= 64'hFFEE_DDCC_BBAA_9988;
                    tx_is_k <= 8'h00;
                end

                // All IDLE K symbols
                4'd4: begin
                    tx_data <= {8{K_IDLE}};
                    tx_is_k <= 8'hFF;
                end

                // START + data + END mixture
                4'd5: begin
                    tx_data <= {
                        K_IDLE,
                        K_IDLE,
                        K_END,
                        8'h33,
                        8'h22,
                        8'h11,
                        8'h00,
                        K_START
                    };
                    tx_is_k <= 8'b1110_0001;
                    // byte0 = K_START
                    // byte5 = K_END
                    // byte6/7 = K_IDLE
                end

                // Mixed K and data
                4'd6: begin
                    tx_data <= {
                        8'h55,
                        K_IDLE,
                        8'h44,
                        K_END,
                        8'h33,
                        K_START,
                        8'h22,
                        8'h11
                    };
                    tx_is_k <= 8'b0101_0100;
                    // byte2 = K_START
                    // byte4 = K_END
                    // byte6 = K_IDLE
                end

                // Walking-ish data
                4'd7: begin
                    tx_data <= 64'h8040_2010_0804_0201;
                    tx_is_k <= 8'h00;
                end

                4'd8: begin
                    tx_data <= 64'h7FBF_DFEF_F7FB_FDFE;
                    tx_is_k <= 8'h00;
                end

                // Repeated byte patterns
                4'd9: begin
                    tx_data <= 64'hAAAA_AAAA_AAAA_AAAA;
                    tx_is_k <= 8'h00;
                end

                4'd10: begin
                    tx_data <= 64'h5555_5555_5555_5555;
                    tx_is_k <= 8'h00;
                end

                // More K IDLE
                4'd11: begin
                    tx_data <= {8{K_IDLE}};
                    tx_is_k <= 8'hFF;
                end

                default: begin
                    tx_data <= {
                        test_count[7:0],
                        test_count[7:0] + 8'd1,
                        test_count[7:0] + 8'd2,
                        test_count[7:0] + 8'd3,
                        test_count[7:0] + 8'd4,
                        test_count[7:0] + 8'd5,
                        test_count[7:0] + 8'd6,
                        test_count[7:0] + 8'd7
                    };
                    tx_is_k <= 8'h00;
                end

            endcase
        end
    end

    // =========================================================================
    // Encoder
    // =========================================================================

    logic [79:0] code80;
    logic        enc_valid;
    logic        enc_err;

    enc_64b80b u_enc_64b80b (
        .clk        (clk),
        .rst        (rst),

        .data_in    (tx_data),
        .is_k_in    (tx_is_k),
        .valid_in   (tx_valid),

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
    // Total practical latency:
    // tx input -> encoder output -> decoder output = 3 clocks.
    // So delay original TX pattern by 3 cycles before comparing.

    logic [63:0] tx_data_d0, tx_data_d1, tx_data_d2;
    logic [7:0]  tx_is_k_d0, tx_is_k_d1, tx_is_k_d2;
    logic        tx_valid_d0, tx_valid_d1, tx_valid_d2;

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
            tx_data_d0  <= tx_data;
            tx_data_d1  <= tx_data_d0;
            tx_data_d2  <= tx_data_d1;

            tx_is_k_d0  <= tx_is_k;
            tx_is_k_d1  <= tx_is_k_d0;
            tx_is_k_d2  <= tx_is_k_d1;

            tx_valid_d0 <= tx_valid;
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
        if (rst) begin
            error_count <= 32'd0;
        end else begin
            if (test_fail) begin
                error_count <= error_count + 32'd1;
            end
        end
    end

    // =========================================================================
    // Debug assignments
    // =========================================================================

    assign dbg_tx_data      = tx_data;
    assign dbg_tx_is_k      = tx_is_k;
    assign dbg_tx_valid     = tx_valid;

    assign dbg_code80       = code80;
    assign dbg_enc_valid    = enc_valid;
    assign dbg_enc_err      = enc_err;

    assign dbg_rx_data      = dec_data;
    assign dbg_rx_is_k      = dec_is_k;
    assign dbg_rx_valid     = dec_valid;

    assign dbg_code_err     = dec_code_err;
    assign dbg_rd_err       = dec_rd_err;
    assign dbg_dec_any_err  = dec_any_err;

    assign dbg_data_match   = data_match;
    assign dbg_is_k_match   = is_k_match;
    assign dbg_test_pass    = test_pass;
    assign dbg_test_fail    = test_fail;

    assign dbg_test_count   = test_count;
    assign dbg_error_count  = error_count;

endmodule
