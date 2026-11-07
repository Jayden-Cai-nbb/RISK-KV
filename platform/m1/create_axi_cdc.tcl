# 固定Vivado2022.2的实际AXI Clock Converter；无DDR参数、引脚或硬件操作。
set_param general.maxThreads 2
create_project axi_cdc_fixture project -part xcvu440-flga2892-1-c
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
create_ip -vlnv xilinx.com:ip:axi_clock_converter:2.1 -module_name rkv_m1_axi_clock_converter
set core [get_ips rkv_m1_axi_clock_converter]
set_property -dict [list \
    CONFIG.PROTOCOL {AXI4} \
    CONFIG.READ_WRITE_MODE {READ_WRITE} \
    CONFIG.ADDR_WIDTH {33} \
    CONFIG.DATA_WIDTH {512} \
    CONFIG.ID_WIDTH {4} \
    CONFIG.ACLK_ASYNC {1} \
    CONFIG.SYNCHRONIZATION_STAGES {3} \
    CONFIG.AWUSER_WIDTH {0} \
    CONFIG.ARUSER_WIDTH {0} \
    CONFIG.WUSER_WIDTH {0} \
    CONFIG.RUSER_WIDTH {0} \
    CONFIG.BUSER_WIDTH {0} \
] $core
report_property -all $core -file cdc-properties.txt
generate_target all $core
export_simulation -of_objects $core -directory simulation-export -simulator xsim
puts "AXI_CDC_512_ASYNC_GENERATED_NOT_BOARD"
exit
