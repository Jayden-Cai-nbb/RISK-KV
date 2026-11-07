# 配对最终整机bit/ltx；不连接硬件、不改变约束或DRC严重级别。
if {$argc!=1} {error "Need final routed board checkpoint"}
set_param general.maxThreads 2
open_checkpoint [lindex $argv 0]
if {[get_property TOP [current_design]] ne "rkv_m1_board_top" || [llength [get_ports]]!=119} {error "Not the final board design"}
if {[llength [get_cells -hier -filter {REF_NAME == IBUFDS}]]!=1 || [llength [get_cells -hier -filter {REF_NAME =~ MMCME*}]]!=2} {error "Reference clock topology changed"}
set f [open configuration-lifetime.tsv w]
puts $f "state\tprimitive\tinit\treset_drivers"
foreach name {
    example/configuration_guard/launched_reg
    example/configuration_guard/reset_fault_reg
    example/boot_selection/service_mode_reg
    example/boot_selection/switch_fault_reg
} {
    set cell [get_cells -quiet $name]
    if {[llength $cell]!=1 || [get_property REF_NAME $cell] ne "FDRE" || [get_property INIT $cell] ne "1'b0"} {error "Configuration state differs: $name"}
    set reset [get_pins $cell/R]
    set drivers [get_cells -of_objects [get_pins -leaf -of_objects [get_nets -of_objects $reset] -filter {DIRECTION == OUT}]]
    set kinds [lsort -unique [get_property REF_NAME $drivers]]
    puts $f "$name\tFDRE\t[get_property INIT $cell]\t$kinds"
    if {$kinds ne "GND"} {error "Ordinary reset must not clear configuration ownership"}
}
close $f
report_drc -ruledeck bitstream_checks -file bitgen-drc.rpt
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "Unresolved bitstream DRC"}
foreach kind {max min} {
    set path [get_timing_paths -delay_type $kind -max_paths 1]
    if {[llength $path]!=1 || [get_property SLACK $path]<0} {error "Final timing fails $kind"}
}
report_cdc -details -file bitgen-cdc.rpt
set f [open bitgen-cdc.rpt r];set cdc [read $f];close $f
if {[regexp -line {^CDC-[0-9]+[ \t]+Critical[ \t]+[1-9]} $cdc]} {error "Unresolved structural CDC critical warning"}
write_debug_probes rkv-m1-board.ltx
write_bitstream rkv-m1-board.bit
puts "M1_EXPERIMENTAL_BOARD_BIT_GENERATED_REQUIRES_PHYSICAL_REVIEW_AND_ACCEPTANCE"
exit
