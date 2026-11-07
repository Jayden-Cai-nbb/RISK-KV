# 实际同源core/fast时钟的完整数字平台综合。无MIG、板级IO时序或硬件操作。
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
file mkdir clock-ip
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clock_48_to_100_50 -dir clock-ip
set_property -dict [list CONFIG.PRIM_IN_FREQ 48.000 \
    CONFIG.PRIM_SOURCE Differential_clock_capable_pin CONFIG.PRIMITIVE MMCM \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 100.000 CONFIG.CLKOUT2_USED true \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 50.000 CONFIG.USE_LOCKED true CONFIG.USE_RESET true] [get_ips clock_48_to_100_50]
set_property GENERATE_SYNTH_CHECKPOINT false [get_files */clock_48_to_100_50.xci]
report_property -all [get_ips clock_48_to_100_50] -file clock-properties.txt
generate_target all [get_ips clock_48_to_100_50]
set fh [open sources/platform/m1/platform_clocked.f r]
foreach name [split [read $fh] "\n"] {
    if {$name eq "" || [string index $name 0] eq "#"} {continue}
    if {[file extension $name] eq ".sv"} {read_verilog -sv sources/$name} else {read_verilog sources/$name}
}
close $fh
# 48MHz输入及core/fast派生时钟由实际Wizard XDC唯一创建，保留其抖动约束。
# UI仅为外部标称接口，真实MIG绑定后另核验，不能以此代替板级时钟。
set fh [open ui-clock.xdc w]
puts $fh {create_clock -name ddr_ui -period 5.208 [get_ports ddr_clk]}
close $fh
read_xdc ui-clock.xdc
synth_design -top rkv_m1_clocked_platform -part xcvu440-flga2892-1-c \
    -mode out_of_context -generic FIRMWARE=firmware.hex
write_checkpoint synthesized.dcp
if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected blackbox"}
if {[llength [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]] != 0} {error "Unexpected latch"}
set mmcm [get_cells -hier -filter {REF_NAME == MMCME3_ADV}]
if {[llength $mmcm] != 1} {error "Expected one actual MMCM"}
foreach {name expected} {CLKIN1_PERIOD 20.833333 CLKFBOUT_MULT_F 62.5 DIVCLK_DIVIDE 3 CLKOUT0_DIVIDE_F 10 CLKOUT1_DIVIDE 20 CLKOUT0_PHASE 0 CLKOUT1_PHASE 0} {
    if {abs([get_property $name $mmcm] - $expected) > 0.001} {error "Actual MMCM $name mismatch"}
}
report_property -all $mmcm -file mmcm-properties.txt
set rkv_core_clock [get_clocks -of_objects [get_ports core_clk]]
set rkv_fast_clock [get_clocks -of_objects [get_ports fast_clk]]
set rkv_ui_clock [get_clocks -of_objects [get_ports ddr_clk]]
set rkv_reference_clock [get_clocks -of_objects [get_ports clock6_p]]
foreach {clock period} [list $rkv_core_clock 20.0 $rkv_fast_clock 10.0 $rkv_ui_clock 5.208 $rkv_reference_clock 20.833333] {
    if {[llength $clock] != 1 || abs([get_property PERIOD $clock] - $period) > 0.001} {error "Unexpected actual clock: $clock"}
}
if {![get_property IS_GENERATED $rkv_core_clock] || ![get_property IS_GENERATED $rkv_fast_clock]} {error "core/fast clocks must be generated"}
if {[get_property MASTER_CLOCK $rkv_core_clock] ne $rkv_reference_clock || [get_property MASTER_CLOCK $rkv_fast_clock] ne $rkv_reference_clock} {error "core/fast do not share actual reference master"}
set fh [open verified-clocks.txt w]
foreach clock [get_clocks] {
    puts $fh "$clock period=[get_property PERIOD $clock] waveform=[get_property WAVEFORM $clock] generated=[get_property IS_GENERATED $clock] master=[get_property MASTER_CLOCK $clock]"
}
close $fh
source platform_clocked_reset_cdc.tcl
report_utilization -file utilization.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_clocks -file clocks.rpt
report_clock_interaction -file clock-interaction.rpt
report_cdc -details -file cdc.rpt
report_exceptions -file exceptions.rpt
report_exceptions -ignored -file ignored-exceptions.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
report_timing -from $rkv_core_clock -to $rkv_fast_clock -delay_type min_max -max_paths 4 -file core-to-fast.rpt
report_timing -from $rkv_fast_clock -to $rkv_core_clock -delay_type min_max -max_paths 4 -file fast-to-core.rpt
report_bus_skew -file bus-skew.rpt
check_timing -verbose -file check-timing.rpt
write_xdc -constraints all effective.xdc
write_checkpoint reviewed-synthesis.dcp
puts "M1_CLOCKED_PLATFORM_SYNTHESIZED_NOT_BOARD_VALIDATED"
exit
