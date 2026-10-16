# Simulation flow shared by run.ps1 and the Makefile, run from the repo root:
#   vsim -c -nolog -do "set MODE rtl; set DEPTH 16; source scripts/sim.tcl"
# MODE: rtl. DEPTH: chain depth; empty means the default in chain_cfg.svh
# Exit code: 0 = pass, 1 = testbench failed, 2 = compile or script error

proc default_depth {} {
    set f [open rtl/chain_cfg.svh r]
    set text [read $f]
    close $f
    regexp {`define\s+CHAIN_DEPTH\s+(\d+)} $text -> depth
    return $depth
}

if {![info exists MODE]} { set MODE rtl }
if {![info exists DEPTH] || $DEPTH eq ""} { set DEPTH [default_depth] }

switch $MODE {
    rtl     { set filelist filelists/rtl.f }
    default { echo "Unknown mode: $MODE"; quit -code 2 }
}

# Each mode and depth gets its own work library, so nothing is shared
set out build/$MODE/d$DEPTH
file delete -force $out
file mkdir $out
transcript file $out/sim.log

echo "=== mode=$MODE depth=$DEPTH out=$out"
vlib $out/work
if {[catch {vlog -work $out/work -sv +define+CHAIN_DEPTH=$DEPTH -f $filelist tb/tb_core.sv}]} {
    echo "=== RESULT: COMPILE ERROR (mode=$MODE depth=$DEPTH)"
    quit -code 2
}

# -t ps: the default ns resolution would round sub-ns delays to zero
if {[catch {vsim -t ps -onfinish stop -lib $out/work tb_core}]} {
    echo "=== RESULT: LOAD ERROR (mode=$MODE depth=$DEPTH)"
    quit -code 2
}
run -all

# $finish means the testbench ended normally; $fatal or a stop does not
if {[string match {*$finish*} [runStatus -full]]} {
    echo "=== RESULT: PASS (mode=$MODE depth=$DEPTH)"
    quit -code 0
} else {
    echo "=== RESULT: FAIL (mode=$MODE depth=$DEPTH)"
    quit -code 1
}
