# Filelists

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

A `.f` file is a list of sources (and options such as `+incdir+`) that Questa
reads with `vlog -f <file>`, as if they were typed on the command line.
Paths are relative to the repo root, which is where the scripts run.

| File | Used by | Contents |
|---|---|---|
| `rtl.f` | `rtl` mode | The synthesizable sources of `core`, in compile order |
| `gls_udp.f` | `gls_udp` mode | Same as `rtl.f`, with the timing cells from `cells/` |

The testbench (`tb/tb_core.sv`) is not in the list; `scripts/sim.tcl` adds it.

## Which version of each cell

`chain_stage` and `dff_stage` exist in more than one file with the same
module name. Each filelist picks one version:

| Mode | `chain_stage` | `dff_stage` |
|---|---|---|
| `rtl` | `rtl/chain_stage_rtl.sv` | `rtl/dff_stage_rtl.sv` |
| `gls_udp` | `cells/chain_stage_cell.sv` (+ `cells/udp_xor.v`) | `cells/dff_stage_cell.sv` (+ `cells/udp_dff.v`) |

`gls_udp.f` also adds `+incdir+build`, where `scripts/gen_timing_cfg.py`
writes `timing_cfg.svh` with the delays of the cells.
