# 独立控制从端结构综合；无板级IO、MIG、bitgen或硬件访问。
set_param general.maxThreads 2
create_project -in_memory -part xcvu440-flga2892-1-c
read_verilog sources/platform/m1/rkv_m1_host_map.v
read_verilog sources/platform/m1/rkv_m1_host_control.v
read_xdc clocks.xdc
synth_design -top rkv_m1_host_control -part xcvu440-flga2892-1-c -mode out_of_context
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected blackbox"}
if {[llength [get_cells -quiet -hier -filter {REF_NAME =~ LD*}]] != 0} {error "Unexpected latch"}
report_utilization -hierarchical -file utilization.rpt
report_clocks -file clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
check_timing -verbose -file check-timing.rpt
write_checkpoint synthesized.dcp
write_verilog -force -mode funcsim synthesized.v
puts "M1_HOST_CONTROL_SYNTHESIZED_NOT_BOARD_TIMING"
exit
