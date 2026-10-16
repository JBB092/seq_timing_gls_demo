# Filelists

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

A `.f` file is a list of sources (and options such as `+incdir+`) that Questa
reads with `vlog -f <file>`, as if they were typed on the command line.
Paths are relative to the repo root, which is where the scripts run.

| File | Used by | Contents |
|---|---|---|
| `rtl.f` | `rtl` mode | The synthesizable sources of `core`, in compile order |

The testbench (`tb/tb_core.sv`) is not in the list; `scripts/sim.tcl` adds it.

## Which version of each cell

`chain_stage` and `dff_stage` exist in more than one file with the same
module name. Each filelist picks one version:

| Mode | `chain_stage` | `dff_stage` |
|---|---|---|
| `rtl` | `rtl/chain_stage_rtl.sv` | `rtl/dff_stage_rtl.sv` |

The filelists for the modes with delays are added in later steps.
