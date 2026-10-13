`timescale 1ns/1ps

module enc_64b80b (
    input  logic        clk,
    input  logic        rst_n,

    // Input from tx_pcs
    input  logic [63:0] data_in,
    input  logic [7:0]  is_k_in,
    input  logic        valid_in,
    output logic        ready_in,

    // Output to GTY-side parallel datapath
    output logic [79:0] code80_out,
    output logic        valid_out,
    input  logic        ready_out,

    output logic        enc_err
);

    // ------------------------------------------------------------
    // Running disparity convention
    // rd_plus = 0 -> current RD-
    // rd_plus = 1 -> current RD+
    // ------------------------------------------------------------
    logic rd_plus_cur;

    typedef struct packed {
        logic       valid;
        logic [9:0] code;
        logic       rd_plus_out;
    } enc_res_t;

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_ENCODE,
        ST_OUTPUT
    } state_t;

    state_t st;

    // ------------------------------------------------------------
    // Stored input word
    // ------------------------------------------------------------
    logic [63:0] data_reg;
    logic [7:0]  is_k_reg;

    // Work registers while encoding the 8 symbols
    logic [79:0] code80_work;
    logic [2:0]  lane_idx;
    logic        rd_work;
    logic        word_err;

    // ------------------------------------------------------------
    // Handshake
    // ------------------------------------------------------------
    logic accept_in;

    assign ready_in  = (st == ST_IDLE);
    assign accept_in = valid_in && ready_in;

    // ------------------------------------------------------------
    // Current symbol being encoded
    // ------------------------------------------------------------
    logic [7:0] cur_data;
    logic       cur_is_k;
    enc_res_t   cur_enc;

    logic [79:0] code80_next;
    logic        word_err_next;

    always_comb begin
        cur_data = data_reg[lane_idx*8 +: 8];
        cur_is_k = is_k_reg[lane_idx];

        cur_enc = encode_symbol(
            cur_data,
            cur_is_k,
            rd_work
        );

        code80_next = code80_work;
        code80_next[lane_idx*10 +: 10] = cur_enc.code;

        word_err_next = word_err || !cur_enc.valid;
    end

    // ------------------------------------------------------------
    // Disparity helper
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // Valid K-code check
    // Valid K symbols:
    //   K28.x for x = 0..7
    //   K23.7, K27.7, K29.7, K30.7
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // 5b/6b positive table
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // 5b/6b negative table
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // 3b/4b positive table
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // 3b/4b negative table
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // Encode one 8-bit symbol
    // ------------------------------------------------------------
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

                // K28.x comma override
                if (is_k && (grp5 == 5'd28)) begin
                    sixb_pos = 6'b001111;
                    sixb_neg = 6'b110000;
                end

                fourb_pos = fourb_pos_fn(grp3, grp5, is_k);
                fourb_neg = fourb_neg_fn(grp3, grp5, is_k);

                // If current RD is positive, choose negative-disparity symbol.
                // If current RD is negative, choose positive-disparity symbol.
                sixb_sel = rd_plus_in ? sixb_neg : sixb_pos;

                disp6 = disparityN({4'b0, sixb_sel}, 6);

                rd_after_6b = rd_plus_in;
                if (disp6 > 0) begin
                    rd_after_6b = 1'b1;
                end else if (disp6 < 0) begin
                    rd_after_6b = 1'b0;
                end

                fourb_sel = rd_after_6b ? fourb_neg : fourb_pos;

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

    // ------------------------------------------------------------
    // Sequential one-symbol-per-cycle encoder
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= ST_IDLE;

            rd_plus_cur <= 1'b0; // start RD-
            rd_work     <= 1'b0;

            data_reg    <= 64'd0;
            is_k_reg    <= 8'd0;

            code80_work <= 80'd0;
            lane_idx    <= 3'd0;
            word_err    <= 1'b0;

            code80_out  <= 80'd0;
            valid_out   <= 1'b0;
            enc_err     <= 1'b0;

        end else begin
            // Default one-cycle pulse
            enc_err <= 1'b0;

            unique case (st)

                // --------------------------------------------------------
                // Wait for a new 64-bit symbol word
                // --------------------------------------------------------
                ST_IDLE: begin
                    valid_out <= 1'b0;

                    if (accept_in) begin
                        data_reg    <= data_in;
                        is_k_reg    <= is_k_in;

                        code80_work <= 80'd0;
                        lane_idx    <= 3'd0;

                        rd_work     <= rd_plus_cur;
                        word_err    <= 1'b0;

                        st          <= ST_ENCODE;
                    end
                end

                // --------------------------------------------------------
                // Encode one 8-bit symbol per clock
                // --------------------------------------------------------
                ST_ENCODE: begin
                    code80_work <= code80_next;
                    word_err    <= word_err_next;

                    if (cur_enc.valid) begin
                        rd_work <= cur_enc.rd_plus_out;
                    end

                    if (lane_idx == 3'd7) begin
                        if (word_err_next) begin
                            // Invalid K-code somewhere in this word.
                            // Do not emit output and do not update global RD.
                            enc_err <= 1'b1;
                            st      <= ST_IDLE;
                        end else begin
                            // Full 80-bit codeword complete.
                            code80_out  <= code80_next;
                            valid_out   <= 1'b1;
                            rd_plus_cur <= cur_enc.rd_plus_out;
                            st          <= ST_OUTPUT;
                        end
                    end else begin
                        lane_idx <= lane_idx + 3'd1;
                    end
                end

                // --------------------------------------------------------
                // Hold completed 80-bit word until downstream accepts it
                // --------------------------------------------------------
                ST_OUTPUT: begin
                    if (ready_out) begin
                        valid_out <= 1'b0;
                        st        <= ST_IDLE;
                    end
                end

                default: begin
                    st        <= ST_IDLE;
                    valid_out <= 1'b0;
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // Simulation-only checks
    // ------------------------------------------------------------
    // synthesis translate_off
`ifdef ASSERTIONS
    logic [79:0] prev_code80_out;
    logic        prev_valid_out;
    logic        prev_stalled;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_code80_out <= 80'd0;
            prev_valid_out  <= 1'b0;
            prev_stalled    <= 1'b0;
        end else begin
            if (prev_stalled) begin
                if (code80_out !== prev_code80_out ||
                    valid_out  !== prev_valid_out) begin
                    $error("enc_64b80b: output changed while stalled");
                end
            end

            prev_code80_out <= code80_out;
            prev_valid_out  <= valid_out;
            prev_stalled    <= valid_out && !ready_out;
        end
    end
`endif
    // synthesis translate_on

endmodule
