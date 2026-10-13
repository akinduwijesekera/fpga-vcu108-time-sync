`timescale 1ns/1ps

module tx_pcs #(
    parameter int MAX_FRAME_BYTES = 64,

    // 8b/10b K-code byte values
    parameter logic [7:0] K_IDLE  = 8'hBC, // K28.5
    parameter logic [7:0] K_START = 8'hFB, // K27.7
    parameter logic [7:0] K_END   = 8'hFD  // K29.7
)(
    input  logic clk,
    input  logic rst_n,

    // AXI frame input from crc_append_axis
    axi_stream_if.slave s_axis,

    // Packed 8-symbol output to enc_64b80b
    //
    // sym_data[7:0]    = symbol lane 0
    // sym_data[15:8]   = symbol lane 1
    // ...
    // sym_data[63:56]  = symbol lane 7
    //
    // sym_is_k[i] = 1 if lane i is a K/control symbol.
    output logic [63:0] sym_data,
    output logic [7:0]  sym_is_k,
    output logic        sym_valid,
    input  logic        sym_ready,

    output logic        pcs_busy,
    output logic        pcs_done,
    output logic        frame_overflow_error
);

    // ------------------------------------------------------------
    // Basic parameter check
    // ------------------------------------------------------------
    initial begin
        if (MAX_FRAME_BYTES < 8) begin
            $error("tx_pcs: MAX_FRAME_BYTES must be at least 8");
        end
    end

    // ------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_CAPTURE,
        ST_SEND
    } state_t;

    state_t state;

    // ------------------------------------------------------------
    // Frame byte buffer
    // ------------------------------------------------------------
    logic [7:0] frame_mem [0:MAX_FRAME_BYTES-1];

    // Number of captured frame bytes
    logic [$clog2(MAX_FRAME_BYTES+1)-1:0] wr_count;
    logic [$clog2(MAX_FRAME_BYTES+1)-1:0] frame_len;

    // Output block counter
    logic [$clog2(((MAX_FRAME_BYTES+2+7)/8)+1)-1:0] send_block_idx;

    // Total symbols = K_START + frame bytes + K_END
    logic [$clog2(MAX_FRAME_BYTES+3)-1:0] total_symbols;

    // Total 64-bit symbol blocks required
    logic [$clog2(((MAX_FRAME_BYTES+2+7)/8)+1)-1:0] total_blocks;
    logic [$clog2(((MAX_FRAME_BYTES+2+7)/8)+1)-1:0] last_block_idx;

    // Handshake
    logic s_fire;
    logic sym_fire;

    assign s_fire  = s_axis.tvalid && s_axis.tready;
    assign sym_fire = sym_valid && sym_ready;

    // Done/error pulse/registers
    logic pcs_done_r;
    logic frame_overflow_error_r;

    assign pcs_done             = pcs_done_r;
    assign frame_overflow_error = frame_overflow_error_r;

    // Busy whenever capturing a frame or sending one.
    assign pcs_busy = (state != ST_CAPTURE) || (wr_count != '0);

    // ------------------------------------------------------------
    // Input ready logic
    //
    // Only capture while in ST_CAPTURE.
    // The wr_count <= MAX_FRAME_BYTES-8 condition guarantees that
    // a full 8-byte AXI beat can always fit safely.
    //
    // For your current design:
    //   tx_packet_framer + crc_append_axis = 36 bytes,
    // so MAX_FRAME_BYTES = 64 is more than enough.
    // ------------------------------------------------------------
    assign s_axis.tready =
        (state == ST_CAPTURE) &&
        (wr_count <= MAX_FRAME_BYTES-8);

    // ------------------------------------------------------------
    // Total block calculation
    // ------------------------------------------------------------
    always_comb begin
        total_symbols = frame_len + 2;              // K_START + data + K_END
        total_blocks  = (total_symbols + 7) >> 3;   // ceil(total_symbols / 8)

        if (total_blocks == '0) begin
            last_block_idx = '0;
        end else begin
            last_block_idx = total_blocks - 1'b1;
        end
    end

    // ------------------------------------------------------------
    // Generate packed symbol block
    //
    // Symbol index meaning:
    //   global symbol index 0              = K_START
    //   global symbol index 1..frame_len   = frame bytes
    //   global symbol index frame_len + 1  = K_END
    //   after that                         = K_IDLE padding
    // ------------------------------------------------------------
    always_comb begin
        sym_data  = {8{K_IDLE}};
        sym_is_k  = 8'hFF;
        sym_valid = 1'b1;

        if (state == ST_SEND) begin
            for (int lane = 0; lane < 8; lane++) begin
                int unsigned global_idx;
                int unsigned data_idx;

                global_idx = (send_block_idx << 3) + lane;

                if (global_idx == 0) begin
                    // Start delimiter
                    sym_data[8*lane +: 8] = K_START;
                    sym_is_k[lane]        = 1'b1;

                end else if (global_idx <= frame_len) begin
                    // Frame data byte
                    data_idx = global_idx - 1;

                    sym_data[8*lane +: 8] = frame_mem[data_idx];
                    sym_is_k[lane]        = 1'b0;

                end else if (global_idx == frame_len + 1) begin
                    // End delimiter
                    sym_data[8*lane +: 8] = K_END;
                    sym_is_k[lane]        = 1'b1;

                end else begin
                    // Padding after K_END
                    sym_data[8*lane +: 8] = K_IDLE;
                    sym_is_k[lane]        = 1'b1;
                end
            end

        end else begin
            // Outside frame transmission, continuously send IDLE.
            sym_data  = {8{K_IDLE}};
            sym_is_k  = 8'hFF;
            sym_valid = 1'b1;
        end
    end

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_CAPTURE;
            wr_count               <= '0;
            frame_len              <= '0;
            send_block_idx         <= '0;
            pcs_done_r             <= 1'b0;
            frame_overflow_error_r <= 1'b0;

        end else begin
            pcs_done_r             <= 1'b0;
            frame_overflow_error_r <= 1'b0;

            unique case (state)

                // ------------------------------------------------
                // Capture AXI frame bytes into local frame buffer.
                // During this state, the output emits IDLE blocks.
                // ------------------------------------------------
                ST_CAPTURE: begin
                    if (s_fire) begin
                        int unsigned k;
                        k = wr_count;

                        for (int i = 0; i < 8; i++) begin
                            if (s_axis.tkeep[i]) begin
                                if (k < MAX_FRAME_BYTES) begin
                                    frame_mem[k] <= s_axis.tdata[8*i +: 8];
                                    k++;
                                end else begin
                                    frame_overflow_error_r <= 1'b1;
                                end
                            end
                        end

                        wr_count <= k[$bits(wr_count)-1:0];

                        if (s_axis.tlast) begin
                            frame_len      <= k[$bits(frame_len)-1:0];
                            send_block_idx <= '0;
                            state          <= ST_SEND;
                        end
                    end
                end

                // ------------------------------------------------
                // Send K_START + frame bytes + K_END + idle padding.
                // The output block is held stable while sym_ready=0.
                // ------------------------------------------------
                ST_SEND: begin
                    if (sym_fire) begin
                        if (send_block_idx == last_block_idx) begin
                            // Finished sending this PCS frame
                            send_block_idx <= '0;
                            wr_count       <= '0;
                            frame_len      <= '0;
                            pcs_done_r     <= 1'b1;
                            state          <= ST_CAPTURE;
                        end else begin
                            send_block_idx <= send_block_idx + 1'b1;
                        end
                    end
                end

                default: begin
                    state          <= ST_CAPTURE;
                    wr_count       <= '0;
                    frame_len      <= '0;
                    send_block_idx <= '0;
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // Simulation-only checks
    // ------------------------------------------------------------
    // synthesis translate_off
`ifdef ASSERTIONS
    logic [63:0] prev_sym_data;
    logic [7:0]  prev_sym_is_k;
    logic        prev_sym_valid;
    logic        prev_sym_stalled;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_sym_data    <= 64'd0;
            prev_sym_is_k    <= 8'd0;
            prev_sym_valid   <= 1'b0;
            prev_sym_stalled <= 1'b0;
        end else begin
            // Output stability while stalled
            if (prev_sym_stalled) begin
                if (sym_valid !== prev_sym_valid ||
                    sym_data  !== prev_sym_data  ||
                    sym_is_k  !== prev_sym_is_k) begin
                    $error("tx_pcs: output changed while sym_ready=0");
                end
            end

            prev_sym_data    <= sym_data;
            prev_sym_is_k    <= sym_is_k;
            prev_sym_valid   <= sym_valid;
            prev_sym_stalled <= sym_valid && !sym_ready;

            if (s_fire && s_axis.tkeep == 8'h00) begin
                $error("tx_pcs: accepted AXI beat with tkeep=0");
            end

            if (s_fire && s_axis.tlast && wr_count == '0 && s_axis.tkeep == 8'h00) begin
                $error("tx_pcs: zero-length frame captured");
            end
        end
    end
`endif
    // synthesis translate_on

endmodule
