# 新整机层级下的三条冷复位握手边界；直接核验综合网表实际Q驱动。
# 与已验证共享子系统同一5.208ns边界，不设整个clock group false_path。
set rkv_reset_index 0
foreach {dst allowed_sources source_clock destination_clock} {
    {shared/reset_coord/core_done_in_ddr_reg[0]/D} {{shared/control_reset/hold_reg[15]} {shared/reset_coord/core_hold_reg[15]}} core ddr_ui
    {shared/reset_coord/ddr_done_in_core_reg[0]/D} {{shared/reset_coord/ddr_hold_reg[15]}} ddr_ui core
    {shared/reset_coord/ddr_release_in_core_reg[0]/D} {shared/reset_coord/ddr_aresetn_reg} ddr_ui core
} {
    set to_pin [get_pins -quiet $dst]
    if {[llength $to_pin] != 1} {error "Reset destination mismatch: $dst"}
    set drivers [get_pins -leaf -of_objects [get_nets -segments -of_objects $to_pin] -filter {DIRECTION == OUT}]
    if {[llength $drivers] != 1 || [get_property REF_PIN_NAME $drivers] ne "Q"} {error "Expected one direct reset Q driver: $dst -> $drivers"}
    set source_cell [get_cells -of_objects $drivers]
    if {[lsearch -exact $allowed_sources $source_cell] < 0} {error "Unexpected reset source: $source_cell -> $dst"}
    if {[get_property REF_NAME $source_cell] ne "FDCE" || [get_property INIT $source_cell] ne "1'b0"} {error "Reset primitive/INIT changed: $source_cell"}
    set from_pin [get_pins -quiet $source_cell/C]
    set target_cell [get_cells -of_objects $to_pin]
    if {![regexp -nocase {^(1|TRUE)$} [get_property ASYNC_REG $target_cell]]} {error "Target is not ASYNC_REG: $dst"}
    if {[get_clocks -of_objects $from_pin] ne $source_clock || [get_clocks -of_objects [get_pins $target_cell/C]] ne $destination_clock} {error "Unexpected reset clock domains: $dst"}
    set_max_delay -datapath_only 5.208 -from $from_pin -to $to_pin
    puts "PLATFORM_RESET_CDC_BOUND $from_pin -> $to_pin max_delay=5.208"
    report_timing -from $from_pin -to $to_pin -delay_type max -max_paths 1 -file reset-cdc-$rkv_reset_index.rpt
    incr rkv_reset_index
}
