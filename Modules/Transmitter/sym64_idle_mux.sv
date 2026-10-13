`timescale 1ns/1ps

module sym64_idle_mux (
    input  logic        clk,
    input  logic        rst_n,

    // Packed symbols from sym8_to_parallel64
    input  logic [63:0] data_in,
    input  logic [7:0]  is_k_in,
    input  logic        valid_in,

    // Continuous packed-symbol output to the single 8b/10b encoder
    output logic [63:0] data_out,
    output logic [7:0]  is_k_out,
    output logic        valid_out
);

    localparam logic [7:0] K_IDLE = 8'hBC;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= {8{K_IDLE}};
            is_k_out  <= 8'hFF;
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b1;

            if (valid_in) begin
                data_out <= data_in;
                is_k_out <= is_k_in;
            end else begin
                data_out <= {8{K_IDLE}};
                is_k_out <= 8'hFF;
            end
        end
    end

endmodule
