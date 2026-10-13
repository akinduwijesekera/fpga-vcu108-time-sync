`timescale 1ns/1ps


interface axi_stream_if #(parameter int WIDTH = 64) (input logic clk);

    logic              tvalid;
    logic [WIDTH-1:0]  tdata;
    logic [WIDTH/8-1:0] tkeep;
    logic              tlast;
    logic              tready;

    // Master drives: tvalid/tdata/tkeep/tlast, reads tready
    modport master (
        output tvalid, tdata, tkeep, tlast,
        input  tready
    );

    // Slave reads: tvalid/tdata/tkeep/tlast, drives tready
    modport slave (
        input  tvalid, tdata, tkeep, tlast,
        output tready
    );

endinterface
