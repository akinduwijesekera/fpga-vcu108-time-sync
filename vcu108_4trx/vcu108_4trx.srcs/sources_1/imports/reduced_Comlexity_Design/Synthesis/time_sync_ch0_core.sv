`timescale 1ns/1ps

module time_sync_ch0_core #(
    parameter logic signed [31:0] GTY_BASE_INC_NS   = 32'sd8,
    parameter logic signed [31:0] GTY_BASE_INC_FRAC = 32'sd0,

    // Period between diagnostic bursts.
    // Wrapper currently passes 500, which is fine.
    parameter int TX_PERIOD_CYCLES = 500,

    // Number of TX clock cycles per diagnostic burst.
    // Make this long enough to easily see in ILA.
    parameter int DIAG_BURST_LEN = 64
)(
    // ------------------------------------------------------------
    // CH0 GTY TX parallel domain
    // ------------------------------------------------------------
    input  logic        tx_clk,
    input  logic        tx_rst,
    output logic [79:0] gty_tx_data,

    // ------------------------------------------------------------
    // CH0 GTY RX parallel domain
    // ------------------------------------------------------------
    input  logic        rx_clk,
    input  logic        rx_rst,
    input  logic [79:0] gty_rx_data,

    // ------------------------------------------------------------
    // Original debug outputs
    // ------------------------------------------------------------
    output logic        dbg_start_tx,
    output logic        dbg_tx_done,
    output logic [15:0] dbg_tx_seq_id,
    output logic        dbg_enc_valid,
    output logic        dbg_enc_err,

    output logic        dbg_pcs_sof,
    output logic        dbg_pcs_frame_done,
    output logic        dbg_pcs_frame_err,
    output logic        dbg_pcs_ctrl_err,
    output logic        dbg_pcs_sym_err,

    output logic        dbg_crc_ok,
    output logic        dbg_crc_fail,
    output logic        dbg_crc_len_err,

    output logic        dbg_df_done,
    output logic        dbg_etype_ok,
    output logic        dbg_etype_err,
    output logic        dbg_df_len_err,

    output logic        dbg_pkt_valid,
    output logic        dbg_pkt_done,
    output logic        dbg_pkt_len_err,
    output logic [7:0]  dbg_rx_msg_type,
    output logic [15:0] dbg_rx_seq_id,
    output logic [47:0] dbg_rx_tod_sec,
    output logic [31:0] dbg_rx_tod_nsec,
    output logic [15:0] dbg_rx_tod_frac,

    // ------------------------------------------------------------
    // Extra TX debug for ILA
    // ------------------------------------------------------------
    output logic [1:0]  dbg_tx_state,
    output logic [2:0]  dbg_tx_code_wr_idx,
    output logic [2:0]  dbg_tx_stream_idx,
    output logic [79:0] dbg_tx_code80,
    output logic        dbg_tx_code80_valid,
    output logic        dbg_tx_crc_done,
    output logic        dbg_tx_pcs_done,
    output logic        dbg_tx_pcs_overflow,

    // ------------------------------------------------------------
    // Extra RX debug for ILA
    // ------------------------------------------------------------
    output logic [1:0]  dbg_rx_cap_state,
    output logic        dbg_rx_word_non_idle,
    output logic [2:0]  dbg_rx_cap_idx,
    output logic [2:0]  dbg_rx_replay_idx,
    output logic [79:0] dbg_rx_code80_in,
    output logic        dbg_rx_code80_valid,
    output logic        dbg_rx_code80_ready,
    output logic        dbg_rx_dec_any_err,
    output logic [63:0] dbg_rx_sym_data,
    output logic [7:0]  dbg_rx_sym_is_k,
    output logic        dbg_rx_sym_valid,
    output logic        dbg_rx_sym_ready,

    // ------------------------------------------------------------
    // Extra timestamp-diff debug for ILA
    // ------------------------------------------------------------
    output logic        dbg_rx_diff_valid,
    output logic [47:0] dbg_rx_diff_sec,
    output logic [31:0] dbg_rx_diff_nsec,
    output logic [15:0] dbg_rx_diff_frac,
    output logic        dbg_rx_diff_underflow
);

    // ============================================================
    // Simple GTY link diagnostic configuration
    // ============================================================

    localparam logic [79:0] GTY_IDLE_WORD     = {40{2'b01}}; // 5555...
    localparam logic [79:0] GTY_IDLE_WORD_ALT = {40{2'b10}}; // AAAA...

    typedef enum logic [1:0] {
        TXS_IDLE  = 2'd0,
        TXS_BURST = 2'd1
    } tx_state_t;

    tx_state_t tx_state;

    logic [31:0] tx_period_counter;
    logic [15:0] tx_burst_counter;
    logic [15:0] tx_packet_counter;

    // Diagnostic payload word.
    // This is deliberately obvious in ILA and changes every burst cycle.
    logic [79:0] tx_diag_word;

    always_comb begin
        tx_diag_word = {
            16'hD1A6,
            tx_packet_counter,
            tx_burst_counter,
            16'hBEEF,
            16'h1234
        };
    end

    // ============================================================
    // TX diagnostic generator
    // ============================================================

    always_ff @(posedge tx_clk) begin
        if (tx_rst) begin
            tx_state          <= TXS_IDLE;
            tx_period_counter <= 32'd0;
            tx_burst_counter  <= 16'd0;
            tx_packet_counter <= 16'd0;

            gty_tx_data       <= GTY_IDLE_WORD;

            dbg_start_tx      <= 1'b0;
            dbg_tx_done       <= 1'b0;
            dbg_tx_seq_id     <= 16'd0;
            dbg_enc_valid     <= 1'b0;
            dbg_enc_err       <= 1'b0;

            dbg_tx_state        <= 2'd0;
            dbg_tx_code_wr_idx  <= 3'd0;
            dbg_tx_stream_idx   <= 3'd0;
            dbg_tx_code80       <= 80'd0;
            dbg_tx_code80_valid <= 1'b0;
            dbg_tx_crc_done     <= 1'b0;
            dbg_tx_pcs_done     <= 1'b0;
            dbg_tx_pcs_overflow <= 1'b0;
        end else begin
            // Default one-cycle strobes
            dbg_start_tx        <= 1'b0;
            dbg_tx_done         <= 1'b0;
            dbg_enc_valid       <= 1'b0;
            dbg_tx_code80_valid <= 1'b0;
            dbg_tx_crc_done     <= 1'b0;
            dbg_tx_pcs_done     <= 1'b0;
            dbg_tx_pcs_overflow <= 1'b0;
            dbg_enc_err         <= 1'b0;

            dbg_tx_state        <= tx_state;
            dbg_tx_seq_id       <= tx_packet_counter;
            dbg_tx_code_wr_idx  <= tx_burst_counter[2:0];
            dbg_tx_stream_idx   <= tx_burst_counter[2:0];

            case (tx_state)

                TXS_IDLE: begin
                    gty_tx_data <= GTY_IDLE_WORD;
                    dbg_tx_code80 <= GTY_IDLE_WORD;

                    if (tx_period_counter == TX_PERIOD_CYCLES-1) begin
                        tx_period_counter <= 32'd0;
                        tx_burst_counter  <= 16'd0;

                        dbg_start_tx <= 1'b1;

                        tx_state <= TXS_BURST;
                    end else begin
                        tx_period_counter <= tx_period_counter + 32'd1;
                    end
                end

                TXS_BURST: begin
                    gty_tx_data <= tx_diag_word;

                    dbg_enc_valid       <= 1'b1;
                    dbg_tx_code80       <= tx_diag_word;
                    dbg_tx_code80_valid <= 1'b1;

                    if (tx_burst_counter == DIAG_BURST_LEN-1) begin
                        tx_burst_counter  <= 16'd0;
                        tx_packet_counter <= tx_packet_counter + 16'd1;

                        dbg_tx_done     <= 1'b1;
                        dbg_tx_crc_done <= 1'b1;
                        dbg_tx_pcs_done <= 1'b1;

                        tx_state <= TXS_IDLE;
                    end else begin
                        tx_burst_counter <= tx_burst_counter + 16'd1;
                    end
                end

                default: begin
                    tx_state    <= TXS_IDLE;
                    gty_tx_data <= GTY_IDLE_WORD;
                end

            endcase
        end
    end

    // ============================================================
    // RX diagnostic monitor
    // ============================================================

    logic rx_word_non_idle;
    logic rx_word_non_idle_d;
    logic rx_seen_non_idle;
    logic [15:0] rx_word_count;
    logic [15:0] rx_packet_counter;

    assign rx_word_non_idle =
        (gty_rx_data != GTY_IDLE_WORD) &&
        (gty_rx_data != GTY_IDLE_WORD_ALT);

    always_ff @(posedge rx_clk) begin
        if (rx_rst) begin
            rx_word_non_idle_d <= 1'b0;
            rx_seen_non_idle   <= 1'b0;
            rx_word_count      <= 16'd0;
            rx_packet_counter  <= 16'd0;

            dbg_rx_word_non_idle <= 1'b0;
            dbg_rx_cap_state     <= 2'd0;
            dbg_rx_cap_idx       <= 3'd0;
            dbg_rx_replay_idx    <= 3'd0;
            dbg_rx_code80_in     <= 80'd0;
            dbg_rx_code80_valid  <= 1'b0;
            dbg_rx_code80_ready  <= 1'b1;
            dbg_rx_dec_any_err   <= 1'b0;
            dbg_rx_sym_data      <= 64'd0;
            dbg_rx_sym_is_k      <= 8'd0;
            dbg_rx_sym_valid     <= 1'b0;
            dbg_rx_sym_ready     <= 1'b1;

            dbg_pcs_sof          <= 1'b0;
            dbg_pcs_frame_done   <= 1'b0;
            dbg_pcs_frame_err    <= 1'b0;
            dbg_pcs_ctrl_err     <= 1'b0;
            dbg_pcs_sym_err      <= 1'b0;

            dbg_crc_ok           <= 1'b0;
            dbg_crc_fail         <= 1'b0;
            dbg_crc_len_err      <= 1'b0;

            dbg_pkt_valid        <= 1'b0;
            dbg_pkt_done         <= 1'b0;
            dbg_pkt_len_err      <= 1'b0;
            dbg_rx_msg_type      <= 8'd0;
            dbg_rx_seq_id        <= 16'd0;
            dbg_rx_tod_sec       <= 48'd0;
            dbg_rx_tod_nsec      <= 32'd0;
            dbg_rx_tod_frac      <= 16'd0;

            dbg_df_done          <= 1'b0;
            dbg_etype_ok         <= 1'b1;
            dbg_etype_err        <= 1'b0;
            dbg_df_len_err       <= 1'b0;

            dbg_rx_diff_valid     <= 1'b0;
            dbg_rx_diff_sec       <= 48'd0;
            dbg_rx_diff_nsec      <= 32'd0;
            dbg_rx_diff_frac      <= 16'd0;
            dbg_rx_diff_underflow <= 1'b0;
        end else begin
            rx_word_non_idle_d <= rx_word_non_idle;

            // Default one-cycle strobes
            dbg_pcs_sof          <= 1'b0;
            dbg_pcs_frame_done   <= 1'b0;
            dbg_crc_ok           <= 1'b0;
            dbg_pkt_valid        <= 1'b0;
            dbg_pkt_done         <= 1'b0;
            dbg_df_done          <= 1'b0;
            dbg_rx_diff_valid    <= 1'b0;

            // Error flags stay low in this diagnostic version
            dbg_pcs_frame_err    <= 1'b0;
            dbg_pcs_ctrl_err     <= 1'b0;
            dbg_pcs_sym_err      <= 1'b0;
            dbg_crc_fail         <= 1'b0;
            dbg_crc_len_err      <= 1'b0;
            dbg_pkt_len_err      <= 1'b0;
            dbg_etype_ok         <= 1'b1;
            dbg_etype_err        <= 1'b0;
            dbg_df_len_err       <= 1'b0;
            dbg_rx_diff_underflow <= 1'b0;
            dbg_rx_dec_any_err   <= 1'b0;

            dbg_rx_word_non_idle <= rx_word_non_idle;
            dbg_rx_code80_in     <= gty_rx_data;
            dbg_rx_code80_valid  <= rx_word_non_idle;
            dbg_rx_code80_ready  <= 1'b1;

            dbg_rx_sym_data      <= gty_rx_data[63:0];
            dbg_rx_sym_is_k      <= 8'h00;
            dbg_rx_sym_valid     <= rx_word_non_idle;
            dbg_rx_sym_ready     <= 1'b1;

            dbg_rx_cap_idx       <= rx_word_count[2:0];
            dbg_rx_replay_idx    <= rx_word_count[2:0];

            if (rx_word_non_idle) begin
                dbg_rx_cap_state <= 2'd1;

                if (!rx_word_non_idle_d) begin
                    // Rising edge of non-idle burst
                    dbg_pcs_sof     <= 1'b1;
                    rx_seen_non_idle <= 1'b1;
                    rx_word_count    <= 16'd1;
                end else begin
                    rx_word_count <= rx_word_count + 16'd1;
                end

            end else begin
                dbg_rx_cap_state <= 2'd0;

                if (rx_word_non_idle_d && rx_seen_non_idle) begin
                    // Falling edge of non-idle burst
                    dbg_pcs_frame_done <= 1'b1;
                    dbg_crc_ok         <= 1'b1;
                    dbg_pkt_valid      <= 1'b1;
                    dbg_pkt_done       <= 1'b1;
                    dbg_df_done        <= 1'b1;
                    dbg_rx_diff_valid  <= 1'b1;

                    dbg_rx_seq_id      <= rx_packet_counter;
                    dbg_rx_msg_type    <= rx_packet_counter[7:0];

                    dbg_rx_diff_sec    <= 48'd0;
                    dbg_rx_diff_nsec   <= {16'd0, rx_word_count};
                    dbg_rx_diff_frac   <= 16'h0000;

                    rx_packet_counter  <= rx_packet_counter + 16'd1;
                    rx_seen_non_idle   <= 1'b0;
                    rx_word_count      <= 16'd0;
                end
            end
        end
    end

endmodule
