# 完整数字平台真实计算层展开；没有MIG、引脚约束、烧写或模型数值验收。
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
synth_design -rtl -top rkv_m1_platform -part xcvu440-flga2892-1-c \
    -mode out_of_context -generic FIRMWARE=firmware.hex
# 保存实际层级供独立复核，禁止用夹具或未解析黑盒冒充完整计算层。
set fh [open hierarchy.txt w]
foreach cell [lsort [get_cells -hier]] {
    puts $fh "$cell [get_property REF_NAME $cell]"
}
close $fh
report_property [get_cells native/system/compute/compute] -file compute-properties.txt
if {[llength [get_cells native/system/compute/compute]] != 1} {error "Missing actual openTPU slice"}
if {[llength [get_cells native/native_memory/adapter]] != 1} {error "Missing actual native adapter"}
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]] != 0} {error "Unexpected elaboration blackbox"}
puts "M1_FULL_PLATFORM_ELABORATED_NOT_NUMERIC_OR_BOARD_VALIDATED"
exit
