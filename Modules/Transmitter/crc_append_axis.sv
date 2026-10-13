`timescale 1ns/1ps

module crc_append_axis (
    input  logic clk,
    input  logic rst_n,

    axi_stream_if.slave  s_axis,  // framed in (from tx_framer)
    axi_stream_if.master m_axis,  // framed out + FCS appended

    output logic crc_busy,
    output logic crc_done
);

    // CRC-32 IEEE (reflected)
    localparam logic [31:0] POLY_R  = 32'hEDB88320;
    localparam logic [31:0] INIT    = 32'hFFFFFFFF;
    localparam logic [31:0] XOROUT  = 32'hFFFFFFFF;

    typedef enum logic [1:0] {ST_IDLE, ST_PASS, ST_SENDCRC} state_t;
    state_t st, st_n;

    // Single-entry buffer (to handle backpressure cleanly)
    logic        buf_valid;
    logic [63:0] buf_data;
    logic [7:0]  buf_keep;
    logic        buf_last;

    // CRC regs
    logic [31:0] crc_reg;
    logic [31:0] crc_final;   // already XORed with XOROUT

    // done pulse
    logic crc_done_r;
    assign crc_done = crc_done_r;

    // Handshake
    wire m_fire = m_axis.tvalid && m_axis.tready;
    wire s_fire = s_axis.tvalid && s_axis.tready;

    // Busy
    assign crc_busy = (st != ST_IDLE) || buf_valid;

    // ----------------------------
    // CRC helper functions
    // ----------------------------
    function automatic logic [31:0] step_byte(input logic [31:0] c, input logic [7:0] d);
        logic [31:0] tmp;
        int i;
        begin
            // reflected CRC: xor byte into low 8 bits
            tmp = c ^ {24'h0, d};
            for (i = 0; i < 8; i++) begin
                if (tmp[0]) tmp = (tmp >> 1) ^ POLY_R;
                else        tmp = (tmp >> 1);
            end
            return tmp;
        end
    endfunction

    // Process bytes lane0..lane7 where keep bit is set (lane0 = d[7:0])
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
                if (k[i]) tmp = step_byte(tmp, d[8*i +: 8]);
            end
            return tmp;
        end
    endfunction

    // ----------------------------
    // Sequential: state + buffer + CRC
    // ----------------------------
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

            // default: no done pulse
            crc_done_r <= 1'b0;

            // Capture into buffer when we accept from s_axis
            if (s_fire) begin
                buf_valid <= 1'b1;
                buf_data  <= s_axis.tdata;
                buf_keep  <= s_axis.tkeep;
                buf_last  <= s_axis.tlast;
            end

            // Start-of-frame: first accepted beat in IDLE resets CRC to INIT
            if (st == ST_IDLE && s_fire) begin
                crc_reg <= INIT;
            end

            // When we forward a buffered beat, update CRC based on what was ACTUALLY sent
            if (st == ST_PASS && buf_valid && m_fire) begin
                logic [31:0] crc_next;
                crc_next = step_keep64(crc_reg, buf_data, buf_keep);

                // If that beat was last (input-last), latch final CRC (XOROUT applied)
                if (buf_last) begin
                    crc_final <= crc_next ^ XOROUT;
                end

                crc_reg   <= crc_next;
                buf_valid <= 1'b0; // consumed
            end

            // When we finish sending CRC beat
            if (st == ST_SENDCRC && m_fire) begin
                crc_done_r <= 1'b1;
            end
        end
    end

    // ----------------------------
    // Combinational: ready/valid + next state
    // ----------------------------
    always_comb begin
        st_n = st;

        // Defaults
        s_axis.tready = 1'b0;

        m_axis.tvalid = 1'b0;
        m_axis.tdata  = 64'd0;
        m_axis.tkeep  = 8'h00;
        m_axis.tlast  = 1'b0;

        unique case (st)

            ST_IDLE: begin
                // ready to accept first beat of a frame if buffer is empty
                s_axis.tready = !buf_valid;

                if (s_fire) begin
                    st_n = ST_PASS;
                end
            end

            ST_PASS: begin
                // Accept next input beat if buffer empty
                s_axis.tready = !buf_valid;

                // Drive output from buffer (if present)
                if (buf_valid) begin
                    m_axis.tvalid = 1'b1;
                    m_axis.tdata  = buf_data;
                    m_axis.tkeep  = buf_keep;

                    // AXI-nicer: suppress TLAST on the final DATA beat because we will append CRC.
                    // Only the CRC beat will have TLAST=1.
                    m_axis.tlast  = 1'b0;

                    // If we just forwarded the last data beat, send CRC next
                    if (m_fire && buf_last) begin
                        st_n = ST_SENDCRC;
                    end
                end
            end

            ST_SENDCRC: begin
                // Output CRC as 4 bytes in lanes 0..3 (LSB-first on stream)
                m_axis.tvalid = 1'b1;
                m_axis.tkeep  = 8'h0F;
                m_axis.tlast  = 1'b1;

                // lane0 = crc[7:0], lane1 = crc[15:8], lane2 = crc[23:16], lane3 = crc[31:24]
                m_axis.tdata = {
                    32'h0000_0000,
                    crc_final[31:24], crc_final[23:16], crc_final[15:8], crc_final[7:0]
                };

                if (m_fire) begin
                    st_n = ST_IDLE;
                end
            end

            default: st_n = ST_IDLE;
        endcase
    end

endmodule
