# 最终整机同位流存储验收：一次配置/一次批次，末次成功后单向移交服务。
if {$argc ni {9 10}} {error "Need bit ltx previous_ltx previous_magic base blocks seconds seed release_service"}
set previous_policy qualification
if {$argc==10} {set previous_policy [lindex $argv 9]}
if {$previous_policy ni {qualification explicit_full_chain_reset}} {error "Invalid old-state policy"}
set release_service [lindex $argv 8]
if {$release_service ni {0 1}} {error "Invalid release selection"}
source [file join [file dirname [info script]] vio_access.tcl]
set base [lindex $argv 4]
set blocks [lindex $argv 5]
set seconds [lindex $argv 6]
set seed [lindex $argv 7]
if {$base<0 || ($base&63) || $blocks<1 || $base+$blocks*64>2147483648 || $seconds<0 || $seconds>3600} {error "Invalid fixed test range"}
proc find_magic {device magic} {
    set found {}
    foreach v [get_hw_vios -of_objects $device] {
        refresh_hw_vio $v
        if {[vio_read_port $v 0 32]==$magic} {lappend found $v}
    }
    if {[llength $found]!=1} {error "Diagnostic magic identity not unique"}
    return $found
}
proc snapshot {v tag} {
    refresh_hw_vio $v
    set f [open "$tag.tsv" w]
    puts $f "wall_us\t[clock microseconds]"
    puts $f "port\tunsigned_decimal_value"
    foreach {p w} {0 32 1 32 2 32 3 32 4 33 5 192 6 48 7 48 8 32 9 3 10 128 11 128 12 128 13 128 14 128 15 128 16 128 17 128 18 1 19 26 20 32} {puts $f "$p\t[vio_read_port $v $p $w]"}
    close $f
    return [vio_read_port $v 2 32]
}
proc capture_trace {device} {
    set v [find_magic $device 0x54524331]
    vio_expect_ports $v {0 1 2 3 4 5} {0}
    refresh_hw_vio $v
    set count [expr {([vio_read_port $v 1 32]>>10)&2047}]
    if {$count<1 || $count>1024} {error "Bad trace count"}
    set f [open trace.tsv w]
    puts $f "index\tmetadata\ttimestamp\tpayload"
    for {set i 0} {$i<$count} {incr i} {
        vio_write_port $v 0 10 $i
        refresh_hw_vio $v
        set m [vio_read_port $v 1 32]
        if {($m&1023)!=$i || !(($m>>21)&1)} {error "Trace index"}
        set data [expr {[vio_read_port $v 2 128]|([vio_read_port $v 3 128]<<128)}]
        puts $f "$i\t$m\t[vio_read_port $v 4 48]\t$data"
    }
    close $f
}
proc ref_word {addr seed round i} {
    set x [expr {($addr ^ $seed ^ $round ^ ((0x9e3779b9*$i)&0xffffffff))&0xffffffff}]
    set x [expr {($x ^ ($x<<13))&0xffffffff}]
    set x [expr {$x ^ ($x>>17)}]
    return [expr {($x ^ ($x<<5))&0xffffffff}]
}
proc save_data {path data} {
    set f [open $path wb];fconfigure $f -translation binary
    for {set i 0} {$i<64} {incr i} {puts -nonewline $f [binary format H* [format %02x [expr {($data>>(8*$i))&255}]]]}
    close $f
}
open_hw_manager
connect_hw_server -url localhost:3121
set target [get_hw_targets *210251130202]
if {[llength $target]!=1} {error "Target identity"}
current_hw_target $target
set_property PARAM.FREQUENCY 1000000 $target
open_hw_target $target
set device [get_hw_devices xcvu440_0]
if {[llength $device]!=1} {error "Device identity"}
set_property PROBES.FILE [file normalize [lindex $argv 2]] $device
refresh_hw_device $device
set old [find_magic $device [lindex $argv 3]]
set oldstatus [vio_read_port $old 2 32]
if {$previous_policy eq "qualification" && ($oldstatus&0x1f)!=9} {error "Previous live test is not calibrated successful idle"}
# 前序若已进入计算模式，DDRQ旧done不能证明计算已退休。此入口只接启动检查链。
set found_board 0
foreach candidate [get_hw_vios -of_objects $device] {
    refresh_hw_vio $candidate
    if {[vio_read_port $candidate 0 32]==0x4d314231} {
        incr found_board
        if {$previous_policy eq "qualification" && ([vio_read_port $candidate 3 32]&24)} {error "Previous board already in service/fault; explicit recovery procedure required"}
        report_property -all $candidate -file previous-board-vio.txt
    }
}
if {$previous_policy eq "explicit_full_chain_reset" && $found_board!=1} {error "Cold recovery requires identified full board"}
set before [open previous-policy.tsv w]
puts $before "policy\t$previous_policy\nqualifier_status\t$oldstatus\nretirement_proven\t[expr {$previous_policy eq "qualification"}]"
close $before
report_property -all $device -file before-device.txt
close_hw_target
set_property PARAM.FREQUENCY 15000000 $target
open_hw_target $target
set device [get_hw_devices xcvu440_0]
set_property PROGRAM.FILE [file normalize [lindex $argv 0]] $device
set_property PROBES.FILE [file normalize [lindex $argv 1]] $device
program_hw_devices $device
puts "DDRQ_CONFIGURATION_COMPLETED"
close_hw_target
set_property PARAM.FREQUENCY 1000000 $target
open_hw_target $target
set device [get_hw_devices xcvu440_0]
set_property PROBES.FILE [file normalize [lindex $argv 1]] $device
refresh_hw_device $device
if {[llength [get_hw_vios -of_objects $device]]!=3} {error "Expected DDRQ, TRC1, and M1B1"}
set q [find_magic $device 0x44445251]
vio_expect_ports $q {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20} {0 1 2 3 4 5 6 7 8}
report_property -all $q -file qualifier-vio.txt
set mig [get_hw_migs -of_objects $device]
if {[llength $mig]!=1} {error "Expected one MIG"}
set result [catch {
    set deadline [expr {[clock milliseconds]+60000}]
    set index 0
    while {1} {
        set status [snapshot $q [format "cal-%03d" $index]]
        if {($status&0x3ffc)!=0 || [vio_read_port $q 5 192]!=0 || [vio_read_port $q 6 48]!=0} {error "Unexpected pre-start state"}
        if {($status&3)==1} {break}
        if {[clock milliseconds]>=$deadline} {error "Calibration timeout"}
        incr index;after 500
    }
    report_hw_mig -file mig-calibrated.txt $mig
    vio_write_port $q 1 32 $base
    vio_write_port $q 2 26 $blocks
    vio_write_port $q 3 32 $seed
    vio_write_port $q 4 16 $seconds
    vio_write_port $q 0 1 1
    set begin_ms [clock milliseconds]
    set deadline [expr {$begin_ms+($seconds+600)*1000}]
    set index 0
    set last_tick -1
    while {1} {
        set status [snapshot $q [format "run-%05d" $index]]
        if {$status&16 || !($status&1) || ($status&2)} {error "DDRQ failure status=$status"}
        if {$status&8} {break}
        set tick [vio_read_port $q 7 48]
        if {$index>0 && $tick==$last_tick} {error "UI progress stopped"}
        set last_tick $tick
        if {[clock milliseconds]>=$deadline} {error "Host deadline; retain isolated state"}
        incr index;after 1000
    }
    set run_end_ms [clock milliseconds]
    set rounds [vio_read_port $q 8 32]
    set expected_count [expr {$rounds*3*$blocks}]
    set counts [vio_read_port $q 5 192]
    if {$rounds<1 || ($status&4) || [vio_read_port $q 9 3]!=5 || [vio_read_port $q 20 32]<$seconds} {error "Incomplete batch result"}
    foreach shift {0 48 96 144} {if {(($counts>>$shift)&0xffffffffffff)!=$expected_count} {error "Write/AR count mismatch"}}
    if {[vio_read_port $q 6 48]!=$expected_count} {error "R count mismatch"}
    set f [open batch-result.tsv w]
    puts $f "base\t$base\nblocks\t$blocks\nseed\t$seed\nrounds\t$rounds\nmin_seconds\t$seconds\nhost_run_ms\t[expr {$run_end_ms-$begin_ms}]\ncycles\t[vio_read_port $q 7 48]\nseconds\t[vio_read_port $q 20 32]\nper_channel_count\t$expected_count"
    close $f
    # 主机指定实际DDR地址发独立读请求，逐个完整512位与主机公式比较。
    set addresses [list $base [expr {$base+64*($blocks-1)}] [expr {$base+64*($blocks/2)}]]
    foreach offset {64 4032 4096 4160 65536 1048576 1073741824} {if {$offset<$blocks*64} {lappend addresses [expr {$base+$offset}]}}
    set addresses [lsort -integer -unique $addresses]
    set f [open host-peeks.tsv w];puts $f "index\taddress\tround\tseed"
    set ack [vio_read_port $q 18 1];set index 0
    foreach addr $addresses {
        set ack [expr {1-$ack}]
        vio_write_port $q 6 32 $addr
        vio_write_port $q 5 1 $ack
        set deadline [expr {[clock milliseconds]+5000}]
        while {1} {
            set status [snapshot $q [format "peek-%03d" $index]]
            if {$status&16 || !($status&1)} {error "Readback fault"}
            if {[vio_read_port $q 18 1]==$ack} {break}
            if {[clock milliseconds]>=$deadline} {error "Peek deadline"}
            after 100
        }
        set data 0;set ref 0
        for {set i 0} {$i<4} {incr i} {set data [expr {$data|([vio_read_port $q [expr {14+$i}] 128]<<(128*$i))}]}
        for {set i 0} {$i<16} {incr i} {set ref [expr {$ref|([ref_word $addr $seed [expr {$rounds-1}] $i]<<(32*$i))}]}
        save_data [format "peek-%03d.bin" $index] $data
        puts $f "$index\t$addr\t[expr {$rounds-1}]\t$seed";flush $f
        if {$data!=$ref} {error "Independent host readback mismatch addr=$addr"}
        incr index
    }
    close $f
    snapshot $q final
    if {[vio_read_port $q 6 48]!=$expected_count+$index || ([vio_read_port $q 5 192]&0xffffffffffff)!=$expected_count+$index} {error "Peek response conservation"}
    if {$release_service} {
        set board [find_magic $device 0x4d314231]
        vio_expect_ports $board {0 1 2 3 4 5 6 7 8 9} {0}
        refresh_hw_vio $board
        if {[vio_read_port $board 3 32]&24} {error "Unexpected pre-handover service/fault"}
        vio_write_port $q 7 1 1
        set deadline [expr {[clock milliseconds]+5000}]
        while {1} {
            refresh_hw_vio $board
            set misc [vio_read_port $board 3 32]
            if {$misc&16} {error "Boot ownership switch fault"}
            if {($misc&13)==13} {break}
            if {[clock milliseconds]>=$deadline} {error "Service clock/boot handover timeout"}
            after 50
        }
        set ack [expr {($misc>>1)&1}]
        set seq [vio_read_port $board 2 32]
        vio_write_port $board 0 32 [expr {1-$ack}]
        after 20
        refresh_hw_vio $board
        if {[vio_read_port $board 2 32]!=(($seq+1)&0xffffffff)} {error "First service snapshot failed"}
        set flags [expr {[vio_read_port $board 4 256]&0xffffffff}]
        # CPU held, host grants, empty fabric; no task, CQ, isolation, error, trap.
        if {($flags&0x84f0)!=0x84f0 || ($flags&0x1807)!=0} {error "Initial service state not cold idle: $flags"}
        set f [open service-handover.tsv w]
        puts $f "flags\t$flags\nmisc\t$misc\nsequence\t[vio_read_port $board 2 32]"
        close $f
    }
    puts "M1_FINAL_BIT_DDR_BATCH_PASSED_NOT_MODEL_ACCEPTANCE"
} detail]
set f [open outcome.txt w];puts $f "result=$result\n$detail";close $f
catch {report_hw_mig -file mig-final.txt $mig} report_detail
catch {capture_trace $device} trace_detail
set f [open capture-details.txt w];puts $f "$report_detail\n$trace_detail";close $f
close_hw_target
disconnect_hw_server
close_hw_manager
if {$result!=0} {error $detail}
exit
