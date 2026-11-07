# 仅根入口责任寄存的OOC综合；不是完整路由/板级时序。
set_param general.maxThreads 2
create_project -in_memory -part xcvu440-flga2892-1-c
read_verilog sources/rkv_m1_host_ingress.v
synth_design -top rkv_m1_host_ingress -mode out_of_context -part xcvu440-flga2892-1-c
create_clock -name core -period 20.000 [get_ports clk]
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected blackbox"}
if {[llength [get_cells -hier -filter {REF_NAME =~ LD*}]] != 0} {error "Unexpected latch"}
report_utilization -file utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
check_timing -verbose -file check-timing.rpt
write_checkpoint synthesized.dcp
write_verilog -mode funcsim synthesized.v
puts "HOST_INGRESS_SYNTHESIZED_NOT_BOARD_TIMING"
exit
