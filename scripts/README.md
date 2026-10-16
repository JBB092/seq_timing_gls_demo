# Scripts

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

`run.ps1` (Windows) and the `Makefile` (Linux) only call these scripts.

| Script | What it does | Reads | Writes | Called by |
|---|---|---|---|---|
| `sim.tcl` | Compiles and simulates one mode at one depth | `filelists/<mode>.f`, `tb/tb_core.sv` | `build/<mode>/d<k>/work`, `build/<mode>/d<k>/sim.log` | `rtl` target |
| `parse_logs.py` | Lists the errors and warnings of every log and merges the T sweeps into a k x T table | `build/*/d*/sim.log` | `build/reports/kxt_<mode>.csv` | `report` target |

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

## Flow

For now, for each depth k:

```
sim.tcl (rtl, k)  ->  build/rtl/d<k>/sim.log  ->  parse_logs.py  ->  k x T table
```
