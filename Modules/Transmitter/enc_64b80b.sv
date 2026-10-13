`timescale 1ns/1ps

module enc_64b80b (
    input  logic        clk,
    input  logic        rst,

    input  logic [63:0] data_in,
    input  logic [7:0]  is_k_in,
    input  logic        valid_in,

    output logic [79:0] code80_out,
    output logic        valid_out,
    output logic        enc_err
);

    // -------------------------------------------------------------------------
    // Pipeline stage 0
    // -------------------------------------------------------------------------
    logic [63:0] data_s0;
    logic [7:0]  is_k_s0;
    logic        valid_s0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_s0  <= 64'd0;
            is_k_s0  <= 8'd0;
            valid_s0 <= 1'b0;
        end else begin
            data_s0  <= data_in;
            is_k_s0  <= is_k_in;
            valid_s0 <= valid_in;
        end
    end

    // -------------------------------------------------------------------------
    // Running disparity state
    // Convention:
    //   rd_plus_cur = 0 -> current running disparity is RD-
    //   rd_plus_cur = 1 -> current running disparity is RD+
    // -------------------------------------------------------------------------
    logic rd_plus_cur;
    logic rd_plus_next_word;

    typedef struct packed {
        logic       valid;
        logic [9:0] code;
        logic       rd_plus_out;
    } enc_res_t;

    // -------------------------------------------------------------------------
    // Disparity helper
    // -------------------------------------------------------------------------
    function automatic integer disparityN(
        input logic [9:0] bits,
        input integer N
    );
        integer ones;
        begin
            ones = 0;
            for (int i = 0; i < N; i++) begin
                ones = ones + bits[i];
            end
            disparityN = ones - (N - ones);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Valid K-code check
    // Valid K symbols:
    //   K28.x for x = 0..7
    //   K23.7, K27.7, K29.7, K30.7
    // -------------------------------------------------------------------------
    function automatic logic valid_k_fn(
        input logic [7:0] data
    );
        logic [4:0] g5;
        logic [2:0] g3;
        begin
            g5 = data[4:0];
            g3 = data[7:5];

            valid_k_fn = 1'b0;

            if (g5 == 5'd28) begin
                valid_k_fn = 1'b1;
            end else if ((g3 == 3'd7) &&
                        ((g5 == 5'd23) ||
                         (g5 == 5'd27) ||
                         (g5 == 5'd29) ||
                         (g5 == 5'd30))) begin
                valid_k_fn = 1'b1;
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // 5b/6b positive table
    // -------------------------------------------------------------------------
    function automatic logic [5:0] sixb_pos_fn(input logic [4:0] grp5_in);
        begin
            unique case (grp5_in)
                5'd0 : sixb_pos_fn = 6'b100111;
                5'd1 : sixb_pos_fn = 6'b011101;
                5'd2 : sixb_pos_fn = 6'b101101;
                5'd3 : sixb_pos_fn = 6'b110001;
                5'd4 : sixb_pos_fn = 6'b110101;
                5'd5 : sixb_pos_fn = 6'b101001;
                5'd6 : sixb_pos_fn = 6'b011001;
                5'd7 : sixb_pos_fn = 6'b111000;
                5'd8 : sixb_pos_fn = 6'b111001;
                5'd9 : sixb_pos_fn = 6'b100101;
                5'd10: sixb_pos_fn = 6'b010101;
                5'd11: sixb_pos_fn = 6'b110100;
                5'd12: sixb_pos_fn = 6'b001101;
                5'd13: sixb_pos_fn = 6'b101100;
                5'd14: sixb_pos_fn = 6'b011100;
                5'd15: sixb_pos_fn = 6'b010111;
                5'd16: sixb_pos_fn = 6'b011011;
                5'd17: sixb_pos_fn = 6'b100011;
                5'd18: sixb_pos_fn = 6'b010011;
                5'd19: sixb_pos_fn = 6'b110010;
                5'd20: sixb_pos_fn = 6'b001011;
                5'd21: sixb_pos_fn = 6'b101010;
                5'd22: sixb_pos_fn = 6'b011010;
                5'd23: sixb_pos_fn = 6'b111010;
                5'd24: sixb_pos_fn = 6'b001100;
                5'd25: sixb_pos_fn = 6'b100110;
                5'd26: sixb_pos_fn = 6'b010110;
                5'd27: sixb_pos_fn = 6'b110110;
                5'd28: sixb_pos_fn = 6'b001110;
                5'd29: sixb_pos_fn = 6'b101110;
                5'd30: sixb_pos_fn = 6'b011110;
                5'd31: sixb_pos_fn = 6'b101011;
                default: sixb_pos_fn = 6'b000000;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // 5b/6b negative table
    // -------------------------------------------------------------------------
    function automatic logic [5:0] sixb_neg_fn(input logic [4:0] grp5_in);
        begin
            unique case (grp5_in)
                5'd0 : sixb_neg_fn = 6'b011000;
                5'd1 : sixb_neg_fn = 6'b100010;
                5'd2 : sixb_neg_fn = 6'b010010;
                5'd3 : sixb_neg_fn = 6'b001110;
                5'd4 : sixb_neg_fn = 6'b001010;
                5'd5 : sixb_neg_fn = 6'b010110;
                5'd6 : sixb_neg_fn = 6'b100110;
                5'd7 : sixb_neg_fn = 6'b000111;
                5'd8 : sixb_neg_fn = 6'b000110;
                5'd9 : sixb_neg_fn = 6'b011010;
                5'd10: sixb_neg_fn = 6'b101010;
                5'd11: sixb_neg_fn = 6'b001011;
                5'd12: sixb_neg_fn = 6'b110010;
                5'd13: sixb_neg_fn = 6'b010011;
                5'd14: sixb_neg_fn = 6'b100011;
                5'd15: sixb_neg_fn = 6'b101000;
                5'd16: sixb_neg_fn = 6'b100100;
                5'd17: sixb_neg_fn = 6'b011100;
                5'd18: sixb_neg_fn = 6'b101100;
                5'd19: sixb_neg_fn = 6'b001101;
                5'd20: sixb_neg_fn = 6'b110100;
                5'd21: sixb_neg_fn = 6'b010101;
                5'd22: sixb_neg_fn = 6'b100101;
                5'd23: sixb_neg_fn = 6'b000101;
                5'd24: sixb_neg_fn = 6'b110011;
                5'd25: sixb_neg_fn = 6'b011001;
                5'd26: sixb_neg_fn = 6'b101001;
                5'd27: sixb_neg_fn = 6'b001001;
                5'd28: sixb_neg_fn = 6'b110001;
                5'd29: sixb_neg_fn = 6'b010001;
                5'd30: sixb_neg_fn = 6'b100001;
                5'd31: sixb_neg_fn = 6'b010100;
                default: sixb_neg_fn = 6'b111111;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // 3b/4b positive table
    // -------------------------------------------------------------------------
    function automatic logic [3:0] fourb_pos_fn(
        input logic [2:0] grp3_in,
        input logic [4:0] grp5_in,
        input logic       is_k
    );
        begin
            unique case (grp3_in)
                3'd0: fourb_pos_fn = 4'b1011;
                3'd1: fourb_pos_fn = 4'b1001;
                3'd2: fourb_pos_fn = 4'b0101;
                3'd3: fourb_pos_fn = 4'b1100;
                3'd4: fourb_pos_fn = 4'b1101;
                3'd5: fourb_pos_fn = 4'b1010;
                3'd6: fourb_pos_fn = 4'b0110;
                3'd7: begin
                    fourb_pos_fn = 4'b1110;

                    if (is_k) begin
                        if ((grp5_in == 5'd23) ||
                            (grp5_in == 5'd27) ||
                            (grp5_in == 5'd29) ||
                            (grp5_in == 5'd30)) begin
                            fourb_pos_fn = 4'b0111;
                        end
                    end else begin
                        if ((grp5_in == 5'd17) ||
                            (grp5_in == 5'd18) ||
                            (grp5_in == 5'd20)) begin
                            fourb_pos_fn = 4'b0111;
                        end
                    end
                end
                default: fourb_pos_fn = 4'b0000;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // 3b/4b negative table
    // -------------------------------------------------------------------------
    function automatic logic [3:0] fourb_neg_fn(
        input logic [2:0] grp3_in,
        input logic [4:0] grp5_in,
        input logic       is_k
    );
        begin
            unique case (grp3_in)
                3'd0: fourb_neg_fn = 4'b0100;
                3'd1: fourb_neg_fn = 4'b0110;
                3'd2: fourb_neg_fn = 4'b1010;
                3'd3: fourb_neg_fn = 4'b0011;
                3'd4: fourb_neg_fn = 4'b0010;
                3'd5: fourb_neg_fn = 4'b0101;
                3'd6: fourb_neg_fn = 4'b1001;
                3'd7: begin
                    fourb_neg_fn = 4'b0001;

                    if (is_k) begin
                        if ((grp5_in == 5'd23) ||
                            (grp5_in == 5'd27) ||
                            (grp5_in == 5'd29) ||
                            (grp5_in == 5'd30)) begin
                            fourb_neg_fn = 4'b1000;
                        end
                    end else begin
                        if ((grp5_in == 5'd11) ||
                            (grp5_in == 5'd13) ||
                            (grp5_in == 5'd14)) begin
                            fourb_neg_fn = 4'b1000;
                        end
                    end
                end
                default: fourb_neg_fn = 4'b1111;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Encode one 8-bit symbol into one 10-bit 8b/10b code group
    // -------------------------------------------------------------------------
    function automatic enc_res_t encode_symbol(
        input logic [7:0] data,
        input logic       is_k,
        input logic       rd_plus_in
    );
        enc_res_t r;

        logic [4:0] grp5;
        logic [2:0] grp3;

        logic [5:0] sixb_pos;
        logic [5:0] sixb_neg;
        logic [5:0] sixb_sel;

        logic [3:0] fourb_pos;
        logic [3:0] fourb_neg;
        logic [3:0] fourb_sel;

        logic       rd_after_6b;

        integer     disp6;
        integer     disp10;

        begin
            r.valid       = 1'b0;
            r.code        = 10'd0;
            r.rd_plus_out = rd_plus_in;

            grp5 = data[4:0];
            grp3 = data[7:5];

            if (is_k && !valid_k_fn(data)) begin
                encode_symbol = r;
            end else begin
                sixb_pos = sixb_pos_fn(grp5);
                sixb_neg = sixb_neg_fn(grp5);

                // K28.x comma 6b override
                if (is_k && (grp5 == 5'd28)) begin
                    sixb_pos = 6'b001111;
                    sixb_neg = 6'b110000;
                end

                fourb_pos = fourb_pos_fn(grp3, grp5, is_k);
                fourb_neg = fourb_neg_fn(grp3, grp5, is_k);

                // If current RD is positive, choose negative-disparity symbol.
                // If current RD is negative, choose positive-disparity symbol.
                sixb_sel = (rd_plus_in) ? sixb_neg : sixb_pos;

                disp6 = disparityN({4'b0, sixb_sel}, 6);

                rd_after_6b = rd_plus_in;
                if (disp6 > 0) begin
                    rd_after_6b = 1'b1;
                end else if (disp6 < 0) begin
                    rd_after_6b = 1'b0;
                end

                fourb_sel = (rd_after_6b) ? fourb_neg : fourb_pos;

                disp10 = disparityN({sixb_sel, fourb_sel}, 10);

                r.rd_plus_out = rd_plus_in;
                if (disp10 > 0) begin
                    r.rd_plus_out = 1'b1;
                end else if (disp10 < 0) begin
                    r.rd_plus_out = 1'b0;
                end

                r.valid = 1'b1;
                r.code  = {sixb_sel, fourb_sel};

                encode_symbol = r;
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // Encode 8 symbols per cycle into one 80-bit word
    // byte 0 -> code80[9:0]
    // byte 1 -> code80[19:10]
    // ...
    // byte 7 -> code80[79:70]
    // -------------------------------------------------------------------------
    logic [79:0] code80_word;
    logic        word_valid;
    logic        word_err;

    always_comb begin
        enc_res_t r;
        logic rd_work;

        code80_word       = 80'd0;
        rd_plus_next_word = rd_plus_cur;
        word_valid        = 1'b1;
        word_err          = 1'b0;

        rd_work = rd_plus_cur;

        for (int n = 0; n < 8; n++) begin
            r = encode_symbol(
                    data_s0[n*8 +: 8],
                    is_k_s0[n],
                    rd_work
                );

            code80_word[n*10 +: 10] = r.code;

            if (!r.valid) begin
                word_valid = 1'b0;
                word_err   = 1'b1;
            end

            rd_work = r.rd_plus_out;
        end

        rd_plus_next_word = rd_work;
    end

    // -------------------------------------------------------------------------
    // Output register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            code80_out  <= 80'd0;
            valid_out   <= 1'b0;
            enc_err     <= 1'b0;
            rd_plus_cur <= 1'b0; // Start in RD-
        end else begin
            valid_out <= 1'b0;
            enc_err   <= 1'b0;

            if (valid_s0) begin
                enc_err <= word_err;

                if (word_valid) begin
                    code80_out  <= code80_word;
                    valid_out   <= 1'b1;
                    rd_plus_cur <= rd_plus_next_word;
                end else begin
                    // Invalid K-code: do not update RD.
                    code80_out <= code80_out;
                    valid_out  <= 1'b0;
                end
            end
        end
    end

endmodule
