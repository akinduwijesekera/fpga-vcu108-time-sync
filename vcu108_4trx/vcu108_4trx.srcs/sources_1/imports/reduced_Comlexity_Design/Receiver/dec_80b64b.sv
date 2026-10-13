`timescale 1ns/1ps

module dec_80b64b (
    input  logic        clk,
    input  logic        rst_n,

    // 80-bit encoded input from GTY / encoder loopback
    input  logic [79:0] code80_in,
    input  logic        valid_in,
    output logic        ready_in,

    // Decoded 64-bit symbol output to rx_pcs
    output logic [63:0] data_out,
    output logic [7:0]  is_k_out,
    output logic        valid_out,
    input  logic        ready_out,

    // Error reporting
    output logic [7:0]  code_err,
    output logic [7:0]  rd_err,
    output logic        any_err
);

    // =========================================================================
    // Running disparity convention
    //   0 = RD-
    //   1 = RD+
    // =========================================================================
    logic rd_plus_cur;

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
    // FSM
    // =========================================================================
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_DECODE,
        ST_OUTPUT
    } state_t;

    state_t st;

    // =========================================================================
    // Stored input word
    // =========================================================================
    logic [79:0] code80_reg;

    // Work registers while decoding
    logic [63:0] data_work;
    logic [7:0]  is_k_work;
    logic [7:0]  code_err_work;
    logic [7:0]  rd_err_work;

    logic [2:0]  lane_idx;
    logic        rd_work;

    // =========================================================================
    // Handshake
    // =========================================================================
    logic accept_in;

    assign ready_in  = (st == ST_IDLE);
    assign accept_in = valid_in && ready_in;

    // =========================================================================
    // Current 10-bit symbol
    // =========================================================================
    logic [9:0] cur_code10;
    dec_res_t   cur_dec;

    logic [63:0] data_next;
    logic [7:0]  is_k_next;
    logic [7:0]  code_err_next;
    logic [7:0]  rd_err_next;

    always_comb begin
        cur_code10 = code80_reg[lane_idx*10 +: 10];

        cur_dec = decode_symbol(
            cur_code10,
            rd_work
        );

        data_next     = data_work;
        is_k_next     = is_k_work;
        code_err_next = code_err_work;
        rd_err_next   = rd_err_work;

        data_next[lane_idx*8 +: 8] = cur_dec.code_err ? 8'h00 : cur_dec.data;
        is_k_next[lane_idx]        = cur_dec.code_err ? 1'b0  : cur_dec.is_k;
        code_err_next[lane_idx]    = cur_dec.code_err;
        rd_err_next[lane_idx]      = cur_dec.rd_err;
    end

    // =========================================================================
    // Disparity helpers
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

            // K28.x
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

            // K23.7, K27.7, K29.7, K30.7
            else if ((grp5 == 5'd23) ||
                     (grp5 == 5'd27) ||
                     (grp5 == 5'd29) ||
                     (grp5 == 5'd30)) begin

                if (!rd_after_6b) begin
                    if (code4 == 4'b0111) begin
                        r.valid = 1'b1;
                        r.grp3  = 3'd7;
                    end
                end else begin
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
    // Sequential one-symbol-per-cycle decoder
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_IDLE;

            rd_plus_cur   <= 1'b0;
            rd_work       <= 1'b0;

            code80_reg    <= 80'd0;

            data_work     <= 64'd0;
            is_k_work     <= 8'd0;
            code_err_work <= 8'd0;
            rd_err_work   <= 8'd0;

            lane_idx      <= 3'd0;

            data_out      <= 64'd0;
            is_k_out      <= 8'd0;
            valid_out     <= 1'b0;
            code_err      <= 8'd0;
            rd_err        <= 8'd0;

        end else begin
            unique case (st)

                // ------------------------------------------------------------
                // Wait for one 80-bit encoded word
                // ------------------------------------------------------------
                ST_IDLE: begin
                    valid_out <= 1'b0;
                    data_out  <= 64'd0;
                    is_k_out  <= 8'd0;
                    code_err  <= 8'd0;
                    rd_err    <= 8'd0;

                    if (accept_in) begin
                        code80_reg    <= code80_in;

                        data_work     <= 64'd0;
                        is_k_work     <= 8'd0;
                        code_err_work <= 8'd0;
                        rd_err_work   <= 8'd0;

                        lane_idx      <= 3'd0;
                        rd_work       <= rd_plus_cur;

                        st            <= ST_DECODE;
                    end
                end

                // ------------------------------------------------------------
                // Decode one 10-bit symbol per cycle
                // ------------------------------------------------------------
                ST_DECODE: begin
                    data_work     <= data_next;
                    is_k_work     <= is_k_next;
                    code_err_work <= code_err_next;
                    rd_err_work   <= rd_err_next;

                    if (!cur_dec.code_err) begin
                        rd_work <= cur_dec.rd_plus_out;
                    end

                    if (lane_idx == 3'd7) begin
                        data_out  <= data_next;
                        is_k_out  <= is_k_next;
                        code_err  <= code_err_next;
                        rd_err    <= rd_err_next;
                        valid_out <= 1'b1;

                        // Advance global RD only if all code groups were legal.
                        // RD errors do not block update because the symbol was recovered
                        // using the opposite expected RD.
                        if (!(|code_err_next)) begin
                            rd_plus_cur <= cur_dec.rd_plus_out;
                        end

                        st <= ST_OUTPUT;
                    end else begin
                        lane_idx <= lane_idx + 3'd1;
                    end
                end

                // ------------------------------------------------------------
                // Hold decoded 64-bit word until downstream accepts it
                // ------------------------------------------------------------
                ST_OUTPUT: begin
                    if (ready_out) begin
                        valid_out <= 1'b0;
                        data_out  <= 64'd0;
                        is_k_out  <= 8'd0;
                        code_err  <= 8'd0;
                        rd_err    <= 8'd0;
                        st        <= ST_IDLE;
                    end
                end

                default: begin
                    st        <= ST_IDLE;
                    valid_out <= 1'b0;
                    data_out  <= 64'd0;
                    is_k_out  <= 8'd0;
                    code_err  <= 8'd0;
                    rd_err    <= 8'd0;
                end

            endcase
        end
    end

    // =========================================================================
    // Error summary
    // =========================================================================
    assign any_err = |(code_err | rd_err);

    // =========================================================================
    // Simulation-only checks
    // =========================================================================
    // synthesis translate_off
`ifdef ASSERTIONS
    logic [63:0] prev_data_out;
    logic [7:0]  prev_is_k_out;
    logic [7:0]  prev_code_err;
    logic [7:0]  prev_rd_err;
    logic        prev_valid_out;
    logic        prev_stalled;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_data_out  <= 64'd0;
            prev_is_k_out  <= 8'd0;
            prev_code_err  <= 8'd0;
            prev_rd_err    <= 8'd0;
            prev_valid_out <= 1'b0;
            prev_stalled   <= 1'b0;
        end else begin
            if (prev_stalled) begin
                if (data_out  !== prev_data_out  ||
                    is_k_out  !== prev_is_k_out  ||
                    code_err  !== prev_code_err  ||
                    rd_err    !== prev_rd_err    ||
                    valid_out !== prev_valid_out) begin
                    $error("dec_80b64b: output changed while stalled");
                end
            end

            prev_data_out  <= data_out;
            prev_is_k_out  <= is_k_out;
            prev_code_err  <= code_err;
            prev_rd_err    <= rd_err;
            prev_valid_out <= valid_out;
            prev_stalled   <= valid_out && !ready_out;
        end
    end
`endif
    // synthesis translate_on

endmodule
