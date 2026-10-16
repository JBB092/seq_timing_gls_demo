`include "chain_cfg.svh"

// LFSR -> delay chain -> capture FF, checked against the reference path
// This is the module that gets simulated; board_top adds the PLL and displays
module core #(
    parameter int WIDTH       = 16,
    parameter int DEPTH       = `CHAIN_DEPTH,
    parameter int COUNT_WIDTH = 24
) (
    input  logic                   clk,
    input  logic                   rst,        // synchronous, active high, hold >= 2 cycles
    input  logic                   clr,        // clears the error counter and flag
    output logic                   chain_q,    // captured chain output
    output logic                   ref_q,      // captured reference output
    output logic [COUNT_WIDTH-1:0] err_count,
    output logic                   err_flag
);

    logic [WIDTH-1:0] lfsr_q;
    logic             chain_d;
    logic             ref_d;

    lfsr #(.WIDTH(WIDTH)) u_lfsr (
        .clk (clk),
        .rst (rst),
        .q   (lfsr_q)
    );

    delay_chain #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_chain (
        .din  (lfsr_q),
        .dout (chain_d)
    );

    ref_path #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_ref (
        .din  (lfsr_q),
        .dout (ref_d)
    );

    // No reset on these two: after rst both hold the same value
    dff_stage u_chain_ff (
        .clk (clk),
        .d   (chain_d),
        .q   (chain_q)
    );

    dff_stage u_ref_ff (
        .clk (clk),
        .d   (ref_d),
        .q   (ref_q)
    );

    error_checker #(.COUNT_WIDTH(COUNT_WIDTH)) u_checker (
        .clk       (clk),
        .clr       (rst | clr),
        .chain_bit (chain_q),
        .ref_bit   (ref_q),
        .err_count (err_count),
        .err_flag  (err_flag)
    );

endmodule
