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
    logic             feedback;
    logic [WIDTH-1:0] q_next;
    assign feedback = ^(q & TAPS);
    assign q_next   = rst ? SEED : {q[WIDTH-2:0], feedback};

    // Every bit launches into a chain stage, so each one is a dff_stage
    // (the cell version adds tCO and setup/hold checks in approach A)
    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : g_ff
            dff_stage u_ff (
                .clk (clk),
                .d   (q_next[i]),
                .q   (q[i])
            );
        end
    endgenerate

endmodule
