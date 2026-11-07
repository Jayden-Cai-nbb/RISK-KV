# Standalone bridge synthesis only; no board clocks, DDR pins, CDC or bitstream.
set_param general.maxThreads 2
read_verilog -sv rkv_m1_native_axi.sv
synth_design -top rkv_m1_native_axi -part xcvu440-flga2892-2-e -mode out_of_context
create_clock -name core -period 20.000 [get_ports clk]
report_utilization -file utilization.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing-estimate.rpt
check_timing -verbose -file check-timing.rpt
write_checkpoint synthesized.dcp
puts "NATIVE_AXI_OOC_SYNTHESIZED_NOT_BOARD_TIMING"
exit
