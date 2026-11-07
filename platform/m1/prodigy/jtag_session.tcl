# 持久主机传输会话。只接受固定操作和数字/十六进制字段，不执行输入代码。
# 不复位AXI，不重配置FPGA，不因工具错误重试事务。JTG1诊断限定。
if {$argc != 4} {error "Need paired LTX, JTAG frequency, target serial, session nonce"}
source [file join [file dirname [info script]] vio_access.tcl]
lassign $argv ltx frequency serial nonce
if {![regexp {^[0-9a-f]{32}$} $nonce] || ![regexp {^[0-9]+$} $serial]} {error "Invalid session identity"}
if {$frequency ni {1000000 5000000 15000000}} {error "Unsupported tested frequency"}
proc reply {sequence status payload} {
    global nonce
    binary scan [encoding convertto utf-8 $payload] H* encoded
    puts "RKVJTAG $nonce $sequence $status $encoded"
    flush stdout
}
proc snapshot {} {
    global vio
    refresh_hw_vio $vio
    set values {}
    foreach {port width} {0 32 1 32 2 32 3 32 4 32 5 64 6 64 7 32} {
        lappend values [format %016x [vio_read_port $vio $port $width]]
    }
    if {[lindex $values 0] ne "000000004a544731"} {error "VIO identity changed"}
    return [join $values " "]
}
set code [catch {
    open_hw_manager
    connect_hw_server -url localhost:3121
    set target [get_hw_targets -quiet *$serial]
    if {[llength $target] != 1} {error "Expected one exact serial target"}
    current_hw_target $target
    set_property PARAM.FREQUENCY $frequency $target
    open_hw_target $target
    set device [get_hw_devices xcvu440_0]
    if {[llength $device] != 1} {error "Expected one VU440"}
    set_property PROBES.FILE [file normalize $ltx] $device
    refresh_hw_device $device
    set vio [get_hw_vios -quiet -of_objects $device]
    set axi [get_hw_axis -quiet -of_objects $device]
    if {[llength $vio] != 1 || [llength $axi] != 1} {error "Missing JTG1 cores"}
    if {[get_property CORE_UUID $vio] ne "C72D39A1593B5615A1BB8959A1A9425A" || [get_property CORE_UUID $axi] ne "31DBB9E70D5F5A19AC49625506F12785"} {error "Wrong diagnostic cores"}
    vio_expect_ports $vio {0 1 2 3 4 5 6 7} {0}
    foreach {property expected} {AXI_ADDR_WIDTH 32 AXI_DATA_WIDTH 64 AXI_ID_WIDTH 4 READ_QUEUE_LENGTH 1 WRITE_QUEUE_LENGTH 1} {
        if {[get_property $property $axi] ne $expected} {error "AXI geometry mismatch: $property"}
    }
    report_property $device -file session-device.txt
    report_property $axi -file session-axi.txt
    snapshot
} result options]
if {$code} {reply 0 ERROR $result; exit 1}
reply 0 READY $result
set last_sequence 0
while {[gets stdin line] >= 0} {
    # split只解析空白字段，避免把输入当作Tcl列表/表达式执行。
    set fields [regexp -all -inline {\S+} $line]
    set sequence [lindex $fields 0]
    if {![regexp {^[1-9][0-9]*$} $sequence] || $sequence != $last_sequence+1} {
        reply 0 ERROR "Out-of-order command sequence"; break
    }
    set last_sequence $sequence
    set operation [lindex $fields 1]
    set code [catch {
        switch -- $operation {
            VIO {
                if {[llength $fields] != 2} {error "Invalid VIO command"}
                snapshot
            }
            VCTL {
                set control [lindex $fields 2]
                if {[llength $fields] != 3 || $control ni {0 1 2 4}} {error "Invalid diagnostic control"}
                set observation [snapshot]
                scan [lindex $observation 2] %x state
                if {$control==1 && ((($state>>13)&3)!=0 || ($state&0x100)!=0)} {error "Actual request pending; cold refused"}
                vio_write_port $vio 0 32 $control
                snapshot
            }
            READ - WRITE {
                if {[llength $fields] != 5} {error "Invalid AXI command"}
                lassign [lrange $fields 2 end] address words payload
                if {![regexp {^[0-9a-f]{8}$} $address] || ![regexp {^[0-9]{1,3}$} $words]} {error "Invalid AXI range"}
                scan $address %x base
                if {$words<1 || $words>256 || ($base&7) || (($base&4095)+8*$words)>4096 || $base+8*$words>0x100000000} {error "Invalid AXI burst"}
                if {$operation eq "WRITE"} {
                    if {![regexp {^[0-9a-f]+$} $payload] || [string length $payload] != 16*$words} {error "Invalid write data"}
                } elseif {$payload ne "-"} {error "Unexpected read payload"}
                set arguments [list -address $address -len $words -type $operation -burst INCR -id 0]
                if {$operation eq "WRITE"} {lappend arguments -data $payload}
                set txn [create_hw_axi_txn session_$sequence $axi {*}$arguments]
                # 失败事务对象保留在会话中供诊断，不重新提交，不reset_hw_axi。
                run_hw_axi $txn
                refresh_hw_axi $axi
                set property [expr {$operation eq "WRITE" ? "STATUS.BRESP" : "STATUS.RRESP"}]
                set response [get_property $property $axi]
                if {$response ni {0 00 0x0 0x00 OKAY Okay}} {error "AXI response $response"}
                set data [string tolower [string map {_ {} " " {} \n {} \r {} \t {}} [get_property DATA $txn]]]
                if {![regexp {^[0-9a-f]+$} $data] || [string length $data] != 16*$words} {error "Invalid DATA length/encoding"}
                delete_hw_axi_txn $txn
                set data
            }
            CLOSE {
                if {[llength $fields] != 2} {error "Invalid close command"}
                set result closed
            }
            default {error "Unknown operation"}
        }
    } result options]
    if {$code} {reply $sequence ERROR $result} else {reply $sequence OK $result}
    if {$operation eq "CLOSE"} {break}
}
catch {close_hw_target}
catch {disconnect_hw_server}
catch {close_hw_manager}
exit
