`timescale 1ns/1ps

module sym8_to_parallel64 (
    input  logic clk,
    input  logic rst_n,

    sym_stream_if.sink sym,

    output logic [63:0] data_out,
    output logic [7:0]  is_k_out,
    output logic        valid_out
);

    logic [63:0] data_buf;
    logic [7:0]  is_k_buf;
    logic [2:0]  count;

    assign sym.ready = 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_buf  <= 64'd0;
            is_k_buf  <= 8'd0;
            count     <= 3'd0;
            data_out  <= 64'd0;
            is_k_out  <= 8'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;

            if (sym.valid && sym.ready) begin
                data_buf[count*8 +: 8] <= sym.data;
                is_k_buf[count]        <= sym.is_k;

                if (count == 3'd7) begin
                    data_out <= {
                        sym.data,
                        data_buf[55:0]
                    };

                    is_k_out <= {
                        sym.is_k,
                        is_k_buf[6:0]
                    };

                    valid_out <= 1'b1;
                    count <= 3'd0;
                end else begin
                    count <= count + 3'd1;
                end
            end
        end
    end

endmodule
