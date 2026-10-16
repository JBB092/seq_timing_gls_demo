# RTL directory

> AI usage disclaimer: this README was created or assisted using AI tooling and then reviewed against the actual project files.

Synthesizable sources of the demo. `core` is the circuit that gets simulated;
the board top level (added later) wraps it with a PLL, a button synchronizer
and the 7-segment displays.

## Module hierarchy

```
core
├── lfsr            16 x dff_stage
├── delay_chain     CHAIN_DEPTH x chain_stage
├── ref_path
├── dff_stage       u_chain_ff (captures the chain output)
├── dff_stage       u_ref_ff   (captures the reference output)
└── error_checker
```

## Files

| File | Module | What it does |
|---|---|---|
| `chain_cfg.svh` | (header) | Defines `CHAIN_DEPTH`, the number of chain stages (default 16) |
| `dff_stage_rtl.sv` | `dff_stage` | Plain D flip-flop |
| `lfsr.sv` | `lfsr` | 16-bit LFSR, period 65535. New data every clock |
| `chain_stage_rtl.sv` | `chain_stage` | One chain stage: XOR of the previous stage and one LFSR bit |
| `delay_chain.sv` | `delay_chain` | `CHAIN_DEPTH` stages in series; the output is always the last stage |
| `ref_path.sv` | `ref_path` | Same function as the chain, written so Quartus can compress it |
| `error_checker.sv` | `error_checker` | Compares both captured bits; 24-bit saturating error counter and sticky error flag |
| `core.sv` | `core` | Connects everything; this is the module the testbench simulates |

## How it works

Every LFSR bit is a launching flip-flop: each chain stage XORs a different
LFSR bit into the chain. Bit 0 enters at the head and is never used again,
so a change on it has to cross all the stages. That is the longest path,
and its delay grows with the depth k.

The reference path computes the same value but always arrives early.
If the captured chain bit and the captured reference bit differ, the chain
was too slow for the clock period (a setup violation), and the error counter
goes up.

### Why `keep` is only in the chain

`chain_stage_rtl.sv` puts `(* keep *)` on its output, so Quartus maps each
stage to its own LUT. Without it, Quartus would merge the XORs into two or
three LUT levels and the long path would disappear.

`ref_path.sv` has no `keep` on purpose. Repeated LFSR bits cancel in the
XOR, so Quartus reduces it to very little logic (one LUT for k = 64), and it
always meets timing.

### Two versions of `chain_stage` and `dff_stage`

The files in this folder are the versions used by Quartus and by the `rtl`
simulation. The `cells/` folder (added later) will have versions of the same
modules with propagation delays, used by the `gls_udp` simulation. The
filelist of each flow picks one or the other; there are no `ifdef`s.

## Changing the depth

`CHAIN_DEPTH` is a macro fixed at compile time. If nothing sets it,
`chain_cfg.svh` uses 16.

- Questa: `vlog +define+CHAIN_DEPTH=24 ...` (the scripts do this for you:
  `.\run.ps1 rtl -Depth 24` or `make rtl DEPTH=24`)
- Quartus: `VERILOG_MACRO "CHAIN_DEPTH=24"`, set by the build script at
  compile time, without editing the `.qsf`

Each depth is a separate compilation. There is no MUX to pick the depth at
run time.

## Main parameters

| Parameter | Default | Meaning |
|---|---|---|
| `WIDTH` | 16 | LFSR width (`lfsr`, `delay_chain`, `ref_path`, `core`) |
| `TAPS` | `16'hB400` | LFSR feedback taps |
| `SEED` | `16'hACE1` | LFSR value after reset (must not be zero) |
| `DEPTH` | `CHAIN_DEPTH` | Number of chain stages |
| `COUNT_WIDTH` | 24 | Error counter width |

## Reset

`rst` is synchronous and active high. It loads the LFSR seed and clears the
error checker. The two capture flip-flops have no reset, so `rst` has to
last at least 2 clock cycles; after that both hold the same value.
`clr` only clears the error counter and flag.
