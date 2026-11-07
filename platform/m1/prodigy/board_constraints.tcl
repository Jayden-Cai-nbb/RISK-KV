# 在实际综合网表上解析派生时钟；不创建独立core/fast时钟或全域false path。
set rkv_core_clock [get_clocks -of_objects [get_pins example/clocks/clk_out2]]
set rkv_fast_clock [get_clocks -of_objects [get_pins example/clocks/clk_out1]]
set rkv_ui_clock [get_clocks -of_objects [get_pins example/u_rkv_ddr_candidate/c0_ddr4_ui_clk]]
foreach {clock period} [list $rkv_core_clock 20.0 $rkv_fast_clock 10.0 $rkv_ui_clock 5.208333] {
    if {[llength $clock]!=1 || abs([get_property PERIOD $clock]-$period)>0.002} {error "Unexpected actual board clock $clock"}
}
if {![get_property IS_GENERATED $rkv_core_clock] || ![get_property IS_GENERATED $rkv_fast_clock]} {error "core/fast must be generated"}
if {[get_property MASTER_CLOCK $rkv_core_clock] ne [get_property MASTER_CLOCK $rkv_fast_clock]} {error "core/fast master mismatch"}
if {[get_property WAVEFORM $rkv_core_clock] ne {0.000 10.000} || [get_property WAVEFORM $rkv_fast_clock] ne {0.000 5.000}} {
    error "core/fast phase mismatch"
}
# 拓扑限定的冷复位握手CDC，沿用已验证边界，仅替换板级实例路径。
set rkv_reset_index 0
foreach {dst allowed_sources source_clock destination_clock} [list \
    {example/platform/shared/reset_coord/core_done_in_ddr_reg[0]/D} \
        {{example/platform/shared/control_reset/hold_reg[15]} {example/platform/shared/reset_coord/core_hold_reg[15]}} $rkv_core_clock $rkv_ui_clock \
    {example/platform/shared/reset_coord/ddr_done_in_core_reg[0]/D} \
        {{example/platform/shared/reset_coord/ddr_hold_reg[15]}} $rkv_ui_clock $rkv_core_clock \
    {example/platform/shared/reset_coord/ddr_release_in_core_reg[0]/D} \
        {example/platform/shared/reset_coord/ddr_aresetn_reg} $rkv_ui_clock $rkv_core_clock] {
    set to_pin [get_pins -quiet $dst]
    if {[llength $to_pin]!=1} {error "Missing cold handshake endpoint $dst"}
    set drivers [get_pins -leaf -of_objects [get_nets -segments -of_objects $to_pin] -filter {DIRECTION == OUT}]
    if {[llength $drivers]!=1 || [get_property REF_PIN_NAME $drivers] ne "Q"} {error "Nonunique cold driver"}
    set source_cell [get_cells -of_objects $drivers]
    if {[lsearch -exact $allowed_sources $source_cell]<0} {error "Cold handshake driver changed: $source_cell"}
    if {[get_property REF_NAME $source_cell] ne "FDCE" || [get_property INIT $source_cell] ne "1'b0"} {error "Cold primitive changed"}
    set target_cell [get_cells -of_objects $to_pin]
    if {![regexp -nocase {^(1|TRUE)$} [get_property ASYNC_REG $target_cell]]} {error "Cold synchronizer absent"}
    set from_pin [get_pins $source_cell/C]
    if {[get_clocks -of_objects $from_pin] ne $source_clock || [get_clocks -of_objects [get_pins $target_cell/C]] ne $destination_clock} {error "Cold clock mismatch"}
    set_max_delay -datapath_only 5.208 -from $from_pin -to $to_pin
    incr rkv_reset_index
}
# 新增两条UI到core的配置级电平。仅首级D限定5.208ns，后级按core时序分析。
foreach {source destination} {
    example/boot_selection/service_mode_reg {example/service_sync_reg[0]}
    example/boot_selection/switch_fault_reg {example/switch_fault_sync_reg[0]}
} {
    set sp [get_pins -quiet $source/C]
    set dp [get_pins -quiet $destination/D]
    if {[llength $sp]!=1 || [llength $dp]!=1} {error "Missing boot ownership CDC"}
    if {![regexp -nocase {^(1|TRUE)$} [get_property ASYNC_REG [get_cells $destination]]]} {error "Missing ownership ASYNC_REG"}
    set_max_delay -datapath_only 5.208 -from $sp -to $dp
}
# 精确异步入口：仅三级reset同步链CLR，后续业务CLR由同域末级同步释放。
# 不覆盖core/fast数据路径、16拍等待、互确认或AXI CDC主体。
foreach domain {core ddr} {
    set names {}
    for {set index 0} {$index<3} {incr index} {
        set name [format {example/platform/shared/reset_coord/%s_reset_release_reg[%d]} $domain $index]
        set cell [get_cells -quiet $name]
        if {[llength $cell]!=1 || [get_property REF_NAME $cell] ne "FDCE" || [get_property INIT $cell] ne "1'b0"} {error "Reset entry primitive changed: $name"}
        if {![regexp -nocase {^(1|TRUE)$} [get_property ASYNC_REG $cell]]} {error "Reset entry ASYNC_REG missing"}
        set clear [get_pins $cell/CLR]
        if {[llength $clear]!=1} {error "Reset entry clear missing"}
        lappend names $clear
    }
    set_false_path -to $names
}
# 健康输入是彼此独立的电平，DDR lock/cal先进入三级同步。只限制首级D布线。
set cal_cell [get_cells -quiet {example/platform/shared/guard/healthy_meta_reg[2]}]
set lock_cell [get_cells -quiet {example/platform/shared/guard/healthy_meta_reg[1]}]
foreach cell [list $cal_cell $lock_cell] {
    if {[llength $cell]!=1 || ![regexp -nocase {^(1|TRUE)$} [get_property ASYNC_REG $cell]]} {error "Health synchronizer missing"}
}
set cal_d [get_pins $cal_cell/D]
set cal_drivers [get_pins -leaf -of_objects [get_nets -segments -of_objects $cal_d] -filter {DIRECTION == OUT}]
if {[llength $cal_drivers]!=1 || [get_property REF_PIN_NAME $cal_drivers] ne "Q"} {error "Unexpected calDone source"}
set cal_source [get_cells -of_objects $cal_drivers]
if {[get_clocks -of_objects [get_pins $cal_source/C]] ne $rkv_ui_clock} {error "calDone clock changed"}
set_max_delay -datapath_only 20.000 -from $rkv_ui_clock -to $cal_d
# MMCM LOCKED是无同步launch沿的异步状态，只进入首级；后两级仍按core完整分析。
set lock_d [get_pins $lock_cell/D]
set lock_drivers [get_pins -leaf -of_objects [get_nets -segments -of_objects $lock_d] -filter {DIRECTION == OUT}]
if {[llength $lock_drivers]!=1 || [get_property REF_PIN_NAME $lock_drivers] ne "LOCKED"} {error "Unexpected DDR lock source"}
if {![string match MMCME* [get_property REF_NAME [get_cells -of_objects $lock_drivers]]]} {error "DDR lock no longer from MMCM"}
set_false_path -to $lock_d
# sticky只异步置1，运行中D保持旧1，健康恢复不清除；仅cold时同步清0且armed=0。
# PRE的撤回不作为数据采样事件。此例外不涵盖sticky/Q到业务逻辑的传播。
foreach index {0 1 2 3} {
    set cell [get_cells -quiet [format {example/platform/shared/guard/capture[%d].sticky_reg} $index]]
    if {[llength $cell]!=1 || [get_property REF_NAME $cell] ne "FDPE"} {error "Sticky fault primitive changed"}
    set_false_path -to [get_pins $cell/PRE]
}
