# Scripts

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

`run.ps1` (Windows) and the `Makefile` (Linux) only call these scripts.

| Script | What it does | Reads | Writes | Called by |
|---|---|---|---|---|
| `sim.tcl` | Compiles and simulates one mode at one depth | `filelists/<mode>.f`, `tb/tb_core.sv` | `build/<mode>/d<k>/work`, `build/<mode>/d<k>/sim.log` | `rtl` target |
| `parse_logs.py` | Lists the errors and warnings of every log and merges the T sweeps into a k x T table | `build/*/d*/sim.log` | `build/reports/kxt_<mode>.csv` | `report` target |
| `build.tcl` | Compiles the Quartus project for one or several depths, or programs the board | `quartus/board.qsf` and the sources it lists | `build/quartus/board_d<k>/`, `build/quartus/board_sweep.csv` | `build`, `build_sweep`, `program` targets |
| `sta_export.tcl` | Exports the critical path of each build (every point, every corner) | `build/quartus/board_d<k>/` | `build/sta/board_summary.csv`, `build/sta/board_path_d<k>.csv` | `sta_export` target |
| `gen_timing_cfg.py` | Turns the STA export into average cell delays for approach A | `build/sta/board_summary.csv` | `build/timing_cfg.svh` | by hand for now |

## sim.tcl

Runs inside Questa, from the repo root:

```
vsim -c -nolog -do "set MODE rtl; set DEPTH 24; source scripts/sim.tcl"
```

- `MODE`: simulation mode (`rtl` for now)
- `DEPTH`: chain depth k; if empty, the default from `rtl/chain_cfg.svh`

Each mode and depth gets its own folder and work library, so runs never mix
and there is no need to clean between them.

Exit code: 0 = all periods passed, 1 = the testbench failed,
2 = compile or load error.

## parse_logs.py

```
python scripts/parse_logs.py                 # all logs in build/
python scripts/parse_logs.py --mode rtl      # one mode
python scripts/parse_logs.py some/sim.log    # specific logs
```

It prints the OS and Python version it ran on and the Questa version found
in the logs, a summary line per log, every error and warning, and the k x T
table. In the table `.` is PASS, `F` is FAIL and `-` is a period that was not
run. The last column is the shortest period that passes along with every
longer one.

## build.tcl

Runs inside Quartus, from the repo root:

```
quartus_sh -t scripts/build.tcl compile board 40
quartus_sh -t scripts/build.tcl sweep   board "8 16 24"
quartus_sh -t scripts/build.tcl program board 40
```

- `compile`: copies the project to `build/quartus/board_d<k>/`, adds
  `VERILOG_MACRO "CHAIN_DEPTH=<k>"` to the copy and runs map, fit, asm and
  sta. Prints the worst setup slack of each corner.
- `sweep`: `compile` for a list of depths (default `8 16 24 32 36 40 44 48 64`)
  and a slack table, also saved as `build/quartus/board_sweep.csv`.
- `program`: loads `build/quartus/board_d<k>/output_files/board.sof` into
  JTAG device 2 (the FPGA).

Details are in `quartus/README.md`.

## sta_export.tcl

Runs inside the Quartus timing analyzer, from the repo root, after the builds:

```
quartus_sta -t scripts/sta_export.tcl board            # every build found
quartus_sta -t scripts/sta_export.tcl board "16 24"    # some depths
```

For each depth and each of the four corners it takes the path from LFSR
bit 0 to the chain capture flip-flop (the one that crosses every stage) and
writes:

- `build/sta/board_path_d<k>.csv`: every point of the path (clock network,
  wire `ic` and LUT `cell` delays of each stage, register input), per corner
- `build/sta/board_summary.csv`: one row per depth and corner with the slack,
  total data delay, clock skew, uncertainty, the sum of LUT and wire delays
  of the chain, the average delay per stage, the worst slack of any path to
  the capture register and the hold slack

The Cyclone V timing model reports the register times (`utco`, `utsu`,
`uth`) as 0: those delays are part of the clock network delay and of the
last cell before the capture register (`reg_in` column).

## gen_timing_cfg.py

```
python scripts/gen_timing_cfg.py
python scripts/gen_timing_cfg.py --csv build/sta/board_summary.csv --out build/timing_cfg.svh --period 10
```

Writes `build/timing_cfg.svh` with the delays used by the approach A cells,
as `min:typ:max` triplets in ns. Questa picks one with `+mindelays`,
`+typdelays` or `+maxdelays`.

| Corner | Taken from |
|---|---|
| min | Fast 1100mV 0C |
| typ | Midpoint of min and max (Quartus has no typical corner, so this is an estimate) |
| max | Slow 1100mV 85C |

| Macro | Meaning | How it is derived |
|---|---|---|
| `T_STAGE` | One chain stage (LUT + wire) | Total chain delay / total stages, over all builds |
| `T_CO` | Clock to output of a register | `reg_in` |
| `T_SU` | Setup time | Uncertainty minus clock skew |
| `T_H` | Hold time | 0, as reported by Quartus |

Since Quartus reports the register times as 0, `T_CO` and `T_SU` are built
from the other columns so that `T_CO + T_SU` is the same margin the STA adds
to the data path. `T_H` stays below `T_CO`, which avoids false hold
violations inside the LFSR, where the feedback has no delay.

The same file works for any depth. The script also prints the largest depth
that should pass at the given period for each corner.

## Flow

For now, for each depth k:

```
sim.tcl (rtl, k)  ->  build/rtl/d<k>/sim.log  ->  parse_logs.py  ->  k x T table
build.tcl compile (k)  ->  slack  ->  build.tcl program (k)  ->  board
build.tcl compile (k)  ->  sta_export.tcl  ->  build/sta/*.csv  ->  gen_timing_cfg.py  ->  build/timing_cfg.svh
```
