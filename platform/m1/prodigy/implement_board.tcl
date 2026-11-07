# 实验时钟结构代理：只综合/实现；没有 bitgen 或硬件操作。
set_param general.maxThreads 2
open_project project/example/rkv_ddr_candidate_ex.xpr
set ipfile [get_files -all */rkv_ddr_candidate.xci]
if {![get_property IS_LOCKED [get_ips rkv_ddr_candidate]]} {error "DDR fixture not under user management"}
# Hierarchy discovery does not descend into user-managed packaged IP.
# Include the explicitly registered sources without automatic unused-file pruning.
set_property source_mgmt_mode None [current_project]
report_compile_order -used_in synthesis -file synthesis-input-order.rpt
set actual_sources [get_files -compile_order sources -used_in synthesis]
foreach name {rkv_boot_trace.v rkv_ddr_init_trace.v} {
    if {![llength [lsearch -all -inline -glob $actual_sources */$name]]} {
        error "Missing explicit synthesis dependency $name"
    }
}
if {[llength [get_ips ddr_init_trace_vio]] != 1} {error "Missing trace VIO IP"}
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis incomplete"}
open_run synth_1
report_clocks -file synthesis-clocks.rpt
report_utilization -file synthesis-utilization.rpt
if {[llength [get_cells -hier -filter {REF_NAME == IBUFDS}]] != 1} {error "Expected exactly one reference IBUFDS"}
if {[llength [get_cells -hier -filter {REF_NAME =~ MMCME*}]] != 2} {error "Expected MIG and independent compute MMCM"}
set checked 0
set out [open mmcm-actual.tsv w]
puts $out "cell\tinput_period_ns\tM\tD\tO0"
foreach cell [get_cells -hier -filter {REF_NAME =~ MMCME*}] {
    set period [get_property CLKIN1_PERIOD $cell]
    set mult [get_property CLKFBOUT_MULT_F $cell]
    set div [get_property DIVCLK_DIVIDE $cell]
    set odiv [get_property CLKOUT0_DIVIDE_F $cell]
    puts $out "$cell\t$period\t$mult\t$div\t$odiv"
    if {abs($period - 20.833) < 0.00001 && $mult == 20 && $div == 1 && $odiv == 5} {
        incr checked
    }
}
close $out
if {$checked != 1} {error "Expected exactly one actual 48 MHz/M20/D1/O5 MMCM"}
set clocks [get_clocks -of_objects [get_ports c0_sys_clk_p]]
# PERIOD 属性按 ps 精度表示；只容许半个 ps 的舍入，不放宽时钟或 DRC。
set out [open input-clock-actual.tsv w]
foreach clk $clocks {puts $out "$clk\t[get_property PERIOD $clk]"}
close $out
if {[llength $clocks] != 1 || abs([get_property PERIOD $clocks] - 20.833333) > 0.0005} {
    error "Actual input constraint is not 48 MHz"
}
source board_constraints.tcl
report_cdc -details -file synthesis-cdc.rpt
write_checkpoint synthesized.dcp
close_design
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
set out [open implementation-status.txt w]
puts $out [get_property STATUS [get_runs impl_1]]
close $out
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation incomplete; preserve first tool rejection"}
open_run impl_1
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
puts "M1_BOARD_ROUTED_REQUIRES_REVIEW_NOT_NUMERICALLY_VALIDATED"
exit
