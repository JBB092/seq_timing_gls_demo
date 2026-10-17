"""Writes one SDF file per depth for approach B (gls_sdf mode).

Usage (from the repo root, after building core_sim and running sta_export):
    python scripts/gen_sdf.py                # every core_sim depth exported
    python scripts/gen_sdf.py --depths 16 40

For each depth k it reads
    build/sta/core_sim_path_d<k>.csv      path from LFSR bit 0, every corner
    build/sta/core_sim_summary.csv        register input, skew, uncertainty
    build/quartus/core_sim_d<k>/simulation/questa/core_sim.svo   the netlist
and writes build/sdf/core_sim_d<k>.sdf with:
    - every chain LUT on the path: IOPATH from the input pin on the path to
      combout = wire delay to that pin + LUT delay
    - every register (dffeas): IOPATH clk -> q = T_CO, and SETUPHOLD on d
      and asdata = T_SU / T_H
Values are min:typ:max triplets in ns, as in gen_timing_cfg.py:
    min = Fast 1100mV 0C, typ = midpoint, max = Slow 1100mV 85C
The registers use the same split as approach A, but with the values of
this build: T_CO = reg_in, T_SU = uncertainty - clock skew, T_H = 0.
Cells off the path (other LUT inputs, reference path, counter) keep the
zero delays of the netlist.
"""

import argparse
import csv
import re
import sys
from pathlib import Path

STA_DIR = Path("build/sta")
SDF_DIR = Path("build/sdf")
MIN_CORNER = "Fast 1100mV 0C"
MAX_CORNER = "Slow 1100mV 85C"

RE_STAGE = re.compile(r"^(u_chain\|g_stage\[(\d+)\]\.u_stage\|y_keep)\|(\w+)$")
RE_DFFEAS = re.compile(r"^dffeas \\(\S+) \(", re.M)
RE_LCELL = re.compile(r"^cyclonev_lcell_comb \\(\S+) \(", re.M)


def netlist_path(depth):
    return Path(f"build/quartus/core_sim_d{depth}/simulation/questa/core_sim.svo")


def sdf_name(name):
    """Escape a netlist name for SDF: every character that is not a letter,
    digit or underscore gets a backslash."""
    return re.sub(r"([^A-Za-z0-9_])", r"\\\1", name)


def triplet(values):
    lo, hi = values[MIN_CORNER], values[MAX_CORNER]
    return f"({lo:.3f}:{(lo + hi) / 2:.3f}:{hi:.3f})"


def read_stages(path_csv):
    """Per corner: {stage: (input pin, wire + LUT delay)} along the path."""
    stages = {}
    pending_ic = {}
    with path_csv.open(newline="") as f:
        for row in csv.DictReader(f):
            m = RE_STAGE.match(row["node"])
            if not m:
                continue
            corner, stage, pin = row["corner"], int(m.group(2)), m.group(3)
            incr = float(row["incr"])
            if row["type"] == "ic":
                pending_ic[corner] = (pin, incr)
            elif row["type"] == "cell" and pin == "combout":
                in_pin, ic = pending_ic.pop(corner)
                stages.setdefault(corner, {})[stage] = (in_pin, ic + incr)
    return stages


def read_summary(depth):
    """Per corner: the summary row of this depth."""
    rows = {}
    with (STA_DIR / "core_sim_summary.csv").open(newline="") as f:
        for row in csv.DictReader(f):
            if int(row["depth"]) == depth:
                rows[row["corner"]] = row
    return rows


def make_sdf(depth):
    """Returns (sdf text, report lines), or raises SystemExit with a reason."""
    path_csv = STA_DIR / f"core_sim_path_d{depth}.csv"
    netlist = netlist_path(depth)
    for p in (path_csv, netlist):
        if not p.exists():
            sys.exit(f"{p} not found. Build core_sim for depth {depth} and run sta_export.")
    if path_csv.stat().st_mtime < netlist.stat().st_mtime:
        sys.exit(f"{path_csv} is older than the netlist of depth {depth}. "
                 "Run sta_export again (-Revision core_sim).")

    text = netlist.read_text(errors="replace")
    registers = RE_DFFEAS.findall(text)
    luts = set(RE_LCELL.findall(text))

    stages = read_stages(path_csv)
    summary = read_summary(depth)
    for corner in (MIN_CORNER, MAX_CORNER):
        if corner not in stages or corner not in summary:
            sys.exit(f"No data for corner '{corner}' at depth {depth}")
        if sorted(stages[corner]) != list(range(1, depth + 1)):
            sys.exit(f"Depth {depth}, {corner}: the path does not cross stages 1..{depth}")

    # Register times of this build, per corner
    t_co, t_su = {}, {}
    for corner in (MIN_CORNER, MAX_CORNER):
        row = summary[corner]
        t_co[corner] = float(row["reg_in"])
        t_su[corner] = abs(float(row["uncertainty"])) - float(row["clock_skew"])
    t_h = {MIN_CORNER: 0.0, MAX_CORNER: 0.0}

    cells = []
    for stage in range(1, depth + 1):
        inst = f"u_chain|g_stage[{stage}].u_stage|y_keep"
        if inst not in luts:
            sys.exit(f"Depth {depth}: {inst} is not a LUT in {netlist}")
        pins = {stages[c][stage][0] for c in (MIN_CORNER, MAX_CORNER)}
        if len(pins) != 1:
            sys.exit(f"Depth {depth}, stage {stage}: input pin differs between corners")
        delay = {c: stages[c][stage][1] for c in (MIN_CORNER, MAX_CORNER)}
        d = triplet(delay)
        cells.append(
            f' (CELL\n'
            f'  (CELLTYPE "cyclonev_lcell_comb")\n'
            f'  (INSTANCE {sdf_name(inst)})\n'
            f'  (DELAY (ABSOLUTE (IOPATH {pins.pop()} combout {d} {d})))\n'
            f' )\n')

    co, su, h = triplet(t_co), triplet(t_su), triplet(t_h)
    for inst in registers:
        cells.append(
            f' (CELL\n'
            f'  (CELLTYPE "dffeas")\n'
            f'  (INSTANCE {sdf_name(inst)})\n'
            f'  (DELAY (ABSOLUTE (IOPATH (posedge clk) q {co} {co})))\n'
            f'  (TIMINGCHECK\n'
            f'   (SETUPHOLD d (posedge clk) {su} {h})\n'
            f'   (SETUPHOLD asdata (posedge clk) {su} {h}))\n'
            f' )\n')

    header = (
        '(DELAYFILE\n'
        ' (SDFVERSION "3.0")\n'
        ' (DESIGN "core")\n'
        ' (VENDOR "seq_timing_gls_demo")\n'
        ' (PROGRAM "scripts/gen_sdf.py")\n'
        f' (VERSION "core_sim depth {depth}")\n'
        ' (DIVIDER /)\n'
        ' (TIMESCALE 1 ns)\n')
    sdf = header + "".join(cells) + ")\n"

    # Shortest period the annotated path allows, per corner
    report = []
    for corner in (MIN_CORNER, MAX_CORNER):
        chain = sum(v[1] for v in stages[corner].values())
        t_min = t_co[corner] + chain + t_su[corner]
        sta = 10.0 - float(summary[corner]["slack"])
        report.append(f"    {corner:16s} T_CO {t_co[corner]:.3f}  chain {chain:.3f}  "
                      f"T_SU {t_su[corner]:.3f}  min T {t_min:.3f} ns (STA: {sta:.3f})")
    report.insert(0, f"  depth {depth}: {depth} LUTs and {len(registers)} registers annotated")
    return sdf, report


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--depths", type=int, nargs="*",
                        help="depths to convert (default: every core_sim export)")
    args = parser.parse_args()

    depths = args.depths
    if not depths:
        depths = sorted(int(m.group(1)) for p in STA_DIR.glob("core_sim_path_d*.csv")
                        if (m := re.search(r"_d(\d+)\.csv$", p.name)))
    if not depths:
        sys.exit("No core_sim export found. Build core_sim and run sta_export first.")

    SDF_DIR.mkdir(parents=True, exist_ok=True)
    for depth in depths:
        sdf, report = make_sdf(depth)
        out = SDF_DIR / f"core_sim_d{depth}.sdf"
        out.write_bytes(sdf.encode())
        print(f"Written {out.as_posix()}")
        print("\n".join(report))


if __name__ == "__main__":
    main()
