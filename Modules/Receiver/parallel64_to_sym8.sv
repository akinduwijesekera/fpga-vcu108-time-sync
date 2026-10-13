`timescale 1ns/1ps

module parallel64_to_sym8 (
    input  logic clk,
    input  logic rst_n,

    input  logic [63:0] data_in,
    input  logic [7:0]  is_k_in,
    input  logic        valid_in,

    sym_stream_if.source sym
);

    logic        active;
    logic [63:0] data_buf;
    logic [7:0]  is_k_buf;
    logic [2:0]  idx;

    always_comb begin
        sym.data  = data_buf[idx*8 +: 8];
        sym.is_k  = is_k_buf[idx];
        sym.valid = active;
        sym.last  = 1'b0;
    end

    wire sym_xfer = sym.valid && sym.ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active   <= 1'b0;
            data_buf <= 64'd0;
            is_k_buf <= 8'd0;
            idx      <= 3'd0;
        end else begin
            if (!active && valid_in) begin
                data_buf <= data_in;
                is_k_buf <= is_k_in;
                idx      <= 3'd0;
                active   <= 1'b1;
            end else if (sym_xfer) begin
                if (idx == 3'd7) begin
                    active <= 1'b0;
                    idx    <= 3'd0;
                end else begin
                    idx <= idx + 3'd1;
                end
            end
        end
    end

endmodule
