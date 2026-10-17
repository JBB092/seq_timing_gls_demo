# Simulation flow shared by run.ps1 and the Makefile, run from the repo root:
#   vsim -c -nolog -do "set MODE rtl; set DEPTH 16; source scripts/sim.tcl"
#   vsim -c -nolog -do "set MODE gls_udp; set CORNER min; set DEPTH {8 16 24}; source scripts/sim.tcl"
# MODE: rtl, gls_func, gls_udp or gls_sdf.
# gls_func and gls_sdf simulate the Quartus netlist of the core_sim revision
# for each depth; a missing or outdated netlist is rebuilt first with
# build.tcl. gls_sdf also refreshes the STA export and the SDF of the depth.
# DEPTH: one depth or a list (recompiled for each); empty means the default
# in chain_cfg.svh.
# CORNER (gls_udp, gls_sdf): min, typ or max (default max), picks the value
# of the min:typ:max delays.
# TCHK_MSG (gls_udp, gls_sdf): 1 prints every timing check violation; by
# default they are only counted by the testbench (x_count column).
# rtl and gls_func must pass at every period; gls_udp and gls_sdf at the
# board period (10 ns) and above.
# Exit code: 0 = pass, 1 = testbench failed, 2 = build, compile or script
# error. With several depths the worst code wins.

proc default_depth {} {
    set f [open rtl/chain_cfg.svh r]
    set text [read $f]
    close $f
    regexp {`define\s+CHAIN_DEPTH\s+(\d+)} $text -> depth
    return $depth
}

proc netlist_path {depth} {
    return build/quartus/core_sim_d$depth/simulation/questa/core_sim.svo
}

proc sdf_path {depth} {
    return build/sdf/core_sim_d$depth.sdf
}

# Reason why a generated file must be made again ("" if it is up to date)
proc outdated {target sources} {
    if {![file exists $target]} { return "missing" }
    foreach src $sources {
        if {[file mtime $src] > [file mtime $target]} { return "older than $src" }
    }
    return ""
}

proc python_cmd {} {
    if {[info exists ::env(PYTHON)]} { return $::env(PYTHON) }
    if {$::tcl_platform(platform) eq "windows"} { return python }
    return python3
}

# Make sure the netlist (and for gls_sdf the STA export and the SDF) of one
# depth are up to date. Returns 0 if everything is ready.
proc update_inputs {mode depth} {
    set netlist [netlist_path $depth]
    set sources [concat [glob rtl/*.sv rtl/*.svh] quartus/core_sim.qsf quartus/core_sim.sdc]
    set reason [outdated $netlist $sources]
    if {$reason ne ""} {
        echo "=== netlist for depth $depth is $reason: compiling core_sim (about 2 minutes)"
        if {[catch {exec quartus_sh -t scripts/build.tcl compile core_sim $depth >@ stdout 2>@ stderr}]} {
            return 2
        }
    }
    if {$mode ne "gls_sdf"} { return 0 }

    set reason [outdated build/sta/core_sim_path_d$depth.csv [list $netlist]]
    if {$reason ne ""} {
        echo "=== STA export for depth $depth is $reason: running sta_export"
        if {[catch {exec quartus_sta -t scripts/sta_export.tcl core_sim $depth >@ stdout 2>@ stderr}]} {
            return 2
        }
    }
    set reason [outdated [sdf_path $depth] [list build/sta/core_sim_path_d$depth.csv scripts/gen_sdf.py]]
    if {$reason ne ""} {
        echo "=== SDF for depth $depth is $reason: running gen_sdf.py"
        if {[catch {exec [python_cmd] scripts/gen_sdf.py --depths $depth >@ stdout 2>@ stderr}]} {
            return 2
        }
    }
    return 0
}

# vlog arguments for the design of one mode and depth
proc design_sources {mode depth} {
    switch $mode {
        rtl     { return [list -f filelists/rtl.f] }
        gls_udp { return [list -f filelists/gls_udp.f] }
        default { return [list -f filelists/gls_sdf.f [netlist_path $depth]] }
    }
}

# Extra vsim options of one mode and depth
proc vsim_options {mode depth corner tchk_msg} {
    # Precompiled Cyclone V atoms and Altera primitives (dffeas)
    set libs {-L cyclonev_ver -L altera_ver}
    set quiet [expr {$tchk_msg ? {} : {+no_tchk_msg}}]
    switch $mode {
        rtl      { return +T_CHECK=0 }
        gls_func { return [concat +T_CHECK=0 $libs] }
        gls_udp  { return [concat +${corner}delays $quiet] }
        gls_sdf  {
            # +<corner>delays only tells the testbench which corner is used
            return [concat $libs -sdf$corner /tb_core/u_dut=[sdf_path $depth] +${corner}delays $quiet]
        }
    }
}

# Build what is needed, compile and simulate one depth. Returns the exit code.
proc run_one {run mode depth corner tchk_msg} {
    if {$mode in {gls_func gls_sdf} && [update_inputs $mode $depth] != 0} {
        echo "=== RESULT: BUILD FAILED (mode=$run depth=$depth)"
        return 2
    }

    # Each mode and depth gets its own work library, so nothing is shared
    set out build/$run/d$depth
    file delete -force $out
    file mkdir $out
    transcript file $out/sim.log

    echo "=== mode=$run depth=$depth out=$out"
    vlib $out/work
    set sources [design_sources $mode $depth]
    if {[catch {eval vlog -work $out/work -sv +define+CHAIN_DEPTH=$depth $sources tb/tb_core.sv}]} {
        echo "=== RESULT: COMPILE ERROR (mode=$run depth=$depth)"
        return 2
    }

    # -t ps: the default ns resolution would round sub-ns delays to zero
    set opts [vsim_options $mode $depth $corner $tchk_msg]
    if {[catch {eval vsim -t ps -onfinish stop $opts -lib $out/work tb_core}]} {
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
set tchk_msg [expr {[info exists TCHK_MSG] && $TCHK_MSG eq "1"}]

if {$MODE in {gls_udp gls_sdf} && [lsearch -exact {min typ max} $CORNER] < 0} {
    echo "Unknown corner: $CORNER (use min, typ or max)"
    quit -code 2
}
switch $MODE {
    rtl      { set run rtl }
    gls_func { set run gls_func }
    gls_udp  {
        if {![file exists build/timing_cfg.svh]} {
            echo "build/timing_cfg.svh not found. Run: python scripts/gen_timing_cfg.py"
            quit -code 2
        }
        # One folder per corner, so the results of each corner are kept
        set run gls_udp_$CORNER
    }
    gls_sdf  { set run gls_sdf_$CORNER }
    default  { echo "Unknown mode: $MODE"; quit -code 2 }
}

set worst 0
set results {}
foreach k $DEPTH {
    set code [run_one $run $MODE $k $CORNER $tchk_msg]
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
