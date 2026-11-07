# Portable system only: generic arithmetic used by the validated RTL simulation.
# No board shell, DDR IP, pins, external I/O delays or routed timing claim.
set_param general.maxThreads 2
set root [file normalize src]
set handle [open $root/rtl/m1/files.f r]
set files [split [read $handle] "\n"]
close $handle
foreach name $files {
    if {[string trim $name] ne ""} {read_verilog -sv [file join $root $name]}
}
synth_design -top rkv_m1_native_system -part xcvu440-flga2892-2-e \
    -mode out_of_context -generic FIRMWARE=firmware.hex
# OOC exposes two input clocks; there is no MMCM path between these ports.
# Nominal waveforms only; actual common source, phase and CDC remain board gates.
create_clock -name core -period 20.000 [get_ports clk]
create_clock -name fast -period 10.000 -waveform {0.000 5.000} [get_ports clk_f]
report_utilization -file utilization.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_timing_summary -file timing-estimate.rpt
report_clocks -file clocks.rpt
write_checkpoint native-synth.dcp
puts "M1_NATIVE_OOC_SYNTHESIZED_NOT_BOARD_VALIDATED"
exit
