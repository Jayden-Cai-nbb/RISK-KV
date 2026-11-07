# 实际native缓存/预取/退休与AXI CDC的全局综合；不生成板级位流。
set_param general.maxThreads 2
create_project -in_memory -part xcvu440-flga2892-1-c
set_property target_language Verilog [current_project]
set xci fixture-copy/project/axi_cdc_fixture.srcs/sources_1/ip/rkv_m1_axi_clock_converter/rkv_m1_axi_clock_converter.xci
read_ip $xci
set_property GENERATE_SYNTH_CHECKPOINT false [get_files $xci]
generate_target all [get_ips rkv_m1_axi_clock_converter]
set source_list [open sources/platform/m1/memory_axi_cdc.f r]
foreach filename [split [read $source_list] "\n"] {
    if {$filename eq "" || [string index $filename 0] eq "#"} {continue}
    if {[file extension $filename] eq ".sv"} {
        read_verilog -sv sources/$filename
    } else {
        read_verilog sources/$filename
    }
}
close $source_list
read_xdc clocks.xdc
synth_design -top rkv_m1_memory_axi_cdc -part xcvu440-flga2892-1-c -mode out_of_context
# 约束仍以真实reset_coord为根，只显式进入新增transport实例。
current_instance transport
source axi_reset_cdc.tcl
current_instance
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
puts "MEMORY_AXI_CDC_NO_BLACKBOX_SYNTHESIZED_NOT_BOARD_TIMING"
exit
