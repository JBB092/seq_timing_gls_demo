# Scripts

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

`run.ps1` (Windows) and the `Makefile` (Linux) only call these scripts.

| Script | What it does | Reads | Writes | Called by |
|---|---|---|---|---|
| `sim.tcl` | Compiles and simulates one mode at one or several depths; for the netlist modes it first makes whatever is missing or outdated | `filelists/<mode>.f`, `tb/tb_core.sv`, `build/timing_cfg.svh` (`gls_udp`), the `core_sim` netlist (`gls_func`, `gls_sdf`), `build/sdf/core_sim_d<k>.sdf` (`gls_sdf`) | `build/<mode>/d<k>/work`, `build/<mode>/d<k>/sim.log` | `rtl`, `gls_func`, `gls_udp`, `gls_sdf` targets |
| `parse_logs.py` | Lists the errors and warnings of every log and merges the T sweeps into a k x T table | `build/*/d*/sim.log` | `build/reports/kxt_<mode>.csv` | `report` target |
| `build.tcl` | Compiles a Quartus revision for one or several depths, or programs the board | `quartus/<revision>.qsf` and the sources it lists | `build/quartus/<revision>_d<k>/`, `build/quartus/<revision>_sweep.csv` | `build`, `build_sweep`, `program` targets; `sim.tcl` for `core_sim` |
| `sta_export.tcl` | Exports the critical path of each build (every point, every corner) | `build/quartus/<revision>_d<k>/` | `build/sta/<revision>_summary.csv`, `build/sta/<revision>_path_d<k>.csv` | `sta_export` target; `sim.tcl` for `core_sim` |
| `gen_timing_cfg.py` | Turns the STA export into average cell delays for approach A | `build/sta/board_summary.csv` | `build/timing_cfg.svh` | `gls_udp` target, when the CSV is newer than the `.svh` |
| `gen_sdf.py` | Turns the STA export of each `core_sim` build into an SDF file for approach B | `build/sta/core_sim_*.csv`, the `core_sim` netlist | `build/sdf/core_sim_d<k>.sdf` | `sim.tcl` (`gls_sdf`), when the export is newer than the SDF |

## sim.tcl

Runs inside Questa, from the repo root:

```
vsim -c -nolog -do "set MODE rtl; set DEPTH 24; source scripts/sim.tcl"
vsim -c -nolog -do "set MODE gls_udp; set CORNER typ; set DEPTH {8 16 24}; source scripts/sim.tcl"
vsim -c -nolog -do "set MODE gls_sdf; set DEPTH {16 32}; source scripts/sim.tcl"
```

| Variable | Meaning |
|---|---|
| `MODE` | `rtl`, `gls_func`, `gls_udp` or `gls_sdf` |
| `DEPTH` | One depth or a list; if empty, the default from `rtl/chain_cfg.svh` |
| `CORNER` | `gls_udp` and `gls_sdf`: `min`, `typ` or `max` (default) |
| `TCHK_MSG` | `gls_udp` and `gls_sdf`: `1` prints every timing check violation (hidden by default with `+no_tchk_msg`) |

| Mode | Filelist | Extra `vsim` options | Results in |
|---|---|---|---|
| `rtl` | `filelists/rtl.f` | `+T_CHECK=0` (must pass at every period) | `build/rtl/d<k>/` |
| `gls_func` | `filelists/gls_sdf.f` + the netlist of depth k | `+T_CHECK=0 -L cyclonev_ver -L altera_ver` | `build/gls_func/d<k>/` |
| `gls_udp` | `filelists/gls_udp.f` | `+<corner>delays +no_tchk_msg` | `build/gls_udp_<corner>/d<k>/` |
| `gls_sdf` | `filelists/gls_sdf.f` + the netlist of depth k | `-L cyclonev_ver -L altera_ver -sdf<corner> /tb_core/u_dut=build/sdf/core_sim_d<k>.sdf +<corner>delays +no_tchk_msg` | `build/gls_sdf_<corner>/d<k>/` |

Before simulating a depth, the netlist modes make sure their inputs are up
to date, and remake only what is missing or older than what it comes from:

| Input | Remade when it is missing or older than | With |
|---|---|---|
| `build/quartus/core_sim_d<k>/simulation/questa/core_sim.svo` | any `rtl/*.sv`, `rtl/*.svh`, `quartus/core_sim.qsf` or `quartus/core_sim.sdc` | `build.tcl compile core_sim <k>` (about 2 minutes) |
| `build/sta/core_sim_path_d<k>.csv` (`gls_sdf`) | the netlist | `sta_export.tcl core_sim <k>` |
| `build/sdf/core_sim_d<k>.sdf` (`gls_sdf`) | the export or `scripts/gen_sdf.py` | `gen_sdf.py --depths <k>` |

Python is taken from the `PYTHON` environment variable if it is set
(the Makefile sets it), otherwise `python` on Windows and `python3` on
Linux.

With a list of depths it compiles and simulates each one in turn (a Questa
compile takes seconds) and ends with a summary:

```
=== Depth sweep, mode=gls_udp_max
       k  result  min T that passes
       8  PASS    4.0 ns
      24  PASS    10.0 ns
      32  FAIL    14.0 ns
```

`result` is the testbench verdict (for `gls_udp` and `gls_sdf`, at 10 ns
and above);
`min T that passes` is the shortest period that passes along with every
longer one.

Each mode, corner and depth gets its own folder and work library, so runs
never mix and there is no need to clean between them. `gls_udp` stops with
code 2 if `build/timing_cfg.svh` is missing; `run.ps1` and the Makefile
generate it first.

Exit code: 0 = pass, 1 = the testbench failed, 2 = build, compile or load
error.
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
quartus_sta -t scripts/sta_export.tcl core_sim 32      # the simulation revision
```

For each depth and each of the four corners it takes the path from LFSR
bit 0 to the chain capture flip-flop (the one that crosses every stage) and
writes:

- `build/sta/board_path_d<k>.csv`: every point of the path (clock network,
  wire `ic` and LUT `cell` delays of each stage, register input), per corner
- `build/sta/board_summary.csv`: one row per depth and corner with the slack,
  total data delay, clock skew, uncertainty, the sum of LUT and wire delays
  of the chain, the average delay per stage, the worst slack of any path to
  the capture register and the hold slack. Rows of depths not exported in
  this run are kept, so exporting one new depth does not drop the others

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

## gen_sdf.py

```
python scripts/gen_sdf.py                 # every core_sim depth exported
python scripts/gen_sdf.py --depths 16 40
```

Approach B annotates the Quartus netlist of `core_sim` with an SDF file (one
per depth), so it needs the `core_sim` builds and their STA export first.
`.\run.ps1 gls_sdf` does all of it; by hand it would be:

```powershell
.\run.ps1 build_sweep -Revision core_sim -Depths 16,40
.\run.ps1 sta_export -Revision core_sim
python scripts/gen_sdf.py
```

What goes into `build/sdf/core_sim_d<k>.sdf`:

| Cells | SDF entry | Value |
|---|---|---|
| The k chain LUTs (`cyclonev_lcell_comb`) | `IOPATH <pin> combout` for the input on the path | Wire delay to that pin + LUT delay |
| Every register (`dffeas`) | `IOPATH (posedge clk) q` | `reg_in` of this build |
| Every register (`dffeas`) | `SETUPHOLD` on `d` and `asdata` | Setup = uncertainty minus clock skew of this build, hold = 0 |

It is the same split as approach A (see `gen_timing_cfg.py`), but each depth
uses the delays of its own build, stage by stage, instead of averages. The
LFSR registers shift through `asdata`, so the check is set on both inputs.
Each value is a `min:typ:max` triplet in ns, with the same corners as
`gen_timing_cfg.py`. Cells off the path (the other LUT inputs, the reference
path, the counter) keep the zero delays of the netlist.

The script checks that every chain LUT is in the netlist of that depth, and
stops if the STA export is older than the netlist (it would come from another
build). For each depth it prints the shortest period the annotated path
allows; it matches `10 ns - slack` from the STA.

Instance names are written with a backslash before every character that is
not a letter, digit or underscore, as SDF requires:
`u_chain|g_stage[3].u_stage|y_keep` becomes
`u_chain\|g_stage\[3\]\.u_stage\|y_keep`.

## Flow

Board and approach A (revision `board`):

```
build.tcl sweep (k list)  ->  slack per k  ->  build.tcl program (k)  ->  board
                          ->  sta_export.tcl  ->  build/sta/board_*.csv
                          ->  gen_timing_cfg.py  ->  build/timing_cfg.svh
sim.tcl (rtl | gls_udp, k list)  ->  build/<mode>/d<k>/sim.log
```

Approach B (revision `core_sim`), per depth, all driven by `sim.tcl`:

```
build.tcl compile core_sim (k)  ->  netlist  ->  sim.tcl (gls_func, k)
                                ->  sta_export.tcl  ->  build/sta/core_sim_*.csv
                                ->  gen_sdf.py  ->  build/sdf/core_sim_d<k>.sdf  ->  sim.tcl (gls_sdf, k)
```

Then `parse_logs.py` merges every log into the k x T tables.

The `board` builds and their STA export are only needed once (or when the
design or the clock changes); after that, `gls_udp` sweeps run in Questa
alone. The `core_sim` side builds itself the first time each depth is
simulated.

In commands:

```powershell
.\run.ps1 build_sweep
.\run.ps1 sta_export
.\run.ps1 gls_udp -Depths 8,16,24,32,36,40,44,48,64 -Corner max
.\run.ps1 gls_sdf -Depths 8,16,24,32,36,40,44,48,64 -Corner max
.\run.ps1 report
```
