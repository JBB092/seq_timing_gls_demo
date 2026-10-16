# Linux entry point for the demo (GNU Make 3.81 compatible).
# Thin wrapper around the shared scripts in scripts/; run.ps1 offers the
# same targets on Windows. New targets are added as the demo grows.
#   make rtl            default depth (rtl/chain_cfg.svh)
#   make rtl DEPTH=24   chain depth 24
#   make report         k x T table from all logs

DEPTH  ?=
PYTHON ?= python3

# Everything generated lives in build/; the quartus/ folders only appear
# if the project is opened from the Quartus GUI
CLEAN_DIRS := build quartus/db quartus/incremental_db quartus/output_files

.PHONY: help rtl report clean

help:
	@echo "Usage: make <target> [DEPTH=<k>]"
	@echo ""
	@echo "Targets:"
	@echo "  help    Show this message (default)"
	@echo "  rtl     Zero-delay RTL simulation of core"
	@echo "  report  Summarize all simulation logs (k x T table)"
	@echo "  clean   Remove build/ and any Quartus output folders"
	@echo ""
	@echo "Options:"
	@echo "  DEPTH   Chain depth k (default: CHAIN_DEPTH in rtl/chain_cfg.svh)"

rtl:
	vsim -c -nolog -do "set MODE rtl; set DEPTH {$(DEPTH)}; source scripts/sim.tcl"

report:
	$(PYTHON) scripts/parse_logs.py

clean:
	rm -rf $(CLEAN_DIRS)
	@echo "Clean done"
