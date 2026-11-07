# Correct only the OOC report model; do not resynthesize or hide board CDC gaps.
set_param general.maxThreads 2
open_checkpoint ../native-ooc-v1/native-synth.dcp
# Vivado create_clock without -add replaces the clock on this source.
# Keep all other DCP constraints intact.
create_clock -name fast -period 10.000 -waveform {0.000 5.000} [get_ports clk_f]
if {[llength [get_clocks]] != 2 || [get_property IS_GENERATED [get_clocks fast]]} {
    error "Expected exactly two primary OOC input clocks"
}
report_clocks -file clocks.rpt
report_timing_summary -file timing-estimate.rpt
puts "M1_OOC_REPORT_REMODELED_NOT_ROUTED_OR_PHASE_VALIDATED"
exit
