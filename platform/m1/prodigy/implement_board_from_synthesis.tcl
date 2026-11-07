# 只在已冻结、综合完成的项目上读取综合网表；不重跑综合，不保存/改写原项目。
if {$argc!=1} {error "Need original synthesized project"}
set_param general.maxThreads 2
open_project -read_only [lindex $argv 0]
open_run synth_1
if {[get_property TOP [current_design]] ne "rkv_m1_board_top"} {error "Wrong netlist top"}
if {[llength [get_cells -hier -filter {REF_NAME == IBUFDS}]]!=1 || [llength [get_cells -hier -filter {REF_NAME =~ MMCME*}]]!=2} {error "Clock topology changed"}
source board_constraints.tcl
report_cdc -details -file synthesis-cdc.rpt
report_exceptions -file synthesis-exceptions.rpt
write_checkpoint linked-synthesis.dcp
# 后续以独立内存设计运行，不触发原工程run/hook，不改原失败证据。
opt_design
place_design
phys_opt_design
route_design
report_drc -file drc.rpt
report_route_status -file route-status.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing.rpt
report_clocks -file clocks.rpt
report_io -file implemented-io.rpt
report_cdc -details -file cdc.rpt
report_bus_skew -file bus-skew.rpt
report_exceptions -ignored -file ignored-exceptions.rpt
write_checkpoint implementation-result.dcp
check_timing -verbose -file check-timing.rpt
report_clock_interaction -file clock-interaction.rpt
report_utilization -file utilization.rpt
report_exceptions -file exceptions.rpt
write_xdc -constraints all effective.xdc
set f [open ports.tsv w]
puts $f "port\tpackage_pin\tiostandard"
foreach p [lsort [get_ports]] {puts $f "$p\t[get_property PACKAGE_PIN $p]\t[get_property IOSTANDARD $p]"}
close $f
puts "M1_BOARD_ROUTED_REQUIRES_REVIEW_NOT_NUMERICALLY_VALIDATED"
exit
