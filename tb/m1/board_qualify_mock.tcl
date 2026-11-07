# Fake Vivado only; no device/DDR. Python supplies expected bytes and old-state selection.

set programmed 0
set started 0
set peeks 0
set index 0
set service $::PREVIOUS_SERVICE
set snapshot_seq 0
set snapshot_ack 0
array set cfg {0 0 1 0 2 1024 3 0 4 0 5 0 6 0}
proc open_hw_manager {} {}
proc connect_hw_server {args} {}
proc get_hw_targets {args} {return target}
proc current_hw_target {args} {}
proc set_property {args} {}
proc open_hw_target {args} {}
proc get_hw_devices {args} {return xcvu440_0}
proc refresh_hw_device {args} {}
proc get_hw_vios {args} {if {$::programmed} {return {q trace board}};if {$::PREVIOUS_BOARD} {return {old board}};return old}
proc vio_expect_ports {args} {}
proc refresh_hw_vio {args} {}
proc vio_read_port {v p w} {
 if {$v eq "board"} {
  switch $p {
   0 {return 0x4d314231}
   2 {return $::snapshot_seq}
   3 {return [expr {5|($::service<<3)|($::snapshot_ack<<1)}]}
   4 {return 0x84f0}
   default {return 0}
  }
 }
 if {$v eq "old"} {if {$p==0} {return 0x44445251};return $::PREVIOUS_STATUS}
 if {$v eq "trace"} {
  switch $p {0 {return 0x54524331} 1 {return [expr {(1<<21)|(1<<10)}]} 2 {return 0} 3 {return 0} 4 {return 10} 5 {return 20}}
 }
 set n [expr {$::started?55*3*33554432:0}]
 switch $p {
  0 {return 0x44445251}
  1 {return 42}
  2 {return [expr {$::started?425:1}]}
  3 {return 10}
  4 {return $::cfg(6)}
  5 {if {$w!=192} {error "Counter width"};return [expr {($n<<144)|($n<<96)|($n<<48)|($n+$::peeks)}]}
  6 {if {$w!=48} {error "R width"};return [expr {$n+$::peeks}]}
  7 {return 123456789012}
  8 {return 55}
  9 {return 5}
  18 {return $::cfg(5)}
  19 {return 0}
  20 {return 1000}
 }
 if {$p>=10&&$p<=13} {return 0}
 if {$p>=14&&$p<=17} {set x [dict get $::expected $::cfg(6)];return [expr {($x>>(128*($p-14)))&((1<<128)-1)}]}
 error "unexpected read"
}
proc vio_write_port {v p w value} {
 if {$v eq "board"} {
  if {$p!=0||$w!=32} {error "board output geometry"}
  set ::snapshot_ack [expr {$value&1}];incr ::snapshot_seq;return
 }
 if {$v eq "q" && $p==7} {
  if {$w!=1||$value!=1||$::peeks!=9} {error "premature or incorrect handover"}
  set ::service 1;return
 }
 if {$v eq "trace"} {if {$p!=0||$value!=0} {error trace};return}
 if {$w!=[lindex {1 32 26 32 16 1 32} $p]} {error "wrong output width"}
 set ::cfg($p) $value
 if {$p==0} {if {$value!=1||[incr ::started]!=1} {error "duplicate start"}}
 if {$p==5} {incr ::peeks}
}
proc report_property {args} {
 set i [lsearch $args -file];set f [open [lindex $args [expr {$i+1}]] w];puts $f MOCK_ONLY;close $f
}
proc close_hw_target {args} {}
proc program_hw_devices {args} {if {[incr ::programmed]!=1} {error "repeat program"};set ::service 0;set f [open programmed-marker.txt w];puts $f MOCK_ONLY;close $f}
proc get_hw_migs {args} {return mig}
proc report_hw_mig {args} {report_property {*}$args}
proc disconnect_hw_server {} {}
proc close_hw_manager {} {if {$::programmed!=1||$::started!=1||$::peeks!=9||!$::service||$::snapshot_seq!=1} {error "coverage"};puts "MOCK_PASS_NO_HARDWARE"}
