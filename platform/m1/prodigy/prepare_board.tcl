# 只操作调用者准备好的全新示例副本，不改母版或 Vivado 安装。
open_project project/example/rkv_ddr_candidate_ex.xpr
set root [file normalize .]
foreach f [get_files -all] {
    set path [file normalize $f]
    if {![string match "$root/*" $path] && ![string match /opt/Xilinx/* $path]} {
        error "External source reference in copied project: $path"
    }
}
set ipfile [get_files -all */rkv_ddr_candidate.xci]
if {[llength $ipfile] != 1} {error "Expected one DDR IP customization"}
# UG896 2022.2：复杂子系统用 IS_LOCKED 进入用户管理；不是绕过 DRC。
# 全局综合直接读取已导出的 RTL，避免复用未修改的 OOC DCP。
set_property GENERATE_SYNTH_CHECKPOINT false $ipfile
set_property IS_LOCKED true $ipfile
report_property -all $ipfile -file user-managed-ip.txt
set locked [get_property IS_LOCKED [get_ips rkv_ddr_candidate]]
if {!$locked} {error "DDR subsystem did not enter locked user management"}
set state [open user-management-state.tsv w]
puts $state "IS_LOCKED\t[expr {$locked ? 1 : 0}]"
puts $state "GENERATE_SYNTH_CHECKPOINT\t[get_property GENERATE_SYNTH_CHECKPOINT $ipfile]"
close $state
set old [get_files -all *example_design.xdc]
if {[llength $old] != 1} {error "Expected one vendor example pin file"}
remove_files $old
add_files rkv_m1_board_top.v
add_files -fileset constrs_1 prodigy-pins.xdc
set_property PROCESSING_ORDER LATE [get_files prodigy-pins.xdc]
set_property top rkv_m1_board_top [current_fileset]
set id_file [open experiment-id.txt r]
set experiment_id [string trim [read $id_file]]
close $id_file
if {![regexp {^[0-9a-f]{16}$} $experiment_id]} {error "Invalid build identity"}
set_property generic "EXPERIMENT_ID=64'h$experiment_id" [current_fileset]

add_files [list rkv_m1_board_memory.sv rkv_ddr_qualifier.v rkv_ddr_first_guard.v]
create_ip -vlnv xilinx.com:ip:vio:3.0 -module_name ddr_qualifier_vio
set vio_config [list CONFIG.C_NUM_PROBE_IN 21 CONFIG.C_NUM_PROBE_OUT 9 CONFIG.C_EN_PROBE_IN_ACTIVITY 0]
lappend vio_config CONFIG.C_PROBE_IN0_WIDTH 32
lappend vio_config CONFIG.C_PROBE_IN1_WIDTH 32
lappend vio_config CONFIG.C_PROBE_IN2_WIDTH 32
lappend vio_config CONFIG.C_PROBE_IN3_WIDTH 32
lappend vio_config CONFIG.C_PROBE_IN4_WIDTH 33
lappend vio_config CONFIG.C_PROBE_IN5_WIDTH 192
lappend vio_config CONFIG.C_PROBE_IN6_WIDTH 48
lappend vio_config CONFIG.C_PROBE_IN7_WIDTH 48
lappend vio_config CONFIG.C_PROBE_IN8_WIDTH 32
lappend vio_config CONFIG.C_PROBE_IN9_WIDTH 3
lappend vio_config CONFIG.C_PROBE_IN10_WIDTH 128
lappend vio_config CONFIG.C_PROBE_IN11_WIDTH 128
lappend vio_config CONFIG.C_PROBE_IN12_WIDTH 128
lappend vio_config CONFIG.C_PROBE_IN13_WIDTH 128
lappend vio_config CONFIG.C_PROBE_IN14_WIDTH 128
lappend vio_config CONFIG.C_PROBE_IN15_WIDTH 128
lappend vio_config CONFIG.C_PROBE_IN16_WIDTH 128
lappend vio_config CONFIG.C_PROBE_IN17_WIDTH 128
lappend vio_config CONFIG.C_PROBE_IN18_WIDTH 1
lappend vio_config CONFIG.C_PROBE_IN19_WIDTH 26
lappend vio_config CONFIG.C_PROBE_IN20_WIDTH 32
lappend vio_config CONFIG.C_PROBE_OUT0_WIDTH 1 CONFIG.C_PROBE_OUT0_INIT_VAL 0x0
lappend vio_config CONFIG.C_PROBE_OUT1_WIDTH 32 CONFIG.C_PROBE_OUT1_INIT_VAL 0x0
lappend vio_config CONFIG.C_PROBE_OUT2_WIDTH 26 CONFIG.C_PROBE_OUT2_INIT_VAL 0x400
lappend vio_config CONFIG.C_PROBE_OUT3_WIDTH 32 CONFIG.C_PROBE_OUT3_INIT_VAL 0x12345678
lappend vio_config CONFIG.C_PROBE_OUT4_WIDTH 16 CONFIG.C_PROBE_OUT4_INIT_VAL 0x0
lappend vio_config CONFIG.C_PROBE_OUT5_WIDTH 1 CONFIG.C_PROBE_OUT5_INIT_VAL 0x0
lappend vio_config CONFIG.C_PROBE_OUT6_WIDTH 32 CONFIG.C_PROBE_OUT6_INIT_VAL 0x0
lappend vio_config CONFIG.C_PROBE_OUT7_WIDTH 1 CONFIG.C_PROBE_OUT7_INIT_VAL 0x0
lappend vio_config CONFIG.C_PROBE_OUT8_WIDTH 2 CONFIG.C_PROBE_OUT8_INIT_VAL 0x0
set_property -dict $vio_config [get_ips ddr_qualifier_vio]
generate_target all [get_ips ddr_qualifier_vio]

add_files [list rkv_boot_trace.v rkv_ddr_init_trace.v]
create_ip -vlnv xilinx.com:ip:vio:3.0 -module_name ddr_init_trace_vio
set trace_config [list CONFIG.C_NUM_PROBE_IN 6 CONFIG.C_NUM_PROBE_OUT 1 CONFIG.C_EN_PROBE_IN_ACTIVITY 0]
foreach {i width} {0 32 1 32 2 128 3 128 4 48 5 48} {
    lappend trace_config CONFIG.C_PROBE_IN${i}_WIDTH $width
}
lappend trace_config CONFIG.C_PROBE_OUT0_WIDTH 10 CONFIG.C_PROBE_OUT0_INIT_VAL 0x0
set_property -dict $trace_config [get_ips ddr_init_trace_vio]
generate_target all [get_ips ddr_init_trace_vio]

# 真实完整平台、互连和AXI CDC使用已验证的固定输入副本。
foreach name {fabric router} {
    set candidates [glob $name-copy/project/*.srcs/sources_1/bd/*/*.bd]
    if {[llength $candidates]!=1} {error "Expected one $name BD"}
    set bd [lindex $candidates 0]
    add_files $bd
    set_property GENERATE_SYNTH_CHECKPOINT false [get_files $bd]
    generate_target all [get_files $bd]
}
set xci cdc-copy/project/axi_cdc_fixture.srcs/sources_1/ip/rkv_m1_axi_clock_converter/rkv_m1_axi_clock_converter.xci
add_files $xci
set_property GENERATE_SYNTH_CHECKPOINT false [get_files $xci]
generate_target all [get_ips rkv_m1_axi_clock_converter]
create_ip -vlnv xilinx.com:ip:jtag_axi:1.2 -module_name rkv_m1_jtag_axi
set_property -dict [list CONFIG.PROTOCOL 0 CONFIG.M_AXI_DATA_WIDTH 64 CONFIG.M_AXI_ADDR_WIDTH 32 CONFIG.M_AXI_ID_WIDTH 4 CONFIG.M_HAS_BURST 0 CONFIG.RD_TXN_QUEUE_LENGTH 1 CONFIG.WR_TXN_QUEUE_LENGTH 1] [get_ips rkv_m1_jtag_axi]
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clock_48_to_100_50
set_property -dict [list CONFIG.PRIM_IN_FREQ 48.000 CONFIG.PRIM_SOURCE No_buffer CONFIG.PRIMITIVE MMCM CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 100.000 CONFIG.CLKOUT2_USED true CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 50.000 CONFIG.USE_LOCKED true CONFIG.USE_RESET true] [get_ips clock_48_to_100_50]
create_ip -vlnv xilinx.com:ip:vio:3.0 -module_name rkv_m1_board_vio
set_property -dict [list CONFIG.C_NUM_PROBE_IN 10 CONFIG.C_NUM_PROBE_OUT 1 CONFIG.C_EN_PROBE_IN_ACTIVITY 0 CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 32 CONFIG.C_PROBE_IN2_WIDTH 32 CONFIG.C_PROBE_IN3_WIDTH 32 CONFIG.C_PROBE_IN4_WIDTH 256 CONFIG.C_PROBE_IN5_WIDTH 256 CONFIG.C_PROBE_IN6_WIDTH 256 CONFIG.C_PROBE_IN7_WIDTH 256 CONFIG.C_PROBE_IN8_WIDTH 256 CONFIG.C_PROBE_IN9_WIDTH 256 CONFIG.C_PROBE_OUT0_WIDTH 32 CONFIG.C_PROBE_OUT0_INIT_VAL 0x0] [get_ips rkv_m1_board_vio]
foreach ip {rkv_m1_jtag_axi clock_48_to_100_50 rkv_m1_board_vio} {
    set_property GENERATE_SYNTH_CHECKPOINT false [get_files */$ip.xci]
    generate_target all [get_ips $ip]
    report_property -all [get_ips $ip] -file properties-$ip.txt
}
set fh [open sources/platform/m1/platform.f r]
foreach name [split [read $fh] "\n"] {
    if {$name eq "" || [string index $name 0] eq "#"} {continue}
    add_files sources/$name
}
close $fh
add_files [list rkv_m1_boot_mux.v rkv_m1_jtag_mask.v]
add_files firmware.hex
set_property FILE_TYPE {Memory Initialization Files} [get_files firmware.hex]
# 对实现用netlist施加同一组可审查约束，不依赖交互会话临时修改。
set_property STEPS.OPT_DESIGN.TCL.PRE [file normalize board_constraints.tcl] [get_runs impl_1]
update_compile_order -fileset sources_1
report_compile_order -constraints -file constraints-order.rpt
close_project
puts "CLOCK48_PROJECT_PREPARED_FOR_EXPLICIT_SOURCE_PATCH"
exit
