`timescale 1ns/1ps

module pcs_rx64 (
    input  logic clk,
    input  logic rst_n,

    // 8 decoded symbols per clock from dec_80b64b
    input  logic [63:0] sym_data,
    input  logic [7:0]  sym_is_k,
    input  logic        sym_valid,

    // Decoder error indicator for this 64-bit decoded word
    input  logic        sym_err_in,

    // AXI stream out
    axi_stream_if.master m_axis,

    // Status/debug
    output logic         in_frame,
    output logic         rx_sof_strobe,
    output logic         frame_done,
    output logic         frame_err,
    output logic         ctrl_err,
    output logic         sym_err
);

    localparam logic [7:0] K_IDLE  = 8'hBC;
    localparam logic [7:0] K_START = 8'hFB;
    localparam logic [7:0] K_END   = 8'hFD;

    typedef enum logic [0:0] {
        ST_WAIT = 1'b0,
        ST_RECV = 1'b1
    } state_t;

    state_t st;

    // -------------------------------------------------------------------------
    // Current partial AXI beat packer
    // -------------------------------------------------------------------------

    logic [63:0] pack_data;
    logic [7:0]  pack_keep;
    logic [2:0]  pack_count;

    // -------------------------------------------------------------------------
    // Pending full beat
    // -------------------------------------------------------------------------
    // A full 8-byte beat is held until we know whether the next frame symbol is
    // more data or K_END. This lets exact 8/16/24-byte frames get correct tlast.
    // -------------------------------------------------------------------------

    logic        pending_valid;
    logic [63:0] pending_data;
    logic [7:0]  pending_keep;

    // -------------------------------------------------------------------------
    // Small output FIFO
    // -------------------------------------------------------------------------
    // pcs_rx64 can need to emit up to two AXI beats in one clock:
    //   - a pending full beat with tlast=0
    //   - a final partial beat with tlast=1
    //
    // The FIFO also protects against short downstream backpressure.
    // -------------------------------------------------------------------------

    localparam int FIFO_DEPTH = 16;
    localparam int FIFO_AW    = 4;

    logic [63:0] fifo_data [FIFO_DEPTH];
    logic [7:0]  fifo_keep [FIFO_DEPTH];
    logic        fifo_last [FIFO_DEPTH];

    logic [FIFO_AW-1:0] fifo_wr_ptr;
    logic [FIFO_AW-1:0] fifo_rd_ptr;
    logic [FIFO_AW:0]   fifo_count;

    wire fifo_pop = m_axis.tvalid && m_axis.tready;

    assign m_axis.tvalid = (fifo_count != 0);
    assign m_axis.tdata  = fifo_data[fifo_rd_ptr];
    assign m_axis.tkeep  = fifo_keep[fifo_rd_ptr];
    assign m_axis.tlast  = fifo_last[fifo_rd_ptr];

    // -------------------------------------------------------------------------
    // Main logic
    // -------------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_WAIT;

            pack_data     <= 64'd0;
            pack_keep     <= 8'd0;
            pack_count    <= 3'd0;

            pending_valid <= 1'b0;
            pending_data  <= 64'd0;
            pending_keep  <= 8'd0;

            fifo_wr_ptr   <= '0;
            fifo_rd_ptr   <= '0;
            fifo_count    <= '0;

            in_frame      <= 1'b0;
            rx_sof_strobe <= 1'b0;
            frame_done    <= 1'b0;
            frame_err     <= 1'b0;
            ctrl_err      <= 1'b0;
            sym_err       <= 1'b0;

        end else begin
            // -----------------------------------------------------------------
            // Local next variables
            // -----------------------------------------------------------------

            state_t       st_v;
            logic         in_frame_v;

            logic [63:0]  pack_data_v;
            logic [7:0]   pack_keep_v;
            logic [2:0]   pack_count_v;

            logic         pending_valid_v;
            logic [63:0]  pending_data_v;
            logic [7:0]   pending_keep_v;

            logic [FIFO_AW-1:0] wr_ptr_v;
            logic [FIFO_AW-1:0] rd_ptr_v;
            logic [FIFO_AW:0]   count_v;

            logic [1:0]   push_count_v;
            logic [63:0]  push_data0_v;
            logic [7:0]   push_keep0_v;
            logic         push_last0_v;
            logic [63:0]  push_data1_v;
            logic [7:0]   push_keep1_v;
            logic         push_last1_v;

            logic         overflow_v;
            logic         abort_v;

            logic [7:0]   cur_data;
            logic         cur_is_k;

            logic [63:0]  next_pack_data;
            logic [7:0]   next_pack_keep;

            // Defaults from registered state
            st_v            = st;
            in_frame_v      = in_frame;

            pack_data_v     = pack_data;
            pack_keep_v     = pack_keep;
            pack_count_v    = pack_count;

            pending_valid_v = pending_valid;
            pending_data_v  = pending_data;
            pending_keep_v  = pending_keep;

            wr_ptr_v        = fifo_wr_ptr;
            rd_ptr_v        = fifo_rd_ptr;
            count_v         = fifo_count;

            push_count_v    = 2'd0;
            push_data0_v    = 64'd0;
            push_keep0_v    = 8'd0;
            push_last0_v    = 1'b0;
            push_data1_v    = 64'd0;
            push_keep1_v    = 8'd0;
            push_last1_v    = 1'b0;

            overflow_v      = 1'b0;
            abort_v         = 1'b0;

            // One-cycle pulses
            rx_sof_strobe <= 1'b0;
            frame_done    <= 1'b0;
            frame_err     <= 1'b0;
            ctrl_err      <= 1'b0;
            sym_err       <= 1'b0;

            // FIFO pop
            if (fifo_pop && (count_v != 0)) begin
                rd_ptr_v = rd_ptr_v + 1'b1;
                count_v  = count_v - 1'b1;
            end

            // -----------------------------------------------------------------
            // Process one decoded 64-bit symbol word
            // -----------------------------------------------------------------

            if (sym_valid) begin

                if (sym_err_in && (st_v == ST_RECV)) begin
                    st_v            = ST_WAIT;
                    in_frame_v      = 1'b0;

                    pack_data_v     = 64'd0;
                    pack_keep_v     = 8'd0;
                    pack_count_v    = 3'd0;

                    pending_valid_v = 1'b0;
                    pending_data_v  = 64'd0;
                    pending_keep_v  = 8'd0;

                    frame_err       <= 1'b1;
                    sym_err         <= 1'b1;
                    abort_v         = 1'b1;
                end

                for (int i = 0; i < 8; i++) begin
                    if (!abort_v) begin
                        cur_data = sym_data[i*8 +: 8];
                        cur_is_k = sym_is_k[i];

                        unique case (st_v)

                            // -------------------------------------------------
                            // Waiting for start of frame
                            // -------------------------------------------------
                            ST_WAIT: begin
                                if (cur_is_k && (cur_data == K_START)) begin
                                    st_v            = ST_RECV;
                                    in_frame_v      = 1'b1;

                                    pack_data_v     = 64'd0;
                                    pack_keep_v     = 8'd0;
                                    pack_count_v    = 3'd0;

                                    pending_valid_v = 1'b0;
                                    pending_data_v  = 64'd0;
                                    pending_keep_v  = 8'd0;

                                    rx_sof_strobe   <= 1'b1;
                                end
                                // Ignore IDLE/data outside frame
                            end

                            // -------------------------------------------------
                            // Receiving frame
                            // -------------------------------------------------
                            ST_RECV: begin

                                if (cur_is_k) begin

                                    // IDLE inside frame is allowed
                                    if (cur_data == K_IDLE) begin
                                        // Do nothing
                                    end

                                    // End of frame
                                    else if (cur_data == K_END) begin
                                        frame_done <= 1'b1;

                                        if (pending_valid_v) begin
                                            if (push_count_v == 2'd0) begin
                                                push_data0_v = pending_data_v;
                                                push_keep0_v = pending_keep_v;
                                                push_last0_v = 1'b1;
                                                push_count_v = 2'd1;
                                            end else if (push_count_v == 2'd1) begin
                                                push_data1_v = pending_data_v;
                                                push_keep1_v = pending_keep_v;
                                                push_last1_v = 1'b1;
                                                push_count_v = 2'd2;
                                            end else begin
                                                overflow_v = 1'b1;
                                            end
                                        end else if (pack_count_v != 3'd0) begin
                                            if (push_count_v == 2'd0) begin
                                                push_data0_v = pack_data_v;
                                                push_keep0_v = pack_keep_v;
                                                push_last0_v = 1'b1;
                                                push_count_v = 2'd1;
                                            end else if (push_count_v == 2'd1) begin
                                                push_data1_v = pack_data_v;
                                                push_keep1_v = pack_keep_v;
                                                push_last1_v = 1'b1;
                                                push_count_v = 2'd2;
                                            end else begin
                                                overflow_v = 1'b1;
                                            end
                                        end

                                        st_v            = ST_WAIT;
                                        in_frame_v      = 1'b0;

                                        pack_data_v     = 64'd0;
                                        pack_keep_v     = 8'd0;
                                        pack_count_v    = 3'd0;

                                        pending_valid_v = 1'b0;
                                        pending_data_v  = 64'd0;
                                        pending_keep_v  = 8'd0;
                                    end

                                    // Any other K-code inside frame is illegal
                                    else begin
                                        st_v            = ST_WAIT;
                                        in_frame_v      = 1'b0;

                                        pack_data_v     = 64'd0;
                                        pack_keep_v     = 8'd0;
                                        pack_count_v    = 3'd0;

                                        pending_valid_v = 1'b0;
                                        pending_data_v  = 64'd0;
                                        pending_keep_v  = 8'd0;

                                        frame_err       <= 1'b1;
                                        ctrl_err        <= 1'b1;
                                        abort_v         = 1'b1;
                                    end
                                end

                                // Normal data byte
                                else begin

                                    // If a full beat is pending, current data proves it was not last.
                                    // Emit pending beat with tlast=0, then start packing current byte.
                                    if (pending_valid_v) begin
                                        if (push_count_v == 2'd0) begin
                                            push_data0_v = pending_data_v;
                                            push_keep0_v = pending_keep_v;
                                            push_last0_v = 1'b0;
                                            push_count_v = 2'd1;
                                        end else if (push_count_v == 2'd1) begin
                                            push_data1_v = pending_data_v;
                                            push_keep1_v = pending_keep_v;
                                            push_last1_v = 1'b0;
                                            push_count_v = 2'd2;
                                        end else begin
                                            overflow_v = 1'b1;
                                        end

                                        pending_valid_v = 1'b0;
                                        pending_data_v  = 64'd0;
                                        pending_keep_v  = 8'd0;

                                        pack_data_v     = 64'd0;
                                        pack_keep_v     = 8'd0;
                                        pack_data_v[7:0] = cur_data;
                                        pack_keep_v[0]   = 1'b1;
                                        pack_count_v     = 3'd1;
                                    end

                                    // No pending beat: continue packing
                                    else begin
                                        next_pack_data = pack_data_v;
                                        next_pack_keep = pack_keep_v;

                                        next_pack_data[8*pack_count_v +: 8] = cur_data;
                                        next_pack_keep[pack_count_v]        = 1'b1;

                                        if (pack_count_v == 3'd7) begin
                                            pending_valid_v = 1'b1;
                                            pending_data_v  = next_pack_data;
                                            pending_keep_v  = 8'hFF;

                                            pack_data_v     = 64'd0;
                                            pack_keep_v     = 8'd0;
                                            pack_count_v    = 3'd0;
                                        end else begin
                                            pack_data_v     = next_pack_data;
                                            pack_keep_v     = next_pack_keep;
                                            pack_count_v    = pack_count_v + 3'd1;
                                        end
                                    end
                                end
                            end

                            default: begin
                                st_v       = ST_WAIT;
                                in_frame_v = 1'b0;
                            end

                        endcase
                    end
                end
            end

            // -----------------------------------------------------------------
            // Push generated AXI beats into FIFO
            // -----------------------------------------------------------------

            if (overflow_v) begin
                frame_err <= 1'b1;
            end

            if ((count_v + push_count_v) > FIFO_DEPTH[FIFO_AW:0]) begin
                frame_err <= 1'b1;
            end else begin
                if (push_count_v >= 2'd1) begin
                    fifo_data[wr_ptr_v] <= push_data0_v;
                    fifo_keep[wr_ptr_v] <= push_keep0_v;
                    fifo_last[wr_ptr_v] <= push_last0_v;
                    wr_ptr_v            = wr_ptr_v + 1'b1;
                    count_v             = count_v + 1'b1;
                end

                if (push_count_v == 2'd2) begin
                    fifo_data[wr_ptr_v] <= push_data1_v;
                    fifo_keep[wr_ptr_v] <= push_keep1_v;
                    fifo_last[wr_ptr_v] <= push_last1_v;
                    wr_ptr_v            = wr_ptr_v + 1'b1;
                    count_v             = count_v + 1'b1;
                end
            end

            // -----------------------------------------------------------------
            // Commit next state
            // -----------------------------------------------------------------

            st            <= st_v;
            in_frame      <= in_frame_v;

            pack_data     <= pack_data_v;
            pack_keep     <= pack_keep_v;
            pack_count    <= pack_count_v;

            pending_valid <= pending_valid_v;
            pending_data  <= pending_data_v;
            pending_keep  <= pending_keep_v;

            fifo_wr_ptr   <= wr_ptr_v;
            fifo_rd_ptr   <= rd_ptr_v;
            fifo_count    <= count_v;
        end
    end

endmodule
