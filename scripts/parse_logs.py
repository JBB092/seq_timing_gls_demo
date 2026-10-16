#!/usr/bin/env python3
"""Summarize the simulation logs written by scripts/sim.tcl.

For each log it reports the mode, depth, result, tool version and every
error/warning line. Then it merges the T sweep tables of all depths into one
k x T table per mode and writes it as CSV to build/reports/.

Usage:
    python scripts/parse_logs.py                 # all build/*/d*/sim.log
    python scripts/parse_logs.py --mode rtl      # only one mode
    python scripts/parse_logs.py path/to/sim.log ...
"""

import argparse
import csv
import platform
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REPORT_DIR = REPO_ROOT / "build" / "reports"

RE_HEADER = re.compile(r"=== mode=(\S+) depth=(\d+)")
RE_RESULT = re.compile(r"=== RESULT: (.+?) \(")
RE_TOOL = re.compile(r"(Questa .*?) (?:vlog|vsim) (\S+)")
RE_MESSAGE = re.compile(r"\*\* (Error|Warning|Fatal)\b(.*)")
RE_SWEEP = re.compile(r"==== T sweep: CHAIN_DEPTH=(\d+), (\d+) cycles per T")
RE_ROW = re.compile(r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(PASS|FAIL)\s*$")
RE_SWEEP_END = re.compile(r"==== \d+ of \d+ periods failed")


def parse_log(path):
    """Return a dict with everything found in one sim.log."""
    info = {"path": path, "mode": "?", "depth": None, "result": "INCOMPLETE",
            "tool": "?", "cycles": None, "messages": [], "rows": []}
    in_sweep = False

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw[2:] if raw.startswith("# ") else raw

        if m := RE_HEADER.search(line):
            info["mode"], info["depth"] = m.group(1), int(m.group(2))
        elif m := RE_RESULT.search(line):
            info["result"] = m.group(1)
        elif m := RE_SWEEP.search(line):
            in_sweep = True
            info["cycles"] = int(m.group(2))
        elif RE_SWEEP_END.search(line):
            in_sweep = False
        elif in_sweep and (m := RE_ROW.match(line)):
            t, chain_err, ref_err, x_count, result = m.groups()
            info["rows"].append({"t_ps": int(t), "chain_err": int(chain_err),
                                 "ref_err": int(ref_err), "x_count": int(x_count),
                                 "result": result})
        elif m := RE_MESSAGE.search(line):
            info["messages"].append((m.group(1), line.strip()))

        if info["tool"] == "?" and (m := RE_TOOL.search(line)):
            info["tool"] = "{} {}".format(m.group(1), m.group(2))

    return info


def min_passing_t(rows):
    """Smallest T such that it and every longer T pass (None if none pass)."""
    best = None
    for row in sorted(rows, key=lambda r: r["t_ps"], reverse=True):
        if row["result"] != "PASS":
            break
        best = row["t_ps"]
    return best


def print_log_summary(logs):
    print("Per-log summary")
    print("-" * 78)
    print("{:<10} {:>5} {:<16} {:>6} {:>8} {:>7}  {}".format(
        "mode", "k", "result", "errors", "warnings", "points", "log"))
    for log in logs:
        n_err = sum(1 for kind, _ in log["messages"] if kind in ("Error", "Fatal"))
        n_warn = sum(1 for kind, _ in log["messages"] if kind == "Warning")
        print("{:<10} {:>5} {:<16} {:>6} {:>8} {:>7}  {}".format(
            log["mode"], str(log["depth"]), log["result"], n_err, n_warn,
            len(log["rows"]), log["path"].relative_to(REPO_ROOT)
            if log["path"].is_relative_to(REPO_ROOT) else log["path"]))
    print()

    noisy = [log for log in logs if log["messages"]]
    if noisy:
        print("Errors and warnings")
        print("-" * 78)
        for log in noisy:
            print("[{} k={}]".format(log["mode"], log["depth"]))
            for _, text in log["messages"]:
                print("  " + text)
        print()


def kxt_table(mode, logs):
    """Print the merged k x T table of one mode and write it as CSV."""
    by_depth = {log["depth"]: log for log in logs if log["rows"]}
    if not by_depth:
        print("[{}] no T sweep tables found\n".format(mode))
        return

    periods = sorted({r["t_ps"] for log in by_depth.values() for r in log["rows"]},
                     reverse=True)
    depths = sorted(by_depth)

    print("k x T table, mode {}  (. = PASS, F = FAIL, - = not run)".format(mode))
    print("-" * 78)
    print("{:>5} | ".format("k") + " ".join("{:>4}".format(_ns(t)) for t in periods)
          + " | min T pass")
    for k in depths:
        cells = {r["t_ps"]: r for r in by_depth[k]["rows"]}
        marks = []
        for t in periods:
            r = cells.get(t)
            marks.append("-" if r is None else ("." if r["result"] == "PASS" else "F"))
        best = min_passing_t(by_depth[k]["rows"])
        print("{:>5} | ".format(k) + " ".join("{:>4}".format(m) for m in marks)
              + " | " + ("none" if best is None else _ns(best) + " ns"))
    print("T in ns\n")

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    out = REPORT_DIR / "kxt_{}.csv".format(mode)
    with out.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["mode", "depth", "t_ps", "chain_err", "ref_err",
                         "x_count", "result"])
        for k in depths:
            for r in sorted(by_depth[k]["rows"], key=lambda r: r["t_ps"], reverse=True):
                writer.writerow([mode, k, r["t_ps"], r["chain_err"], r["ref_err"],
                                 r["x_count"], r["result"]])
    print("Written {}\n".format(out.relative_to(REPO_ROOT)))


def _ns(t_ps):
    return "{:g}".format(t_ps / 1000)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("logs", nargs="*", type=Path,
                        help="log files (default: build/*/d*/sim.log)")
    parser.add_argument("--mode", help="only logs of this mode")
    args = parser.parse_args()

    paths = [p.resolve() for p in args.logs] or sorted(REPO_ROOT.glob("build/*/d*/sim.log"))
    if not paths:
        print("No logs found. Run a simulation first, e.g. .\\run.ps1 rtl")
        return 1

    logs = [parse_log(p) for p in paths]
    if args.mode:
        logs = [log for log in logs if log["mode"] == args.mode]
    logs.sort(key=lambda log: (log["mode"], log["depth"] or 0))

    tools = sorted({log["tool"] for log in logs} - {"?"}) or ["unknown"]
    print("Parsed {} log(s) on {} {} with Python {}".format(
        len(logs), platform.system(), platform.release(), platform.python_version()))
    print("Simulator: {}\n".format(", ".join(tools)))

    print_log_summary(logs)
    for mode in sorted({log["mode"] for log in logs}):
        kxt_table(mode, [log for log in logs if log["mode"] == mode])

    failed = [log for log in logs if log["result"] != "PASS"]
    print("{} of {} simulations passed".format(len(logs) - len(failed), len(logs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
