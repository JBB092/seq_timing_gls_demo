# Linux entry point for the demo (GNU Make 3.81 compatible).
# Thin wrapper around the shared scripts in scripts/; run.ps1 offers the
# same targets on Windows. New targets are added as the demo grows.
#   make rtl            default depth (rtl/chain_cfg.svh)
#   make rtl DEPTH=24   chain depth 24
#   make gls_udp DEPTHS="8 16 24" CORNER=typ  approach A, one run per depth
#   make build DEPTH=24 Quartus compile of the board project
#   make build_sweep DEPTHS="8 16 24"  compile several depths
#   make sta_export     critical path of every build to build/sta/ (CSV)
#   make program DEPTH=24  load that .sof into the FPGA
#   make report         k x T table from all logs

DEPTH  ?=
DEPTHS ?=
CORNER ?= max
PYTHON ?= python3

# Everything generated lives in build/; the quartus/ folders only appear
# if the project is opened from the Quartus GUI
CLEAN_DIRS := build quartus/db quartus/incremental_db quartus/output_files

# Simulations take DEPTHS if given, otherwise DEPTH
SIM_DEPTHS = $(if $(DEPTHS),$(DEPTHS),$(DEPTH))

.PHONY: help rtl gls_udp build build_sweep sta_export program report clean

help:
	@echo "Usage: make <target> [DEPTH=<k>] [DEPTHS=\"k1 k2 ...\"] [CORNER=min|typ|max]"
	@echo ""
	@echo "Targets:"
	@echo "  help    Show this message (default)"
	@echo "  rtl     Zero-delay RTL simulation of core"
	@echo "  gls_udp Approach A: UDP cells with delays from the STA"
	@echo "  build   Quartus compile of the board project"
	@echo "  build_sweep  Compile several depths and summarize their slack"
	@echo "  sta_export   Export the critical path of the builds to build/sta/ (CSV)"
	@echo "  program Load the .sof of that depth into the FPGA (JTAG device 2)"
	@echo "  report  Summarize all simulation logs (k x T table)"
	@echo "  clean   Remove build/ and any Quartus output folders"
	@echo ""
	@echo "Options:"
	@echo "  DEPTH   Chain depth k (default: CHAIN_DEPTH in rtl/chain_cfg.svh)"
	@echo "  DEPTHS  Depth list: rtl and gls_udp simulate each one, build_sweep"
	@echo "          compiles each one (default: list in scripts/build.tcl),"
	@echo "          sta_export exports each one (default: every build found)"
	@echo "  CORNER  Delay corner for gls_udp: min, typ or max (default max)"

rtl:
	vsim -c -nolog -do "set MODE rtl; set DEPTH {$(SIM_DEPTHS)}; source scripts/sim.tcl"

gls_udp: build/timing_cfg.svh
	vsim -c -nolog -do "set MODE gls_udp; set CORNER $(CORNER); set DEPTH {$(SIM_DEPTHS)}; source scripts/sim.tcl"

# Regenerated when the STA export is newer
build/timing_cfg.svh: build/sta/board_summary.csv
	$(PYTHON) scripts/gen_timing_cfg.py

build/sta/board_summary.csv:
	@echo "$@ not found. Run make build_sweep and make sta_export first."
	@exit 2

build:
	quartus_sh -t scripts/build.tcl compile board $(DEPTH)

build_sweep:
	quartus_sh -t scripts/build.tcl sweep board "$(DEPTHS)"

sta_export:
	quartus_sta -t scripts/sta_export.tcl board "$(DEPTHS)"

program:
	quartus_sh -t scripts/build.tcl program board $(DEPTH)

report:
	$(PYTHON) scripts/parse_logs.py

clean:
	rm -rf $(CLEAN_DIRS)
	@echo "Clean done"
