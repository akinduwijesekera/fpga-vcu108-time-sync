`timescale 1ns/1ps

module packet_tx #(
    parameter logic [7:0]  PTP_LITE_VERSION = 8'h01,
    parameter logic [7:0]  DEFAULT_FLAGS    = 8'h00,
    parameter logic [23:0] DEFAULT_RESERVED = 24'h000000
)(
    input  logic clk,
    input  logic rst_n,

    input  logic start_tx,
    input  logic [7:0] msg_type,

    input  logic [47:0] tod_sec,
    input  logic [31:0] tod_nsec,
    input  logic [15:0] tod_frac,

    axi_stream_if.master m_axis,

    output logic tx_busy,
    output logic tx_done,
    output logic [15:0] seq_id_out
);

    typedef enum logic [1:0] { S_IDLE, S_W0, S_W1, S_W2 } state_t;
    state_t state, state_n;

    logic [15:0] seq_id_reg;

    logic [47:0] sec_latched;
    logic [31:0] nsec_latched;
    logic [15:0] frac_latched;
    logic [7:0]  msg_type_latched;

    logic beat_accepted;
    assign beat_accepted = m_axis.tvalid && m_axis.tready;

    assign seq_id_out = seq_id_reg;

    logic [63:0] word0, word1, word2;

    // tx_done 1-cycle pulse
    logic tx_done_r;
    assign tx_done = tx_done_r;

    // start pulse detect
    logic start_tx_d;
    logic start_pulse;

    function automatic logic [63:0] pack8(
        input logic [7:0] b0, b1, b2, b3, b4, b5, b6, b7
    );
        pack8 = {b7,b6,b5,b4,b3,b2,b1,b0};
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) start_tx_d <= 1'b0;
        else        start_tx_d <= start_tx;
    end

    assign start_pulse = start_tx & ~start_tx_d;

    // Payload byte layout (20 bytes total):
    //  0: msg_type
    //  1: version
    //  2: seq_id[15:8]
    //  3: seq_id[7:0]
    //  4: flags
    //  5: reserved[23:16]
    //  6: reserved[15:8]
    //  7: reserved[7:0]
    //  8: sec[47:40]
    //  9: sec[39:32]
    // 10: sec[31:24]
    // 11: sec[23:16]
    // 12: sec[15:8]
    // 13: sec[7:0]
    // 14: nsec[31:24]
    // 15: nsec[23:16]
    // 16: nsec[15:8]
    // 17: nsec[7:0]
    // 18: frac[15:8]
    // 19: frac[7:0]

    always_comb begin
        word0 = pack8(
            msg_type_latched,
            PTP_LITE_VERSION,
            seq_id_reg[15:8],
            seq_id_reg[7:0],
            DEFAULT_FLAGS,
            DEFAULT_RESERVED[23:16],
            DEFAULT_RESERVED[15:8],
            DEFAULT_RESERVED[7:0]
        );

        word1 = pack8(
            sec_latched[47:40],
            sec_latched[39:32],
            sec_latched[31:24],
            sec_latched[23:16],
            sec_latched[15:8],
            sec_latched[7:0],
            nsec_latched[31:24],
            nsec_latched[23:16]
        );

        // Lanes 0..3 valid
        word2 = {
            32'h00000000,
            frac_latched[7:0],
            frac_latched[15:8],
            nsec_latched[7:0],
            nsec_latched[15:8]
        };
    end

    always_comb begin
        state_n       = state;

        m_axis.tvalid = 1'b0;
        m_axis.tdata  = 64'd0;
        m_axis.tkeep  = 8'h00;
        m_axis.tlast  = 1'b0;

        tx_busy       = 1'b0;

        unique case (state)
            S_IDLE: begin
                if (start_pulse) state_n = S_W0;
            end

            S_W0: begin
                tx_busy       = 1'b1;
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = word0;
                m_axis.tkeep  = 8'hFF;
                if (beat_accepted) state_n = S_W1;
            end

            S_W1: begin
                tx_busy       = 1'b1;
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = word1;
                m_axis.tkeep  = 8'hFF;
                if (beat_accepted) state_n = S_W2;
            end

            S_W2: begin
                tx_busy       = 1'b1;
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = word2;
                m_axis.tkeep  = 8'h0F;
                m_axis.tlast  = 1'b1;
                if (beat_accepted) state_n = S_IDLE;
            end

            default: state_n = S_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            seq_id_reg       <= 16'd0;

            sec_latched      <= 48'd0;
            nsec_latched     <= 32'd0;
            frac_latched     <= 16'd0;
            msg_type_latched <= 8'd0;

            tx_done_r        <= 1'b0;
        end else begin
            state <= state_n;

            tx_done_r <= 1'b0;

            if (state == S_IDLE && start_pulse) begin
                sec_latched      <= tod_sec;
                nsec_latched     <= tod_nsec;
                frac_latched     <= tod_frac;
                msg_type_latched <= msg_type;
            end

            if (state == S_W2 && beat_accepted) begin
                seq_id_reg <= seq_id_reg + 16'd1;
                tx_done_r  <= 1'b1;
            end
        end
    end

endmodule
