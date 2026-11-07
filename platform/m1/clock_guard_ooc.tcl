# 只验证异步故障捕获的器件映射；没有板级异步脉宽/恢复移除或CDC验收。
set_param general.maxThreads 2
read_verilog rkv_m1_clock_guard.v
synth_design -top rkv_m1_clock_guard -part xcvu440-flga2892-1-c -mode out_of_context
create_clock -name core -period 20.000 [get_ports core_clk]
set captures [get_cells -hier -filter {REF_NAME == FDPE}]
if {[llength $captures] != 4} {error "Expected four asynchronous preset capture FFs; got [llength $captures]"}
set f [open capture-mapping.txt w]
foreach cell [lsort $captures] {
    puts $f "CELL $cell REF [get_property REF_NAME $cell] INIT [get_property INIT $cell]"
    foreach pin {C CE D PRE Q} {
        set p [get_pins $cell/$pin]
        puts $f "  $pin NET [get_nets -of_objects $p]"
        if {$pin eq "PRE"} {
            puts $f "  PRE_STARTPOINTS [all_fanin -flat -startpoints_only -to $p]"
        }
    }
}
close $f
report_utilization -file utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
check_timing -verbose -file check-timing.rpt
write_checkpoint synthesized.dcp
write_verilog -force -mode funcsim synthesized.v
puts "CLOCK_GUARD_FOUR_ASYNC_CAPTURES_SYNTHESIZED_NOT_BOARD_TIMING"
exit
