# seq_timing_gls_demo

Demo for simulating propagation delays in a sequential circuit on a Cyclone V FPGA (Terasic
DE10-Standard). On Cyclone V, Quartus only produces a functional (zero-delay)
gate-level netlist, so plain RTL and GLS simulations never catch timing
problems. This repo shows two ways to add realistic delays in Questa
(custom UDP cells, and the Quartus netlist with a hand-made SDF), using a
register-to-register path whose combinational depth is set at compile time,
and compares the results against Quartus STA and the real board.
All generated output goes to `build/`, which is not tracked.
