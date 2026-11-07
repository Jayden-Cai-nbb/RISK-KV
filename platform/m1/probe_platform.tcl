# Read-only tool/device enumeration. No programming, reset, AXI or VIO writes.
set_param general.maxThreads 2
puts "M1_TOOL_VERSION [version -short]"
set parts [get_parts -quiet xcvu440-flga2892-2-e]
puts "M1_INSTALLED_EXPECTED_PART $parts"
if {[llength $parts] != 1} {error "Expected VU440 part is unavailable"}
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -quiet]
puts "M1_HW_TARGETS $targets"
if {[llength $targets] == 1} {
    open_hw_target [lindex $targets 0]
    foreach device [get_hw_devices -quiet] {
        refresh_hw_device -update_hw_probes false $device
        puts "M1_HW_DEVICE $device"
        foreach property {PART IDCODE PROGRAM.IS_PROGRAMMED REGISTER.CONFIG_STATUS} {
            if {[lsearch -exact [list_property $device] $property] >= 0} {
                puts "M1_HW_PROPERTY $property [get_property $property $device]"
            }
        }
    }
    puts "M1_HW_AXI [get_hw_axis -quiet]"
    puts "M1_HW_VIO [get_hw_vios -quiet]"
    close_hw_target
} else {
    puts "M1_HW_NOT_OPENED target_count=[llength $targets]"
}
disconnect_hw_server
close_hw_manager
puts "M1_PROBE_FINISHED_NO_PROGRAMMING"
exit
