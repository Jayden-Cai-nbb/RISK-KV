# 固定2022.2的真实主机地址路由；与共享DDR互连分开，控制路径不进入DDR规范化。
if {$argc != 1} {error "Need generated address-spec.tcl from frozen JSON layout"}
source [lindex $argv 0]
if {$rkv_logical_bytes != 0x80000000 || $rkv_control_base != 0x80000000 || $rkv_mailbox_base != 0x80010000} {error "Address contract changed; review before generation"}
set_param general.maxThreads 2
create_project host_router_fixture project -part xcvu440-flga2892-1-c
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
create_bd_design rkv_m1_host_router
set router [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 router]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2} CONFIG.NUM_CLKS {1}] $router
set clk [create_bd_port -dir I -type clk -freq_hz 50000000 core_clk]
set rst [create_bd_port -dir I -type rst core_aresetn]
set_property CONFIG.POLARITY ACTIVE_LOW $rst
connect_bd_net $clk [get_bd_pins router/aclk]
connect_bd_net $rst [get_bd_pins router/aresetn]
set host [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 HOST]
set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH 64 CONFIG.ADDR_WIDTH 32 CONFIG.ID_WIDTH 4 CONFIG.FREQ_HZ 50000000 CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 1 CONFIG.HAS_CACHE 1 CONFIG.HAS_PROT 1 CONFIG.HAS_QOS 1 CONFIG.HAS_REGION 0 CONFIG.NUM_READ_OUTSTANDING 1 CONFIG.NUM_WRITE_OUTSTANDING 1 CONFIG.MAX_BURST_LENGTH 256 CONFIG.SUPPORTS_NARROW_BURST 0] $host
connect_bd_intf_net $host [get_bd_intf_pins router/S00_AXI]
foreach {name pin} {DDR M00_AXI CONTROL M01_AXI} {
    set port [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 $name]
    set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.DATA_WIDTH 64 CONFIG.ADDR_WIDTH 32 CONFIG.FREQ_HZ 50000000 CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 1 CONFIG.HAS_CACHE 1 CONFIG.HAS_PROT 1 CONFIG.HAS_QOS 1 CONFIG.HAS_REGION 0 CONFIG.NUM_READ_OUTSTANDING 1 CONFIG.NUM_WRITE_OUTSTANDING 1] $port
    connect_bd_intf_net $port [get_bd_intf_pins router/$pin]
}
set_property -dict [list CONFIG.ASSOCIATED_BUSIF {HOST:DDR:CONTROL} CONFIG.ASSOCIATED_RESET {core_aresetn}] $clk
assign_bd_address -offset 0 -range $rkv_logical_bytes [get_bd_addr_segs DDR/Reg]
# 一个128KiB窗口包含控制寄存器及邮箱别名；空洞由真实控制从端返回DECERR。
set control_span 1
while {$control_span < $rkv_mailbox_base + $rkv_mailbox_bytes - $rkv_control_base} {set control_span [expr {$control_span * 2}]}
assign_bd_address -offset $rkv_control_base -range $control_span [get_bd_addr_segs CONTROL/Reg]
validate_bd_design
save_bd_design
foreach name {HOST DDR CONTROL} {report_property -all [get_bd_intf_ports $name] -file interface-$name.txt}
report_property -all $router -file router-properties.txt
write_bd_tcl router-export.tcl
set bd [get_files */rkv_m1_host_router.bd]
generate_target all $bd
make_wrapper -files $bd -top
export_simulation -of_objects $bd -directory simulation-export -simulator xsim
puts "M1_HOST_ROUTER_GENERATED_NOT_INTEGRATED_OR_BOARD"
exit
