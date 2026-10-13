`timescale 1ns/1ps

module tx_packet_framer #(
    parameter logic [7:0]  PTP_LITE_VERSION = 8'h01,
    parameter logic [7:0]  DEFAULT_FLAGS    = 8'h00,
    parameter logic [7:0]  DEFAULT_RESERVED = 8'h00,

    parameter logic [47:0] DEFAULT_DST_MAC   = 48'hDA_02_03_04_05_06,
    parameter logic [47:0] DEFAULT_SRC_MAC   = 48'h5A_02_03_04_05_06,
    parameter logic [15:0] DEFAULT_ETHER_TYPE = 16'h88F7
)(
    input  logic clk,
    input  logic rst_n,

    // Start one frame transmission.
    // Can be a pulse or a held-high request.
    input  logic start_tx,

    // PTP-lite message type, e.g. SYNC, DELAY_REQ, etc.
    input  logic [7:0] msg_type,

    // Optional runtime frame fields.
    // If you do not need runtime MAC changes, just tie these to constants.
    input  logic [47:0] dst_mac,
    input  logic [47:0] src_mac,
    input  logic [15:0] ether_type,

    // Timestamp from local_time_counter
    input  logic [47:0] tod_sec,
    input  logic [31:0] tod_nsec,
    input  logic [15:0] tod_frac,

    // Full frame output, excluding CRC/FCS.
    // This should feed crc_append_axis.
    axi_stream_if.master m_axis,

    output logic tx_busy,
    output logic tx_done,
    output logic [15:0] seq_id_out
);

    // ------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_W0,
        S_W1,
        S_W2,
        S_W3
    } state_t;

    state_t state, state_n;

    // ------------------------------------------------------------
    // Internal registers
    // ------------------------------------------------------------
    logic [15:0] seq_id_reg;

    logic [47:0] dst_latched;
    logic [47:0] src_latched;
    logic [15:0] etype_latched;

    logic [47:0] sec_latched;
    logic [31:0] nsec_latched;
    logic [15:0] frac_latched;
    logic [7:0]  msg_type_latched;

    logic tx_done_r;

    assign tx_done    = tx_done_r;
    assign seq_id_out = seq_id_reg;

    // ------------------------------------------------------------
    // Start request handling
    // ------------------------------------------------------------
    logic start_tx_d;
    logic start_pulse;
    logic start_accept;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_tx_d <= 1'b0;
        end else begin
            start_tx_d <= start_tx;
        end
    end

    assign start_pulse  = start_tx & ~start_tx_d;
    assign start_accept = (state == S_IDLE) && start_pulse;

    // ------------------------------------------------------------
    // AXI handshake
    // ------------------------------------------------------------
    logic beat_accepted;

    assign beat_accepted = m_axis.tvalid && m_axis.tready;

    // ------------------------------------------------------------
    // Byte packing helper
    //
    // b0 goes to AXI byte lane 0: tdata[7:0]
    // b7 goes to AXI byte lane 7: tdata[63:56]
    // ------------------------------------------------------------
    function automatic logic [63:0] pack8(
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3,
        input logic [7:0] b4,
        input logic [7:0] b5,
        input logic [7:0] b6,
        input logic [7:0] b7
    );
        pack8 = {b7, b6, b5, b4, b3, b2, b1, b0};
    endfunction

    // ------------------------------------------------------------
    // Frame word construction
    //
    // Frame format before CRC:
    //
    // Bytes  0..5  : Destination MAC
    // Bytes  6..11 : Source MAC
    // Bytes 12..13 : EtherType
    // Bytes 14..31 : PTP-lite payload, 18 bytes
    //
    // PTP-lite payload:
    // Byte  14 : msg_type
    // Byte  15 : version
    // Byte  16 : sequence_id[15:8]
    // Byte  17 : sequence_id[7:0]
    // Byte  18 : flags
    // Byte  19 : reserved
    // Byte  20 : seconds[47:40]
    // Byte  21 : seconds[39:32]
    // Byte  22 : seconds[31:24]
    // Byte  23 : seconds[23:16]
    // Byte  24 : seconds[15:8]
    // Byte  25 : seconds[7:0]
    // Byte  26 : nanoseconds[31:24]
    // Byte  27 : nanoseconds[23:16]
    // Byte  28 : nanoseconds[15:8]
    // Byte  29 : nanoseconds[7:0]
    // Byte  30 : frac_ns[15:8]
    // Byte  31 : frac_ns[7:0]
    // ------------------------------------------------------------
    logic [63:0] word0;
    logic [63:0] word1;
    logic [63:0] word2;
    logic [63:0] word3;

    always_comb begin
        // Bytes 0..7:
        // Dst MAC[0..5], Src MAC[0..1]
        word0 = pack8(
            dst_latched[47:40],
            dst_latched[39:32],
            dst_latched[31:24],
            dst_latched[23:16],
            dst_latched[15:8],
            dst_latched[7:0],
            src_latched[47:40],
            src_latched[39:32]
        );

        // Bytes 8..15:
        // Src MAC[2..5], EtherType, msg_type, version
        word1 = pack8(
            src_latched[31:24],
            src_latched[23:16],
            src_latched[15:8],
            src_latched[7:0],
            etype_latched[15:8],
            etype_latched[7:0],
            msg_type_latched,
            PTP_LITE_VERSION
        );

        // Bytes 16..23:
        // seq_id, flags, reserved, seconds[47:16]
        word2 = pack8(
            seq_id_reg[15:8],
            seq_id_reg[7:0],
            DEFAULT_FLAGS,
            DEFAULT_RESERVED,
            sec_latched[47:40],
            sec_latched[39:32],
            sec_latched[31:24],
            sec_latched[23:16]
        );

        // Bytes 24..31:
        // seconds[15:0], nanoseconds[31:0], frac[15:0]
        word3 = pack8(
            sec_latched[15:8],
            sec_latched[7:0],
            nsec_latched[31:24],
            nsec_latched[23:16],
            nsec_latched[15:8],
            nsec_latched[7:0],
            frac_latched[15:8],
            frac_latched[7:0]
        );
    end

    // ------------------------------------------------------------
    // Combinational FSM output logic
    // ------------------------------------------------------------
    always_comb begin
        state_n = state;

        m_axis.tvalid = 1'b0;
        m_axis.tdata  = 64'd0;
        m_axis.tkeep  = 8'h00;
        m_axis.tlast  = 1'b0;

        tx_busy = (state != S_IDLE);

        unique case (state)

            S_IDLE: begin
                if (start_pulse) begin
                    state_n = S_W0;
                end
            end

            S_W0: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = word0;
                m_axis.tkeep  = 8'hFF;
                m_axis.tlast  = 1'b0;

                if (beat_accepted) begin
                    state_n = S_W1;
                end
            end

            S_W1: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = word1;
                m_axis.tkeep  = 8'hFF;
                m_axis.tlast  = 1'b0;

                if (beat_accepted) begin
                    state_n = S_W2;
                end
            end

            S_W2: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = word2;
                m_axis.tkeep  = 8'hFF;
                m_axis.tlast  = 1'b0;

                if (beat_accepted) begin
                    state_n = S_W3;
                end
            end

            S_W3: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = word3;
                m_axis.tkeep  = 8'hFF;
                m_axis.tlast  = 1'b1;

                if (beat_accepted) begin
                    state_n = S_IDLE;
                end
            end

            default: begin
                state_n = S_IDLE;
            end

        endcase
    end

    // ------------------------------------------------------------
    // Sequential state, timestamp latch, and sequence update
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;

            seq_id_reg       <= 16'd0;

            dst_latched      <= DEFAULT_DST_MAC;
            src_latched      <= DEFAULT_SRC_MAC;
            etype_latched    <= DEFAULT_ETHER_TYPE;

            sec_latched      <= 48'd0;
            nsec_latched     <= 32'd0;
            frac_latched     <= 16'd0;
            msg_type_latched <= 8'd0;

            tx_done_r        <= 1'b0;

        end else begin
            state <= state_n;

            // Default: no done pulse
            tx_done_r <= 1'b0;

            // Latch all frame fields at the exact accepted start boundary.
            // The first AXI word is emitted one cycle later.
            if (start_accept) begin
                dst_latched      <= dst_mac;
                src_latched      <= src_mac;
                etype_latched    <= ether_type;

                sec_latched      <= tod_sec;
                nsec_latched     <= tod_nsec;
                frac_latched     <= tod_frac;
                msg_type_latched <= msg_type;
            end

            // Complete frame once final word is accepted
            if (state == S_W3 && beat_accepted) begin
                seq_id_reg <= seq_id_reg + 16'd1;
                tx_done_r  <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------
    // Simulation-only checks
    // ------------------------------------------------------------
    // synthesis translate_off
`ifdef ASSERTIONS
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (m_axis.tvalid && !m_axis.tready) begin
                // AXI requires tdata/tkeep/tlast to remain stable
                // while valid is high and ready is low.
                // In this FSM, this is guaranteed because state and
                // latched frame fields do not change until beat_accepted.
            end

            if (tod_nsec >= 32'd1_000_000_000) begin
                $error("tx_packet_framer: tod_nsec out of range: %0d", tod_nsec);
            end
        end
    end
`endif
    // synthesis translate_on

endmodule
