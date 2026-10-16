# Quartus flow shared by run.ps1 and the Makefile, run from the repo root:
#   quartus_sh -t scripts/build.tcl compile <revision> [depth]
#   quartus_sh -t scripts/build.tcl program <revision> [depth]
# compile copies the project to build/quartus/<revision>_d<k>/, sets
# CHAIN_DEPTH there as a VERILOG_MACRO (the .qsf in quartus/ is never
# modified) and runs map, fit, asm and sta.
# program loads that .sof into the FPGA (device 2 of the DE10-Standard JTAG
# chain; device 1 is the HPS). Set JTAG_CABLE to use another cable name.

load_package flow

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

proc print_slack {summary} {
    if {![file exists $summary]} return
    set corner ""
    foreach line [split [read_file $summary] "\n"] {
        if {[regexp {^Type\s*:\s*(.*) Setup '(.*)'} $line -> corner clock]} continue
        if {$corner ne "" && [regexp {^Slack\s*:\s*(\S+)} $line -> slack]} {
            puts [format "    %-22s setup slack %8s ns" $corner $slack]
            set corner ""
        }
    }
}

set action   [lindex $argv 0]
set revision [lindex $argv 1]
set depth    [lindex $argv 2]
if {$revision eq ""} { set revision board }
if {$depth eq ""}    { set depth [default_depth] }

set src_dir [file normalize quartus]
set out_dir [file normalize build/quartus/${revision}_d$depth]
set sof     $out_dir/output_files/$revision.sof

switch $action {
    compile {
        puts "=== compile revision=$revision depth=$depth out=$out_dir"
        file delete -force $out_dir
        file mkdir $out_dir
        write_file $out_dir/$revision.qpf "PROJECT_REVISION = \"$revision\"\n"
        copy_qsf $src_dir/$revision.qsf $out_dir/$revision.qsf $src_dir $depth

        cd $out_dir
        project_open $revision -revision $revision
        set failed [catch {execute_flow -compile} msg]
        project_close

        if {$failed} {
            puts "=== RESULT: BUILD FAILED (revision=$revision depth=$depth)"
            puts $msg
            exit 1
        }
        print_slack $out_dir/output_files/$revision.sta.summary
        puts "=== RESULT: BUILD OK (revision=$revision depth=$depth)"
        puts "    $sof"
    }
    program {
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
        puts "Usage: quartus_sh -t scripts/build.tcl compile|program <revision> \[depth\]"
        exit 2
    }
}
