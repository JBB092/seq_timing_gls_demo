# Design

> AI usage disclaimer: this document was created or assisted using AI tooling and then reviewed against the actual project files.

Why the demo is built the way it is. The testbench and the simulation modes
are described in `tb/README.md`; the theory is in `theory.md`.

## 1. The problem

The goal is to run Questa simulations of a sequential circuit with delays
close to those of a gate-level simulation (GLS) with timing, and to compare
them with the real board.

On Cyclone V this is not available out of the box. Quartus writes a
gate-level netlist (`.svo`) made of Cyclone V cells, but no SDF file with
their delays. The Questa models of those cells have timing checks and delay
paths, all set to 0. So the GLS that Quartus gives is **functional only**:
it checks that synthesis kept the logic, but like the RTL simulation it can
never show a setup violation.

The reference repo for the course does exactly that kind of functional GLS.
This demo keeps it (`gls_func` mode) and adds two ways to put delays back.

## 2. The circuit

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

(Stage i uses LFSR bit j = 1 + (i-1) mod 15, so the bits repeat every 15
stages. Bit 0 only enters at the head.)

- **LFSR** (16 bits, `x^16+x^14+x^13+x^11+1`, seed `ACE1`): new data on every
  clock edge, so the chain is always switching. It is deterministic, so the
  testbench can predict every value. All 16 bits are launching registers.
- **Delay chain**: stage i is `XOR(stage i-1, one LFSR bit)`. `(* keep *)`
  forces one LUT per stage; without it Quartus would merge the chain into
  two or three LUT levels. LFSR bit 0 enters at the head and crosses all k
  stages, which makes it the longest path: t_comb grows about linearly with
  k.
- **Capture flip-flop**: samples the chain output on the next edge. When
  the chain is too slow, it stores the wrong value.
- **Reference**: the same XOR of the same LFSR bits, without `keep`. Quartus
  compresses it to one or two LUTs, so it always meets timing. It does not
  need to predict the LFSR: both paths get the same inputs and only differ in
  how long they take.
- **Error checker**: compares the two captured bits, counts the differences
  (24 bits, saturating) and keeps a sticky error flag. On the board the
  count goes to the displays.

The clock period T stays fixed and the depth k changes t_comb. Each depth is
compiled separately. On the board the period is 10 ns (a PLL makes 100 MHz
from the 50 MHz oscillator). That frequency was chosen after the first
timing analysis so that the threshold falls in the middle of the swept
depths (8 to 64).

There is no oscilloscope or logic analyzer: the evidence from the board is
the error count on the 7-segment displays and the error LED.

### Depth set with a `define`

The depth is the macro `CHAIN_DEPTH` (default 16 in `rtl/chain_cfg.svh`),
fixed at compile time. This was suggested by the course instructor.

- Questa: `vlog +define+CHAIN_DEPTH=<k>`
- Quartus: `scripts/build.tcl` adds `VERILOG_MACRO "CHAIN_DEPTH=<k>"` to a
  copy of the project in `build/quartus/<revision>_d<k>/`, so the `.qsf` in
  the repo is never edited and every depth keeps its own outputs.

The alternative was one long chain with a multiplexer, driven by the board
switches, to pick the depth at run time. It was dropped because:

- the multiplexer adds its own delay, and every tap of the chain becomes a
  timing path, so the timing report has many critical paths and some fail
  on purpose
- with the macro each build has **one** critical path, so the slack Quartus
  reports is a clean prediction of whether that depth passes

The price is one Quartus build (about 2 minutes) and one `.sof` per depth.
The scripts build a list of depths in one go (`build_sweep`).

## 3. Approach A: custom cells (UDP + specify)

The chain stage and the flip-flop are written twice, with the same module
name and ports:

| Module | RTL version (Quartus, `rtl` mode) | Cell version (`gls_udp` mode) |
|---|---|---|
| `chain_stage` | `rtl/chain_stage_rtl.sv`, XOR with `keep` | `cells/chain_stage_cell.sv` |
| `dff_stage` | `rtl/dff_stage_rtl.sv`, `always_ff` | `cells/dff_stage_cell.sv` |

The cell versions are built from user-defined primitives (a truth table, as
suggested by the instructor) and a `specify` block:

- each chain stage: one delay from each input to the output, `T_STAGE`
- each flip-flop: `T_CO` from clock to output, and `$setuphold` with `T_SU`
  and `T_H`; a violation makes the output `X`

The filelist of each mode picks the version (`filelists/rtl.f` or
`filelists/gls_udp.f`), so the code has no `ifdef`. The delays are averages
over all the board builds, written by `scripts/gen_timing_cfg.py` to
`build/timing_cfg.svh` as `min:typ:max` triplets; one file serves every
depth, and a Questa compile takes seconds, so sweeping k is cheap.

- **Good**: easy to read and to explain; it does not depend on Quartus
  internal names.
- **Limits**: the topology is written by hand and every stage has the same
  average delay, while the real wiring changes from stage to stage and from
  build to build.

Details in `cells/README.md`.

## 4. Approach B: Quartus netlist + our own SDF

A second Quartus revision, `core_sim` (`quartus/core_sim.qsf`), compiles only
`core`: no PLL, the clock on the same pin as on the board, and the other
ports as virtual pins, so the testbench can set the period. Quartus writes
its netlist for every depth.

`scripts/gen_sdf.py` writes an SDF file for each depth from the timing
analysis of **that** build:

- every chain LUT on the path: the wire delay to its input plus the LUT
  delay
- every register (`dffeas` cells): clock-to-output delay and a setup/hold
  check

Questa loads it with `-sdfmin`, `-sdftyp` or `-sdfmax`, replacing the zero
delays of the cell models. `scripts/sim.tcl` builds the netlist, the timing
export and the SDF of a depth when they are missing or outdated.

- **Good**: the real structure of the chip, and the delays of each build
  stage by stage; it is the closest to a GLS with timing.
- **Limits**: it depends on Quartus internal names (they match the RTL names
  here, e.g. `u_chain|g_stage[3].u_stage|y_keep`); among the LUTs only the
  chain stages on the critical path get delays (the other inputs, the
  reference and the counter keep zero delay); the `core_sim` builds are
  placed a little differently from the board builds.

Two risks were checked when it was built: the names in the timing report
match the netlist instances directly, and the registers come out as
`dffeas`, whose model does have usable setup/hold checks.

## 5. Where the delays come from

Both approaches take their delays from the Quartus timing analysis.
`scripts/sta_export.tcl` runs in `quartus_sta` and, for every build and
every corner, exports the path from LFSR bit 0 to the capture flip-flop
point by point: the wire (`ic`) and LUT (`cell`) delay of every stage, the
clock network delays, the uncertainty and the slack.

The Cyclone V timing model reports the register times (`uTco`, `uTsu`,
`uTh`) as **0**. The register delay is inside the clock network delay and in
the last cell before the capture register (`reg_in` column, about 0.22 ns
in the slow corner). So tCO, tSU and tH are derived, the same way in both
approaches:

| Value | Taken as |
|---|---|
| tCO | `reg_in` |
| tSU | uncertainty minus clock skew |
| tH | 0 |
| Stage delay | wire + LUT delay of the stage |

`tCO + tSU` is then exactly the margin the timing analyzer adds to the data
path, so the shortest period of a simulated depth matches the one from the
STA. tH = 0 stays below tCO in every corner, which avoids false hold
violations between the LFSR registers (their feedback has no delay in the
model).

The three values of each triplet:

| | Corner |
|---|---|
| min | Fast 1100mV 0C |
| typ | Midpoint of min and max (Quartus has no typical corner) |
| max | Slow 1100mV 85C |

A uses averages over all the board builds; B uses the values of each
`core_sim` build.

## 6. Notes

- Each depth is placed and routed separately, so the delay per stage is not
  the same in every build (0.34 to 0.43 ns in the slow corner). The slack is
  close to linear in k, but not exactly.
- The worst path of a build sometimes starts at LFSR bit 1 or 2 instead of
  bit 0 (a longer wire to the first stages). The difference is at most
  0.3 ns. The export always uses the bit 0 path, the one that crosses every
  stage, and also records the worst slack.
- A design is signed off with the slow corner. The board works beyond that,
  because a chip at room temperature is faster than the worst case.
- On the board a failing depth does not count errors slowly: the counter
  saturates right away. One extra stage adds 0.2 to 0.4 ns, much more than
  the small window where a path fails only now and then.
- Hold, skew and metastability are covered in `theory.md`; the demo
  measures setup only.

Results: `results.md`.
