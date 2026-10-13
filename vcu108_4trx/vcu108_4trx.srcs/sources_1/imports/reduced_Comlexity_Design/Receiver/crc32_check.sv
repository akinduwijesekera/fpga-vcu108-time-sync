`timescale 1ns/1ps

module crc32_check #(
    parameter int OUT_FRAME_BYTES = 32,
    parameter int FCS_BYTES       = 4
)(
    input  logic clk,
    input  logic rst_n,

    axi_stream_if.slave  s_axis,
    axi_stream_if.master m_axis,

    output logic crc_busy,
    output logic crc_ok,
    output logic crc_fail,
    output logic len_err
);

    localparam int IN_FRAME_BYTES = OUT_FRAME_BYTES + FCS_BYTES;
    localparam int IN_BEATS       = (IN_FRAME_BYTES + 7) / 8;   // 36 bytes -> 5 beats
    localparam int OUT_BEATS      = (OUT_FRAME_BYTES + 7) / 8;  // 32 bytes -> 4 beats

    localparam int IN_BEAT_W      = $clog2(IN_BEATS + 1);
    localparam int OUT_BEAT_W     = $clog2(OUT_BEATS + 1);
    localparam int CRC_IDX_W      = $clog2(OUT_FRAME_BYTES + 1);

    localparam logic [31:0] POLY_R = 32'hEDB88320;
    localparam logic [31:0] INIT   = 32'hFFFF_FFFF;
    localparam logic [31:0] XOROUT = 32'hFFFF_FFFF;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_RECV,
        ST_CRC_INIT,
        ST_CRC_STEP,
        ST_CHECK,
        ST_SEND
    } state_t;

    state_t st;

    // ------------------------------------------------------------------------
    // Store frame as AXI beats rather than individual bytes
    // ------------------------------------------------------------------------
    logic [63:0] beat_data [0:IN_BEATS-1];
    logic [7:0]  beat_keep [0:IN_BEATS-1];
    logic        beat_last [0:IN_BEATS-1];

    logic [IN_BEAT_W-1:0]  wr_beat;
    logic [OUT_BEAT_W-1:0] rd_beat;
    logic [CRC_IDX_W-1:0]  crc_idx;

    logic overflow_seen;
    logic format_err_seen;

    logic [31:0] crc_reg;
    logic [31:0] crc_calc;
    logic [31:0] crc_recv;

    logic        out_valid;
    logic [63:0] out_data;
    logic [7:0]  out_keep;
    logic        out_last;

    assign m_axis.tvalid = out_valid;
    assign m_axis.tdata  = out_data;
    assign m_axis.tkeep  = out_keep;
    assign m_axis.tlast  = out_last;

    logic s_fire;
    logic m_fire;

    assign s_fire = s_axis.tvalid && s_axis.tready;
    assign m_fire = m_axis.tvalid && m_axis.tready;

    assign crc_busy = (st != ST_IDLE);

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
    // CRC helper
    // ------------------------------------------------------------------------
    function automatic logic [31:0] step_byte(
        input logic [31:0] c,
        input logic [7:0]  d
    );
        logic [31:0] tmp;
        int i;
        begin
            tmp = c ^ {24'h0, d};

            for (i = 0; i < 8; i++) begin
                if (tmp[0]) begin
                    tmp = (tmp >> 1) ^ POLY_R;
                end else begin
                    tmp = (tmp >> 1);
                end
            end

            return tmp;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Byte access from beat storage
    // ------------------------------------------------------------------------
    function automatic logic [7:0] get_frame_byte(
        input logic [CRC_IDX_W-1:0] idx
    );
        logic [2:0] lane;
        logic [IN_BEAT_W-1:0] beat;
        begin
            beat = idx[CRC_IDX_W-1:3];
            lane = idx[2:0];
            get_frame_byte = beat_data[beat][8*lane +: 8];
        end
    endfunction

    integer i;

    logic [31:0] recv_tmp;

    // ------------------------------------------------------------------------
    // Main sequential logic
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st              <= ST_IDLE;

            wr_beat         <= '0;
            rd_beat         <= '0;
            crc_idx         <= '0;

            overflow_seen   <= 1'b0;
            format_err_seen <= 1'b0;

            crc_reg         <= INIT;
            crc_calc        <= 32'd0;
            crc_recv        <= 32'd0;

            out_valid       <= 1'b0;
            out_data        <= 64'd0;
            out_keep        <= 8'd0;
            out_last        <= 1'b0;

            crc_ok          <= 1'b0;
            crc_fail        <= 1'b0;
            len_err         <= 1'b0;

            for (i = 0; i < IN_BEATS; i++) begin
                beat_data[i] <= 64'd0;
                beat_keep[i] <= 8'd0;
                beat_last[i] <= 1'b0;
            end

        end else begin
            crc_ok   <= 1'b0;
            crc_fail <= 1'b0;
            len_err  <= 1'b0;

            if (m_fire) begin
                out_valid <= 1'b0;
                out_data  <= 64'd0;
                out_keep  <= 8'd0;
                out_last  <= 1'b0;
            end

            unique case (st)

                // ------------------------------------------------------------
                // Wait for first input beat
                // ------------------------------------------------------------
                ST_IDLE: begin
                    wr_beat         <= '0;
                    rd_beat         <= '0;
                    crc_idx         <= '0;
                    overflow_seen   <= 1'b0;
                    format_err_seen <= 1'b0;
                    crc_reg         <= INIT;

                    if (s_fire) begin
                        beat_data[0] <= s_axis.tdata;
                        beat_keep[0] <= s_axis.tkeep;
                        beat_last[0] <= s_axis.tlast;

                        // For this reduced fixed frame, first four beats should be full.
                        if (s_axis.tkeep != 8'hFF) begin
                            format_err_seen <= 1'b1;
                        end

                        if (s_axis.tlast) begin
                            // A complete 36-byte frame cannot end on beat 0.
                            format_err_seen <= 1'b1;
                            st <= ST_CRC_INIT;
                        end else begin
                            wr_beat <= 1;
                            st      <= ST_RECV;
                        end
                    end
                end

                // ------------------------------------------------------------
                // Receive remaining beats
                // ------------------------------------------------------------
                ST_RECV: begin
                    if (s_fire) begin
                        if (wr_beat < IN_BEATS) begin
                            beat_data[wr_beat] <= s_axis.tdata;
                            beat_keep[wr_beat] <= s_axis.tkeep;
                            beat_last[wr_beat] <= s_axis.tlast;

                            if (wr_beat < OUT_BEATS) begin
                                if (s_axis.tkeep != 8'hFF) begin
                                    format_err_seen <= 1'b1;
                                end

                                if (s_axis.tlast) begin
                                    format_err_seen <= 1'b1;
                                    st <= ST_CRC_INIT;
                                end else begin
                                    wr_beat <= wr_beat + 1'b1;
                                end
                            end else begin
                                // Final beat should contain only 4 FCS bytes.
                                if (s_axis.tkeep != 8'h0F) begin
                                    format_err_seen <= 1'b1;
                                end

                                if (!s_axis.tlast) begin
                                    format_err_seen <= 1'b1;
                                end

                                st <= ST_CRC_INIT;
                            end
                        end else begin
                            overflow_seen <= 1'b1;

                            if (s_axis.tlast) begin
                                st <= ST_CRC_INIT;
                            end
                        end
                    end
                end

                // ------------------------------------------------------------
                // Validate received frame shape
                // ------------------------------------------------------------
                ST_CRC_INIT: begin
                    if (overflow_seen || format_err_seen) begin
                        len_err  <= 1'b1;
                        crc_fail <= 1'b1;
                        st       <= ST_IDLE;
                    end else begin
                        crc_reg <= INIT;
                        crc_idx <= '0;
                        st      <= ST_CRC_STEP;
                    end
                end

                // ------------------------------------------------------------
                // CRC over one payload/frame byte per cycle
                // ------------------------------------------------------------
                ST_CRC_STEP: begin
                    crc_reg <= step_byte(crc_reg, get_frame_byte(crc_idx));

                    if (crc_idx == OUT_FRAME_BYTES - 1) begin
                        st <= ST_CHECK;
                    end else begin
                        crc_idx <= crc_idx + 1'b1;
                    end
                end

                // ------------------------------------------------------------
                // Compare calculated CRC to received FCS
                // ------------------------------------------------------------
                ST_CHECK: begin
                    crc_calc <= crc_reg ^ XOROUT;

                    recv_tmp = beat_data[OUT_BEATS][31:0];

                    crc_recv <= recv_tmp;

                    if ((crc_reg ^ XOROUT) == recv_tmp) begin
                        crc_ok  <= 1'b1;
                        rd_beat <= '0;
                        st      <= ST_SEND;
                    end else begin
                        crc_fail <= 1'b1;
                        st       <= ST_IDLE;
                    end
                end

                // ------------------------------------------------------------
                // Send four full output beats excluding FCS
                // ------------------------------------------------------------
                ST_SEND: begin
                    if (!out_valid) begin
                        out_valid <= 1'b1;
                        out_data  <= beat_data[rd_beat];
                        out_keep  <= 8'hFF;
                        out_last  <= (rd_beat == OUT_BEATS - 1);

                        if (rd_beat == OUT_BEATS - 1) begin
                            rd_beat <= '0;
                        end else begin
                            rd_beat <= rd_beat + 1'b1;
                        end
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

    // ------------------------------------------------------------------------
    // Simulation-only checks
    // ------------------------------------------------------------------------
    // synthesis translate_off
`ifdef ASSERTIONS
    logic [63:0] prev_m_tdata;
    logic [7:0]  prev_m_tkeep;
    logic        prev_m_tlast;
    logic        prev_m_tvalid;
    logic        prev_m_stalled;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_m_tdata   <= 64'd0;
            prev_m_tkeep   <= 8'd0;
            prev_m_tlast   <= 1'b0;
            prev_m_tvalid  <= 1'b0;
            prev_m_stalled <= 1'b0;
        end else begin
            if (prev_m_stalled) begin
                if (m_axis.tvalid !== prev_m_tvalid ||
                    m_axis.tdata  !== prev_m_tdata  ||
                    m_axis.tkeep  !== prev_m_tkeep  ||
                    m_axis.tlast  !== prev_m_tlast) begin
                    $error("crc32_check: AXI output changed while stalled");
                end
            end

            prev_m_tdata   <= m_axis.tdata;
            prev_m_tkeep   <= m_axis.tkeep;
            prev_m_tlast   <= m_axis.tlast;
            prev_m_tvalid  <= m_axis.tvalid;
            prev_m_stalled <= m_axis.tvalid && !m_axis.tready;

            if (s_fire && s_axis.tkeep == 8'h00) begin
                $error("crc32_check: accepted input beat with tkeep=0");
            end

            if (m_axis.tvalid && m_axis.tkeep == 8'h00) begin
                $error("crc32_check: generated output beat with tkeep=0");
            end
        end
    end
`endif
    // synthesis translate_on

endmodule
