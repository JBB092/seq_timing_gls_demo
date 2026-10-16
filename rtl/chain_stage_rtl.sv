// One stage of the delay chain (RTL version)
// cells/chain_stage_cell.sv has the same module for approach A
module chain_stage (
    input  logic a,  // previous stage
    input  logic b,  // LFSR bit
    output logic y
);

    // keep: one LUT per stage, otherwise Quartus merges them
    (* keep *) logic y_keep;
    assign y_keep = a ^ b;
    assign y      = y_keep;

endmodule
