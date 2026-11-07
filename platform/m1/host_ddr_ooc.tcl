# 主机DDR入口独立综合；只评估结构，不绑定未知板级IO或生成位流。
set_param general.maxThreads 2
create_project -in_memory -part xcvu440-flga2892-1-c
read_verilog sources/platform/m1/rkv_m1_host_ddr.v
read_xdc clocks.xdc
synth_design -top rkv_m1_host_ddr -part xcvu440-flga2892-1-c -mode out_of_context
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected blackbox"}
if {[llength [get_cells -quiet -hier -filter {REF_NAME =~ LD*}]] != 0} {error "Unexpected latch"}
report_utilization -hierarchical -file utilization.rpt
report_clocks -file clocks.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
check_timing -verbose -file check-timing.rpt
write_checkpoint synthesized.dcp
write_verilog -force -mode funcsim synthesized.v
puts "HOST_DDR_GATE_SYNTHESIZED_NOT_BOARD_TIMING"
exit
