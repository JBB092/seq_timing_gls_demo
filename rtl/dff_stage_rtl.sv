// One D flip-flop (RTL version)
// cells/dff_stage_cell.sv has the same module for approach A
module dff_stage (
    input  logic clk,
    input  logic d,
    output logic q
);

    always_ff @(posedge clk) q <= d;

endmodule
