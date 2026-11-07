# 持久主机传输会话。只接受固定操作和数字/十六进制字段，不执行输入代码。
# 不复位AXI，不重配置FPGA，不因工具错误重试事务。M1实验性整机限定；snapshot经core域请求/确认锁存。
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
proc fixed_hex {value digits} {
    set result ""
    for {set i [expr {$digits-1}]} {$i>=0} {incr i -1} {append result [format %x [expr {($value>>(4*$i))&15}]]}
    return $result
}
set board_control 0
proc snapshot {} {
    global vio board_control
    refresh_hw_vio $vio
    set seq [vio_read_port $vio 2 32]
    set old_ack [expr {([vio_read_port $vio 3 32]>>1)&1}]
    set wanted [expr {1-$old_ack}]
    vio_write_port $vio 0 32 [expr {$board_control | $wanted}]
    set matched 0
    for {set i 0} {$i<50} {incr i} {
        refresh_hw_vio $vio
        set now [vio_read_port $vio 2 32]
        if {$now==(($seq+1)&0xffffffff) && (([vio_read_port $vio 3 32]>>1)&1)==$wanted} {set matched 1;break}
        after 10
    }
    if {!$matched} {error "Board snapshot handshake stalled"}
    set values {}
    foreach port {0 1 2 3} {lappend values [fixed_hex [vio_read_port $vio $port 32] 16]}
    foreach port {4 5 6 7 8 9} {lappend values [fixed_hex [vio_read_port $vio $port 256] 64]}
    refresh_hw_vio $vio
    if {[vio_read_port $vio 2 32]!=$now} {error "Snapshot changed while reading"}
    if {[lindex $values 0] ne "000000004d314231"} {error "Wrong board identity"}
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
    set vio {}; set qualification_vio {}
    foreach candidate [get_hw_vios -quiet -of_objects $device] {
        refresh_hw_vio $candidate
        if {[catch {vio_read_port $candidate 0 32} magic]} {continue}
        if {$magic==0x4d314231} {lappend vio $candidate}
        if {$magic==0x44445251} {lappend qualification_vio $candidate}
    }
    set axi [get_hw_axis -quiet -of_objects $device]
    if {[llength $vio]!=1 || [llength $qualification_vio]!=1 || [llength $axi]!=1} {error "Missing exact M1 board cores"}
    vio_expect_ports $vio {0 1 2 3 4 5 6 7 8 9} {0}
    vio_expect_ports $qualification_vio {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20} {0 1 2 3 4 5 6 7 8}
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
                if {[llength $fields]!=3 || ![regexp {^[0-9a-f]{1,4}$} $control]} {error "Invalid board control"}
                scan $control %x value
                if {$value & ~0xff06} {error "Reserved board control bits"}
                set board_control $value
                snapshot
            }
            QSTATUS {
                if {[llength $fields]!=2} {error "Invalid DDR status request"}
                refresh_hw_vio $qualification_vio
                fixed_hex [vio_read_port $qualification_vio 2 32] 8
            }
            LOSS {
                if {[llength $fields]!=3 || [lindex $fields 2] ni {0 1 2 3}} {error "Invalid loss injection"}
                vio_write_port $qualification_vio 8 2 [lindex $fields 2]
                set result applied
            }
            BREAD - BWRITE {
                if {[llength $fields]!=5} {error "Invalid bulk command"}
                lassign [lrange $fields 2 end] address bytes payload
                if {![regexp {^[0-9a-f]{8}$} $address] || ![regexp {^[0-9]{1,7}$} $bytes]} {error "Invalid bulk range"}
                scan $address %x base
                if {$bytes<8 || $bytes>1048576 || ($bytes&7) || ($base&7) || $base+$bytes>0x80000000} {error "Invalid DDR bulk boundary"}
                set write [expr {$operation eq "BWRITE"}]
                if {$write} {
                    if {![regexp {^[0-9a-f]+$} $payload] || [string length $payload]!=2*$bytes} {error "Invalid bulk payload"}
                } elseif {$payload ne "-"} {error "Unexpected bulk payload"}
                set responses {}
                for {set at 0} {$at<$bytes} {incr at $count} {
                    set count [expr {min(2048,4096-(($base+$at)&4095),$bytes-$at)}]
                    set arguments [list -address [format %08x [expr {$base+$at}]] -len [expr {$count/8}] -type [expr {$write ? "WRITE" : "READ"}] -burst INCR -id 0]
                    if {$write} {
                        set first [expr {2*($bytes-$at-$count)}]
                        set part [string range $payload $first [expr {$first+2*$count-1}]]
                        lappend arguments -data $part
                    }
                    set txn [create_hw_axi_txn bulk_${sequence}_${at} $axi {*}$arguments]
                    run_hw_axi $txn
                    refresh_hw_axi $axi
                    set response [get_property [expr {$write ? "STATUS.BRESP" : "STATUS.RRESP"}] $axi]
                    if {$response ni {0 00 0x0 0x00 OKAY Okay}} {error "AXI bulk response $response at $at"}
                    set data [string tolower [string map {_ {} " " {} \n {} \r {} \t {}} [get_property DATA $txn]]]
                    if {![regexp {^[0-9a-f]+$} $data] || [string length $data]!=2*$count} {error "Invalid bulk DATA at $at"}
                    if {$write && $data ne $part} {error "Bulk write identity mismatch at $at"}
                    delete_hw_axi_txn $txn
                    lappend responses $data
                }
                join [lreverse $responses] ""
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
