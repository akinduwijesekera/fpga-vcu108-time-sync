`timescale 1ns/1ps

module rx_pcs #(
    parameter int FIFO_DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [63:0] sym_data,
    input  logic [7:0]  sym_is_k,
    input  logic        sym_valid,
    output logic        sym_ready,

    input  logic [7:0]  code_err_in,
    input  logic [7:0]  rd_err_in,
    input  logic        any_err_in,

    axi_stream_if.master m_axis,

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

    localparam int FIFO_AW = $clog2(FIFO_DEPTH);

    initial begin
        if (FIFO_DEPTH < 4) begin
            $error("rx_pcs: FIFO_DEPTH must be at least 4");
        end

        if ((FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0) begin
            $error("rx_pcs: FIFO_DEPTH should be a power of two");
        end
    end

    typedef enum logic [0:0] {
        ST_WAIT = 1'b0,
        ST_RECV = 1'b1
    } state_t;

    state_t st;

    // -------------------------------------------------------------------------
    // Input register stage
    // -------------------------------------------------------------------------
    logic        in_valid;
    logic [63:0] in_sym_data;
    logic [7:0]  in_sym_is_k;
    logic [7:0]  in_code_err;
    logic [7:0]  in_rd_err;
    logic        in_any_err;

    logic input_accept;

    // -------------------------------------------------------------------------
    // Packer state
    // -------------------------------------------------------------------------
    logic [63:0] pack_data;
    logic [7:0]  pack_keep;
    logic [2:0]  pack_count;

    logic        pending_valid;
    logic [63:0] pending_data;
    logic [7:0]  pending_keep;

    // -------------------------------------------------------------------------
    // Registered push buffer
    //
    // Parser writes here first.
    // FIFO write stage consumes these registered beats next cycle.
    // This breaks the path:
    //      st_reg/control -> fifo_keep/fifo_data
    // -------------------------------------------------------------------------
    logic        push0_valid;
    logic [63:0] push0_data;
    logic [7:0]  push0_keep;
    logic        push0_last;

    logic        push1_valid;
    logic [63:0] push1_data;
    logic [7:0]  push1_keep;
    logic        push1_last;

    logic push_pending;

    assign push_pending = push0_valid || push1_valid;

    // -------------------------------------------------------------------------
    // Output FIFO
    // -------------------------------------------------------------------------
    logic [63:0] fifo_data [0:FIFO_DEPTH-1];
    logic [7:0]  fifo_keep [0:FIFO_DEPTH-1];
    logic        fifo_last [0:FIFO_DEPTH-1];

    logic [FIFO_AW-1:0] fifo_wr_ptr;
    logic [FIFO_AW-1:0] fifo_rd_ptr;
    logic [FIFO_AW:0]   fifo_count;

    logic fifo_pop;

    assign fifo_pop = m_axis.tvalid && m_axis.tready;

    assign m_axis.tvalid = (fifo_count != 0);
    assign m_axis.tdata  = fifo_data[fifo_rd_ptr];
    assign m_axis.tkeep  = fifo_keep[fifo_rd_ptr];
    assign m_axis.tlast  = fifo_last[fifo_rd_ptr];

    // Conservative input ready:
    // - input register must be empty
    // - push buffer must be empty
    // - FIFO must have room for up to two generated beats
    assign sym_ready = !in_valid &&
                       !push_pending &&
                       (fifo_count <= FIFO_DEPTH - 2);

    assign input_accept = sym_valid && sym_ready;

    // -------------------------------------------------------------------------
    // Main sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_WAIT;

            in_valid      <= 1'b0;
            in_sym_data   <= 64'd0;
            in_sym_is_k   <= 8'd0;
            in_code_err   <= 8'd0;
            in_rd_err     <= 8'd0;
            in_any_err    <= 1'b0;

            pack_data     <= 64'd0;
            pack_keep     <= 8'd0;
            pack_count    <= 3'd0;

            pending_valid <= 1'b0;
            pending_data  <= 64'd0;
            pending_keep  <= 8'd0;

            push0_valid   <= 1'b0;
            push0_data    <= 64'd0;
            push0_keep    <= 8'd0;
            push0_last    <= 1'b0;

            push1_valid   <= 1'b0;
            push1_data    <= 64'd0;
            push1_keep    <= 8'd0;
            push1_last    <= 1'b0;

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

            logic        push0_valid_v;
            logic [63:0] push0_data_v;
            logic [7:0]  push0_keep_v;
            logic        push0_last_v;

            logic        push1_valid_v;
            logic [63:0] push1_data_v;
            logic [7:0]  push1_keep_v;
            logic        push1_last_v;

            logic [1:0]   gen_count_v;

            logic [63:0]  gen_data0_v;
            logic [7:0]   gen_keep0_v;
            logic         gen_last0_v;

            logic [63:0]  gen_data1_v;
            logic [7:0]   gen_keep1_v;
            logic         gen_last1_v;

            logic         overflow_v;
            logic         abort_v;
            logic         consume_input_v;

            logic [7:0]   cur_data;
            logic         cur_is_k;

            logic [63:0]  next_pack_data;
            logic [7:0]   next_pack_keep;

            // -----------------------------------------------------------------
            // Defaults
            // -----------------------------------------------------------------
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

            push0_valid_v   = push0_valid;
            push0_data_v    = push0_data;
            push0_keep_v    = push0_keep;
            push0_last_v    = push0_last;

            push1_valid_v   = push1_valid;
            push1_data_v    = push1_data;
            push1_keep_v    = push1_keep;
            push1_last_v    = push1_last;

            gen_count_v     = 2'd0;

            gen_data0_v     = 64'd0;
            gen_keep0_v     = 8'd0;
            gen_last0_v     = 1'b0;

            gen_data1_v     = 64'd0;
            gen_keep1_v     = 8'd0;
            gen_last1_v     = 1'b0;

            overflow_v      = 1'b0;
            abort_v         = 1'b0;
            consume_input_v = 1'b0;

            rx_sof_strobe <= 1'b0;
            frame_done    <= 1'b0;
            frame_err     <= 1'b0;
            ctrl_err      <= 1'b0;
            sym_err       <= 1'b0;

            // -----------------------------------------------------------------
            // FIFO pop
            // -----------------------------------------------------------------
            if (fifo_pop && (count_v != 0)) begin
                rd_ptr_v = rd_ptr_v + 1'b1;
                count_v  = count_v - 1'b1;
            end

            // -----------------------------------------------------------------
            // FIFO write stage from registered push buffer
            // -----------------------------------------------------------------
            if ((count_v + push0_valid_v + push1_valid_v) > FIFO_DEPTH[FIFO_AW:0]) begin
                frame_err <= 1'b1;
            end else begin
                if (push0_valid_v) begin
                    fifo_data[wr_ptr_v] <= push0_data_v;
                    fifo_keep[wr_ptr_v] <= push0_keep_v;
                    fifo_last[wr_ptr_v] <= push0_last_v;

                    wr_ptr_v      = wr_ptr_v + 1'b1;
                    count_v       = count_v + 1'b1;
                    push0_valid_v = 1'b0;
                end

                if (push1_valid_v) begin
                    fifo_data[wr_ptr_v] <= push1_data_v;
                    fifo_keep[wr_ptr_v] <= push1_keep_v;
                    fifo_last[wr_ptr_v] <= push1_last_v;

                    wr_ptr_v      = wr_ptr_v + 1'b1;
                    count_v       = count_v + 1'b1;
                    push1_valid_v = 1'b0;
                end
            end

            // -----------------------------------------------------------------
            // Parser stage
            // Only parse when push buffer has been drained.
            // -----------------------------------------------------------------
            if (in_valid && !push0_valid_v && !push1_valid_v) begin
                consume_input_v = 1'b1;

                if (in_any_err && (st_v == ST_RECV)) begin
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
                        cur_data = in_sym_data[i*8 +: 8];
                        cur_is_k = in_sym_is_k[i];

                        unique case (st_v)

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
                            end

                            ST_RECV: begin
                                if (cur_is_k) begin
                                    if (cur_data == K_END) begin
                                        frame_done <= 1'b1;

                                        if (pending_valid_v) begin
                                            if (gen_count_v == 2'd0) begin
                                                gen_data0_v = pending_data_v;
                                                gen_keep0_v = pending_keep_v;
                                                gen_last0_v = 1'b1;
                                                gen_count_v = 2'd1;
                                            end else begin
                                                gen_data1_v = pending_data_v;
                                                gen_keep1_v = pending_keep_v;
                                                gen_last1_v = 1'b1;
                                                gen_count_v = 2'd2;
                                            end
                                        end else if (pack_count_v != 3'd0) begin
                                            if (gen_count_v == 2'd0) begin
                                                gen_data0_v = pack_data_v;
                                                gen_keep0_v = pack_keep_v;
                                                gen_last0_v = 1'b1;
                                                gen_count_v = 2'd1;
                                            end else begin
                                                gen_data1_v = pack_data_v;
                                                gen_keep1_v = pack_keep_v;
                                                gen_last1_v = 1'b1;
                                                gen_count_v = 2'd2;
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
                                    end else begin
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
                                end else begin
                                    if (pending_valid_v) begin
                                        if (gen_count_v == 2'd0) begin
                                            gen_data0_v = pending_data_v;
                                            gen_keep0_v = pending_keep_v;
                                            gen_last0_v = 1'b0;
                                            gen_count_v = 2'd1;
                                        end else begin
                                            gen_data1_v = pending_data_v;
                                            gen_keep1_v = pending_keep_v;
                                            gen_last1_v = 1'b0;
                                            gen_count_v = 2'd2;
                                        end

                                        pending_valid_v = 1'b0;
                                        pending_data_v  = 64'd0;
                                        pending_keep_v  = 8'd0;

                                        pack_data_v      = 64'd0;
                                        pack_keep_v      = 8'd0;
                                        pack_data_v[7:0] = cur_data;
                                        pack_keep_v[0]   = 1'b1;
                                        pack_count_v     = 3'd1;
                                    end else begin
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

                // Parser output goes to registered push buffer, not FIFO directly.
                if (gen_count_v >= 2'd1) begin
                    push0_valid_v = 1'b1;
                    push0_data_v  = gen_data0_v;
                    push0_keep_v  = gen_keep0_v;
                    push0_last_v  = gen_last0_v;
                end

                if (gen_count_v == 2'd2) begin
                    push1_valid_v = 1'b1;
                    push1_data_v  = gen_data1_v;
                    push1_keep_v  = gen_keep1_v;
                    push1_last_v  = gen_last1_v;
                end
            end

            // -----------------------------------------------------------------
            // Commit parser/packer state
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

            push0_valid   <= push0_valid_v;
            push0_data    <= push0_data_v;
            push0_keep    <= push0_keep_v;
            push0_last    <= push0_last_v;

            push1_valid   <= push1_valid_v;
            push1_data    <= push1_data_v;
            push1_keep    <= push1_keep_v;
            push1_last    <= push1_last_v;

            // -----------------------------------------------------------------
            // Input register update
            // -----------------------------------------------------------------
            if (consume_input_v) begin
                in_valid <= 1'b0;
            end

            if (input_accept) begin
                in_valid    <= 1'b1;
                in_sym_data <= sym_data;
                in_sym_is_k <= sym_is_k;
                in_code_err <= code_err_in;
                in_rd_err   <= rd_err_in;
                in_any_err  <= any_err_in;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Simulation-only checks
    // -------------------------------------------------------------------------
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
                    $error("rx_pcs: AXI output changed while stalled");
                end
            end

            prev_m_tdata   <= m_axis.tdata;
            prev_m_tkeep   <= m_axis.tkeep;
            prev_m_tlast   <= m_axis.tlast;
            prev_m_tvalid  <= m_axis.tvalid;
            prev_m_stalled <= m_axis.tvalid && !m_axis.tready;

            if (fifo_count > FIFO_DEPTH[FIFO_AW:0]) begin
                $error("rx_pcs: FIFO count exceeded FIFO_DEPTH");
            end

            if (m_axis.tvalid && (m_axis.tkeep == 8'h00)) begin
                $error("rx_pcs: output AXI beat has tkeep=0");
            end
        end
    end
`endif
    // synthesis translate_on

endmodule
