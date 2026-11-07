# Run only in an opened, actually routed board implementation.
# Usage in Vivado Tcl: set m1_report_dir <new directory>; source this_file
# No constraints, clocks, IP or exception are invented here. No bitstream is generated.
if {![info exists m1_report_dir]} { error "set m1_report_dir to a NEW evidence directory" }
if {[file exists $m1_report_dir]} { error "refusing to overwrite existing evidence" }
file mkdir $m1_report_dir
set m1_meta [open [file join $m1_report_dir environment.txt] w]
puts $m1_meta "Vivado: [version -short]"
puts $m1_meta "Design: [current_design]"
puts $m1_meta "Part: [get_property PART [current_design]]"
close $m1_meta
check_timing -verbose -file [file join $m1_report_dir check_timing.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $m1_report_dir timing_summary.rpt]
report_cdc -details -file [file join $m1_report_dir cdc.rpt]
report_drc -file [file join $m1_report_dir drc.rpt]
report_clocks -file [file join $m1_report_dir clocks.rpt]
report_clock_interaction -file [file join $m1_report_dir clock_interaction.rpt]
report_exceptions -file [file join $m1_report_dir exceptions.rpt]
report_utilization -hierarchical -file [file join $m1_report_dir utilization.rpt]
report_route_status -file [file join $m1_report_dir route_status.rpt]
puts "M1 reports collected; manual/source-based clock, reset, CDC and exception review still required."
