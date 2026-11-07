# 在已保存DCP上独立复核，不重新综合，也不生成bit。
if {[llength $argv] != 1} {error "Usage: platform_review_synthesis.tcl synthesized.dcp"}
set_param general.maxThreads 2
open_checkpoint [lindex $argv 0]
if {[get_property PART [current_design]] ne "xcvu440-flga2892-1-c"} {error "Unexpected part"}
source platform_reset_cdc.tcl
if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected blackbox"}
if {[llength [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]] != 0} {error "Unexpected latch"}
report_clocks -file clocks.rpt
report_utilization -hierarchical -file utilization.rpt
report_cdc -details -file cdc.rpt
report_clock_interaction -file clock-interaction.rpt
report_exceptions -file exceptions.rpt
report_exceptions -ignored -file ignored-exceptions.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
report_bus_skew -file bus-skew.rpt
check_timing -verbose -file check-timing.rpt
write_xdc -constraints all effective.xdc
write_checkpoint reviewed-synthesis.dcp
puts "M1_PLATFORM_RESET_BOUND_REVIEW_COMPLETE_NOT_BOARD_TIMING"
exit
