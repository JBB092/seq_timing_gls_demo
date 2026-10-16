// Pseudo-random data source for the delay chain
// 16-bit LFSR that feeds the delay chain with new data every clock
module lfsr #(
    parameter int              WIDTH = 16,
    parameter logic [WIDTH-1:0] TAPS = 16'hB400,  // bits 16, 14, 13, 11 (1-based)
    parameter logic [WIDTH-1:0] SEED = 16'hACE1   // any non-zero value
) (
    input  logic             clk,
    input  logic             rst,   // synchronous, active high
    output logic [WIDTH-1:0] q
);

    // The all-zeros state is a lock-up state (0 XOR 0 = 0), hence a non-zero seed
    logic feedback;
    assign feedback = ^(q & TAPS);

    always_ff @(posedge clk) begin
        if (rst) q <= SEED;
        else     q <= {q[WIDTH-2:0], feedback};
    end

endmodule
