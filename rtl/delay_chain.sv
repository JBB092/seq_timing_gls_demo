`include "chain_cfg.svh"

module delay_chain #(
    parameter int WIDTH = 16,            // LFSR width
    parameter int DEPTH = `CHAIN_DEPTH   // number of stages
) (
    input  logic [WIDTH-1:0] din,
    output logic             dout
);

    logic [DEPTH:0] s;

    // din[0] is only used at the head, so it always goes through every
    // stage and never cancels out in the XOR
    assign s[0] = din[0];

    genvar i;
    generate
        for (i = 1; i <= DEPTH; i++) begin : g_stage
            chain_stage u_stage (
                .a (s[i-1]),
                .b (din[1 + (i-1) % (WIDTH-1)]),
                .y (s[i])
            );
        end
    endgenerate

    assign dout = s[DEPTH];

endmodule
