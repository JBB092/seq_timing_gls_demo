# Timing theory

> AI usage disclaimer: this document was created or assisted using AI tooling and then reviewed against the actual project files.

The minimum theory needed to follow the demo: what limits the clock of a
register-to-register path, and why a zero-delay simulation never sees it.

## A register-to-register path

```
           launch                       capture
          +------+     combinational   +------+
   d ---->| FF A |---> logic (t_comb) ->| FF B |----> q
          +------+                     +------+
             ^                            ^
   clk ------+----------------------------+
```

On every rising edge, FF A launches a new value. It has to cross the logic
and reach FF B before the next rising edge, one clock period T later. In
the demo, FF A is the LFSR, the logic is the delay chain of k XOR stages and
FF B is the capture flip-flop `u_chain_ff`.

## The three register times

| Time | Name | Meaning |
|---|---|---|
| tCO | Clock to output | After the clock edge, how long the flip-flop takes to show the new value at its output |
| tSU | Setup time | How long before the clock edge the input must be stable |
| tH | Hold time | How long after the clock edge the input must stay stable |

```
clk        ____/""""""""\________/""""""""
                  |<-tCO->|
q (FF A)   ======X=================X======
d (FF B)   ==========X===========|======|===
                                  |<tSU>|<tH>|
                                       edge
```

The input of FF B must not change inside the window from tSU before the
edge to tH after it.

## Setup: the path must be fast enough

The new value leaves FF A tCO after the edge and needs t_comb more to reach
FF B, where it must arrive tSU before the next edge:

```
tCO + t_comb + tSU <= T
```

The margin is the **setup slack**:

```
slack = T - (tCO + t_comb + tSU)
```

Positive slack: the path meets the clock. Negative slack: the value arrives
too late. The timing analyzer (STA) in Quartus computes this slack for every
path.

In the demo T is fixed at 10 ns (100 MHz) and t_comb grows with the chain
depth k, about 0.35 ns per stage in the slow corner, so there is a depth
where the slack crosses zero. For example, at k = 16 Quartus reports a
slack of 2.740 ns in the slow corner, and at k = 40, -5.241 ns.

### What happens on a setup violation

- **On the chip**, the capture flip-flop samples the input while it is
  still changing. Usually it keeps the old value (the new one arrived too
  late); if the input changes right at the edge, the output can be wrong or
  even metastable (see below). Either way the stored bit is not the one the
  logic computed.
- **In a simulation with timing checks**, a change inside the setup window
  makes the flip-flop output `X` (unknown). A change that arrives after the
  edge is outside the window, so no check fires, but the flip-flop keeps the
  old value and the result is wrong anyway.

The demo detects both: the testbench and the on-chip checker compare the
captured bit against a reference that always arrives in time.

## Hold: the path must not be too fast

The value launched on an edge must not reach FF B so early that it
overwrites the value FF B is capturing on that same edge:

```
tCO + t_comb_min >= tH
```

Hold problems do not depend on T, so slowing the clock does not fix them.
In this demo every path from a register to a register has at least tCO of
delay and tH is smaller than tCO, so hold always passes. The simulations
check it anyway: a model with tH > tCO gives false hold violations inside
the LFSR (see `cells/README.md`).

## Clock skew and uncertainty

The clock does not reach every flip-flop at the same instant.

- **Skew** is the difference between the clock arrival at the capture and
  at the launch flip-flop. If the capture clock arrives later, the data
  gets a bit more time (helps setup, hurts hold), and the other way round.
- **Uncertainty** covers jitter (edge-to-edge variation of the clock) and
  other effects; the analyzer takes it away from the margin.

With both, the setup slack becomes:

```
slack = (T + skew - uncertainty) - (tCO + t_comb + tSU)
```

In the demo the skew is small (about -0.07 ns in most builds) and the
uncertainty is 0.08 ns on the board (PLL clock).

## Metastability

If the input of a flip-flop changes right at the clock edge, the flip-flop
can stay between 0 and 1 for a while before settling on either value. This
cannot be avoided for signals that are not synchronous to the clock, such as
a push button. The usual fix is a **synchronizer**: two flip-flops in a row,
so the first one has a whole clock period to settle before the second one
samples it. The board top level uses one for `KEY0` and one for the PLL
`locked` signal.

Metastability is not simulated in this demo (a simulator only knows 0, 1
and `X`).

## PVT corners

The delays of a chip depend on:

- **P**rocess: every chip comes out of the factory a bit faster or slower
- **V**oltage: lower supply voltage, slower logic
- **T**emperature: in this device, hotter is slower

The timing analyzer cannot know the exact chip, so it checks the extremes.
For Cyclone V, Quartus reports four corners:

| Corner | Meaning |
|---|---|
| Slow 1100mV 85C | Slow silicon at 85 C, the worst case for setup |
| Slow 1100mV 0C | Slow silicon at 0 C |
| Fast 1100mV 85C | Fast silicon at 85 C |
| Fast 1100mV 0C | Fast silicon at 0 C, the best case (and the worst for hold) |

A design is signed off when it passes in every corner. A real chip at room
temperature lands somewhere between the slow and the fast corners, which is
why the board in this demo still works at depths that fail in the slow
corner (see `results.md`).

## RTL, functional GLS and GLS with delays

| Simulation | What it simulates | Delays | Finds |
|---|---|---|---|
| RTL | The HDL code | None: every gate switches in zero time | Logic errors |
| Functional gate-level (GLS) | The netlist after synthesis and placement, built from the device cells | None | Synthesis problems (logic that changed) |
| GLS with delays | The same netlist with the delay of every cell and wire (an SDF file) | Real, per corner | Timing problems, as well as the above |

In a zero-delay simulation the value launched on an edge is always at the
capture flip-flop before the next edge, whatever T is, so a setup violation
cannot happen. For many device families Quartus writes the SDF file needed
for the third kind. **For Cyclone V it does not**: it only writes the
functional netlist, so the gate-level simulation it gives is the second
kind. This demo adds delays in two ways to get the third kind; see
`design.md`.
