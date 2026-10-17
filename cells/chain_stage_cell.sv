// One stage of the delay chain (approach A version)
// Same module as rtl/chain_stage_rtl.sv, built from a UDP with the average
// stage delay (LUT + wire) from build/timing_cfg.svh
`timescale 1ns/1ps
`include "timing_cfg.svh"

module chain_stage (
    input  wire a,  // previous stage
    input  wire b,  // LFSR bit
    output wire y
);

    udp_xor u_xor (y, a, b);

    specify
        specparam tSTAGE = `T_STAGE;
        (a => y) = tSTAGE;
        (b => y) = tSTAGE;
    endspecify

endmodule
