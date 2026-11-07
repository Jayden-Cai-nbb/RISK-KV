# 真实SmartConnect/CDC与两入口全局综合；无引脚、MIG或硬件操作。
set_param general.maxThreads 2
create_project -in_memory -part xcvu440-flga2892-1-c
set_property target_language Verilog [current_project]
set bd fabric-copy/project/axi_fabric_fixture.srcs/sources_1/bd/rkv_m1_axi_fabric/rkv_m1_axi_fabric.bd
read_bd $bd
set_property GENERATE_SYNTH_CHECKPOINT false [get_files $bd]
generate_target all [get_files $bd]
set xci cdc-copy/project/axi_cdc_fixture.srcs/sources_1/ip/rkv_m1_axi_clock_converter/rkv_m1_axi_clock_converter.xci
read_ip $xci
set_property GENERATE_SYNTH_CHECKPOINT false [get_files $xci]
generate_target all [get_ips rkv_m1_axi_clock_converter]
set source_list [open sources/platform/m1/shared_axi.f r]
foreach filename [split [read $source_list] "\n"] {
    if {$filename eq "" || [string index $filename 0] eq "#"} {continue}
    if {[file extension $filename] eq ".sv"} {read_verilog -sv sources/$filename} else {read_verilog sources/$filename}
}
close $source_list
read_xdc clocks.xdc
synth_design -top rkv_m1_shared_axi -part xcvu440-flga2892-1-c -mode out_of_context
source shared_axi_reset_cdc.tcl
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected synthesis blackbox"}
if {[llength [get_cells -hier -filter {REF_NAME =~ LD*}]] != 0} {error "Unexpected latch"}
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
puts "SHARED_AXI_NO_BLACKBOX_SYNTHESIZED_NOT_BOARD_TIMING"
exit
