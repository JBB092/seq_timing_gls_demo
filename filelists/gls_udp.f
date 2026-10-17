// Sources of core for approach A: same as rtl.f, but chain_stage and
// dff_stage come from cells/ (UDP + specify). Delays from build/timing_cfg.svh
+incdir+rtl
+incdir+build
cells/udp_dff.v
cells/dff_stage_cell.sv
rtl/lfsr.sv
cells/udp_xor.v
cells/chain_stage_cell.sv
rtl/delay_chain.sv
rtl/ref_path.sv
rtl/error_checker.sv
rtl/core.sv
