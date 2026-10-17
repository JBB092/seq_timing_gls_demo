# Simulation flow shared by run.ps1 and the Makefile, run from the repo root:
#   vsim -c -nolog -do "set MODE rtl; set DEPTH 16; source scripts/sim.tcl"
#   vsim -c -nolog -do "set MODE gls_udp; set CORNER min; set DEPTH {8 16 24}; source scripts/sim.tcl"
# MODE: rtl or gls_udp.
# DEPTH: one depth or a list (recompiled for each); empty means the default
# in chain_cfg.svh.
# CORNER (gls_udp only): min, typ or max (default max), picks the value of
# the min:typ:max delays in build/timing_cfg.svh.
# TCHK_MSG (gls_udp only): 1 prints every timing check violation; by default
# they are only counted by the testbench (x_count column).
# rtl must pass at every period; gls_udp at the board period (10 ns) and above.
# Exit code: 0 = pass, 1 = testbench failed, 2 = compile or script error.
# With several depths the worst code wins.

proc default_depth {} {
    set f [open rtl/chain_cfg.svh r]
    set text [read $f]
    close $f
    regexp {`define\s+CHAIN_DEPTH\s+(\d+)} $text -> depth
    return $depth
}

# Compile and simulate one depth. Returns the exit code.
proc run_one {run filelist vsim_opts depth} {
    # Each mode and depth gets its own work library, so nothing is shared
    set out build/$run/d$depth
    file delete -force $out
    file mkdir $out
    transcript file $out/sim.log

    echo "=== mode=$run depth=$depth out=$out"
    vlib $out/work
    if {[catch {vlog -work $out/work -sv +define+CHAIN_DEPTH=$depth -f $filelist tb/tb_core.sv}]} {
        echo "=== RESULT: COMPILE ERROR (mode=$run depth=$depth)"
        return 2
    }

    # -t ps: the default ns resolution would round sub-ns delays to zero
    if {[catch {eval vsim -t ps -onfinish stop $vsim_opts -lib $out/work tb_core}]} {
        echo "=== RESULT: LOAD ERROR (mode=$run depth=$depth)"
        return 2
    }
    run -all

    # $finish means the testbench ended normally; $fatal or a stop does not
    set code 1
    if {[string match {*$finish*} [runStatus -full]]} { set code 0 }
    quit -sim
    if {$code == 0} {
        echo "=== RESULT: PASS (mode=$run depth=$depth)"
    } else {
        echo "=== RESULT: FAIL (mode=$run depth=$depth)"
    }
    return $code
}

# Shortest passing period printed by the testbench in a log
proc min_passing_t {log} {
    set min_t -
    if {![file exists $log]} { return $min_t }
    set f [open $log r]
    regexp {every longer one: (\d+) ps} [read $f] -> min_t
    close $f
    if {$min_t ne "-"} { set min_t [format "%.1f ns" [expr {$min_t / 1000.0}]] }
    return $min_t
}

if {![info exists MODE]} { set MODE rtl }
if {![info exists DEPTH] || $DEPTH eq ""} { set DEPTH [default_depth] }
if {![info exists CORNER] || $CORNER eq ""} { set CORNER max }

switch $MODE {
    rtl {
        set run       rtl
        set filelist  filelists/rtl.f
        set vsim_opts +T_CHECK=0
    }
    gls_udp {
        if {[lsearch -exact {min typ max} $CORNER] < 0} {
            echo "Unknown corner: $CORNER (use min, typ or max)"
            quit -code 2
        }
        if {![file exists build/timing_cfg.svh]} {
            echo "build/timing_cfg.svh not found. Run: python scripts/gen_timing_cfg.py"
            quit -code 2
        }
        # One folder per corner, so the results of each corner are kept
        set run       gls_udp_$CORNER
        set filelist  filelists/gls_udp.f
        set vsim_opts +${CORNER}delays
        if {![info exists TCHK_MSG] || $TCHK_MSG ne "1"} { lappend vsim_opts +no_tchk_msg }
    }
    default { echo "Unknown mode: $MODE"; quit -code 2 }
}

set worst 0
set results {}
foreach k $DEPTH {
    set code [run_one $run $filelist $vsim_opts $k]
    lappend results [list $k $code]
    if {$code > $worst} { set worst $code }
}
transcript file ""

if {[llength $DEPTH] > 1} {
    echo ""
    echo "=== Depth sweep, mode=$run"
    echo [format "    %4s  %-6s  %s" k result "min T that passes"]
    foreach r $results {
        set k [lindex $r 0]
        set label [lindex {PASS FAIL ERROR} [lindex $r 1]]
        echo [format "    %4s  %-6s  %s" $k $label [min_passing_t build/$run/d$k/sim.log]]
    }
}
quit -code $worst
