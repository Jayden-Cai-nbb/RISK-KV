# Run inside an isolated Tcl interpreter; no hardware API is reachable here.
set fixture [dict create a [dict create TYPE vio_input PROBE_PORT 0 WIDTH 16 PROBE_PORT_BITS 16 INPUT_VALUE 0001001000110100] \
    b [dict create TYPE vio_input PROBE_PORT 0 WIDTH 8 PROBE_PORT_BITS 8 INPUT_VALUE 01010110] \
    c [dict create TYPE vio_input PROBE_PORT 0 WIDTH 8 PROBE_PORT_BITS 0 INPUT_VALUE 01111000] \
    out [dict create TYPE vio_output PROBE_PORT 0 WIDTH 1]]
proc get_hw_probes {args} {return [dict keys $::fixture]}
proc get_property {name object} {return [dict get $::fixture $object $name]}
proc set_property {name value object} {dict set ::fixture $object $name $value}
proc commit_hw_vio {probe} {set ::committed $probe}
source vio_access.tcl
vio_expect_ports test {0} {0}
if {![catch {vio_expect_ports test {0 1} {0}}]} {error "Wrong diagnostic geometry accepted"}
if {[vio_read_port test 0 32] != 0x12345678} {error "Split probe reconstruction failed"}
dict set fixture a PROBE_PORT_BITS {31:16}
if {[vio_read_port test 0 32] != 0x12345678} {error "Explicit range reconstruction failed"}
vio_write_port test 0 1 1
if {$committed ne "out" || [dict get $fixture out OUTPUT_VALUE] ne "1"} {error "Output commit failed"}
if {![catch {vio_write_port test 0 1 2}]} {error "Out of range accepted"}
dict set fixture duplicate [dict get $fixture c]
if {![catch {vio_read_port test 0 32}]} {error "Overlapping probes accepted"}
dict unset fixture duplicate
dict unset fixture c
if {![catch {vio_read_port test 0 32}]} {error "Missing byte accepted"}
puts "VIO_ACCESS_TEST_PASS"
