# 固定Vivado2022.2的实际SmartConnect：主机64-bit和native512-bit共享512-bit出口。
# 本夹具无MIG、引脚、bitgen或硬件访问；控制窗口在未来平台路由层独立处理。
set_param general.maxThreads 2
create_project axi_fabric_fixture project -part xcvu440-flga2892-1-c
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
create_bd_design rkv_m1_axi_fabric
set fabric [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 fabric]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] $fabric
set clk [create_bd_port -dir I -type clk -freq_hz 50000000 core_clk]
set rst [create_bd_port -dir I -type rst core_aresetn]
set_property CONFIG.POLARITY ACTIVE_LOW $rst
connect_bd_net $clk [get_bd_pins fabric/aclk]
connect_bd_net $rst [get_bd_pins fabric/aresetn]
foreach {name width addr pin} {HOST 64 32 S00_AXI NATIVE 512 33 S01_AXI} {
    set port [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 $name]
    set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH $width CONFIG.ADDR_WIDTH $addr CONFIG.ID_WIDTH 4 CONFIG.FREQ_HZ 50000000 CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 1 CONFIG.HAS_CACHE 1 CONFIG.HAS_PROT 1 CONFIG.HAS_QOS 1 CONFIG.HAS_REGION 0 CONFIG.NUM_READ_OUTSTANDING 1 CONFIG.NUM_WRITE_OUTSTANDING 1 CONFIG.MAX_BURST_LENGTH 256 CONFIG.SUPPORTS_NARROW_BURST 0] $port
    connect_bd_intf_net $port [get_bd_intf_pins fabric/$pin]
}
set memory [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 MEMORY]
# SmartConnect出口无ID，原SI身份在内部保存；后级CDC统一发送ID0并核对返回ID。
# ID_WIDTH/MAX_BURST_LENGTH/SUPPORTS_NARROW_BURST由IP推导，不能写只读参数。
set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH 512 CONFIG.ADDR_WIDTH 33 CONFIG.FREQ_HZ 50000000 CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 1 CONFIG.HAS_CACHE 1 CONFIG.HAS_PROT 1 CONFIG.HAS_QOS 1 CONFIG.HAS_REGION 0 CONFIG.NUM_READ_OUTSTANDING 1 CONFIG.NUM_WRITE_OUTSTANDING 1] $memory
connect_bd_intf_net $memory [get_bd_intf_pins fabric/M00_AXI]
set_property -dict [list CONFIG.ASSOCIATED_BUSIF {HOST:NATIVE:MEMORY} CONFIG.ASSOCIATED_RESET {core_aresetn}] $clk
assign_bd_address -offset 0x00000000 -range 0x80000000 [get_bd_addr_segs MEMORY/Reg]
validate_bd_design
foreach {property expected} {ID_WIDTH 0 DATA_WIDTH 512 ADDR_WIDTH 33 SUPPORTS_NARROW_BURST 0} {
    if {[get_property CONFIG.$property $memory] != $expected} {error "Unexpected MEMORY $property"}
}
save_bd_design
foreach name {HOST NATIVE MEMORY} {
    report_property -all [get_bd_intf_ports $name] -file interface-$name.txt
}
report_property -all $fabric -file fabric-properties.txt
write_bd_tcl fabric-export.tcl
set bd [get_files */rkv_m1_axi_fabric.bd]
generate_target all $bd
make_wrapper -files $bd -top
export_simulation -of_objects $bd -directory simulation-export -simulator xsim

# JTAG源独立生成，避免用行为激励冒充实际JTAG传输测试。
create_ip -vlnv xilinx.com:ip:jtag_axi:1.2 -module_name rkv_m1_jtag_axi
set jtag [get_ips rkv_m1_jtag_axi]
set_property -dict [list CONFIG.PROTOCOL {0} CONFIG.M_AXI_DATA_WIDTH {64} CONFIG.M_AXI_ADDR_WIDTH {32} CONFIG.M_AXI_ID_WIDTH {4} CONFIG.M_HAS_BURST {0} CONFIG.RD_TXN_QUEUE_LENGTH {1} CONFIG.WR_TXN_QUEUE_LENGTH {1}] $jtag
report_property -all $jtag -file jtag-properties.txt
generate_target all $jtag
puts "M1_ACTUAL_AXI_FABRIC_GENERATED_NOT_BOARD"
exit
