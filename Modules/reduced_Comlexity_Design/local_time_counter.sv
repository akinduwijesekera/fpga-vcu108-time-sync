`timescale 1ns/1ps

module local_time_counter #(
    // ------------------------------------------------------------
    // Base increment per clock tick
    // ------------------------------------------------------------
    //
    // Timestamp format:
    //   tod_sec  = integer seconds
    //   tod_nsec = integer nanoseconds within current second
    //   tod_frac = fractional nanoseconds
    //
    // tod_frac uses 16 fractional bits:
    //   1 LSB = 1 / 2^16 ns
    //
    // Examples:
    //
    // 200 MHz clock:
    //   period = 5 ns
    //   BASE_INC_NS   = 5
    //   BASE_INC_FRAC = 0
    //
    // 250 MHz clock:
    //   period = 4 ns
    //   BASE_INC_NS   = 4
    //   BASE_INC_FRAC = 0
    //
    // 125 MHz clock:
    //   period = 8 ns
    //   BASE_INC_NS   = 8
    //   BASE_INC_FRAC = 0
    //
    // 156.25 MHz clock:
    //   period = 6.4 ns
    //   BASE_INC_NS   = 6
    //   BASE_INC_FRAC = 0.4 * 65536 ≈ 26214
    //
    parameter logic signed [31:0] BASE_INC_NS   = 32'sd5,
    parameter logic signed [31:0] BASE_INC_FRAC = 32'sd0
)(
    input  logic clk,
    input  logic rst_n,
    input  logic enable,

    // ------------------------------------------------------------
    // Frequency adjustment per clock tick
    // ------------------------------------------------------------
    //
    // freq_adj_ns:
    //   Signed integer nanosecond adjustment per tick.
    //
    // freq_adj_frac:
    //   Signed fractional-nanosecond adjustment per tick.
    //   1 LSB = 1 / 2^16 ns.
    //
    // Example:
    //   freq_adj_ns   = 0
    //   freq_adj_frac = -16'sd1
    //
    // means the counter advances by:
    //   base_increment - 1/65536 ns
    //
    input  logic signed [15:0] freq_adj_ns,
    input  logic signed [15:0] freq_adj_frac,

    output logic [47:0] tod_sec,
    output logic [31:0] tod_nsec,
    output logic [15:0] tod_frac
);

    // ------------------------------------------------------------
    // Time registers
    // ------------------------------------------------------------
    logic [47:0] sec_reg;
    logic [31:0] nsec_reg;
    logic [15:0] frac_reg;

    logic [47:0] sec_next;
    logic [31:0] nsec_next;
    logic [15:0] frac_next;

    // ------------------------------------------------------------
    // Timestamp format constants
    // ------------------------------------------------------------
    localparam logic [31:0] NS_PER_SEC = 32'd1_000_000_000;

    // Fractional format:
    // 1 ns = 2^16 fractional units
    localparam int FRAC_BITS = 16;

    // 1 second in fractional-nanosecond units:
    // 1,000,000,000 ns * 2^16
    localparam logic signed [48:0] NS_PER_SEC_UNITS =
        49'sd1_000_000_000 <<< FRAC_BITS;

    // ------------------------------------------------------------
    // Parameter extension into internal 49-bit signed format
    // ------------------------------------------------------------
    logic signed [48:0] base_inc_ns_ext;
    logic signed [48:0] base_inc_frac_ext;
    logic signed [48:0] base_inc_units;

    always_comb begin
        base_inc_ns_ext   = $signed({{17{BASE_INC_NS[31]}},   BASE_INC_NS});
        base_inc_frac_ext = $signed({{17{BASE_INC_FRAC[31]}}, BASE_INC_FRAC});

        base_inc_units = (base_inc_ns_ext <<< FRAC_BITS)
                       + base_inc_frac_ext;
    end

    // ------------------------------------------------------------
    // Increment calculation
    // ------------------------------------------------------------
    logic signed [48:0] freq_adj_ns_units;
    logic signed [48:0] freq_adj_frac_units;
    logic signed [48:0] inc_units;

    // Current sub-second time in fractional-nanosecond units
    logic        [47:0] subsec_units_u;
    logic signed [48:0] subsec_units_s;

    // New sub-second sum before normalisation
    logic signed [48:0] subsec_sum_s;

    // Normalised sub-second value
    logic signed [48:0] subsec_norm_s;

    always_comb begin
        // Sign-extend then shift nanosecond adjustment into fractional units
        freq_adj_ns_units =
            $signed({{33{freq_adj_ns[15]}}, freq_adj_ns}) <<< FRAC_BITS;

        // Sign-extend fractional adjustment
        freq_adj_frac_units =
            $signed({{33{freq_adj_frac[15]}}, freq_adj_frac});

        // Effective increment per clock tick
        inc_units = base_inc_units
                  + freq_adj_ns_units
                  + freq_adj_frac_units;

        // Current sub-second field:
        // {nsec_reg, frac_reg} = nsec_reg * 2^16 + frac_reg
        subsec_units_u = {nsec_reg, frac_reg};
        subsec_units_s = $signed({1'b0, subsec_units_u});

        // Default values: hold state
        sec_next       = sec_reg;
        nsec_next      = nsec_reg;
        frac_next      = frac_reg;
        subsec_sum_s   = subsec_units_s;
        subsec_norm_s  = subsec_units_s;

        if (enable) begin
            subsec_sum_s  = subsec_units_s + inc_units;
            subsec_norm_s = subsec_sum_s;

            // ----------------------------------------------------
            // Normalise sub-second field
            // ----------------------------------------------------
            if (subsec_sum_s >= NS_PER_SEC_UNITS) begin
                // Rollover into next second
                subsec_norm_s = subsec_sum_s - NS_PER_SEC_UNITS;
                sec_next      = sec_reg + 48'd1;

            end else if (subsec_sum_s < 0) begin
                // Borrow from previous second.
                //
                // This branch should not normally be used for clock
                // frequency correction because inc_units should remain
                // positive. It is included for completeness.
                if (sec_reg != 48'd0) begin
                    subsec_norm_s = subsec_sum_s + NS_PER_SEC_UNITS;
                    sec_next      = sec_reg - 48'd1;
                end else begin
                    // Saturate at zero if an invalid negative adjustment
                    // would push time below 0.
                    subsec_norm_s = 49'sd0;
                    sec_next      = 48'd0;
                end
            end

            // Convert back from fractional-ns units into nsec + frac
            nsec_next = subsec_norm_s[47:16];
            frac_next = subsec_norm_s[15:0];

            // synthesis translate_off
`ifdef ASSERTIONS
            // The effective increment should normally remain positive.
            if (inc_units <= 0) begin
                $error("local_time_counter: inc_units is non-positive: %0d", inc_units);
            end

            if (base_inc_units <= 0) begin
                $error("local_time_counter: base_inc_units is non-positive: %0d", base_inc_units);
            end

            if (nsec_next >= NS_PER_SEC) begin
                $error("local_time_counter: nsec_next out of range: %0d", nsec_next);
            end

            if (subsec_sum_s >= (NS_PER_SEC_UNITS <<< 1)) begin
                $error("local_time_counter: subsec_sum_s too large; multi-rollover needed: %0d", subsec_sum_s);
            end

            if (nsec_reg >= NS_PER_SEC) begin
                $error("local_time_counter: nsec_reg out of range before update: %0d", nsec_reg);
            end
`endif
            // synthesis translate_on
        end
    end

    // ------------------------------------------------------------
    // Sequential state update
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sec_reg  <= 48'd0;
            nsec_reg <= 32'd0;
            frac_reg <= 16'd0;
        end else begin
            sec_reg  <= sec_next;
            nsec_reg <= nsec_next;
            frac_reg <= frac_next;
        end
    end

    // ------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------
    assign tod_sec  = sec_reg;
    assign tod_nsec = nsec_reg;
    assign tod_frac = frac_reg;

endmodule
