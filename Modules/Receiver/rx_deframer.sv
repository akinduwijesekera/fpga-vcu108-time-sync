`timescale 1ns/1ps

module rx_deframer #(
    parameter logic [15:0] EXPECTED_ETYPE = 16'h88B5
)(
    input  logic clk,
    input  logic rst_n,

    axi_stream_if.slave  s_axis,   // validated 34-byte frame from crc32_check
    axi_stream_if.master m_axis,   // 20-byte payload out

    output logic [47:0] dst_mac_out,
    output logic [47:0] src_mac_out,
    output logic [15:0] ether_type_out,

    output logic        hdr_valid,
    output logic        etype_ok,
    output logic        etype_err,
    output logic        len_err,
    output logic        df_busy,
    output logic        df_done
);

    localparam int IN_FRAME_BYTES = 34;
    localparam int PAYLOAD_BYTES  = 20;

    typedef enum logic [2:0] {
        ST_IDLE   = 3'd0,
        ST_RECV   = 3'd1,
        ST_CHECK  = 3'd2,
        ST_SEND0  = 3'd3,
        ST_SEND1  = 3'd4,
        ST_SEND2  = 3'd5
    } state_t;

    state_t st;

    // ------------------------------------------------------------------------
    // Full validated frame buffer
    // bytes  0.. 5 = dst mac
    // bytes  6..11 = src mac
    // bytes 12..13 = ether type
    // bytes 14..33 = payload (20B)
    // ------------------------------------------------------------------------
    logic [7:0] frame_buf [0:IN_FRAME_BYTES-1];

    logic [5:0] wr_count;
    logic       overflow_seen;

    // latched parsed header
    logic [47:0] dst_mac_l;
    logic [47:0] src_mac_l;
    logic [15:0] ether_type_l;

    // output holding register
    logic        out_valid;
    logic [63:0] out_data;
    logic [7:0]  out_keep;
    logic        out_last;

    wire s_fire = s_axis.tvalid && s_axis.tready;
    wire m_fire = m_axis.tvalid && m_axis.tready;

    assign m_axis.tvalid = out_valid;
    assign m_axis.tdata  = out_data;
    assign m_axis.tkeep  = out_keep;
    assign m_axis.tlast  = out_last;

    assign dst_mac_out    = dst_mac_l;
    assign src_mac_out    = src_mac_l;
    assign ether_type_out = ether_type_l;

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

    logic [5:0]  next_wr_count;
    logic [63:0] send_data_tmp;
    logic [7:0]  send_keep_tmp;
    logic        send_last_tmp;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_IDLE;
            wr_count      <= 6'd0;
            overflow_seen <= 1'b0;

            dst_mac_l    <= 48'd0;
            src_mac_l    <= 48'd0;
            ether_type_l <= 16'd0;

            out_valid <= 1'b0;
            out_data  <= 64'd0;
            out_keep  <= 8'd0;
            out_last  <= 1'b0;

            hdr_valid <= 1'b0;
            etype_ok  <= 1'b0;
            etype_err <= 1'b0;
            len_err   <= 1'b0;
            df_done   <= 1'b0;
            df_busy   <= 1'b0;

            for (i = 0; i < IN_FRAME_BYTES; i = i + 1)
                frame_buf[i] <= 8'h00;

        end else begin
            // default pulse outputs low
            hdr_valid <= 1'b0;
            etype_ok  <= 1'b0;
            etype_err <= 1'b0;
            len_err   <= 1'b0;
            df_done   <= 1'b0;

            df_busy   <= (st != ST_IDLE);

            // clear output beat after handshake
            if (m_fire) begin
                out_valid <= 1'b0;
                out_data  <= 64'd0;
                out_keep  <= 8'd0;
                out_last  <= 1'b0;
            end

            unique case (st)

                // ------------------------------------------------------------
                // Wait for first beat of a validated 34-byte frame
                // ------------------------------------------------------------
                ST_IDLE: begin
                    wr_count      <= 6'd0;
                    overflow_seen <= 1'b0;

                    if (s_fire) begin
                        next_wr_count = 6'd0;

                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            if (s_axis.tkeep[lane]) begin
                                if (next_wr_count < IN_FRAME_BYTES) begin
                                    frame_buf[next_wr_count] <= s_axis.tdata[8*lane +: 8];
                                    next_wr_count = next_wr_count + 6'd1;
                                end else begin
                                    overflow_seen <= 1'b1;
                                end
                            end
                        end

                        wr_count <= next_wr_count;

                        if (s_axis.tlast) st <= ST_CHECK;
                        else              st <= ST_RECV;
                    end
                end

                // ------------------------------------------------------------
                // Continue receiving remaining frame beats
                // ------------------------------------------------------------
                ST_RECV: begin
                    if (s_fire) begin
                        next_wr_count = wr_count;

                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            if (s_axis.tkeep[lane]) begin
                                if (next_wr_count < IN_FRAME_BYTES) begin
                                    frame_buf[next_wr_count] <= s_axis.tdata[8*lane +: 8];
                                    next_wr_count = next_wr_count + 6'd1;
                                end else begin
                                    overflow_seen <= 1'b1;
                                end
                            end
                        end

                        wr_count <= next_wr_count;

                        if (s_axis.tlast)
                            st <= ST_CHECK;
                    end
                end

                // ------------------------------------------------------------
                // Check length, parse header, verify EtherType
                // ------------------------------------------------------------
                ST_CHECK: begin
                    if (overflow_seen || (wr_count != IN_FRAME_BYTES)) begin
                        len_err <= 1'b1;
                        st      <= ST_IDLE;
                    end else begin
                        // Parse header exactly matching tx_framer byte order
                        dst_mac_l <= {
                            frame_buf[0], frame_buf[1], frame_buf[2],
                            frame_buf[3], frame_buf[4], frame_buf[5]
                        };

                        src_mac_l <= {
                            frame_buf[6], frame_buf[7], frame_buf[8],
                            frame_buf[9], frame_buf[10], frame_buf[11]
                        };

                        ether_type_l <= {frame_buf[12], frame_buf[13]};

                        hdr_valid <= 1'b1;

                        if ({frame_buf[12], frame_buf[13]} == EXPECTED_ETYPE) begin
                            etype_ok <= 1'b1;
                            st       <= ST_SEND0;
                        end else begin
                            etype_err <= 1'b1;
                            st        <= ST_IDLE;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Send payload bytes 14..21 => payload[0..7]
                // ------------------------------------------------------------
                ST_SEND0: begin
                    if (!out_valid) begin
                        send_data_tmp = {
                            frame_buf[21], frame_buf[20], frame_buf[19], frame_buf[18],
                            frame_buf[17], frame_buf[16], frame_buf[15], frame_buf[14]
                        };
                        send_keep_tmp = 8'hFF;
                        send_last_tmp = 1'b0;

                        out_valid <= 1'b1;
                        out_data  <= send_data_tmp;
                        out_keep  <= send_keep_tmp;
                        out_last  <= send_last_tmp;
                    end

                    if (m_fire)
                        st <= ST_SEND1;
                end

                // ------------------------------------------------------------
                // Send payload bytes 22..29 => payload[8..15]
                // ------------------------------------------------------------
                ST_SEND1: begin
                    if (!out_valid) begin
                        send_data_tmp = {
                            frame_buf[29], frame_buf[28], frame_buf[27], frame_buf[26],
                            frame_buf[25], frame_buf[24], frame_buf[23], frame_buf[22]
                        };
                        send_keep_tmp = 8'hFF;
                        send_last_tmp = 1'b0;

                        out_valid <= 1'b1;
                        out_data  <= send_data_tmp;
                        out_keep  <= send_keep_tmp;
                        out_last  <= send_last_tmp;
                    end

                    if (m_fire)
                        st <= ST_SEND2;
                end

                // ------------------------------------------------------------
                // Send payload bytes 30..33 => payload[16..19]
                // ------------------------------------------------------------
                ST_SEND2: begin
                    if (!out_valid) begin
                        send_data_tmp = {
                            32'h00000000,
                            frame_buf[33], frame_buf[32], frame_buf[31], frame_buf[30]
                        };
                        send_keep_tmp = 8'h0F;
                        send_last_tmp = 1'b1;

                        out_valid <= 1'b1;
                        out_data  <= send_data_tmp;
                        out_keep  <= send_keep_tmp;
                        out_last  <= send_last_tmp;
                    end

                    if (m_fire) begin
                        df_done <= 1'b1;
                        st      <= ST_IDLE;
                    end
                end

                default: begin
                    st <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
