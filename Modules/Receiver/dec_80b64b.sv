`timescale 1ns / 1ps

module dec_80b64b (
    input  logic        clk,
    input  logic        rst,

    input  logic [79:0] code80_in,
    input  logic        valid_in,

    output logic [63:0] data_out,
    output logic [7:0]  is_k_out,
    output logic        valid_out,

    output logic [7:0]  code_err,
    output logic [7:0]  rd_err,
    output logic        any_err
);

    // =========================================================================
    // Pipeline stage 0
    // =========================================================================

    logic [79:0] code80_s0;
    logic        valid_s0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            code80_s0 <= 80'd0;
            valid_s0  <= 1'b0;
        end else begin
            code80_s0 <= code80_in;
            valid_s0  <= valid_in;
        end
    end

    // =========================================================================
    // Running disparity tracker
    // =========================================================================
    // Convention:
    //   0 = RD-
    //   1 = RD+
    // =========================================================================

    logic rd_plus_cur;
    logic rd_plus_next_word;

    // =========================================================================
    // Helper types
    // =========================================================================

    typedef struct packed {
        logic       valid;
        logic [4:0] grp5;
        logic       k28_special;
    } six_dec_t;

    typedef struct packed {
        logic       valid;
        logic [2:0] grp3;
    } four_dec_t;

    typedef struct packed {
        logic [7:0] data;
        logic       is_k;
        logic       code_err;
        logic       rd_err;
        logic       rd_plus_out;
    } dec_res_t;

    typedef struct packed {
        logic       valid;
        logic [7:0] data;
        logic       is_k;
        logic       rd_plus_out;
    } dec_once_t;

    // =========================================================================
    // Disparity helper
    // =========================================================================

    function automatic integer disparity10(
        input logic [9:0] bits
    );
        integer ones;
        begin
            ones = 0;

            for (int i = 0; i < 10; i++) begin
                ones = ones + bits[i];
            end

            disparity10 = ones - (10 - ones);
        end
    endfunction

    function automatic integer disparity6(
        input logic [5:0] bits
    );
        integer ones;
        begin
            ones = 0;

            for (int i = 0; i < 6; i++) begin
                ones = ones + bits[i];
            end

            disparity6 = ones - (6 - ones);
        end
    endfunction

    // =========================================================================
    // 6b decoder
    // =========================================================================
    // This mirrors your encoder:
    //
    //   If RD- entering symbol:
    //      encoder selects sixb_pos
    //
    //   If RD+ entering symbol:
    //      encoder selects sixb_neg
    //
    // Special case:
    //      K28.x uses comma 6b values:
    //          RD- input -> 001111
    //          RD+ input -> 110000
    // =========================================================================

    function automatic six_dec_t decode_6b_expected(
        input logic [5:0] code6,
        input logic       rd_plus_in
    );
        six_dec_t r;
        begin
            r.valid       = 1'b1;
            r.grp5        = 5'd0;
            r.k28_special = 1'b0;

            if (!rd_plus_in) begin
                // Expected RD- input, encoder used sixb_pos table.

                unique case (code6)
                    6'b100111: r.grp5 = 5'd0;
                    6'b011101: r.grp5 = 5'd1;
                    6'b101101: r.grp5 = 5'd2;
                    6'b110001: r.grp5 = 5'd3;
                    6'b110101: r.grp5 = 5'd4;
                    6'b101001: r.grp5 = 5'd5;
                    6'b011001: r.grp5 = 5'd6;
                    6'b111000: r.grp5 = 5'd7;
                    6'b111001: r.grp5 = 5'd8;
                    6'b100101: r.grp5 = 5'd9;
                    6'b010101: r.grp5 = 5'd10;
                    6'b110100: r.grp5 = 5'd11;
                    6'b001101: r.grp5 = 5'd12;
                    6'b101100: r.grp5 = 5'd13;
                    6'b011100: r.grp5 = 5'd14;
                    6'b010111: r.grp5 = 5'd15;
                    6'b011011: r.grp5 = 5'd16;
                    6'b100011: r.grp5 = 5'd17;
                    6'b010011: r.grp5 = 5'd18;
                    6'b110010: r.grp5 = 5'd19;
                    6'b001011: r.grp5 = 5'd20;
                    6'b101010: r.grp5 = 5'd21;
                    6'b011010: r.grp5 = 5'd22;
                    6'b111010: r.grp5 = 5'd23;
                    6'b001100: r.grp5 = 5'd24;
                    6'b100110: r.grp5 = 5'd25;
                    6'b010110: r.grp5 = 5'd26;
                    6'b110110: r.grp5 = 5'd27;
                    6'b001110: r.grp5 = 5'd28;
                    6'b101110: r.grp5 = 5'd29;
                    6'b011110: r.grp5 = 5'd30;
                    6'b101011: r.grp5 = 5'd31;

                    // K28.x comma special for RD-
                    6'b001111: begin
                        r.grp5        = 5'd28;
                        r.k28_special = 1'b1;
                    end

                    default: begin
                        r.valid       = 1'b0;
                        r.grp5        = 5'd0;
                        r.k28_special = 1'b0;
                    end
                endcase

            end else begin
                // Expected RD+ input, encoder used sixb_neg table.

                unique case (code6)
                    6'b011000: r.grp5 = 5'd0;
                    6'b100010: r.grp5 = 5'd1;
                    6'b010010: r.grp5 = 5'd2;
                    6'b001110: r.grp5 = 5'd3;
                    6'b001010: r.grp5 = 5'd4;
                    6'b010110: r.grp5 = 5'd5;
                    6'b100110: r.grp5 = 5'd6;
                    6'b000111: r.grp5 = 5'd7;
                    6'b000110: r.grp5 = 5'd8;
                    6'b011010: r.grp5 = 5'd9;
                    6'b101010: r.grp5 = 5'd10;
                    6'b001011: r.grp5 = 5'd11;
                    6'b110010: r.grp5 = 5'd12;
                    6'b010011: r.grp5 = 5'd13;
                    6'b100011: r.grp5 = 5'd14;
                    6'b101000: r.grp5 = 5'd15;
                    6'b100100: r.grp5 = 5'd16;
                    6'b011100: r.grp5 = 5'd17;
                    6'b101100: r.grp5 = 5'd18;
                    6'b001101: r.grp5 = 5'd19;
                    6'b110100: r.grp5 = 5'd20;
                    6'b010101: r.grp5 = 5'd21;
                    6'b100101: r.grp5 = 5'd22;
                    6'b000101: r.grp5 = 5'd23;
                    6'b110011: r.grp5 = 5'd24;
                    6'b011001: r.grp5 = 5'd25;
                    6'b101001: r.grp5 = 5'd26;
                    6'b001001: r.grp5 = 5'd27;
                    6'b110001: r.grp5 = 5'd28;
                    6'b010001: r.grp5 = 5'd29;
                    6'b100001: r.grp5 = 5'd30;
                    6'b010100: r.grp5 = 5'd31;

                    // K28.x comma special for RD+
                    6'b110000: begin
                        r.grp5        = 5'd28;
                        r.k28_special = 1'b1;
                    end

                    default: begin
                        r.valid       = 1'b0;
                        r.grp5        = 5'd0;
                        r.k28_special = 1'b0;
                    end
                endcase
            end

            decode_6b_expected = r;
        end
    endfunction

    // =========================================================================
    // 4b decoder for normal data symbols
    // =========================================================================

    function automatic four_dec_t decode_4b_data_expected(
        input logic [3:0] code4,
        input logic       rd_after_6b,
        input logic [4:0] grp5
    );
        four_dec_t r;
        begin
            r.valid = 1'b1;
            r.grp3  = 3'd0;

            if (!rd_after_6b) begin
                // Encoder used fourb_pos table.

                unique case (code4)
                    4'b1011: r.grp3 = 3'd0;
                    4'b1001: r.grp3 = 3'd1;
                    4'b0101: r.grp3 = 3'd2;
                    4'b1100: r.grp3 = 3'd3;
                    4'b1101: r.grp3 = 3'd4;
                    4'b1010: r.grp3 = 3'd5;
                    4'b0110: r.grp3 = 3'd6;
                    4'b1110: r.grp3 = 3'd7;

                    // Alternate D.x.7 form for selected data symbols.
                    4'b0111: begin
                        if ((grp5 == 5'd17) ||
                            (grp5 == 5'd18) ||
                            (grp5 == 5'd20)) begin
                            r.grp3 = 3'd7;
                        end else begin
                            r.valid = 1'b0;
                        end
                    end

                    default: begin
                        r.valid = 1'b0;
                        r.grp3  = 3'd0;
                    end
                endcase

            end else begin
                // Encoder used fourb_neg table.

                unique case (code4)
                    4'b0100: r.grp3 = 3'd0;
                    4'b0110: r.grp3 = 3'd1;
                    4'b1010: r.grp3 = 3'd2;
                    4'b0011: r.grp3 = 3'd3;
                    4'b0010: r.grp3 = 3'd4;
                    4'b0101: r.grp3 = 3'd5;
                    4'b1001: r.grp3 = 3'd6;
                    4'b0001: r.grp3 = 3'd7;

                    // Alternate D.x.7 form for selected data symbols.
                    4'b1000: begin
                        if ((grp5 == 5'd11) ||
                            (grp5 == 5'd13) ||
                            (grp5 == 5'd14)) begin
                            r.grp3 = 3'd7;
                        end else begin
                            r.valid = 1'b0;
                        end
                    end

                    default: begin
                        r.valid = 1'b0;
                        r.grp3  = 3'd0;
                    end
                endcase
            end

            decode_4b_data_expected = r;
        end
    endfunction

    // =========================================================================
    // 4b decoder for K symbols
    // =========================================================================
    // Valid K symbols supported by your encoder:
    //   K28.0 to K28.7
    //   K23.7, K27.7, K29.7, K30.7
    // =========================================================================

    function automatic four_dec_t decode_4b_k_expected(
        input logic [3:0] code4,
        input logic       rd_after_6b,
        input logic [4:0] grp5,
        input logic       k28_special
    );
        four_dec_t r;
        begin
            r.valid = 1'b0;
            r.grp3  = 3'd0;

            // -------------------------------------------------------------
            // K28.x: special 6b comma indicates K28.
            // 4b section uses the normal K table, which for K28.x is same
            // as the basic 3b/4b mapping.
            // -------------------------------------------------------------
            if (k28_special && (grp5 == 5'd28)) begin
                r.valid = 1'b1;

                if (!rd_after_6b) begin
                    unique case (code4)
                        4'b1011: r.grp3 = 3'd0;
                        4'b1001: r.grp3 = 3'd1;
                        4'b0101: r.grp3 = 3'd2;
                        4'b1100: r.grp3 = 3'd3;
                        4'b1101: r.grp3 = 3'd4;
                        4'b1010: r.grp3 = 3'd5;
                        4'b0110: r.grp3 = 3'd6;
                        4'b1110: r.grp3 = 3'd7;
                        default: begin
                            r.valid = 1'b0;
                            r.grp3  = 3'd0;
                        end
                    endcase
                end else begin
                    unique case (code4)
                        4'b0100: r.grp3 = 3'd0;
                        4'b0110: r.grp3 = 3'd1;
                        4'b1010: r.grp3 = 3'd2;
                        4'b0011: r.grp3 = 3'd3;
                        4'b0010: r.grp3 = 3'd4;
                        4'b0101: r.grp3 = 3'd5;
                        4'b1001: r.grp3 = 3'd6;
                        4'b0001: r.grp3 = 3'd7;
                        default: begin
                            r.valid = 1'b0;
                            r.grp3  = 3'd0;
                        end
                    endcase
                end

            end

            // -------------------------------------------------------------
            // K23.7, K27.7, K29.7, K30.7
            // -------------------------------------------------------------
            else if ((grp5 == 5'd23) ||
                     (grp5 == 5'd27) ||
                     (grp5 == 5'd29) ||
                     (grp5 == 5'd30)) begin

                if (!rd_after_6b) begin
                    // fourb_pos_fn K special gives 0111
                    if (code4 == 4'b0111) begin
                        r.valid = 1'b1;
                        r.grp3  = 3'd7;
                    end
                end else begin
                    // fourb_neg_fn K special gives 1000
                    if (code4 == 4'b1000) begin
                        r.valid = 1'b1;
                        r.grp3  = 3'd7;
                    end
                end
            end

            decode_4b_k_expected = r;
        end
    endfunction

    // =========================================================================
    // Decode one 10b symbol assuming expected RD is correct
    // =========================================================================

    function automatic dec_once_t decode_symbol_expected_rd(
        input logic [9:0] code10,
        input logic       rd_plus_in
    );
        dec_once_t r;

        logic [5:0] code6;
        logic [3:0] code4;

        six_dec_t  six_dec;
        four_dec_t data_four_dec;
        four_dec_t k_four_dec;

        logic       rd_after_6b;
        logic       rd_plus_out;

        integer     disp6;
        integer     disp10;

        logic [7:0] data_candidate;
        logic       data_candidate_valid;
        logic       k_candidate_valid;

        begin
            r.valid       = 1'b0;
            r.data        = 8'h00;
            r.is_k        = 1'b0;
            r.rd_plus_out = rd_plus_in;

            code6 = code10[9:4];
            code4 = code10[3:0];

            six_dec = decode_6b_expected(code6, rd_plus_in);

            if (!six_dec.valid) begin
                decode_symbol_expected_rd = r;
            end else begin
                // RD after 6b follows the same rule as the encoder.
                disp6 = disparity6(code6);

                rd_after_6b = rd_plus_in;
                if (disp6 > 0) begin
                    rd_after_6b = 1'b1;
                end else if (disp6 < 0) begin
                    rd_after_6b = 1'b0;
                end

                data_four_dec = decode_4b_data_expected(
                    code4,
                    rd_after_6b,
                    six_dec.grp5
                );

                k_four_dec = decode_4b_k_expected(
                    code4,
                    rd_after_6b,
                    six_dec.grp5,
                    six_dec.k28_special
                );

                data_candidate_valid = data_four_dec.valid && !six_dec.k28_special;
                k_candidate_valid    = k_four_dec.valid;

                // Reject ambiguous result, though this should not occur with
                // the current encoder table.
                if (data_candidate_valid && !k_candidate_valid) begin
                    data_candidate = {data_four_dec.grp3, six_dec.grp5};

                    disp10 = disparity10(code10);

                    rd_plus_out = rd_plus_in;
                    if (disp10 > 0) begin
                        rd_plus_out = 1'b1;
                    end else if (disp10 < 0) begin
                        rd_plus_out = 1'b0;
                    end

                    r.valid       = 1'b1;
                    r.data        = data_candidate;
                    r.is_k        = 1'b0;
                    r.rd_plus_out = rd_plus_out;

                end else if (k_candidate_valid && !data_candidate_valid) begin
                    data_candidate = {k_four_dec.grp3, six_dec.grp5};

                    disp10 = disparity10(code10);

                    rd_plus_out = rd_plus_in;
                    if (disp10 > 0) begin
                        rd_plus_out = 1'b1;
                    end else if (disp10 < 0) begin
                        rd_plus_out = 1'b0;
                    end

                    r.valid       = 1'b1;
                    r.data        = data_candidate;
                    r.is_k        = 1'b1;
                    r.rd_plus_out = rd_plus_out;

                end else begin
                    r.valid       = 1'b0;
                    r.data        = 8'h00;
                    r.is_k        = 1'b0;
                    r.rd_plus_out = rd_plus_in;
                end

                decode_symbol_expected_rd = r;
            end
        end
    endfunction

    // =========================================================================
    // Decode one 10b symbol with RD checking
    // =========================================================================
    // First try expected RD.
    // If that fails, try opposite RD:
    //   - if opposite RD works, symbol is legal but RD error is flagged
    //   - if neither works, code error is flagged
    // =========================================================================

    function automatic dec_res_t decode_symbol(
        input logic [9:0] code10,
        input logic       rd_plus_in
    );
        dec_res_t  r;
        dec_once_t exp;
        dec_once_t opp;

        begin
            r.data        = 8'h00;
            r.is_k        = 1'b0;
            r.code_err    = 1'b1;
            r.rd_err      = 1'b0;
            r.rd_plus_out = rd_plus_in;

            exp = decode_symbol_expected_rd(code10, rd_plus_in);

            if (exp.valid) begin
                r.data        = exp.data;
                r.is_k        = exp.is_k;
                r.code_err    = 1'b0;
                r.rd_err      = 1'b0;
                r.rd_plus_out = exp.rd_plus_out;
            end else begin
                opp = decode_symbol_expected_rd(code10, ~rd_plus_in);

                if (opp.valid) begin
                    r.data        = opp.data;
                    r.is_k        = opp.is_k;
                    r.code_err    = 1'b0;
                    r.rd_err      = 1'b1;
                    r.rd_plus_out = opp.rd_plus_out;
                end
            end

            decode_symbol = r;
        end
    endfunction

    // =========================================================================
    // Decode 80b word into 8 decoded symbols
    // =========================================================================

    logic [63:0] data_dec_word;
    logic [7:0]  is_k_dec_word;
    logic [7:0]  code_err_dec_word;
    logic [7:0]  rd_err_dec_word;

    always_comb begin
        dec_res_t r;
        logic rd_work;

        data_dec_word     = 64'd0;
        is_k_dec_word     = 8'd0;
        code_err_dec_word = 8'd0;
        rd_err_dec_word   = 8'd0;

        rd_work = rd_plus_cur;

        for (int n = 0; n < 8; n++) begin
            r = decode_symbol(code80_s0[n*10 +: 10], rd_work);

            data_dec_word[n*8 +: 8] = r.code_err ? 8'h00 : r.data;
            is_k_dec_word[n]        = r.code_err ? 1'b0  : r.is_k;
            code_err_dec_word[n]    = r.code_err;
            rd_err_dec_word[n]      = r.rd_err;

            if (!r.code_err) begin
                rd_work = r.rd_plus_out;
            end
        end

        rd_plus_next_word = rd_work;
    end

    // =========================================================================
    // Output register
    // =========================================================================

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out    <= 64'd0;
            is_k_out    <= 8'd0;
            valid_out   <= 1'b0;
            code_err    <= 8'd0;
            rd_err      <= 8'd0;
            rd_plus_cur <= 1'b0;
        end else begin
            valid_out <= valid_s0;

            if (valid_s0) begin
                data_out <= data_dec_word;
                is_k_out <= is_k_dec_word;
                code_err <= code_err_dec_word;
                rd_err   <= rd_err_dec_word;

                // Keep behaviour close to your previous decoder:
                // advance stream RD if all code groups were legal.
                if (!(|code_err_dec_word)) begin
                    rd_plus_cur <= rd_plus_next_word;
                end
            end else begin
                data_out <= 64'd0;
                is_k_out <= 8'd0;
                code_err <= 8'd0;
                rd_err   <= 8'd0;
            end
        end
    end

    assign any_err = |(code_err | rd_err);

endmodule
