//============================================================
// sym_stream_if.sv
// Simple symbol-stream interface (byte + is_k) with ready/valid
//============================================================
interface sym_stream_if #(parameter int W = 8) (input logic clk);
    logic [W-1:0] data;   // symbol byte
    logic         is_k;   // 1=control(K), 0=data
    logic         valid;
    logic         ready;
    logic         last;   // optional: end-of-frame marker (not required)

    modport source (
        output data, output is_k, output valid, input ready, output last
    );

    modport sink (
        input  data, input  is_k, input  valid, output ready, input last
    );
endinterface
