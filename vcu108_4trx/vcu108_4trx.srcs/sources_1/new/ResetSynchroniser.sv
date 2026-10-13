`timescale 1ns / 1ps
// @module ResetSynchroniser
//
// @date 04.02.2025
// 
// @brief Synchronises slowly changing reset signal from another clock domain into new clock domain.

//
// @file ResetSynchroniser.sv
//
// @author Kari Clark (Salisen), University College London

module ResetSynchroniser #(
    parameter DEPTH    = 4,
    parameter POLARITY = "pos"
) (
    input        clk_in   ,
    input        reset_in ,
    output logic reset_out
);

    (* ASYNC_REG = "true" *) logic  shiftReg [DEPTH:0];

    assign shiftReg[0] = reset_in;
    assign reset_out   = shiftReg[DEPTH];

    generate
        if (POLARITY == "pos")
            always_ff @(posedge clk_in, posedge reset_in) begin : proc_resetSyncChain
                if (DEPTH == 0)
                    $error("ResetSynchroniser cannot have a depth of zero!");
                else if (reset_in)
                    for (int i = 1; i <= DEPTH; i++)
                        shiftReg[i] <= 1'b1;
                else
                    for (int i = 1; i <= DEPTH; i++)
                        shiftReg[i] <= shiftReg[i-1];
            end
        else if (POLARITY == "neg")
            always_ff @(posedge clk_in, negedge reset_in) begin : proc_resetSyncChain
                if (DEPTH == 0)
                    $error("ResetSynchroniser cannot have a depth of zero!");
                else if (reset_in)
                    for (int i = 1; i <= DEPTH; i++)
                        shiftReg[i] <= 1'b0;
                else
                    for (int i = 1; i <= DEPTH; i++)
                        shiftReg[i] <= shiftReg[i-1];
            end
        else
            $error("ResetSynchroniser must have a polarity of pos or neg!");
    endgenerate

endmodule