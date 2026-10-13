`timescale 1ns / 1ps
// @module Synchroniser
//
// @date 12.03.2018
// 
// @brief Synchronises slowly changing signal from another clock domain into new clock domain.
//    e.g. to/from a VIO or to synchronise a reset.  Shouldn't be used for fast changing buses, okay 
//    for slowly changing buses.
//
// @file Synchroniser.sv
//
// @author Kari Clark (Salisen), University College London

module Synchroniser #(
    parameter WIDTH = 1,
    parameter DEPTH = 4
) (
    input                    clk_in,
    input        [WIDTH-1:0] i_in  ,
    output logic [WIDTH-1:0] o_out
);

    (* ASYNC_REG = "true" *) logic  [WIDTH-1:0] shiftReg [DEPTH:0];

    assign shiftReg[0] = i_in;
    assign o_out       = shiftReg[DEPTH];

    always_ff @(posedge clk_in) begin : proc_syncChain
        if (DEPTH == 0)
            $error("Synchroniser cannot have a DEPTH of zero!");
        else
            for (int i = 1; i<= DEPTH; i++)
                shiftReg[i] <= shiftReg[i-1];
    end

endmodule