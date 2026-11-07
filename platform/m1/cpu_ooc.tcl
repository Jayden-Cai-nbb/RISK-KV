# Run in a fresh output directory with a hash-recorded src/ snapshot.
# CPU/control synthesis only; no DDR, pin, physical timing or board claim.
set_param general.maxThreads 2
set root [file normalize src]
read_verilog -sv [list $root/vendor/picorv32/picorv32.v \
    $root/rtl/m1/rkv_m1_layout_pkg.sv \
    $root/rtl/m1/rkv_m1_control.sv $root/rtl/m1/rkv_m1_cleaner.sv \
    $root/rtl/m1/rkv_m1_executor.sv $root/rtl/m1/rkv_m1_service.sv \
    $root/rtl/m1/rkv_m1_mmio.sv $root/rtl/m1/rkv_m1_cpu.sv]
synth_design -top rkv_m1_cpu -part xcvu440-flga2892-2-e \
    -mode out_of_context -generic FIRMWARE=firmware.hex
create_clock -name core -period 20.000 [get_ports clk]
report_utilization -file utilization.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_timing_summary -file timing-estimate.rpt
write_checkpoint cpu-synth.dcp
puts "M1_CPU_OOC_SYNTHESIZED_NOT_BOARD_VALIDATED"
exit
