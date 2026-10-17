# Quartus directory

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

Quartus project for the Terasic DE10-Standard (Cyclone V SX, `5CSXFC6D6F31C6`).

## Contents

| File | What it is |
|---|---|
| `board.qpf` | Project file, revision `board` |
| `board.qsf` | Settings of the `board` revision: device, sources, pins |
| `board.sdc` | Timing constraints |
| `ip/pll_main.v` | PLL variation: 50 MHz in, 100 MHz out, with a `locked` output |
| `ip/pll_main.qip` | Quartus settings that go with the PLL |

## The `board` revision

Top level: `rtl/board_top.sv`. It wraps `core` with the PLL, a 2-FF
synchronizer for KEY0 and the 7-segment displays.

| Board | Use |
|---|---|
| `KEY0` | Clears the error counter and the error LED |
| `HEX5-HEX4` | Compiled depth k, in decimal |
| `HEX3-HEX0` | Error count in hex (shows `FFFF` once it goes above 16 bits) |
| `LEDR0` | At least one error since the last KEY0 |
| `LEDR9` | PLL locked |

Only the 54 pins used by the design are assigned (taken from the Terasic
Golden Top), all 3.3-V LVTTL.

## How the depth is passed

`board.qsf` does not set `CHAIN_DEPTH`. `scripts/build.tcl` copies the
project to `build/quartus/board_d<k>/`, adds

```
set_global_assignment -name VERILOG_MACRO "CHAIN_DEPTH=<k>"
```

to the copy and compiles it there. The files in this folder are never
modified by a build, and each depth keeps its own output folder, so
several `.sof` files can exist at the same time.

## Timing constraints (`board.sdc`)

```
create_clock -name CLOCK_50 -period 20 [get_ports CLOCK_50]
derive_pll_clocks
derive_clock_uncertainty
set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {LEDR[*] HEX*}]
```

- `create_clock`: the 50 MHz board oscillator.
- `derive_pll_clocks`: creates the 100 MHz PLL output clock from the PLL settings.
- `derive_clock_uncertainty`: adds the PLL jitter to the analysis.
- The false paths remove the button and the displays from the analysis:
  KEY0 goes through a synchronizer and the displays are read by a person.

## Slack as a prediction

The only timing path that matters is LFSR -> delay chain -> capture flip-flop.
Its delay grows with k, so the worst setup slack of each build tells whether
that depth should work at 100 MHz (T = 10 ns):

- positive slack: the chain output arrives before the clock edge
- negative slack: it arrives late, and the error counter should go up

Quartus reports four corners. The slow corners are the worst case (slowest
silicon, high temperature); the fast corners are the best case. A real chip
at room temperature lands somewhere in between.

Worst setup slack from `.\run.ps1 build_sweep` (ns):

| k | Slow 85C | Slow 0C | Fast 85C | Fast 0C |
|---|---|---|---|---|
| 8 | 5.789 | 6.015 | 7.606 | 7.859 |
| 16 | 2.740 | 2.950 | 6.069 | 6.392 |
| 24 | 0.584 | 0.856 | 4.751 | 5.190 |
| 32 | -2.088 | -1.699 | 3.272 | 3.863 |
| 36 | -2.858 | -2.470 | 2.896 | 3.505 |
| 40 | -5.241 | -4.664 | 1.388 | 2.185 |
| 44 | -6.534 | -5.923 | 0.871 | 1.676 |
| 48 | -7.252 | -6.704 | 0.449 | 1.281 |
| 64 | -13.992 | -13.310 | -3.188 | -2.039 |

The slack drops by about 0.35 ns per stage, but not exactly linearly: each
depth is a separate compilation and the placement (and so the wiring delay)
changes a little between them. The board results go in `docs/results.md`.

## Building

```powershell
.\run.ps1 build                    # default depth (16)
.\run.ps1 build -Depth 40
.\run.ps1 build_sweep              # 8 16 24 32 36 40 44 48 64
.\run.ps1 build_sweep -Depths 37,38,39
```

On Linux: `make build`, `make build DEPTH=40`, `make build_sweep`,
`make build_sweep DEPTHS="37 38 39"`.

A build takes about 2 minutes. Outputs:

| Path | Content |
|---|---|
| `build/quartus/board_d<k>/output_files/board.sof` | Bitstream for depth k |
| `build/quartus/board_d<k>/output_files/board.sta.rpt` | Full timing report |
| `build/quartus/board_sweep.csv` | Worst setup slack per depth and corner (last sweep) |

## Programming

```powershell
.\run.ps1 program -Depth 40
```

This runs

```
quartus_pgm -c "DE-SoC [USB-1]" -m JTAG -o "p;build/quartus/board_d40/output_files/board.sof@2"
```

The `@2` matters: the DE10-Standard JTAG chain has the HPS (ARM side) as
device 1 and the FPGA as device 2. Run `jtagconfig` to see the chain. If the
cable has another name, set the `JTAG_CABLE` environment variable.

There is one `.sof` per depth. To test the board: program a depth, press
KEY0, and watch HEX3-HEX0 and LEDR0 for a few seconds.

## The PLL (`ip/`)

`pll_main.v` and `pll_main.qip` are the whole PLL variation; nothing else is
needed to build. They were generated with `ip-generate` (the tool behind the
IP Catalog). To change the frequency, run it again with another value of
`gui_output_clock_frequency0`:

```powershell
C:\altera_lite\25.1std\quartus\sopc_builder\bin\ip-generate.exe `
  --component-name=altera_pll --output-name=pll_main --output-directory=quartus/ip `
  --file-set=QUARTUS_SYNTH --language=VERILOG `
  --system-info=DEVICE_FAMILY="Cyclone V" --system-info=DEVICE=5CSXFC6D6F31C6 --system-info=DEVICE_SPEEDGRADE=6 `
  --component-parameter=gui_reference_clock_frequency=50.0 `
  --component-parameter=gui_number_of_clocks=1 `
  --component-parameter=gui_output_clock_frequency0=100.0 `
  --component-parameter=gui_operation_mode=direct `
  --component-parameter=gui_use_locked=true
```

The PLL reset input is tied to 0, so Quartus prints a warning about it. With
the stable board oscillator the PLL does not lose lock; if it ever did,
programming the board again resets it.

## Notes

- Opening `board.qpf` in the Quartus GUI and compiling there also works, but
  it uses the default depth and writes `db/`, `incremental_db/` and
  `output_files/` inside this folder (ignored by git, removed by
  `.\run.ps1 clean`).
- `board.qsf` ends with `LAST_QUARTUS_VERSION`. Quartus adds that line on
  every compile, so keeping it avoids a modified `.qsf` after opening the
  project.
