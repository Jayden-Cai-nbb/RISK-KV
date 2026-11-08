# Analyze the already-routed final design. No hardware access, implementation, or bitgen.
set rkv_root [file dirname [file dirname [file dirname [file normalize [info script]]]]]
set rkv_checkpoint [file join $rkv_root build reproduction g3-board-demo-20261107 build-v4 work implementation-result.dcp]
set rkv_gui [expr {[lindex $argv 0] eq "gui"}]
set_param general.maxThreads 4
open_checkpoint $rkv_checkpoint
puts "RISK-KV OFFLINE IMPLEMENTATION VIEW; hardware session untouched."
puts "Design: [current_design] / Part: [get_property PART [current_design]]"
if {$rkv_gui} {
    report_timing_summary -delay_type min_max -report_unconstrained -name RKV_TIMING -file offline-timing.rpt
    report_utilization -name RKV_RESOURCES -file offline-utilization.rpt
} else {
    report_timing_summary -delay_type min_max -report_unconstrained -file offline-timing.rpt
    report_utilization -file offline-utilization.rpt
}
# Vivado 2022.2 rejects -name together with -hierarchical. Keep this report textual.
report_utilization -hierarchical -hierarchical_depth 4 -file offline-hierarchy.rpt
report_route_status -file offline-route.rpt
puts "RISK-KV OFFLINE REPORTS READY in [pwd]"
puts "GUI: inspect RKV_TIMING, RKV_RESOURCES and the Device window."
puts "Hierarchy text report: [file normalize offline-hierarchy.rpt]"
