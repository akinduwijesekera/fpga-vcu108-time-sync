`timescale 1ns/1ps

module axis64_to_sym8 (
    input  logic clk,
    input  logic rst_n,

    axi_stream_if.slave  s_axis,
    sym_stream_if.source sym
);

    // -------------------------------------------------------------------------
    // 8b/10b control symbol byte values
    // -------------------------------------------------------------------------
    localparam logic [7:0] K_IDLE  = 8'hBC; // K28.5
    localparam logic [7:0] K_START = 8'hFB; // K27.7
    localparam logic [7:0] K_END   = 8'hFD; // K29.7

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_START,
        ST_DATA,
        ST_END
    } state_t;

    state_t st;

    // -------------------------------------------------------------------------
    // One AXI beat buffer
    // -------------------------------------------------------------------------
    logic        buf_valid;
    logic [63:0] buf_data;
    logic [7:0]  buf_keep;
    logic        buf_last;

    // Byte scanning
    logic [2:0] ptr;
    logic [2:0] sel;
    logic       found;

    logic [7:0] sel_mask;
    logic [7:0] keep_after_clear;
    logic [7:0] sel_byte;

    // -------------------------------------------------------------------------
    // Find next valid byte from buf_keep starting at ptr
    // -------------------------------------------------------------------------
    always_comb begin
        found = 1'b0;
        sel   = 3'd0;

        for (int i = 0; i < 8; i++) begin
            if (!found && (i >= ptr) && buf_keep[i]) begin
                found = 1'b1;
                sel   = i[2:0];
            end
        end
    end

    assign sel_mask         = (8'h01 << sel);
    assign keep_after_clear = buf_keep & ~sel_mask;
    assign sel_byte         = buf_data[8*sel +: 8];

    // -------------------------------------------------------------------------
    // AXI / symbol handshakes
    // -------------------------------------------------------------------------
    wire sym_xfer = sym.valid && sym.ready;
    wire axi_xfer = s_axis.tvalid && s_axis.tready;

    // Accept a new AXI beat only when the current beat buffer is empty.
    //
    // This creates backpressure while the current 64-bit beat is being
    // serialised into 8-bit symbols.
    assign s_axis.tready = rst_n && !buf_valid;

    // -------------------------------------------------------------------------
    // Symbol output
    // -------------------------------------------------------------------------
    // Behaviour:
    //   ST_IDLE  : emit continuous K_IDLE when no frame is active
    //   ST_START : emit one K_START
    //   ST_DATA  : emit data bytes only when a buffered AXI beat exists
    //              IMPORTANT: no K_IDLE is emitted inside a frame
    //   ST_END   : emit one K_END
    //
    // This means if the upstream AXI source has a gap between beats, sym.valid
    // goes low during the gap instead of inserting K_IDLE into the frame.
    // -------------------------------------------------------------------------
    always_comb begin
        // Safe defaults
        sym.data  = K_IDLE;
        sym.is_k  = 1'b1;
        sym.valid = 1'b0;
        sym.last  = 1'b0;

        unique case (st)

            ST_IDLE: begin
                // Outside a frame, continuously transmit IDLE.
                sym.data  = K_IDLE;
                sym.is_k  = 1'b1;
                sym.valid = 1'b1;
                sym.last  = 1'b0;
            end

            ST_START: begin
                // Start-of-frame delimiter.
                sym.data  = K_START;
                sym.is_k  = 1'b1;
                sym.valid = 1'b1;
                sym.last  = 1'b0;
            end

            ST_DATA: begin
                if (buf_valid && found) begin
                    // Data byte inside frame.
                    sym.data  = sel_byte;
                    sym.is_k  = 1'b0;
                    sym.valid = 1'b1;
                    sym.last  = 1'b0;
                end else begin
                    // Inside a frame, but waiting for the next AXI beat.
                    // Do NOT insert IDLE here, otherwise pcs_rx treats it as
                    // an illegal K-code inside the frame.
                    sym.data  = K_IDLE;
                    sym.is_k  = 1'b1;
                    sym.valid = 1'b0;
                    sym.last  = 1'b0;
                end
            end

            ST_END: begin
                // End-of-frame delimiter.
                sym.data  = K_END;
                sym.is_k  = 1'b1;
                sym.valid = 1'b1;
                sym.last  = 1'b1;
            end

            default: begin
                sym.data  = K_IDLE;
                sym.is_k  = 1'b1;
                sym.valid = 1'b1;
                sym.last  = 1'b0;
            end

        endcase
    end

    // -------------------------------------------------------------------------
    // Sequential FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_IDLE;
            buf_valid <= 1'b0;
            buf_data  <= 64'd0;
            buf_keep  <= 8'd0;
            buf_last  <= 1'b0;
            ptr       <= 3'd0;
        end else begin

            // -------------------------------------------------------------
            // Capture incoming AXI beat
            // -------------------------------------------------------------
            if (axi_xfer) begin
                buf_valid <= 1'b1;
                buf_data  <= s_axis.tdata;
                buf_keep  <= s_axis.tkeep;
                buf_last  <= s_axis.tlast;
                ptr       <= 3'd0;

                if (st == ST_IDLE) begin
                    st <= ST_START;
                end
            end

            // -------------------------------------------------------------
            // Advance symbol stream
            // -------------------------------------------------------------
            if (sym_xfer) begin
                unique case (st)

                    ST_IDLE: begin
                        // Stay in IDLE until an AXI beat is captured.
                        // If axi_xfer happens in this same cycle, the assignment
                        // above moves the FSM to ST_START.
                    end

                    ST_START: begin
                        st  <= ST_DATA;
                        ptr <= 3'd0;
                    end

                    ST_DATA: begin
                        if (buf_valid && found) begin
                            // Mark selected byte as consumed.
                            buf_keep[sel] <= 1'b0;

                            if (keep_after_clear == 8'h00) begin
                                // Finished this AXI beat.
                                buf_valid <= 1'b0;
                                ptr       <= 3'd0;

                                if (buf_last) begin
                                    // Last AXI beat of frame consumed.
                                    st <= ST_END;
                                end else begin
                                    // Stay in ST_DATA and wait for next AXI beat.
                                    // sym.valid will be 0 during the wait.
                                    st <= ST_DATA;
                                end
                            end else begin
                                ptr <= sel + 3'd1;
                            end
                        end
                    end

                    ST_END: begin
                        st <= ST_IDLE;
                    end

                    default: begin
                        st <= ST_IDLE;
                    end

                endcase
            end
        end
    end

endmodule
