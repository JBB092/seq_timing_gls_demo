// One D flip-flop (approach A version)
// Same module as rtl/dff_stage_rtl.sv, built from a UDP with tCO and a
// setup/hold check from build/timing_cfg.svh. A violation toggles the
// notifier and q goes to x.
`timescale 1ns/1ps
`include "timing_cfg.svh"

module dff_stage (
    input  wire clk,
    input  wire d,
    output wire q
);

    reg notifier;

    udp_dff u_ff (q, d, clk, notifier);

    specify
        specparam tCO = `T_CO, tSU = `T_SU, tH = `T_H;
        (posedge clk => (q +: d)) = tCO;
        $setuphold(posedge clk, d, tSU, tH, notifier);
    endspecify

endmodule
