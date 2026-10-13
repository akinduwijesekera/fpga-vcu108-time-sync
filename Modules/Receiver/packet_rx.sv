`timescale 1ns/1ps

module packet_rx (
    input  logic clk,
    input  logic rst_n,

    axi_stream_if.slave s_axis,   // 20-byte payload from rx_deframer

    output logic [7:0]  msg_type,
    output logic [7:0]  version,
    output logic [15:0] seq_id,
    output logic [7:0]  flags,
    output logic [23:0] reserved,
    output logic [47:0] tod_sec,
    output logic [31:0] tod_nsec,
    output logic [15:0] tod_frac,

    output logic        pkt_valid,   // pulses when a valid payload is parsed
    output logic        pkt_done,    // pulses when final beat received and parsed
    output logic        len_err,     // wrong payload length
    output logic        pr_busy
);

    localparam int PAYLOAD_BYTES = 20;

    typedef enum logic [1:0] {
        ST_IDLE  = 2'd0,
        ST_RECV  = 2'd1,
        ST_PARSE = 2'd2
    } state_t;

    state_t st;

    // ------------------------------------------------------------------------
    // Payload storage
    // ------------------------------------------------------------------------
    logic [7:0] payload_buf [0:PAYLOAD_BYTES-1];

    logic [5:0] wr_count;
    logic       overflow_seen;

    wire s_fire = s_axis.tvalid && s_axis.tready;

    // ------------------------------------------------------------------------
    // Input ready
    // ------------------------------------------------------------------------
    always_comb begin
        s_axis.tready = 1'b0;

        unique case (st)
            ST_IDLE,
            ST_RECV: s_axis.tready = 1'b1;
            default: s_axis.tready = 1'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // Main logic
    // ------------------------------------------------------------------------
    integer i;
    integer lane;

    logic [5:0] next_wr_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_IDLE;
            wr_count      <= 6'd0;
            overflow_seen <= 1'b0;

            msg_type <= 8'd0;
            version  <= 8'd0;
            seq_id   <= 16'd0;
            flags    <= 8'd0;
            reserved <= 24'd0;
            tod_sec  <= 48'd0;
            tod_nsec <= 32'd0;
            tod_frac <= 16'd0;

            pkt_valid <= 1'b0;
            pkt_done  <= 1'b0;
            len_err   <= 1'b0;
            pr_busy   <= 1'b0;

            for (i = 0; i < PAYLOAD_BYTES; i = i + 1)
                payload_buf[i] <= 8'h00;

        end else begin
            // default pulse outputs low
            pkt_valid <= 1'b0;
            pkt_done  <= 1'b0;
            len_err   <= 1'b0;

            pr_busy <= (st != ST_IDLE);

            unique case (st)

                // ------------------------------------------------------------
                // Wait for first beat of a new payload
                // ------------------------------------------------------------
                ST_IDLE: begin
                    wr_count      <= 6'd0;
                    overflow_seen <= 1'b0;

                    if (s_fire) begin
                        next_wr_count = 6'd0;

                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            if (s_axis.tkeep[lane]) begin
                                if (next_wr_count < PAYLOAD_BYTES) begin
                                    payload_buf[next_wr_count] <= s_axis.tdata[8*lane +: 8];
                                    next_wr_count = next_wr_count + 6'd1;
                                end else begin
                                    overflow_seen <= 1'b1;
                                end
                            end
                        end

                        wr_count <= next_wr_count;

                        if (s_axis.tlast) st <= ST_PARSE;
                        else              st <= ST_RECV;
                    end
                end

                // ------------------------------------------------------------
                // Continue receiving payload beats
                // ------------------------------------------------------------
                ST_RECV: begin
                    if (s_fire) begin
                        next_wr_count = wr_count;

                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            if (s_axis.tkeep[lane]) begin
                                if (next_wr_count < PAYLOAD_BYTES) begin
                                    payload_buf[next_wr_count] <= s_axis.tdata[8*lane +: 8];
                                    next_wr_count = next_wr_count + 6'd1;
                                end else begin
                                    overflow_seen <= 1'b1;
                                end
                            end
                        end

                        wr_count <= next_wr_count;

                        if (s_axis.tlast)
                            st <= ST_PARSE;
                    end
                end

                // ------------------------------------------------------------
                // Parse 20-byte payload
                // ------------------------------------------------------------
                ST_PARSE: begin
                    if (overflow_seen || (wr_count != PAYLOAD_BYTES)) begin
                        len_err <= 1'b1;
                    end else begin
                        // Byte layout matches packet_tx exactly:
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

                        msg_type <= payload_buf[0];
                        version  <= payload_buf[1];
                        seq_id   <= {payload_buf[2], payload_buf[3]};
                        flags    <= payload_buf[4];
                        reserved <= {payload_buf[5], payload_buf[6], payload_buf[7]};
                        tod_sec  <= {
                            payload_buf[8],  payload_buf[9],  payload_buf[10],
                            payload_buf[11], payload_buf[12], payload_buf[13]
                        };
                        tod_nsec <= {
                            payload_buf[14], payload_buf[15],
                            payload_buf[16], payload_buf[17]
                        };
                        tod_frac <= {payload_buf[18], payload_buf[19]};

                        pkt_valid <= 1'b1;
                        pkt_done  <= 1'b1;
                    end

                    st <= ST_IDLE;
                end

                default: begin
                    st <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
