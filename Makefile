# Linux entry point for the demo (GNU Make 3.81 compatible).
# Thin wrapper around the shared scripts in scripts/; run.ps1 offers the
# same targets on Windows. New targets are added as the demo grows.

# Everything generated lives in build/; the quartus/ folders only appear
# if the project is opened from the Quartus GUI
CLEAN_DIRS := build quartus/db quartus/incremental_db quartus/output_files

.PHONY: help clean

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  help    Show this message (default)"
	@echo "  clean   Remove build/ and any Quartus output folders"

clean:
	rm -rf $(CLEAN_DIRS)
	@echo "Clean done"
