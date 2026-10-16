# Testbench directory

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

`tb_core.sv` is a self-checking testbench for `core`. The same file is meant
to work for every simulation mode, because it only looks at the ports of
`core`.

## What it does

1. Generates the clock with a period T that can change during the run.
2. Keeps its own model of the LFSR and of the chain function, so it knows
   the right value of every captured bit without looking inside the DUT.
3. Holds `rst` for 3 cycles before each period (`core` needs at least 2) and
   does not check anything while `rst` is high.
4. Checks `chain_q` and `ref_q` on every cycle, half a period after the edge
   that captured them, with `!==`. An `X` counts as an error.
5. Sweeps T from long to short and prints a T -> PASS/FAIL table.
6. Ends with `$finish` if every period passed, or `$fatal` if any failed.

The testbench only sweeps T. The depth k is fixed when the design is
compiled (`CHAIN_DEPTH`), so to try several depths the scripts run the
simulation once per k.

## Running it

```powershell
.\run.ps1 rtl              # default depth (16)
.\run.ps1 rtl -Depth 24
.\run.ps1 report           # k x T table of all the runs
```

On Linux: `make rtl`, `make rtl DEPTH=24`, `make report`.

The log of each run is in `build/<mode>/d<k>/sim.log`.

## Options

Plusargs, all times in ps:

| Plusarg | Default | Meaning |
|---|---|---|
| `+T_MAX` | 40000 | First (longest) period |
| `+T_MIN` | 2000 | Last (shortest) period |
| `+T_STEP` | 2000 | Step between periods |
| `+CYCLES` | 1000 | Cycles checked at each period |

For now the scripts always use the defaults. To change them, call `vsim` by
hand on a library already built by the scripts, for example:

```
vsim -c -t ps -onfinish stop -lib build/rtl/d16/work tb_core +T_MIN=4000 -do "run -all; quit -f"
```

## Reading the output

```
==== T sweep: CHAIN_DEPTH=16, 1000 cycles per T ====
   T(ps)  chain_err    ref_err  x_count  result
   40000          0          0        0  PASS
   ...
    2000          0          0        0  PASS
==== 0 of 20 periods failed ====
```

- `chain_err`: cycles where the captured chain bit was wrong
- `ref_err`: same for the reference bit (should always be 0)
- `x_count`: cycles where one of the outputs was `X`

The last line printed by the script is `=== RESULT: PASS`, `FAIL` or
`COMPILE ERROR`, and the exit code is 0, 1 or 2.

## Simulation modes

| Mode | What is simulated | Expected result |
|---|---|---|
| `rtl` | The RTL code, zero delay | Passes at every T and every k |

`rtl` checks that the logic is right. It cannot find timing problems,
because every gate switches in zero time. The modes with delays are added
in later steps.

## Why `-t ps`

The default time resolution in Questa is 1 ns. Delays smaller than that
would be rounded to zero, so the scripts always call `vsim -t ps`.
