# Quartus flow shared by run.ps1 and the Makefile, run from the repo root:
#   quartus_sh -t scripts/build.tcl compile <revision> [depth]
#   quartus_sh -t scripts/build.tcl sweep   <revision> ["k1 k2 ..."]
#   quartus_sh -t scripts/build.tcl program <revision> [depth]
# compile copies the project to build/quartus/<revision>_d<k>/, sets
# CHAIN_DEPTH there as a VERILOG_MACRO (the .qsf in quartus/ is never
# modified) and runs map, fit, asm and sta.
# sweep compiles a list of depths and writes the worst setup slack of each
# one to build/quartus/<revision>_sweep.csv.
# program loads that .sof into the FPGA (device 2 of the DE10-Standard JTAG
# chain; device 1 is the HPS). Set JTAG_CABLE to use another cable name.

load_package flow

set DEFAULT_SWEEP {8 16 24 32 48 64}

proc default_depth {} {
    set f [open rtl/chain_cfg.svh r]
    set text [read $f]
    close $f
    regexp {`define\s+CHAIN_DEPTH\s+(\d+)} $text -> depth
    return $depth
}

proc read_file {path} {
    set f [open $path r]
    set text [read $f]
    close $f
    return $text
}

proc write_file {path text} {
    set f [open $path w]
    fconfigure $f -translation lf
    puts -nonewline $f $text
    close $f
}

# Copy the .qsf, turning the relative source paths into absolute ones so
# the copy works from the build folder
proc copy_qsf {src dst src_dir depth} {
    set path_settings {SYSTEMVERILOG_FILE VERILOG_FILE QIP_FILE SDC_FILE SEARCH_PATH}
    set out ""
    foreach line [split [read_file $src] "\n"] {
        if {[regexp {^(\s*set_global_assignment\s+-name\s+)(\S+)\s+(\S+)(.*)$} $line -> head name value tail]
            && [lsearch -exact $path_settings $name] >= 0} {
            set value [file normalize [file join $src_dir [string trim $value \"]]]
            set line "$head$name \"$value\"$tail"
        }
        append out "$line\n"
    }
    append out "\n# Added by scripts/build.tcl\n"
    append out "set_global_assignment -name VERILOG_MACRO \"CHAIN_DEPTH=$depth\"\n"
    write_file $dst $out
}

# Worst setup slack per corner, as a list of {corner slack} pairs
proc read_slack {summary} {
    set result {}
    if {![file exists $summary]} { return $result }
    set corner ""
    foreach line [split [read_file $summary] "\n"] {
        if {[regexp {^Type\s*:\s*(.*) Model Setup '} $line -> corner]} continue
        if {$corner ne "" && [regexp {^Slack\s*:\s*(\S+)} $line -> slack]} {
            lappend result [list $corner $slack]
            set corner ""
        }
    }
    return $result
}

# Compile one depth. Returns the slack list, empty if the compile failed.
proc compile_one {revision depth} {
    set src_dir [file normalize quartus]
    set out_dir [file normalize build/quartus/${revision}_d$depth]
    set top_dir [pwd]

    puts "=== compile revision=$revision depth=$depth out=$out_dir"
    file delete -force $out_dir
    file mkdir $out_dir
    write_file $out_dir/$revision.qpf "PROJECT_REVISION = \"$revision\"\n"
    copy_qsf $src_dir/$revision.qsf $out_dir/$revision.qsf $src_dir $depth

    cd $out_dir
    project_open $revision -revision $revision
    set failed [catch {execute_flow -compile} msg]
    project_close
    cd $top_dir

    if {$failed} {
        puts "=== RESULT: BUILD FAILED (revision=$revision depth=$depth)"
        puts $msg
        return {}
    }
    set slack [read_slack $out_dir/output_files/$revision.sta.summary]
    foreach pair $slack {
        puts [format "    %-16s setup slack %8s ns" [lindex $pair 0] [lindex $pair 1]]
    }
    puts "=== RESULT: BUILD OK (revision=$revision depth=$depth)"
    puts "    $out_dir/output_files/$revision.sof"
    return $slack
}

# One row per depth, one column per corner, printed and saved as CSV
proc write_sweep_summary {revision rows} {
    set corners {}
    foreach row $rows {
        foreach pair [lindex $row 1] {
            if {[lsearch -exact $corners [lindex $pair 0]] < 0} {
                lappend corners [lindex $pair 0]
            }
        }
    }

    set header [format "%6s" k]
    foreach c $corners { append header [format " %16s" $c] }
    set csv "depth,[join $corners ,]\n"

    puts ""
    puts "=== Sweep summary: worst setup slack (ns), revision=$revision"
    puts $header
    foreach row $rows {
        set k [lindex $row 0]
        set line [format "%6s" $k]
        set values {}
        foreach c $corners {
            set v FAILED
            foreach pair [lindex $row 1] {
                if {[lindex $pair 0] eq $c} { set v [lindex $pair 1] }
            }
            append line [format " %16s" $v]
            lappend values $v
        }
        puts $line
        append csv "$k,[join $values ,]\n"
    }

    set csv_file [file normalize build/quartus/${revision}_sweep.csv]
    write_file $csv_file $csv
    puts "=== Written $csv_file"
}

set action   [lindex $argv 0]
set revision [lindex $argv 1]
set depth    [lindex $argv 2]
if {$revision eq ""} { set revision board }
if {$depth eq ""} {
    if {$action eq "sweep"} { set depth $DEFAULT_SWEEP } else { set depth [default_depth] }
}

switch $action {
    compile {
        if {[llength [compile_one $revision $depth]] == 0} { exit 1 }
    }
    sweep {
        set rows {}
        set n_failed 0
        foreach k $depth {
            set slack [compile_one $revision $k]
            if {[llength $slack] == 0} { incr n_failed }
            lappend rows [list $k $slack]
        }
        write_sweep_summary $revision $rows
        if {$n_failed > 0} { exit 1 }
    }
    program {
        set sof [file normalize build/quartus/${revision}_d$depth/output_files/$revision.sof]
        if {![file exists $sof]} {
            puts "=== No .sof for depth $depth. Build it first: $sof"
            exit 1
        }
        set cable "DE-SoC \[USB-1\]"
        if {[info exists ::env(JTAG_CABLE)]} { set cable $::env(JTAG_CABLE) }
        puts "=== program depth=$depth cable=$cable"
        if {[catch {exec quartus_pgm -c $cable -m JTAG -o "p;$sof@2" >@ stdout 2>@ stderr}]} {
            puts "=== RESULT: PROGRAM FAILED"
            exit 1
        }
        puts "=== RESULT: PROGRAM OK (depth=$depth)"
    }
    default {
        puts "Usage: quartus_sh -t scripts/build.tcl compile|sweep|program <revision> \[depth(s)\]"
        exit 2
    }
}
