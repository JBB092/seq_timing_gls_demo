# seq_timing_gls_demo

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

Demo for simulating propagation delays in a sequential circuit on a Cyclone V
FPGA (Terasic DE10-Standard), made for the course Taller de Diseño Digital
(TEC, Costa Rica).

On Cyclone V, Quartus only writes a functional (zero-delay) gate-level
netlist, so the RTL simulation and the gate-level simulation (GLS) never
catch timing problems. This repo adds realistic delays in Questa in two ways
and compares them with the Quartus timing analysis (STA) and the real board:

- **Approach A**: custom cells (user-defined primitives with `specify`
  blocks), with average delays taken from the STA
- **Approach B**: the Quartus netlist with an SDF file written from the STA
  of each build

The circuit is a register-to-register path whose combinational depth k is
set at compile time. The clock stays at 100 MHz and k grows until the path
is too slow.

## The circuit

```
          bit 0     bit 1     bit 2           bit j
  +------+  |         |         |               |
  |      |  v         v         v               v
  | LFSR |--+------>[XOR]---->[XOR]--> ... -->[XOR]-->[capture FF]--+
  | 16 b |        stage 1   stage 2         stage k                 |
  |      |                                                          v
  |      |--> reference (same XOR, no keep) ------->[ref FF]---->[compare]--> error counter
  +------+                                                                    error flag
```

- The LFSR changes on every clock edge, so the chain is always switching.
- The delay chain has k XOR stages, one LUT each (`keep`). LFSR bit 0 crosses
  all of them: the longer the chain, the later the capture flip-flop gets
  the right value.
- The reference computes the same function in one or two LUTs, so it is
  always on time. When the two captured bits differ, the chain was too slow
  (a setup violation) and the error counter goes up.
- k is the macro `CHAIN_DEPTH` (default 16). Each value of k is a separate
  compilation.

On the board, `HEX5-HEX4` show k, `HEX3-HEX0` the error count and `LEDR0`
lights up on the first error.

## Results at 100 MHz

| Method | Last k that passes | First k that fails |
|---|---|---|
| `rtl` and `gls_func` (zero delay) | every k | none |
| STA and approaches A and B, slow corner | 24 | 32 |
| Approach A, typical (midpoint) | 32 | 36 |
| Approach B, typical (midpoint) | 36 | 37 |
| STA and approaches A and B, fast corner | 48 | 64 |
| **DE10-Standard board** | **39** | **40** |

The zero-delay simulations pass for every depth, even the ones that fail on
the board. The simulations with delays fail in the same place as the STA,
and the board falls between the slow and the fast corners. Full tables and
conclusions in [`docs/results.md`](docs/results.md).

## Requirements

Reference system (all results were taken on it):

| Item | Version |
|---|---|
| OS | Windows 10 22H2 (64-bit); Ubuntu support through the `Makefile` (not tested yet) |
| Quartus | Quartus Prime 25.1std.0 Lite Edition |
| Questa | Questa Altera Starter FPGA Edition 2025.2 (free license) |
| Python | 3.11 or newer (only the standard library) |
| Windows shell | PowerShell 5.1 |
| Linux tools | GNU Make (3.81 or newer) |
| Board | Terasic DE10-Standard, Cyclone V SX `5CSXFC6D6F31C6N`, USB-Blaster II on board |

Questa comes with the Cyclone V simulation libraries already compiled
(`cyclonev_ver`, `altera_ver`), so nothing has to be compiled from
`quartus/eda/sim_lib`.

## Environment

The scripts call `vsim`, `vlog`, `quartus_sh`, `quartus_sta`, `quartus_pgm`
and `python` by name, so they must be in `PATH`. Questa also needs its
license.

| Variable | Value on the reference system |
|---|---|
| `PATH` | includes `C:\altera_lite\25.1std\questa_fse\win64` and `C:\altera_lite\25.1std\quartus\bin64` |
| `QUARTUS_ROOTDIR` | `C:\altera_lite\25.1std\quartus` |
| `LM_LICENSE_FILE` | path to the Questa license `.dat` file |
| `MGLS_LICENSE_FILE` | same file |
| `SALT_LICENSE_SERVER` | same file |

On Linux the same variables apply, for example:

```bash
export QUARTUS_ROOTDIR=$HOME/altera_lite/25.1std/quartus
export PATH=$HOME/altera_lite/25.1std/questa_fse/bin:$QUARTUS_ROOTDIR/bin:$PATH
export LM_LICENSE_FILE=$HOME/altera_lite/LR-xxxxxx_License.dat
export MGLS_LICENSE_FILE=$LM_LICENSE_FILE
export SALT_LICENSE_SERVER=$LM_LICENSE_FILE
```

Check with `vsim -version`, `quartus_sh --version` and `jtagconfig` (with
the board connected it lists `DE-SoC [USB-1]` with the HPS as device 1 and
the FPGA as device 2).

## Commands

Run everything from the repo root. `run.ps1` (Windows) and the `Makefile`
(Linux) are thin wrappers around the same Tcl and Python scripts.

| Task | Windows | Linux |
|---|---|---|
| Help | `.\run.ps1 help` | `make help` |
| RTL simulation (default k = 16) | `.\run.ps1 rtl` | `make rtl` |
| RTL simulation, k = 24 | `.\run.ps1 rtl -Depth 24` | `make rtl DEPTH=24` |
| Functional GLS (Quartus netlist, zero delay) | `.\run.ps1 gls_func -Depth 24` | `make gls_func DEPTH=24` |
| Approach A, slow corner | `.\run.ps1 gls_udp -Depth 24` | `make gls_udp DEPTH=24` |
| Approach A, sweep of k, typical corner | `.\run.ps1 gls_udp -Depths 8,16,24,32,40 -Corner typ` | `make gls_udp DEPTHS="8 16 24 32 40" CORNER=typ` |
| Approach B, slow corner | `.\run.ps1 gls_sdf -Depth 24` | `make gls_sdf DEPTH=24` |
| Approach B, sweep of k | `.\run.ps1 gls_sdf -Depths 8,16,24,32,40` | `make gls_sdf DEPTHS="8 16 24 32 40"` |
| Build for the board, k = 24 | `.\run.ps1 build -Depth 24` | `make build DEPTH=24` |
| Build several k (default list 8 to 64) | `.\run.ps1 build_sweep` | `make build_sweep` |
| Build only some k | `.\run.ps1 build_sweep -Depths 37,38,39` | `make build_sweep DEPTHS="37 38 39"` |
| Export the STA paths (needed by approach A) | `.\run.ps1 sta_export` | `make sta_export` |
| Program the board, k = 24 | `.\run.ps1 program -Depth 24` | `make program DEPTH=24` |
| Table k x T of every simulation | `.\run.ps1 report` | `make report` |
| Delete everything generated | `.\run.ps1 clean` | `make clean` |

`-Corner` / `CORNER=` is `min`, `typ` or `max` (default). On Windows,
`make` also works if `PYTHON=python` is given, since `python3` is the Linux
name.

### First run

Approach A takes its delays from the board builds, so build and export them
once:

```powershell
.\run.ps1 build_sweep      # about 2 minutes per depth
.\run.ps1 sta_export
.\run.ps1 gls_udp -Depths 8,16,24,32,40,48,64
```

`gls_func` and `gls_sdf` build what they need (the netlist of each depth,
its STA export and its SDF file) the first time each depth is simulated,
and again whenever the design changes.

### Showing a timing failure

On the board used for this demo the path stops meeting 100 MHz at
**k = 40**: k = 39 shows `0000` errors and k = 40 jumps straight to `FFFF`
with `LEDR0` on. Every chip is a bit different (process, temperature,
supply), so on another DE10-Standard the threshold can move a few stages
around 40; the STA guarantees only k <= 24 (slow corner).

```powershell
# Board: passes (HEX3-HEX0 = 0000, LEDR0 off)
.\run.ps1 build -Depth 39
.\run.ps1 program -Depth 39

# Board: fails (HEX3-HEX0 = FFFF, LEDR0 on); any k >= 40 also fails
.\run.ps1 build -Depth 40
.\run.ps1 program -Depth 40
```

After programming, wait for `LEDR9` (PLL locked) and press `KEY0` to clear
the counter. On Linux: `make build DEPTH=40` and `make program DEPTH=40`.

The same depth in simulation:

```powershell
.\run.ps1 rtl -Depth 40                  # PASS: zero delay never sees it
.\run.ps1 gls_func -Depth 40             # PASS: the netlist alone neither
.\run.ps1 gls_sdf -Depth 40              # FAIL at 10 ns (needs 16 ns)
.\run.ps1 gls_udp -Depth 40 -Corner typ  # FAIL at 10 ns (needs 12 ns)
```

## Repository layout

```
seq_timing_gls_demo/
├── README.md, run.ps1, Makefile
├── rtl/        synthesizable design (core, board_top, LFSR, delay chain, ...)
├── cells/      simulation cells for approach A (UDP + specify)
├── tb/         self-checking testbench, shared by every simulation mode
├── filelists/  what each simulation mode compiles
├── quartus/    board and core_sim revisions, constraints, PLL
├── scripts/    simulation, build, STA export, SDF and log scripts
└── docs/       theory, design and results
```

Everything generated (Quartus builds, netlists, SDF files, CSV files, work
libraries, logs) goes to `build/`, which is not tracked.

## Documentation

Start with [`docs/README.md`](docs/README.md): theory, then design, then
results. Each folder has its own README:
[`rtl/`](rtl/README.md), [`cells/`](cells/README.md), [`tb/`](tb/README.md),
[`filelists/`](filelists/README.md), [`quartus/`](quartus/README.md),
[`scripts/`](scripts/README.md).

## License

MIT, see [`LICENSE`](LICENSE).
