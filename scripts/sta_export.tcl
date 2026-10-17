# Exports the critical path of each Quartus build to CSV, for every corner.
# Run from the repo root, after build.tcl:
#   quartus_sta -t scripts/sta_export.tcl <revision> ["k1 k2 ..."]
# Without a depth list it exports every build/quartus/<revision>_d<k>.
# Writes:
#   build/sta/<revision>_summary.csv   one row per depth and corner (rows of
#                                      depths not exported this time are kept)
#   build/sta/<revision>_path_d<k>.csv every point of the path, per corner
#
# The exported path always starts at LFSR bit 0, the only one that goes
# through every stage. The worst path can start at another bit when the
# placement makes its wiring longer; its slack is exported as worst_slack.
#
# Note: the Cyclone V timing model reports uTco, uTsu and uTh as 0. The
# register delays are part of the clock network delay and of the last cell
# before the capture register (reg_in), so those are exported too.

proc write_file {path text} {
    set f [open $path w]
    fconfigure $f -translation lf
    puts -nonewline $f $text
    close $f
}

proc node_name {point} {
    set node [get_point_info $point -node]
    if {$node eq ""} { return "" }
    return [get_node_info $node -name]
}

# Value of the first point of a given type, 0 if there is none
proc point_incr {points type} {
    foreach_in_collection pt $points {
        if {[get_point_info $pt -type] eq $type} { return [get_point_info $pt -incr] }
    }
    return 0
}

# Exports one build. Appends to the summary text and writes the path CSV.
proc export_build {revision depth out_dir summary_var} {
    upvar $summary_var summary
    set path_csv "corner,index,type,rise_fall,incr,total,node\n"

    project_open $revision -revision $revision
    create_timing_netlist
    read_sdc
    update_timing_netlist

    foreach_in_collection oc [get_available_operating_conditions] {
        set_operating_conditions $oc
        update_timing_netlist
        set corner [string map {" Model" ""} [get_operating_conditions_info $oc -display_name]]

        set to    [get_keepers *u_chain_ff*]
        set setup [get_timing_paths -setup -npaths 1 -from [get_keepers {*g_ff[0]*}] -to $to]
        set worst [get_timing_paths -setup -npaths 1 -to $to]
        set hold  [get_timing_paths -hold  -npaths 1 -to $to]

        foreach_in_collection p $setup {
            set arrival  [get_path_info $p -arrival_points]
            set required [get_path_info $p -required_points]

            # Walk the data path: chain stages, then the capture register input
            set index 0
            set stages 0
            set chain_ic 0.0
            set chain_cell 0.0
            set reg_in 0.0
            foreach_in_collection pt $arrival {
                set type [get_point_info $pt -type]
                set incr [get_point_info $pt -incr]
                set name [node_name $pt]
                append path_csv "$corner,$index,$type,[get_point_info $pt -rise_fall],$incr,[get_point_info $pt -total],$name\n"
                incr index
                if {[string match *g_stage* $name]} {
                    if {$type eq "ic"}   { set chain_ic   [expr {$chain_ic + $incr}] }
                    if {$type eq "cell"} { set chain_cell [expr {$chain_cell + $incr}]; incr stages }
                } elseif {[string match *u_chain_ff* $name] && $type eq "cell"} {
                    set reg_in $incr
                }
            }
            foreach_in_collection pt $required {
                append path_csv "$corner,$index,[get_point_info $pt -type],,[get_point_info $pt -incr],[get_point_info $pt -total],[node_name $pt]\n"
                incr index
            }

            set worst_slack ""
            set worst_bit ""
            foreach_in_collection w $worst {
                set worst_slack [get_path_info $w -slack]
                regexp {g_ff\[(\d+)\]} [get_node_info [get_path_info $w -from] -name] -> worst_bit
            }
            set hold_slack ""
            foreach_in_collection h $hold { set hold_slack [get_path_info $h -slack] }

            append summary [join [list $depth $corner \
                [get_path_info $p -slack] [get_path_info $p -data_delay] \
                [get_path_info $p -clock_skew] [point_incr $required unc] \
                [point_incr $arrival utco] [point_incr $required utsu] $reg_in \
                $stages [format %.3f $chain_cell] [format %.3f $chain_ic] \
                [format %.3f [expr {$stages ? ($chain_cell + $chain_ic) / $stages : 0}]] \
                $worst_slack $worst_bit $hold_slack] ,]\n
            puts [format "    %-16s slack %8s  stages %3d  avg stage %s ns" $corner \
                [get_path_info $p -slack] $stages \
                [format %.3f [expr {$stages ? ($chain_cell + $chain_ic) / $stages : 0}]]]
        }
    }
    delete_timing_netlist
    project_close
    write_file $out_dir/${revision}_path_d$depth.csv $path_csv
}

set revision [lindex $argv 0]
set depths   [lindex $argv 1]
if {$revision eq ""} { set revision board }

set top_dir [pwd]
if {$depths eq ""} {
    foreach dir [glob -nocomplain -type d build/quartus/${revision}_d*] {
        if {[regexp {_d(\d+)$} $dir -> k]} { lappend depths $k }
    }
    set depths [lsort -integer $depths]
}
if {[llength $depths] == 0} {
    puts "=== No builds found in build/quartus/${revision}_d*. Run the build first."
    exit 1
}

set out_dir [file normalize build/sta]
file mkdir $out_dir
set summary "depth,corner,slack,data_delay,clock_skew,uncertainty,utco,utsu,reg_in,stages,chain_cell,chain_ic,avg_stage,worst_slack,worst_from_bit,hold_slack\n"
set n_failed 0

foreach k $depths {
    set build_dir [file normalize build/quartus/${revision}_d$k]
    puts "=== export revision=$revision depth=$k"
    if {![file exists $build_dir/output_files/$revision.sta.rpt]} {
        puts "    no finished build in $build_dir"
        incr n_failed
        continue
    }
    cd $build_dir
    if {[catch {export_build $revision $k $out_dir summary} msg]} {
        puts "    export failed: $msg"
        incr n_failed
    }
    cd $top_dir
}

# Keep the rows of the depths not exported this time, sorted by depth
# (lsort is stable, so the corner order inside a depth stays)
set summary_csv $out_dir/${revision}_summary.csv
set lines [lrange [split [string trim $summary] "\n"] 1 end]
if {[file exists $summary_csv]} {
    set f [open $summary_csv r]
    foreach line [lrange [split [string trim [read $f]] "\n"] 1 end] {
        if {[lsearch -exact $depths [lindex [split $line ,] 0]] < 0} { lappend lines $line }
    }
    close $f
}
set rows {}
foreach line $lines { lappend rows [list [lindex [split $line ,] 0] $line] }
set header [lindex [split $summary "\n"] 0]
set text "$header\n"
foreach row [lsort -integer -index 0 $rows] { append text "[lindex $row 1]\n" }
write_file $summary_csv $text
puts "=== Written $summary_csv"
if {$n_failed > 0} { exit 1 }
