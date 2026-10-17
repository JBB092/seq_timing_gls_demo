# Scripts

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

`run.ps1` (Windows) and the `Makefile` (Linux) only call these scripts.

| Script | What it does | Reads | Writes | Called by |
|---|---|---|---|---|
| `sim.tcl` | Compiles and simulates one mode at one depth | `filelists/<mode>.f`, `tb/tb_core.sv` | `build/<mode>/d<k>/work`, `build/<mode>/d<k>/sim.log` | `rtl` target |
| `parse_logs.py` | Lists the errors and warnings of every log and merges the T sweeps into a k x T table | `build/*/d*/sim.log` | `build/reports/kxt_<mode>.csv` | `report` target |
| `build.tcl` | Compiles the Quartus project for one or several depths, or programs the board | `quartus/board.qsf` and the sources it lists | `build/quartus/board_d<k>/`, `build/quartus/board_sweep.csv` | `build`, `build_sweep`, `program` targets |

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

## Flow

For now, for each depth k:

```
sim.tcl (rtl, k)  ->  build/rtl/d<k>/sim.log  ->  parse_logs.py  ->  k x T table
build.tcl compile (k)  ->  slack  ->  build.tcl program (k)  ->  board
```
