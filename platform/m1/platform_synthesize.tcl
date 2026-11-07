# 完整真实数字平台全局综合；没有MIG、外部延迟、引脚或板级时序结论。
set_param general.maxThreads 2
create_project -in_memory -part xcvu440-flga2892-1-c
set_property target_language Verilog [current_project]
foreach name {fabric router} {
    set candidates [glob $name-copy/project/*.srcs/sources_1/bd/*/*.bd]
    if {[llength $candidates] != 1} {error "Expected one $name BD"}
    set bd [lindex $candidates 0]
    read_bd $bd
    set_property GENERATE_SYNTH_CHECKPOINT false [get_files $bd]
    generate_target all [get_files $bd]
}
set xci cdc-copy/project/axi_cdc_fixture.srcs/sources_1/ip/rkv_m1_axi_clock_converter/rkv_m1_axi_clock_converter.xci
read_ip $xci
set_property GENERATE_SYNTH_CHECKPOINT false [get_files $xci]
generate_target all [get_ips rkv_m1_axi_clock_converter]
set fh [open sources/platform/m1/platform.f r]
foreach name [split [read $fh] "\n"] {
    if {$name eq "" || [string index $name 0] eq "#"} {continue}
    if {[file extension $name] eq ".sv"} {read_verilog -sv sources/$name} else {read_verilog sources/$name}
}
close $fh
set fh [open clocks.xdc w]
puts $fh {# OOC标称波形不是实际时钟发生器/引脚/相位关系的证据，不设置域间整体false_path。
create_clock -name core -period 20.000 [get_ports core_clk]
create_clock -name fast -period 10.000 -waveform {0.000 5.000} [get_ports fast_clk]
create_clock -name ddr_ui -period 5.208 [get_ports ddr_clk]
}
close $fh
read_xdc clocks.xdc
synth_design -top rkv_m1_platform -part xcvu440-flga2892-1-c \
    -mode out_of_context -generic FIRMWARE=firmware.hex
if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected synthesis blackbox"}
if {[llength [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]] != 0} {error "Unexpected synthesis latch"}
if {[llength [get_clocks]] != 3} {error "Expected core/fast/UI clocks"}
# 先保存可恢复的综合结果；后续具体复位端点审查独立进行，不为报告重跑综合。
write_checkpoint synthesized.dcp
report_utilization -file utilization.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_clocks -file clocks.rpt
report_clock_interaction -file clock-interaction.rpt
report_cdc -details -file cdc.rpt
report_exceptions -file exceptions.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
check_timing -verbose -file check-timing.rpt
write_xdc -constraints all effective.xdc
set fh [open reset-candidates.txt w]
foreach cell [lsort [get_cells -hier -regexp {.*(hold_reg|done_in_|release_in_|aresetn_reg).*}]] {
    puts $fh "$cell [get_property REF_NAME $cell]"
}
close $fh
puts "M1_FULL_PLATFORM_SYNTHESIZED_NOT_BOARD_VALIDATED"
exit
