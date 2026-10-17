# Testbench directory

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

`tb_core.sv` is a self-checking testbench for `core`. The same file works
for every simulation mode, because it only looks at the ports of `core`.

## What it does

1. Generates the clock with a period T that can change during the run.
2. Keeps its own model of the LFSR and of the chain function, so it knows
   the right value of every captured bit without looking inside the DUT.
3. Holds `rst` for 3 cycles before each period (`core` needs at least 2) and
   does not check anything while `rst` is high.
4. Checks `chain_q` and `ref_q` on every cycle, half a period after the edge
   that captured them, with `!==`. An `X` counts as an error.
5. Sweeps T from long to short and prints a T -> PASS/FAIL table.
6. Gives a verdict: `$finish` if it passed, `$fatal` if it failed.

The testbench only sweeps T. The depth k is fixed when the design is
compiled (`CHAIN_DEPTH`), so to try several depths the scripts run the
simulation once per k.

## Running it

```powershell
.\run.ps1 rtl                          # default depth (16)
.\run.ps1 rtl -Depth 24
.\run.ps1 gls_udp                      # approach A, slow corner
.\run.ps1 gls_udp -Depth 40 -Corner typ
.\run.ps1 gls_udp -Depths 8,16,24,32,40,48,64
.\run.ps1 report                       # k x T table of all the runs
```

On Linux: `make rtl`, `make rtl DEPTH=24`, `make gls_udp DEPTH=40 CORNER=typ`,
`make gls_udp DEPTHS="8 16 24 32 40 48 64"`, `make report`.

The log of each run is in `build/<mode>/d<k>/sim.log`; for `gls_udp` the
folder includes the corner (`build/gls_udp_max/d40/sim.log`).

## Simulation modes

| Mode | What is simulated | Passes when | Expected result |
|---|---|---|---|
| `rtl` | The RTL code, zero delay | Every period passes | Passes at every T and every k |
| `gls_udp` | Approach A: the chain stages and flip-flops are the cells in `cells/`, with delays from the Quartus timing analysis | Every period from 10 ns up passes | Fails from some k on |

`rtl` checks that the logic is right. It cannot find timing problems,
because every gate switches in zero time; a failure there is a real bug.

`gls_udp` is judged at the board period (10 ns, 100 MHz) and above, so its
result says whether that depth would work on the board according to the
chosen corner. Shorter periods are still simulated and shown in the table.

## The three zones

At the board period, as k grows:

1. Small k: passes in every corner and on the board.
2. Middle k: fails with the slow corner but passes on the board, because a
   chip at room temperature is faster than the worst case.
3. Large k: fails everywhere.

Results with T = 10 ns (`.\run.ps1 gls_udp -Depths ... -Corner <c>`):

| | Last k that passes | First k that fails |
|---|---|---|
| `gls_udp`, max (slow corner) | 24 | 32 |
| `gls_udp`, typ | 32 | 36 |
| `gls_udp`, min (fast corner) | 48 | 64 |
| Board | 39 | 40 |

`rtl` passes for every k.

## Options

Plusargs, all times in ps:

| Plusarg | Default | Meaning |
|---|---|---|
| `+T_MAX` | 40000 | First (longest) period |
| `+T_MIN` | 2000 | Last (shortest) period |
| `+T_STEP` | 2000 | Step between periods |
| `+CYCLES` | 1000 | Cycles checked at each period |
| `+T_CHECK` | 10000 | The verdict only looks at periods >= this one; 0 means every period |

`scripts/sim.tcl` passes `+T_CHECK=0` for `rtl` and leaves the default for
`gls_udp`. To change the others, call `vsim` by hand on a library already
built by the scripts, for example:

```
vsim -c -t ps +maxdelays -onfinish stop -lib build/gls_udp_max/d16/work tb_core +T_MAX=8000 +T_MIN=5000 +T_STEP=500 +T_CHECK=0 -do "run -all; quit -f"
```

## Reading the output

```
==== T sweep: CHAIN_DEPTH=16, 1000 cycles per T ====
Delay corner: max (+maxdelays)
chain_err/ref_err: wrong or X output; x_count: X outputs (timing check violations)
   T(ps)  chain_err    ref_err  x_count  result
   40000          0          0        0  PASS
   ...
    8000          0          0        0  PASS
    6000        503          0        0  FAIL
    4000        781          0      525  FAIL
    2000        584          0       74  FAIL
==== 3 of 20 periods failed ====
Shortest period that passes along with every longer one: 8000 ps
Verdict at T >= 10000 ps: PASS
```

- `Delay corner`: detected from the `+mindelays` / `+maxdelays` option; the
  RTL has no delays, so it does not matter there
- `chain_err`: cycles where the captured chain bit was wrong or `X`
- `ref_err`: same for the reference bit. The reference path has no delay,
  so it should always be 0; anything else would mean a false hold violation
  in the LFSR
- `x_count`: cycles where an output was `X`. In `gls_udp` an `X` only comes
  from a setup/hold violation in a cell, so this counts the violations

In the example, at 6 ns the chain output arrives after the clock edge: the
flip-flop keeps the old value (errors, no `X`). At 4 ns some changes land
inside the setup window and give `X`. See `cells/README.md`.

The last line printed by the script is `=== RESULT: PASS`, `FAIL`,
`COMPILE ERROR` or `LOAD ERROR`, and the exit code is 0, 1 or 2.

## Timing check messages

Every setup/hold violation would print a 3-line `** Error: $setup(...)`
message, hundreds per run. `gls_udp` hides them with `+no_tchk_msg`; the
violations still happen and still give `X`, so they are counted in
`x_count`. To see each one:

```
vsim -c -nolog -do "set MODE gls_udp; set TCHK_MSG 1; set DEPTH 16; source scripts/sim.tcl"
```

## The k x T table

`.\run.ps1 report` (`scripts/parse_logs.py`) merges the tables of all logs,
one table per mode and corner:

```
k x T table, mode gls_udp_typ  (. = PASS, F = FAIL, - = not run)
    k |   40   38  ...   12   10    8    6    4    2 | min T pass
    8 |    .    .  ...    .    .    .    .    .    F | 4 ns
   32 |    .    .  ...    .    .    F    F    F    F | 10 ns
   40 |    .    .  ...    .    F    F    F    F    F | 12 ns
```

It is also saved as `build/reports/kxt_<mode>.csv`.

## Why `-t ps`

The default time resolution in Questa is 1 ns. Delays smaller than that
would be rounded to zero, so the scripts always call `vsim -t ps`.
