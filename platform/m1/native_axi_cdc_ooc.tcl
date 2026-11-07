# 独立全局综合：必须包含真实AXI CDC逻辑，不能用IP黑盒冒充通过。
# 输入由记录器快照至本目录；不生成位流，不设置未知板级IO约束。
set_param general.maxThreads 2
create_project -in_memory -part xcvu440-flga2892-1-c
set_property target_language Verilog [current_project]
set xci fixture-copy/project/axi_cdc_fixture.srcs/sources_1/ip/rkv_m1_axi_clock_converter/rkv_m1_axi_clock_converter.xci
read_ip $xci
set_property GENERATE_SYNTH_CHECKPOINT false [get_files $xci]
generate_target all [get_ips rkv_m1_axi_clock_converter]
read_verilog sources/platform/m1/rkv_m1_clock_guard.v
read_verilog sources/platform/m1/rkv_m1_axi_reset.v
read_verilog -sv sources/platform/m1/rkv_m1_native_axi.sv
read_verilog sources/platform/m1/rkv_m1_native_axi_cdc.v
read_xdc clocks.xdc
synth_design -top rkv_m1_native_axi_cdc -part xcvu440-flga2892-1-c -mode out_of_context
source axi_reset_cdc.tcl
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected synthesis blackbox"}
if {[llength [get_clocks]] != 2} {error "Expected core and DDR UI clocks only"}
report_utilization -hierarchical -file utilization.rpt
report_clocks -file clocks.rpt
report_cdc -details -file cdc.rpt
report_clock_interaction -file clock-interaction.rpt
report_exceptions -file exceptions.rpt
report_bus_skew -file bus-skew.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
check_timing -verbose -file check-timing.rpt
write_xdc -constraints all effective.xdc
write_checkpoint synthesized.dcp
write_verilog -force -mode funcsim synthesized.v
puts "NATIVE_AXI_CDC_NO_BLACKBOX_SYNTHESIZED_NOT_BOARD_TIMING"
exit
