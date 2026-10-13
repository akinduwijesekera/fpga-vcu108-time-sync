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

    // ------------------------------------------------------------
    // Timestamp constants
    // ------------------------------------------------------------
    localparam int FRAC_BITS = 16;

    localparam logic [31:0] NS_PER_SEC = 32'd1_000_000_000;

    // 1 second in fractional-nanosecond units:
    // 1,000,000,000 ns * 2^16
    localparam logic [47:0] SUBSEC_PER_SEC =
        48'd1_000_000_000 << FRAC_BITS;

    // ------------------------------------------------------------
    // Convert sub-second fields into fixed-point units
    //
    // subsec_units = nsec * 2^16 + frac
    // ------------------------------------------------------------
    logic [47:0] rx_subsec_units;
    logic [47:0] tx_subsec_units;

    logic [47:0] subsec_diff_units;
    logic [47:0] subsec_diff_norm;

    logic [47:0] sec_diff_raw;
    logic        borrow_sec;
    logic        underflow_c;

    logic [47:0] diff_sec_c;
    logic [31:0] diff_nsec_c;
    logic [15:0] diff_frac_c;

    always_comb begin
        // Defaults
        rx_subsec_units  = {rx_local_nsec, rx_local_frac};
        tx_subsec_units  = {tx_stamp_nsec, tx_stamp_frac};

        subsec_diff_units = 48'd0;
        subsec_diff_norm  = 48'd0;

        sec_diff_raw = 48'd0;
        borrow_sec   = 1'b0;
        underflow_c  = 1'b0;

        diff_sec_c   = 48'd0;
        diff_nsec_c  = 32'd0;
        diff_frac_c  = 16'd0;

        // --------------------------------------------------------
        // Sub-second subtraction
        // --------------------------------------------------------
        if (rx_subsec_units >= tx_subsec_units) begin
            subsec_diff_units = rx_subsec_units - tx_subsec_units;
            borrow_sec        = 1'b0;
        end else begin
            subsec_diff_units = (rx_subsec_units + SUBSEC_PER_SEC) - tx_subsec_units;
            borrow_sec        = 1'b1;
        end

        // --------------------------------------------------------
        // Seconds subtraction
        // --------------------------------------------------------
        if (rx_local_sec >= (tx_stamp_sec + borrow_sec)) begin
            sec_diff_raw = rx_local_sec - tx_stamp_sec - borrow_sec;

            subsec_diff_norm = subsec_diff_units;

            diff_sec_c  = sec_diff_raw;
            diff_nsec_c = subsec_diff_norm[47:16];
            diff_frac_c = subsec_diff_norm[15:0];

            underflow_c = 1'b0;
        end else begin
            diff_sec_c  = 48'd0;
            diff_nsec_c = 32'd0;
            diff_frac_c = 16'd0;

            underflow_c = 1'b1;
        end
    end

    // ------------------------------------------------------------
    // Output registers
    // ------------------------------------------------------------
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
                diff_sec   <= diff_sec_c;
                diff_nsec  <= diff_nsec_c;
                diff_frac  <= diff_frac_c;
                underflow  <= underflow_c;
            end
        end
    end

    // ------------------------------------------------------------
    // Simulation-only checks
    // ------------------------------------------------------------
    // synthesis translate_off
`ifdef ASSERTIONS
    always_ff @(posedge clk or negedge rst_n) begin
        if (rst_n) begin
            if (valid_in && rx_local_nsec >= NS_PER_SEC) begin
                $error("timestamp_diff: rx_local_nsec out of range: %0d", rx_local_nsec);
            end

            if (valid_in && tx_stamp_nsec >= NS_PER_SEC) begin
                $error("timestamp_diff: tx_stamp_nsec out of range: %0d", tx_stamp_nsec);
            end

            if (diff_valid && diff_nsec >= NS_PER_SEC) begin
                $error("timestamp_diff: diff_nsec out of range: %0d", diff_nsec);
            end
        end
    end
`endif
    // synthesis translate_on

endmodule
