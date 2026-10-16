`include "chain_cfg.svh"

// DE10-Standard top level: PLL clock, KEY0 to clear the errors,
// k on HEX5-4 (decimal) and the error count on HEX3-0 (hex)
module board_top (
    input  logic       CLOCK_50,
    input  logic [0:0] KEY,       // KEY[0], active low
    output logic [9:0] LEDR,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5
);

    localparam int DEPTH = `CHAIN_DEPTH;

    logic        clk;
    logic        pll_locked;
    logic [1:0]  locked_sync = '0;  // power-up value, so rst starts high
    logic [1:0]  key_sync    = '0;
    logic        rst;
    logic        clr;
    logic [23:0] err_count;
    logic        err_flag;
    logic [15:0] err_disp;

    pll_main u_pll (
        .refclk   (CLOCK_50),
        .rst      (1'b0),
        .outclk_0 (clk),
        .locked   (pll_locked)
    );

    // locked and KEY0 are asynchronous to clk, so both go through 2 FFs
    always_ff @(posedge clk) begin
        locked_sync <= {locked_sync[0], pll_locked};
        key_sync    <= {key_sync[0], ~KEY[0]};
    end

    assign rst = ~locked_sync[1];  // core stays in reset until the PLL locks
    assign clr = key_sync[1];

    core #(.DEPTH(DEPTH)) u_core (
        .clk       (clk),
        .rst       (rst),
        .clr       (clr),
        .chain_q   (),
        .ref_q     (),
        .err_count (err_count),
        .err_flag  (err_flag)
    );

    // Only 4 hex digits on the board: show FFFF once the count needs more
    assign err_disp = (err_count[23:16] != '0) ? 16'hFFFF : err_count[15:0];

    hex7seg u_hex0 (.value(err_disp[3:0]),   .seg_n(HEX0));
    hex7seg u_hex1 (.value(err_disp[7:4]),   .seg_n(HEX1));
    hex7seg u_hex2 (.value(err_disp[11:8]),  .seg_n(HEX2));
    hex7seg u_hex3 (.value(err_disp[15:12]), .seg_n(HEX3));

    // k in decimal (last two digits if it ever goes above 99)
    hex7seg u_hex4 (.value(4'((DEPTH % 10))),      .seg_n(HEX4));
    hex7seg u_hex5 (.value(4'((DEPTH / 10) % 10)), .seg_n(HEX5));

    assign LEDR[0]   = err_flag;
    assign LEDR[8:1] = '0;
    assign LEDR[9]   = pll_locked;

endmodule
