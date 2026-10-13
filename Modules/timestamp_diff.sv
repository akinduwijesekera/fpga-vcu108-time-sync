`timescale 1ns/1ps

module timestamp_diff (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        valid_in,

    input  logic [47:0] rx_local_sec,
    input  logic [31:0] rx_local_nsec,
    input  logic [15:0] rx_local_frac,

    input  logic [47:0] tx_stamp_sec,
    input  logic [31:0] tx_stamp_nsec,
    input  logic [15:0] tx_stamp_frac,

    output logic        diff_valid,
    output logic [47:0] diff_sec,
    output logic [31:0] diff_nsec,
    output logic [15:0] diff_frac,
    output logic        underflow
);

    localparam logic [31:0] ONE_BILLION_NS = 32'd1_000_000_000;

    logic [15:0] frac_diff_c;
    logic [31:0] nsec_diff_c;
    logic [47:0] sec_diff_c;

    logic        borrow_nsec_c;
    logic        borrow_sec_c;
    logic        underflow_c;

    logic [32:0] tx_nsec_plus_borrow;
    logic [48:0] tx_sec_plus_borrow;

    always_comb begin
        frac_diff_c        = 16'd0;
        nsec_diff_c        = 32'd0;
        sec_diff_c         = 48'd0;
        borrow_nsec_c      = 1'b0;
        borrow_sec_c       = 1'b0;
        underflow_c        = 1'b0;
        tx_nsec_plus_borrow = 33'd0;
        tx_sec_plus_borrow  = 49'd0;

        // ------------------------------------------------------------
        // Fractional nanosecond subtraction
        // Base = 2^16 fractional ns
        // ------------------------------------------------------------
        if (rx_local_frac >= tx_stamp_frac) begin
            frac_diff_c   = rx_local_frac - tx_stamp_frac;
            borrow_nsec_c = 1'b0;
        end else begin
            frac_diff_c   = rx_local_frac + 16'd65535 + 16'd1 - tx_stamp_frac;
            borrow_nsec_c = 1'b1;
        end

        // ------------------------------------------------------------
        // Nanosecond subtraction
        // Base = 1,000,000,000 ns
        // ------------------------------------------------------------
        tx_nsec_plus_borrow = {1'b0, tx_stamp_nsec} + borrow_nsec_c;

        if ({1'b0, rx_local_nsec} >= tx_nsec_plus_borrow) begin
            nsec_diff_c  = {1'b0, rx_local_nsec} - tx_nsec_plus_borrow;
            borrow_sec_c = 1'b0;
        end else begin
            nsec_diff_c  = {1'b0, rx_local_nsec} + {1'b0, ONE_BILLION_NS} - tx_nsec_plus_borrow;
            borrow_sec_c = 1'b1;
        end

        // ------------------------------------------------------------
        // Seconds subtraction
        // ------------------------------------------------------------
        tx_sec_plus_borrow = {1'b0, tx_stamp_sec} + borrow_sec_c;

        if ({1'b0, rx_local_sec} >= tx_sec_plus_borrow) begin
            sec_diff_c  = {1'b0, rx_local_sec} - tx_sec_plus_borrow;
            underflow_c = 1'b0;
        end else begin
            sec_diff_c   = 48'd0;
            nsec_diff_c  = 32'd0;
            frac_diff_c  = 16'd0;
            underflow_c  = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diff_valid <= 1'b0;
            diff_sec   <= 48'd0;
            diff_nsec  <= 32'd0;
            diff_frac  <= 16'd0;
            underflow  <= 1'b0;
        end else begin
            diff_valid <= 1'b0;

            if (valid_in) begin
                diff_valid <= 1'b1;
                diff_sec   <= sec_diff_c;
                diff_nsec  <= nsec_diff_c;
                diff_frac  <= frac_diff_c;
                underflow  <= underflow_c;
            end
        end
    end

endmodule
