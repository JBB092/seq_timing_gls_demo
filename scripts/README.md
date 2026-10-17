# Scripts

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

`run.ps1` (Windows) and the `Makefile` (Linux) only call these scripts.

| Script | What it does | Reads | Writes | Called by |
|---|---|---|---|---|
| `sim.tcl` | Compiles and simulates one mode at one or several depths | `filelists/<mode>.f`, `tb/tb_core.sv`, `build/timing_cfg.svh` (`gls_udp`) | `build/<mode>/d<k>/work`, `build/<mode>/d<k>/sim.log` | `rtl`, `gls_udp` targets |
| `parse_logs.py` | Lists the errors and warnings of every log and merges the T sweeps into a k x T table | `build/*/d*/sim.log` | `build/reports/kxt_<mode>.csv` | `report` target |
| `build.tcl` | Compiles the Quartus project for one or several depths, or programs the board | `quartus/board.qsf` and the sources it lists | `build/quartus/board_d<k>/`, `build/quartus/board_sweep.csv` | `build`, `build_sweep`, `program` targets |
| `sta_export.tcl` | Exports the critical path of each build (every point, every corner) | `build/quartus/board_d<k>/` | `build/sta/board_summary.csv`, `build/sta/board_path_d<k>.csv` | `sta_export` target |
| `gen_timing_cfg.py` | Turns the STA export into average cell delays for approach A | `build/sta/board_summary.csv` | `build/timing_cfg.svh` | `gls_udp` target, when the CSV is newer than the `.svh` |

## sim.tcl

Runs inside Questa, from the repo root:

```
vsim -c -nolog -do "set MODE rtl; set DEPTH 24; source scripts/sim.tcl"
vsim -c -nolog -do "set MODE gls_udp; set CORNER typ; set DEPTH {8 16 24}; source scripts/sim.tcl"
```

| Variable | Meaning |
|---|---|
| `MODE` | `rtl` or `gls_udp` |
| `DEPTH` | One depth or a list; if empty, the default from `rtl/chain_cfg.svh` |
| `CORNER` | `gls_udp` only: `min`, `typ` or `max` (default), passed to `vsim` as `+mindelays`, `+typdelays` or `+maxdelays` |
| `TCHK_MSG` | `gls_udp` only: `1` prints every timing check violation (hidden by default with `+no_tchk_msg`) |

| Mode | Filelist | Extra `vsim` options | Results in |
|---|---|---|---|
| `rtl` | `filelists/rtl.f` | `+T_CHECK=0` (must pass at every period) | `build/rtl/d<k>/` |
| `gls_udp` | `filelists/gls_udp.f` | `+<corner>delays +no_tchk_msg` | `build/gls_udp_<corner>/d<k>/` |

With a list of depths it compiles and simulates each one in turn (a Questa
compile takes seconds) and ends with a summary:

```
=== Depth sweep, mode=gls_udp_max
       k  result  min T that passes
       8  PASS    4.0 ns
      24  PASS    10.0 ns
      32  FAIL    14.0 ns
```

`result` is the testbench verdict (for `gls_udp`, at 10 ns and above);
`min T that passes` is the shortest period that passes along with every
longer one.

Each mode, corner and depth gets its own folder and work library, so runs
never mix and there is no need to clean between them. `gls_udp` stops with
code 2 if `build/timing_cfg.svh` is missing; `run.ps1` and the Makefile
generate it first.

Exit code: 0 = pass, 1 = the testbench failed, 2 = compile or load error.
With several depths the worst code wins, so a sweep that crosses the
threshold ends with 1.

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

```
build.tcl sweep (k list)  ->  slack per k  ->  build.tcl program (k)  ->  board
                          ->  sta_export.tcl  ->  build/sta/*.csv
                          ->  gen_timing_cfg.py  ->  build/timing_cfg.svh
sim.tcl (rtl | gls_udp, k list)  ->  build/<mode>/d<k>/sim.log  ->  parse_logs.py  ->  k x T table
```

The Quartus builds and the STA export are only needed once (or when the
design or the clock changes). After that, `gls_udp` sweeps run in Questa
alone.

In commands:

```powershell
.\run.ps1 build_sweep
.\run.ps1 sta_export
.\run.ps1 gls_udp -Depths 8,16,24,32,36,40,44,48,64 -Corner max
.\run.ps1 report
```
