`timescale 1ns/1ps

module packet_rx #(
    parameter logic [15:0] EXPECTED_ETHER_TYPE = 16'h88F7,
    parameter logic [7:0]  EXPECTED_VERSION    = 8'h01,

    // Set to 1 to enforce EtherType check.
    parameter bit CHECK_ETHER_TYPE = 1'b1,

    // Set to 1 to enforce PTP-lite version check.
    parameter bit CHECK_VERSION = 1'b1
)(
    input  logic clk,
    input  logic rst_n,

    // Validated 32-byte frame from crc32_check, excluding FCS.
    //
    // Frame layout:
    //   bytes  0..5  = destination MAC
    //   bytes  6..11 = source MAC
    //   bytes 12..13 = EtherType
    //   bytes 14..31 = 18-byte PTP-lite payload
    axi_stream_if.slave s_axis,

    // Parsed Ethernet-style header
    output logic [47:0] dst_mac,
    output logic [47:0] src_mac,
    output logic [15:0] ether_type,

    // Parsed PTP-lite payload
    output logic [7:0]  msg_type,
    output logic [7:0]  version,
    output logic [15:0] seq_id,
    output logic [7:0]  flags,
    output logic [7:0]  reserved,

    output logic [47:0] tx_tod_sec,
    output logic [31:0] tx_tod_nsec,
    output logic [15:0] tx_tod_frac,

    // Status pulses
    output logic        pkt_valid,     // pulses when a valid packet is parsed
    output logic        pkt_done,      // pulses when frame was received and parsed
    output logic        len_err,       // wrong frame length
    output logic        ether_type_err,
    output logic        version_err,
    output logic        pkt_err,

    output logic        pr_busy
);

    // ------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------
    localparam int FRAME_BYTES   = 32;
    localparam int FRAME_COUNT_W = $clog2(FRAME_BYTES + 1);

    // ------------------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_RECV,
        ST_PARSE
    } state_t;

    state_t st;

    // ------------------------------------------------------------------------
    // Frame buffer
    // ------------------------------------------------------------------------
    logic [7:0] frame_buf [0:FRAME_BYTES-1];

    logic [FRAME_COUNT_W-1:0] wr_count;
    logic                     overflow_seen;

    // ------------------------------------------------------------------------
    // Handshake
    // ------------------------------------------------------------------------
    logic s_fire;

    assign s_fire = s_axis.tvalid && s_axis.tready;

    // ------------------------------------------------------------------------
    // Input ready
    //
    // Accept frame data only while receiving.
    // Back-pressure during parse.
    // ------------------------------------------------------------------------
    always_comb begin
        s_axis.tready = 1'b0;

        unique case (st)
            ST_IDLE,
            ST_RECV: begin
                s_axis.tready = 1'b1;
            end

            default: begin
                s_axis.tready = 1'b0;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Working variables
    // ------------------------------------------------------------------------
    integer i;
    integer lane;

    logic [FRAME_COUNT_W-1:0] next_wr_count;

    logic [47:0] dst_mac_tmp;
    logic [47:0] src_mac_tmp;
    logic [15:0] ether_type_tmp;

    logic [7:0]  msg_type_tmp;
    logic [7:0]  version_tmp;
    logic [15:0] seq_id_tmp;
    logic [7:0]  flags_tmp;
    logic [7:0]  reserved_tmp;

    logic [47:0] tx_tod_sec_tmp;
    logic [31:0] tx_tod_nsec_tmp;
    logic [15:0] tx_tod_frac_tmp;

    logic ether_type_bad;
    logic version_bad;
    logic length_bad;

    // ------------------------------------------------------------------------
    // Main sequential logic
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_IDLE;
            wr_count      <= '0;
            overflow_seen <= 1'b0;

            dst_mac    <= 48'd0;
            src_mac    <= 48'd0;
            ether_type <= 16'd0;

            msg_type <= 8'd0;
            version  <= 8'd0;
            seq_id   <= 16'd0;
            flags    <= 8'd0;
            reserved <= 8'd0;

            tx_tod_sec  <= 48'd0;
            tx_tod_nsec <= 32'd0;
            tx_tod_frac <= 16'd0;

            pkt_valid      <= 1'b0;
            pkt_done       <= 1'b0;
            len_err        <= 1'b0;
            ether_type_err <= 1'b0;
            version_err    <= 1'b0;
            pkt_err        <= 1'b0;
            pr_busy        <= 1'b0;

            for (i = 0; i < FRAME_BYTES; i++) begin
                frame_buf[i] <= 8'h00;
            end

        end else begin
            // ------------------------------------------------------------
            // Default one-cycle pulses
            // ------------------------------------------------------------
            pkt_valid      <= 1'b0;
            pkt_done       <= 1'b0;
            len_err        <= 1'b0;
            ether_type_err <= 1'b0;
            version_err    <= 1'b0;
            pkt_err        <= 1'b0;

            pr_busy <= (st != ST_IDLE);

            unique case (st)

                // --------------------------------------------------------
                // Wait for first beat of 32-byte frame
                // --------------------------------------------------------
                ST_IDLE: begin
                    wr_count      <= '0;
                    overflow_seen <= 1'b0;

                    if (s_fire) begin
                        next_wr_count = '0;

                        for (lane = 0; lane < 8; lane++) begin
                            if (s_axis.tkeep[lane]) begin
                                if (next_wr_count < FRAME_BYTES) begin
                                    frame_buf[next_wr_count] <= s_axis.tdata[8*lane +: 8];
                                    next_wr_count = next_wr_count + 1'b1;
                                end else begin
                                    overflow_seen <= 1'b1;
                                end
                            end
                        end

                        wr_count <= next_wr_count;

                        if (s_axis.tlast) begin
                            st <= ST_PARSE;
                        end else begin
                            st <= ST_RECV;
                        end
                    end
                end

                // --------------------------------------------------------
                // Continue receiving frame beats
                // --------------------------------------------------------
                ST_RECV: begin
                    if (s_fire) begin
                        next_wr_count = wr_count;

                        for (lane = 0; lane < 8; lane++) begin
                            if (s_axis.tkeep[lane]) begin
                                if (next_wr_count < FRAME_BYTES) begin
                                    frame_buf[next_wr_count] <= s_axis.tdata[8*lane +: 8];
                                    next_wr_count = next_wr_count + 1'b1;
                                end else begin
                                    overflow_seen <= 1'b1;
                                end
                            end
                        end

                        wr_count <= next_wr_count;

                        if (s_axis.tlast) begin
                            st <= ST_PARSE;
                        end
                    end
                end

                // --------------------------------------------------------
                // Parse 32-byte frame
                // --------------------------------------------------------
                ST_PARSE: begin
                    // ----------------------------------------------------
                    // Check length first
                    // ----------------------------------------------------
                    length_bad = overflow_seen || (wr_count != FRAME_BYTES);

                    if (length_bad) begin
                        len_err <= 1'b1;
                        pkt_err <= 1'b1;

                    end else begin
                        // ------------------------------------------------
                        // Header fields
                        // ------------------------------------------------
                        dst_mac_tmp = {
                            frame_buf[0], frame_buf[1], frame_buf[2],
                            frame_buf[3], frame_buf[4], frame_buf[5]
                        };

                        src_mac_tmp = {
                            frame_buf[6], frame_buf[7], frame_buf[8],
                            frame_buf[9], frame_buf[10], frame_buf[11]
                        };

                        ether_type_tmp = {
                            frame_buf[12], frame_buf[13]
                        };

                        // ------------------------------------------------
                        // PTP-lite payload fields
                        //
                        // Payload begins at byte 14.
                        //
                        // Byte 14 : msg_type
                        // Byte 15 : version
                        // Byte 16 : seq_id[15:8]
                        // Byte 17 : seq_id[7:0]
                        // Byte 18 : flags
                        // Byte 19 : reserved
                        // Byte 20 : seconds[47:40]
                        // Byte 21 : seconds[39:32]
                        // Byte 22 : seconds[31:24]
                        // Byte 23 : seconds[23:16]
                        // Byte 24 : seconds[15:8]
                        // Byte 25 : seconds[7:0]
                        // Byte 26 : nanoseconds[31:24]
                        // Byte 27 : nanoseconds[23:16]
                        // Byte 28 : nanoseconds[15:8]
                        // Byte 29 : nanoseconds[7:0]
                        // Byte 30 : frac_ns[15:8]
                        // Byte 31 : frac_ns[7:0]
                        // ------------------------------------------------
                        msg_type_tmp = frame_buf[14];
                        version_tmp  = frame_buf[15];
                        seq_id_tmp   = {frame_buf[16], frame_buf[17]};
                        flags_tmp    = frame_buf[18];
                        reserved_tmp = frame_buf[19];

                        tx_tod_sec_tmp = {
                            frame_buf[20], frame_buf[21], frame_buf[22],
                            frame_buf[23], frame_buf[24], frame_buf[25]
                        };

                        tx_tod_nsec_tmp = {
                            frame_buf[26], frame_buf[27],
                            frame_buf[28], frame_buf[29]
                        };

                        tx_tod_frac_tmp = {
                            frame_buf[30], frame_buf[31]
                        };

                        // ------------------------------------------------
                        // Checks
                        // ------------------------------------------------
                        ether_type_bad = CHECK_ETHER_TYPE &&
                                         (ether_type_tmp != EXPECTED_ETHER_TYPE);

                        version_bad = CHECK_VERSION &&
                                      (version_tmp != EXPECTED_VERSION);

                        if (ether_type_bad) begin
                            ether_type_err <= 1'b1;
                            pkt_err        <= 1'b1;
                        end

                        if (version_bad) begin
                            version_err <= 1'b1;
                            pkt_err     <= 1'b1;
                        end

                        // ------------------------------------------------
                        // Update outputs regardless, so debug can see fields.
                        // Only pkt_valid indicates accepted packet.
                        // ------------------------------------------------
                        dst_mac    <= dst_mac_tmp;
                        src_mac    <= src_mac_tmp;
                        ether_type <= ether_type_tmp;

                        msg_type <= msg_type_tmp;
                        version  <= version_tmp;
                        seq_id   <= seq_id_tmp;
                        flags    <= flags_tmp;
                        reserved <= reserved_tmp;

                        tx_tod_sec  <= tx_tod_sec_tmp;
                        tx_tod_nsec <= tx_tod_nsec_tmp;
                        tx_tod_frac <= tx_tod_frac_tmp;

                        if (!ether_type_bad && !version_bad) begin
                            pkt_valid <= 1'b1;
                        end

                        pkt_done <= 1'b1;
                    end

                    st <= ST_IDLE;
                end

                default: begin
                    st <= ST_IDLE;
                end

            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Simulation-only checks
    // ------------------------------------------------------------------------
    // synthesis translate_off
`ifdef ASSERTIONS
    always_ff @(posedge clk or negedge rst_n) begin
        if (rst_n) begin
            if (s_fire && s_axis.tkeep == 8'h00) begin
                $error("packet_rx: accepted AXI beat with tkeep=0");
            end

            if (pkt_valid && pkt_err) begin
                $error("packet_rx: pkt_valid asserted while pkt_err is high");
            end

            if (pkt_valid && (tx_tod_nsec >= 32'd1_000_000_000)) begin
                $error("packet_rx: parsed nanoseconds out of range: %0d", tx_tod_nsec);
            end
        end
    end
`endif
    // synthesis translate_on

endmodule
