`timescale 1ns/1ps

module axis_register_slice #(
    parameter int WIDTH = 64
)(
    input  logic clk,
    input  logic rst_n,

    axi_stream_if.slave  s_axis,
    axi_stream_if.master m_axis
);

    logic [WIDTH-1:0]   data_r;
    logic [WIDTH/8-1:0] keep_r;
    logic               last_r;
    logic               valid_r;

    assign s_axis.tready = !valid_r || m_axis.tready;

    assign m_axis.tvalid = valid_r;
    assign m_axis.tdata  = data_r;
    assign m_axis.tkeep  = keep_r;
    assign m_axis.tlast  = last_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_r  <= '0;
            keep_r  <= '0;
            last_r  <= 1'b0;
            valid_r <= 1'b0;
        end else begin
            if (s_axis.tready) begin
                valid_r <= s_axis.tvalid;

                if (s_axis.tvalid) begin
                    data_r <= s_axis.tdata;
                    keep_r <= s_axis.tkeep;
                    last_r <= s_axis.tlast;
                end
            end
        end
    end

endmodule
