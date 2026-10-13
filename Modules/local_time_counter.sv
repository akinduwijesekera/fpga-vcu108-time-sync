    `timescale 1ns/1ps

    module local_time_counter (
        input  logic clk,
        input  logic rst_n,
        input  logic enable,

        input  logic signed [15:0] freq_adj_ns,
        input  logic signed [15:0] freq_adj_frac,

        output logic [47:0] tod_sec,
        output logic [31:0] tod_nsec,
        output logic [15:0] tod_frac
    );

        logic [47:0] sec_reg;
        logic [31:0] nsec_reg;
        logic [15:0] frac_reg;

        logic [47:0] sec_next;
        logic [31:0] nsec_next;
        logic [15:0] frac_next;

        logic signed [17:0] frac_sum_s;  // room for carry
        logic        [17:0] frac_sum_u;  // unsigned view for carry extraction
        logic signed [32:0] nsec_sum_s;  // room for carry / bounds
        logic               frac_carry;

        localparam int IncNs   = 5;   // 200 MHz → 5 ns per tick
        localparam int IncFrac = 0;

        // Effective increments = base + adjustments
        // assume freq_adj_* are chosen so that the result remains non-negative
        logic signed [31:0] inc_ns_eff_s;
        logic signed [16:0] inc_frac_eff_s; // 16b frac + sign room

        always_comb begin
            inc_ns_eff_s   = $signed(32'(IncNs))   + $signed(freq_adj_ns);
            inc_frac_eff_s = $signed(17'(IncFrac)) + $signed(freq_adj_frac);

    `ifdef ASSERTIONS
            if (inc_ns_eff_s < 0)
                $error("inc_ns_eff_s went negative: %0d", inc_ns_eff_s);

            if (inc_frac_eff_s < 0)
                $error("inc_frac_eff_s went negative: %0d", inc_frac_eff_s);

            if (inc_ns_eff_s >= 32'sd1_000_000_000)
                $error("inc_ns_eff_s too large for single-rollover counter: %0d", inc_ns_eff_s);
    `endif
        end

        always_comb begin
            // defaults (enable=0 holds state)
            sec_next  = sec_reg;
            nsec_next = nsec_reg;
            frac_next = frac_reg;

            frac_sum_s = '0;
            frac_sum_u = '0;
            nsec_sum_s = '0;
            frac_carry = 1'b0;

            if (enable) begin
                // 1) fractional
                frac_sum_s = $signed({1'b0, frac_reg}) + inc_frac_eff_s;

                // unsigned view for robust carry extraction
                frac_sum_u = frac_sum_s;
                frac_carry = frac_sum_u[16];

                frac_next  = frac_sum_s[15:0];

                // 2) nanoseconds + carry
                nsec_sum_s = $signed({1'b0, nsec_reg})
                        + inc_ns_eff_s
                        + $signed({32'd0, frac_carry});

                // 3) Handle 1,000,000,000 ns to +1 second
                if (nsec_sum_s >= 33'sd1_000_000_000) begin
                    nsec_next = nsec_sum_s - 33'sd1_000_000_000;
                    sec_next  = sec_reg + 48'd1;
                end else begin
                    nsec_next = nsec_sum_s[31:0];
                end

    `ifdef ASSERTIONS
                if (nsec_next >= 32'd1_000_000_000)
                    $error("nsec_next out of range: %0d", nsec_next);

                if (nsec_sum_s >= 33'sd2_000_000_000)
                    $error("nsec_sum_s too large; multi-rollover needed: %0d", nsec_sum_s);
    `endif
            end
        end

        // Sequential state update
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                sec_reg  <= '0;
                nsec_reg <= '0;
                frac_reg <= '0;
            end else begin
                sec_reg  <= sec_next;
                nsec_reg <= nsec_next;
                frac_reg <= frac_next;
            end
        end

        // Outputs
        assign tod_sec  = sec_reg;
        assign tod_nsec = nsec_reg;
        assign tod_frac = frac_reg;

    endmodule
