`include "chain_cfg.svh"

// Same function as delay_chain but without keep, so Quartus packs it into
// a few LUT levels and it always meets timing
module ref_path #(
    parameter int WIDTH = 16,
    parameter int DEPTH = `CHAIN_DEPTH
) (
    input  logic [WIDTH-1:0] din,
    output logic             dout
);

    // Must use the same bit order as delay_chain
    always_comb begin
        dout = din[0];
        for (int i = 1; i <= DEPTH; i++)
            dout = dout ^ din[1 + (i-1) % (WIDTH-1)];
    end

endmodule
