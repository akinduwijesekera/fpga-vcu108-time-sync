`timescale 1ns/1ps

module crc_append_axis (
    input  logic clk,
    input  logic rst_n,

    // Input frame without FCS
    axi_stream_if.slave  s_axis,

    // Output frame with FCS appended
    axi_stream_if.master m_axis,

    output logic crc_busy,
    output logic crc_done
);

    // ------------------------------------------------------------
    // CRC-32 Ethernet / IEEE 802.3, reflected form
    //
    // Polynomial normal form : 0x04C11DB7
    // Reflected form         : 0xEDB88320
    // Init                   : 0xFFFFFFFF
    // Final XOR              : 0xFFFFFFFF
    //
    // Byte order:
    //   AXI lane 0 = tdata[7:0] is processed first.
    //   FCS is appended little-endian on the stream:
    //      lane 0 = crc_final[7:0]
    //      lane 1 = crc_final[15:8]
    //      lane 2 = crc_final[23:16]
    //      lane 3 = crc_final[31:24]
    // ------------------------------------------------------------
    localparam logic [31:0] POLY_R = 32'hEDB88320;
    localparam logic [31:0] INIT   = 32'hFFFF_FFFF;
    localparam logic [31:0] XOROUT = 32'hFFFF_FFFF;

    // ------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_PASS,
        ST_SENDCRC
    } state_t;

    state_t st, st_n;

    // ------------------------------------------------------------
    // Single-entry input buffer
    // ------------------------------------------------------------
    logic        buf_valid;
    logic [63:0] buf_data;
    logic [7:0]  buf_keep;
    logic        buf_last;

    // ------------------------------------------------------------
    // CRC registers
    // ------------------------------------------------------------
    logic [31:0] crc_reg;
    logic [31:0] crc_next_from_buf;
    logic [31:0] crc_final;

    // ------------------------------------------------------------
    // Done pulse
    // ------------------------------------------------------------
    logic crc_done_r;
    assign crc_done = crc_done_r;

    // ------------------------------------------------------------
    // Handshake signals
    // ------------------------------------------------------------
    logic s_fire;
    logic m_fire;

    assign s_fire = s_axis.tvalid && s_axis.tready;
    assign m_fire = m_axis.tvalid && m_axis.tready;

    assign crc_busy = (st != ST_IDLE) || buf_valid;

    // ------------------------------------------------------------
    // CRC helper: process one byte
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // CRC helper: process valid bytes in a 64-bit AXI beat
    //
    // Lane 0 is processed first:
    //   lane 0 = d[7:0]
    //   lane 1 = d[15:8]
    //   ...
    //   lane 7 = d[63:56]
    // ------------------------------------------------------------
    function automatic logic [31:0] step_keep64(
        input logic [31:0] c,
        input logic [63:0] d,
        input logic [7:0]  k
    );
        logic [31:0] tmp;
        int i;
        begin
            tmp = c;

            for (i = 0; i < 8; i++) begin
                if (k[i]) begin
                    tmp = step_byte(tmp, d[8*i +: 8]);
                end
            end

            return tmp;
        end
    endfunction

    // ------------------------------------------------------------
    // CRC next calculation
    // ------------------------------------------------------------
    always_comb begin
        crc_next_from_buf = step_keep64(crc_reg, buf_data, buf_keep);
    end

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st         <= ST_IDLE;

            buf_valid  <= 1'b0;
            buf_data   <= 64'd0;
            buf_keep   <= 8'd0;
            buf_last   <= 1'b0;

            crc_reg    <= INIT;
            crc_final  <= 32'd0;

            crc_done_r <= 1'b0;

        end else begin
            st <= st_n;

            // Default: no done pulse
            crc_done_r <= 1'b0;

            // ----------------------------------------------------
            // Capture input beat into the single-entry buffer
            // ----------------------------------------------------
            if (s_fire) begin
                buf_valid <= 1'b1;
                buf_data  <= s_axis.tdata;
                buf_keep  <= s_axis.tkeep;
                buf_last  <= s_axis.tlast;
            end

            // ----------------------------------------------------
            // Reset CRC at the first accepted beat of a frame
            // ----------------------------------------------------
            if (st == ST_IDLE && s_fire) begin
                crc_reg <= INIT;
            end

            // ----------------------------------------------------
            // When a buffered beat is accepted by the output,
            // update CRC using the exact data that was forwarded.
            // ----------------------------------------------------
            if (st == ST_PASS && buf_valid && m_fire) begin
                crc_reg <= crc_next_from_buf;

                if (buf_last) begin
                    crc_final <= crc_next_from_buf ^ XOROUT;
                end

                buf_valid <= 1'b0;
            end

            // ----------------------------------------------------
            // CRC beat accepted: frame complete
            // ----------------------------------------------------
            if (st == ST_SENDCRC && m_fire) begin
                crc_done_r <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------
    // Combinational ready/valid and next-state logic
    // ------------------------------------------------------------
    always_comb begin
        st_n = st;

        s_axis.tready = 1'b0;

        m_axis.tvalid = 1'b0;
        m_axis.tdata  = 64'd0;
        m_axis.tkeep  = 8'h00;
        m_axis.tlast  = 1'b0;

        unique case (st)

            // ----------------------------------------------------
            // Wait for first frame beat
            // ----------------------------------------------------
            ST_IDLE: begin
                s_axis.tready = !buf_valid;

                if (s_fire) begin
                    st_n = ST_PASS;
                end
            end

            // ----------------------------------------------------
            // Pass all input data beats through.
            // The input TLAST is suppressed because the CRC beat
            // becomes the real final output beat.
            // ----------------------------------------------------
            ST_PASS: begin
                s_axis.tready = !buf_valid;

                if (buf_valid) begin
                    m_axis.tvalid = 1'b1;
                    m_axis.tdata  = buf_data;
                    m_axis.tkeep  = buf_keep;
                    m_axis.tlast  = 1'b0;

                    if (m_fire && buf_last) begin
                        st_n = ST_SENDCRC;
                    end
                end
            end

            // ----------------------------------------------------
            // Append 32-bit FCS in AXI lanes 0..3
            // ----------------------------------------------------
            ST_SENDCRC: begin
                m_axis.tvalid = 1'b1;
                m_axis.tkeep  = 8'h0F;
                m_axis.tlast  = 1'b1;

                m_axis.tdata = {
                    32'h0000_0000,
                    crc_final[31:24],
                    crc_final[23:16],
                    crc_final[15:8],
                    crc_final[7:0]
                };

                if (m_fire) begin
                    st_n = ST_IDLE;
                end
            end

            default: begin
                st_n = ST_IDLE;
            end

        endcase
    end

    // ------------------------------------------------------------
    // Simulation-only checks
    // ------------------------------------------------------------
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
            // AXI stability check:
            // if valid was high and ready was low last cycle,
            // data/control must be stable this cycle.
            if (prev_m_stalled) begin
                if (m_axis.tvalid !== prev_m_tvalid ||
                    m_axis.tdata  !== prev_m_tdata  ||
                    m_axis.tkeep  !== prev_m_tkeep  ||
                    m_axis.tlast  !== prev_m_tlast) begin
                    $error("crc_append_axis: AXI output changed while stalled");
                end
            end

            prev_m_tdata   <= m_axis.tdata;
            prev_m_tkeep   <= m_axis.tkeep;
            prev_m_tlast   <= m_axis.tlast;
            prev_m_tvalid  <= m_axis.tvalid;
            prev_m_stalled <= m_axis.tvalid && !m_axis.tready;

            if (s_fire && s_axis.tkeep == 8'h00) begin
                $error("crc_append_axis: accepted beat with tkeep=0");
            end
        end
    end
`endif
    // synthesis translate_on

endmodule
