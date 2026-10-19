# Results

> AI usage disclaimer: this document was created or assisted using AI tooling and then reviewed against the actual project files.

All results use a 100 MHz clock (T = 10 ns) from the PLL on the board, and
the same period as the verdict in simulation.

## Environment

### Windows (reference system)

Recorded on 2026-10-16.

| Item | Version |
|---|---|
| Operating system | Windows 10 Home Single Language 22H2, build 19045.6466, 64-bit |
| Quartus | Quartus Prime 25.1std.0 Build 1129 10/21/2025 SC Lite Edition |
| Questa | Questa Altera Starter FPGA Edition-64 vsim 2025.2 (2025.05, May 31 2025) |
| Python | 3.12.6 |
| PowerShell | 5.1.19041.6456 |
| make | GNU Make 3.81 |
| git | 2.49.0.windows.1 |
| Board | Terasic DE10-Standard |
| FPGA | Cyclone V SX SoC, 5CSXFC6D6F31C6N |

JTAG chain (`jtagconfig`), checked when the environment was set up:

| Item | Value |
|---|---|
| Cable | `DE-SoC [USB-1]` (on-board USB-Blaster II) |
| Device 1 | HPS (`SOCVHPS`) |
| Device 2 | FPGA (the one the scripts program, `@2`) |

The full `jtagconfig` output is still to be added.

### Ubuntu

Recorded on 2026-10-19, on the same laptop (dual boot) and the same board.

| Item | Version |
|---|---|
| Operating system | Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic, x86_64 |
| Quartus | Quartus Prime 25.1std.0 Build 1129 10/21/2025 SC Lite Edition |
| Questa | Questa Altera Starter FPGA Edition-64 vsim 2025.2 (2025.05, May 31 2025) |
| Python | 3.14.4 |
| make | GNU Make 4.4.1 |
| git | 2.53.0 |

`jtagconfig`:

```
1) DE-SoC [1-2]
  4BA00477   SOCVHPS
  02D020DD   5CSEBA6(.|ES)/5CSEMA6/..
```

`02D020DD` is the JTAG ID shared by several Cyclone V SoC parts, so
`jtagconfig` prints a list of names; the device is the 5CSXFC6D6F31C6N.

Notes from the setup (Ubuntu 26.04 is newer than the distributions Quartus
25.1 lists as supported, but nothing extra was needed):

- Quartus, Questa and the Cyclone V device file come from the Quartus Lite
  Linux download; with the three installers in one folder, the Quartus
  installer also installs the other two
  (`--mode unattended --installdir $HOME/altera_lite/25.1std`).
- The Questa license file from Windows works as is (it is tied to the MAC
  address of the network card, the same card in the dual boot).
- The environment variables are the same as on Windows (see the root
  README), set in `~/.bashrc`.
- The USB-Blaster II needs a udev rule (vendor `09fb`) to be used without
  `sudo`.
- On Linux the cable name includes the USB port (`DE-SoC [1-2]`,
  `DE-SoC [1-3]`, ...) and changes when the board is plugged into another
  port, so `scripts/build.tcl` reads it from `jtagconfig` before programming.

Results with `make` (one run of each, from a clean `build/`):

| Command | Result |
|---|---|
| `make rtl DEPTHS="16 40"` | PASS, PASS (every period) |
| `make build_sweep DEPTHS="16 39 40"` | 3 builds OK, 3 min 12 s |
| `make gls_udp DEPTHS="16 40"` | k = 16 PASS (8 ns), k = 40 FAIL (16 ns) |
| `make gls_udp DEPTHS="16 40" CORNER=typ` | k = 16 PASS (6 ns), k = 40 FAIL (12 ns) |
| `make gls_func DEPTH=40` | PASS (every period), with its `core_sim` build |
| `make gls_sdf DEPTH=40` | FAIL (16 ns), SDF annotation complete, 0 warnings |
| `make report` | k x T tables of the 8 runs |

In brackets, the shortest period that passes. These are the same values as
on Windows. Worst setup slack (ns) of the `board` builds on Ubuntu:

| k | Slow 85C | Slow 0C | Fast 85C | Fast 0C |
|---|---|---|---|---|
| 16 | 2.272 | 2.619 | 5.640 | 6.053 |
| 39 | -4.434 | -3.898 | 1.876 | 2.632 |
| 40 | -5.106 | -4.579 | 1.448 | 2.208 |

They differ a little from the Windows builds (k = 16: 2.272 against 2.740;
k = 40: -5.106 against -5.241): the placement is not the same on both
systems. The verdicts at 10 ns do not change. The approach A delays from
these three builds (`T_STAGE` 0.192:0.284:0.376 ns) are also close to the
Windows ones (0.184:0.274:0.364 ns, from nine builds).

Board test with the Ubuntu builds (same procedure as below):

| k | HEX3-HEX0 | LEDR0 | Result |
|---|---|---|---|
| 16 | `0000` | off | PASS |
| 39 | `0000` | off | PASS |
| 40 | counts up, then `FFFF` | on | FAIL |

The threshold is the same as on Windows (39 passes, 40 fails), but the
k = 40 build from Ubuntu fails differently: the count does not jump to
`FFFF` at once. HEX3-HEX2 count up slowly enough to follow by eye while
HEX1-HEX0 read `00`, and only when HEX3-HEX2 reach `FF` does the display
saturate to `FFFF`. HEX2 moves once every 256 errors, so the path fails on
a small fraction of the cycles (on the order of thousands of errors per
second out of 100 million cycles), and the two low digits change too fast
to read. This build is a little faster than the Windows one (slack -5.106
against -5.241 ns in the slow corner), so on this chip at room temperature
its path lands right at the edge: it misses the clock only on some data
patterns, the ones that make the slowest transition through the chain.

## Board test

Procedure for each depth k:

1. `.\run.ps1 program -Depth <k>`
2. Wait for `LEDR9` (PLL locked) and press `KEY0` to clear the counter.
3. Watch `HEX3-HEX0` (error count) and `LEDR0` (sticky error flag) for a
   few seconds.

The board was at room temperature.

| k | HEX3-HEX0 | LEDR0 | Result |
|---|---|---|---|
| 8 | `0000` | off | PASS |
| 16 | `0000` | off | PASS |
| 24 | `0000` | off | PASS |
| 32 | `0000` | off | PASS |
| 36 | `0000` | off | PASS |
| 37 | `0000` | off | PASS |
| 38 | `0000` | off | PASS |
| 39 | `0000` | off | PASS |
| 40 | `FFFF` | on | FAIL |
| 44 | `FFFF` | on | FAIL |
| 48 | `FFFF` | on | FAIL |
| 64 | `FFFF` | on | FAIL |

The failing depths reach `FFFF` (the display saturates above 16 bits) right
after `KEY0` is released: at 100 MHz, 65 536 cycles take 0.66 ms. None of
the Windows builds made the counter grow slowly. Each extra stage adds about
0.2 to 0.4 ns, much more than the small window where a path fails only now
and then, so a build usually either meets the clock edge or misses it on
most cycles. The k = 40 build made on Ubuntu landed inside that window and
counted up slowly (see the Ubuntu section above).

Depths 37, 38 and 39 are not in the default build list; they were built
separately (`.\run.ps1 build_sweep -Depths 37,38,39`) to find the exact
threshold.

## Comparison per depth

Verdict at T = 10 ns. Simulation columns: verdict, with the shortest passing
period in ns in brackets.

### Board builds and approach A

STA columns: worst setup slack in ns of the `board` builds, from
`.\run.ps1 build_sweep` (positive = should pass). Approach A (`gls_udp`)
takes its average delays from these builds.

| k | STA slow 85C | STA fast 0C | A max | A typ | A min | Board |
|---|---|---|---|---|---|---|
| 8 | 5.789 | 7.859 | PASS (4) | PASS (4) | PASS (2) | PASS |
| 16 | 2.740 | 6.392 | PASS (8) | PASS (6) | PASS (4) | PASS |
| 24 | 0.584 | 5.190 | PASS (10) | PASS (8) | PASS (6) | PASS |
| 32 | -2.088 | 3.863 | FAIL (14) | PASS (10) | PASS (8) | PASS |
| 36 | -2.858 | 3.505 | FAIL (14) | FAIL (12) | PASS (8) | PASS |
| 37 | -3.595 | 3.086 | FAIL (14) | FAIL (12) | PASS (8) | PASS |
| 38 | -4.058 | 2.911 | FAIL (16) | FAIL (12) | PASS (8) | PASS |
| 39 | -4.503 | 2.567 | FAIL (16) | FAIL (12) | PASS (8) | PASS |
| 40 | -5.241 | 2.185 | FAIL (16) | FAIL (12) | PASS (8) | **FAIL** |
| 44 | -6.534 | 1.676 | FAIL (18) | FAIL (14) | PASS (10) | FAIL |
| 48 | -7.252 | 1.281 | FAIL (18) | FAIL (14) | PASS (10) | FAIL |
| 64 | -13.992 | -2.039 | FAIL (24) | FAIL (18) | FAIL (14) | FAIL |

### Simulation builds and approach B

STA columns: worst setup slack in ns of the `core_sim` builds (no PLL, clock
from a pin, virtual pins), from `build/sta/core_sim_summary.csv`. Approach B
(`gls_sdf`) annotates the netlist of each of these builds with its own
delays.

| k | STA slow 85C | STA fast 0C | B max | B typ | B min | Board |
|---|---|---|---|---|---|---|
| 8 | 4.876 | 7.322 | PASS (6) | PASS (4) | PASS (4) | PASS |
| 16 | 2.370 | 5.974 | PASS (8) | PASS (6) | PASS (4) | PASS |
| 24 | 0.143 | 4.826 | PASS (10) | PASS (8) | PASS (6) | PASS |
| 32 | -1.833 | 3.892 | FAIL (12) | PASS (10) | PASS (8) | PASS |
| 36 | -3.053 | 3.205 | FAIL (14) | PASS (10) | PASS (8) | PASS |
| 37 | -3.229 | 3.163 | FAIL (14) | FAIL (12) | PASS (8) | PASS |
| 38 | -3.477 | 3.029 | FAIL (14) | FAIL (12) | PASS (8) | PASS |
| 39 | -4.334 | 2.687 | FAIL (16) | FAIL (12) | PASS (8) | PASS |
| 40 | -4.797 | 2.356 | FAIL (16) | FAIL (12) | PASS (8) | **FAIL** |
| 44 | -5.514 | 1.987 | FAIL (16) | FAIL (12) | PASS (10) | FAIL |
| 48 | -6.881 | 1.362 | FAIL (18) | FAIL (14) | PASS (10) | FAIL |
| 64 | -14.125 | -2.501 | FAIL (26) | FAIL (20) | FAIL (14) | FAIL |

The `core_sim` builds place the chain a little differently from the `board`
builds, so their slack is close but not the same (for example k = 40:
-4.797 against -5.241 ns in the slow corner).

`rtl` and `gls_func` (the Quartus netlist without delays) pass at every
period for every depth tested (`gls_func`: k = 16, 24 and 40).

## Thresholds

Last depth that passes and first that fails at T = 10 ns:

| Method | Last pass | First fail |
|---|---|---|
| STA `board`, slow 85C | 24 | 32 |
| STA `board`, fast 0C | 48 | 64 |
| STA `core_sim`, slow 85C | 24 | 32 |
| STA `core_sim`, fast 0C | 48 | 64 |
| Approach A, max (slow corner) | 24 | 32 |
| Approach A, typ (midpoint) | 32 | 36 |
| Approach A, min (fast corner) | 48 | 64 |
| Approach B, max (slow corner) | 24 | 32 |
| Approach B, typ (midpoint) | 36 | 37 |
| Approach B, min (fast corner) | 48 | 64 |
| Board | **39** | **40** |
| `rtl`, `gls_func` | every depth | none |

## Conclusions

- The zero-delay simulations pass for every depth, including the ones that
  fail on the board: `rtl` checks the logic and `gls_func` checks that
  Quartus built the same logic, but neither sees timing. In Cyclone V the
  gate-level simulation that Quartus gives is only `gls_func`.
- Approaches A and B both match the STA in the slow and fast corners (same
  thresholds at T = 10 ns), as expected: their delays come from the same
  timing analysis.
- B is the more precise of the two: each depth uses the delays of its own
  build, stage by stage, while A uses one average stage delay for every
  depth. For example, at k = 8 the `core_sim` build has long wires in its
  first stages (about 0.52 ns per stage against the 0.36 ns average), so B
  needs 6 ns where A passes at 4 ns; the STA agrees with B (4.64 ns for
  the path from LFSR bit 0).
- The board fails between k = 39 and k = 40, between the slow and the fast
  corners. A chip at room temperature and nominal voltage is faster than
  the worst case (slow silicon at 85 C) but not as fast as the best case.
  The midpoint (`typ`) is a closer guess than either corner, but still
  pessimistic (A: 32, B: 36).
- So the three zones show up: k <= 24 passes everywhere; 32 <= k <= 39
  fails in the slow-corner simulations and the STA but works on the board;
  k >= 40 fails on the board, and from 64 on it fails in every corner.
- A design is signed off with the slow corner: by that rule only k <= 24
  is safe at 100 MHz, even though the board still works up to k = 39.
