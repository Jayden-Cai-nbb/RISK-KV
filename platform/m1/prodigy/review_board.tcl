# 只读最终整机checkpoint，补充时钟、复位端点及层级资源证据，不修改约束/严重级别。
if {$argc != 1} {error "Need final routed board checkpoint"}
set_param general.maxThreads 2
open_checkpoint [lindex $argv 0]
if {[get_property TOP [current_design]] ne "rkv_m1_board_top" || [llength [get_ports]] != 119} {error "Wrong final board design"}
set f [open structure.tsv w]
puts $f "kind\tname\tproperty\tvalue"
puts $f "design\t[current_design]\tpart\t[get_property PART [current_design]]"
puts $f "design\t[current_design]\tblackboxes\t[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]]"
foreach cell [get_cells -hier -filter {REF_NAME == IBUFDS || REF_NAME =~ MMCME*}] {
    puts $f "clock_cell\t$cell\tprimitive\t[get_property REF_NAME $cell]"
    if {[string match MMCME* [get_property REF_NAME $cell]]} {
        foreach key {CLKFBOUT_MULT_F DIVCLK_DIVIDE CLKOUT0_DIVIDE_F CLKOUT1_DIVIDE CLKOUT0_PHASE CLKOUT1_PHASE CLKIN1_PERIOD} {
            puts $f "clock_cell\t$cell\t$key\t[get_property $key $cell]"
        }
        foreach pin {CLKIN1 CLKIN2} {
            set p [get_pins $cell/$pin]
            puts $f "clock_cell\t$cell\t${pin}_drivers\t[get_pins -leaf -of_objects [get_nets -segments -of_objects $p] -filter {DIRECTION == OUT}]"
        }
    }
}
foreach clk [lsort [get_clocks]] {
    foreach key {PERIOD WAVEFORM MASTER_CLOCK SOURCE_PINS} {
        puts $f "clock\t$clk\t$key\t[get_property $key $clk]"
    }
}
foreach name {sys_rst_n c0_ddr4_reset_n} {
    set p [get_ports $name]
    foreach key {DIRECTION PACKAGE_PIN IOSTANDARD} {puts $f "reset_port\t$name\t$key\t[get_property $key $p]"}
    if {[get_property DIRECTION $p] eq "IN"} {
        set pins [all_fanout -flat -endpoints_only -from $p]
    } else {
        set pins [all_fanin -flat -startpoints_only -to $p]
    }
    foreach endpoint $pins {puts $f "reset_port\t$name\tendpoint\t$endpoint"}
}
foreach kind {max min} {
    set path [get_timing_paths -delay_type $kind -max_paths 1]
    if {[llength $path] != 1} {error "No final $kind timing path"}
    puts $f "timing\t$kind\tslack_ns\t[get_property SLACK $path]"
    puts $f "timing\t$kind\tstart\t[get_property STARTPOINT_PIN $path]"
    puts $f "timing\t$kind\tend\t[get_property ENDPOINT_PIN $path]"
}
close $f
report_timing -delay_type max -max_paths 20 -file setup-paths.rpt
report_timing -delay_type min -max_paths 20 -file hold-paths.rpt
report_utilization -hierarchical -hierarchical_depth 5 -file utilization-hierarchy.rpt
report_methodology -file methodology.rpt
puts "M1_BOARD_READONLY_REVIEW_REPORTS_NOT_ACCEPTANCE"
exit
