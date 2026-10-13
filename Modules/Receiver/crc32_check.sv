`timescale 1ns/1ps

module crc32_check (
    input  logic clk,
    input  logic rst_n,

    axi_stream_if.slave  s_axis,   // from pcs_rx: 38-byte frame including FCS
    axi_stream_if.master m_axis,   // to rx_deframer: 34-byte frame excluding FCS

    output logic crc_busy,
    output logic crc_ok,
    output logic crc_fail,
    output logic len_err
);

    // ------------------------------------------------------------------------
    // CRC-32 IEEE (reflected) -- must match crc_append_axis
    // ------------------------------------------------------------------------
    localparam logic [31:0] POLY_R = 32'hEDB88320;
    localparam logic [31:0] INIT   = 32'hFFFFFFFF;
    localparam logic [31:0] XOROUT = 32'hFFFFFFFF;

    localparam int IN_FRAME_BYTES  = 38; // 34-byte frame + 4-byte FCS
    localparam int OUT_FRAME_BYTES = 34; // frame without FCS

    typedef enum logic [1:0] {
        ST_IDLE  = 2'd0,
        ST_RECV  = 2'd1,
        ST_CHECK = 2'd2,
        ST_SEND  = 2'd3
    } state_t;

    state_t st;

    // ------------------------------------------------------------------------
    // Whole-frame storage
    // ------------------------------------------------------------------------
    logic [7:0] frame_buf [0:IN_FRAME_BYTES-1];

    logic [5:0] wr_count;       // number of bytes stored so far
    logic [5:0] rd_count;       // number of bytes sent so far
    logic       overflow_seen;  // too many input bytes

    // CRC bookkeeping / debug
    logic [31:0] crc_calc;
    logic [31:0] crc_recv;

    // AXI output holding register
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

    assign crc_busy = (st != ST_IDLE);

    // ------------------------------------------------------------------------
    // CRC helper function
    // ------------------------------------------------------------------------
    function automatic logic [31:0] step_byte(
        input logic [31:0] c,
        input logic [7:0]  d
    );
        logic [31:0] tmp;
        integer i;
        begin
            tmp = c ^ {24'h0, d};
            for (i = 0; i < 8; i = i + 1) begin
                if (tmp[0]) tmp = (tmp >> 1) ^ POLY_R;
                else        tmp = (tmp >> 1);
            end
            step_byte = tmp;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Input readiness
    // ------------------------------------------------------------------------
    always_comb begin
        s_axis.tready = 1'b0;

        unique case (st)
            ST_IDLE,
            ST_RECV:  s_axis.tready = 1'b1;
            default:  s_axis.tready = 1'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // Main sequential logic
    // ------------------------------------------------------------------------
    integer i;
    integer lane;

    logic [5:0]  next_wr_count;
    logic [31:0] calc_tmp;
    logic [31:0] recv_tmp;
    logic [63:0] send_data_tmp;
    logic [7:0]  send_keep_tmp;
    logic        send_last_tmp;
    logic [5:0]  bytes_left;
    logic [5:0]  send_n;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_IDLE;
            wr_count      <= 6'd0;
            rd_count      <= 6'd0;
            overflow_seen <= 1'b0;

            crc_calc <= 32'd0;
            crc_recv <= 32'd0;

            out_valid <= 1'b0;
            out_data  <= 64'd0;
            out_keep  <= 8'd0;
            out_last  <= 1'b0;

            crc_ok   <= 1'b0;
            crc_fail <= 1'b0;
            len_err  <= 1'b0;

            for (i = 0; i < IN_FRAME_BYTES; i = i + 1)
                frame_buf[i] <= 8'h00;

        end else begin
            // default pulse outputs low
            crc_ok   <= 1'b0;
            crc_fail <= 1'b0;
            len_err  <= 1'b0;

            // clear output beat after handshake
            if (m_fire) begin
                out_valid <= 1'b0;
                out_data  <= 64'd0;
                out_keep  <= 8'd0;
                out_last  <= 1'b0;
            end

            unique case (st)

                // ------------------------------------------------------------
                // Wait for start of a new AXI frame
                // ------------------------------------------------------------
                ST_IDLE: begin
                    wr_count      <= 6'd0;
                    rd_count      <= 6'd0;
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
                // Receive remaining AXI beats
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
                // Check total length and CRC
                // ------------------------------------------------------------
                ST_CHECK: begin
                    if (overflow_seen || (wr_count != IN_FRAME_BYTES)) begin
                        len_err  <= 1'b1;
                        crc_fail <= 1'b1;
                        st       <= ST_IDLE;
                    end else begin
                        calc_tmp = INIT;
                        for (i = 0; i < OUT_FRAME_BYTES; i = i + 1) begin
                            calc_tmp = step_byte(calc_tmp, frame_buf[i]);
                        end
                        calc_tmp = calc_tmp ^ XOROUT;

                        // Received FCS byte order from tx:
                        // lane0=crc[7:0], lane1=crc[15:8], lane2=crc[23:16], lane3=crc[31:24]
                        recv_tmp = {
                            frame_buf[37], // MSB
                            frame_buf[36],
                            frame_buf[35],
                            frame_buf[34]  // LSB
                        };

                        crc_calc <= calc_tmp;
                        crc_recv <= recv_tmp;

                        if (calc_tmp == recv_tmp) begin
                            crc_ok   <= 1'b1;
                            rd_count <= 6'd0;
                            st       <= ST_SEND;
                        end else begin
                            crc_fail <= 1'b1;
                            st       <= ST_IDLE;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Send validated 34-byte frame onward as AXI
                // ------------------------------------------------------------
                ST_SEND: begin
                    if (!out_valid) begin
                        send_data_tmp = 64'd0;
                        send_keep_tmp = 8'd0;
                        send_last_tmp = 1'b0;

                        bytes_left = OUT_FRAME_BYTES - rd_count;
                        if (bytes_left >= 6'd8) send_n = 6'd8;
                        else                    send_n = bytes_left;

                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            if (lane < send_n) begin
                                send_data_tmp[8*lane +: 8] = frame_buf[rd_count + lane];
                                send_keep_tmp[lane]        = 1'b1;
                            end
                        end

                        if ((rd_count + send_n) == OUT_FRAME_BYTES)
                            send_last_tmp = 1'b1;

                        out_valid <= 1'b1;
                        out_data  <= send_data_tmp;
                        out_keep  <= send_keep_tmp;
                        out_last  <= send_last_tmp;

                        rd_count <= rd_count + send_n;
                    end

                    if (m_fire && out_last) begin
                        st <= ST_IDLE;
                    end
                end

                default: begin
                    st <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
