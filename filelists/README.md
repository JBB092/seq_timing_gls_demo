# Filelists

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

A `.f` file is a list of sources (and options such as `+incdir+`) that Questa
reads with `vlog -f <file>`, as if they were typed on the command line.
Paths are relative to the repo root, which is where the scripts run.

| File | Used by | Contents |
|---|---|---|
| `rtl.f` | `rtl` mode | The synthesizable sources of `core`, in compile order |
| `gls_udp.f` | `gls_udp` mode | Same as `rtl.f`, with the timing cells from `cells/` |
| `gls_sdf.f` | `gls_func` and `gls_sdf` modes | Only `+incdir+rtl`; the design is the Quartus netlist of the depth |

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

## The netlist modes

`gls_func` and `gls_sdf` do not compile the RTL at all. They compile the
netlist that Quartus writes for the `core_sim` revision, one per depth:

```
build/quartus/core_sim_d<k>/simulation/questa/core_sim.svo
```

Its path changes with k, so `scripts/sim.tcl` adds it after `gls_sdf.f`.
The file itself only has `+incdir+rtl`, because the testbench includes
`chain_cfg.svh`. The netlist is made of Cyclone V cells
(`cyclonev_lcell_comb`, `dffeas`, ...), which come precompiled with Questa
(`-L cyclonev_ver -L altera_ver`), so there is no `chain_stage` or
`dff_stage` to pick.
