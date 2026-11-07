# 工具级固定参数实验：未核验实际内存模式，不输出bit、不访问硬件。
set_param general.maxThreads 2
create_project candidate project -part xcvu440-flga2892-1-c
set_property target_language Verilog [current_project]
create_ip -vlnv xilinx.com:ip:ddr4:2.2 -module_name rkv_ddr_candidate
set core [get_ips rkv_ddr_candidate]
set_property -dict [list \
 CONFIG.C0.DDR4_isCustom {true} CONFIG.C0.DDR4_CustomParts [file normalize custom.csv] \
 CONFIG.C0.DDR4_MemoryType {SODIMMs} \
 CONFIG.C0.DDR4_MemoryPart {RKV_KVR26S19S8_8_COMPAT_HYPOTHESIS} \
 CONFIG.C0.DDR4_DataWidth {64} CONFIG.C0.DDR4_Ecc {false} \
 CONFIG.C0.DDR4_DataMask {DM_NO_DBI} CONFIG.C0.DDR4_TimePeriod {1302} \
 CONFIG.C0.DDR4_InputClockPeriod {10417} \
 CONFIG.C0.DDR4_Specify_MandD {true} CONFIG.C0.DDR4_CLKFBOUT_MULT {10} \
 CONFIG.C0.DDR4_DIVCLK_DIVIDE {1} CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
 CONFIG.C0.DDR4_CasLatency {12} CONFIG.C0.DDR4_CasWriteLatency {11} \
 CONFIG.C0.DDR4_AxiSelection {true} CONFIG.C0.DDR4_AxiDataWidth {512} \
 CONFIG.C0.DDR4_AxiAddressWidth {33} CONFIG.System_Clock {Differential} \
 CONFIG.Debug_Signal {Enable}] $core
report_property -all $core -file candidate-properties.txt
generate_target all $core
open_example_project -dir example $core
puts "DDR_COMPAT_CANDIDATE_GENERATED_NOT_BOARD_VALIDATED"
exit
