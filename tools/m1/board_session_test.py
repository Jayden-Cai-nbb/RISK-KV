"""Execute the actual board RPC Tcl against a memory/clock-free tool mock; no hardware."""
import argparse,hashlib,json,subprocess
from pathlib import Path
MOCK=r'''
set argc 4
set argv {unused.ltx 15000000 210251130202 0123456789abcdef0123456789abcdef}
set seq 0;set ack 0
array set memory {}
array set transactions {}
foreach name {open_hw_manager connect_hw_server current_hw_target open_hw_target set_property refresh_hw_device report_property refresh_hw_vio close_hw_target disconnect_hw_server close_hw_manager refresh_hw_axi} {proc $name {args} {return {}}}
proc get_hw_targets {args} {return target}
proc get_hw_devices {args} {return xcvu440_0}
proc get_hw_vios {args} {return {board qualifier}}
proc get_hw_axis {args} {return axi}
proc vio_expect_ports {v ins outs} {
    if {$v eq "board" && ($ins ne {0 1 2 3 4 5 6 7 8 9} || $outs ne {0})} {error "wrong board geometry"}
    if {$v eq "qualifier" && $outs ne {0 1 2 3 4 5 6 7 8}} {error "wrong qualifier geometry"}
}
proc vio_read_port {v port width} {
    global seq ack
    if {$v eq "qualifier"} {if {$port==2} {return 9};return 0x44445251}
    switch $port {
        0 {return 0x4d314231}
        1 {return 12345}
        2 {return $seq}
        3 {return [expr {12 | ($ack<<1)}]}
        default {return [expr {(1<<255) | (1<<128) | ($port<<64) | 0x123456789abcdef}]}
    }
}
proc vio_write_port {v port width value} {
    global seq ack
    if {$v eq "board"} {
        if {$port!=0 || $width!=32} {error "wrong output width"}
        if {($value&1)!=$ack} {set ack [expr {$value&1}];incr seq}
    } elseif {$port!=8 || $width!=2} {error "wrong loss output width"}
}
proc get_property {key object} {
    global transactions
    switch $key {
        AXI_ADDR_WIDTH {return 32}
        AXI_DATA_WIDTH {return 64}
        AXI_ID_WIDTH {return 4}
        READ_QUEUE_LENGTH - WRITE_QUEUE_LENGTH {return 1}
        STATUS.BRESP - STATUS.RRESP {return 0}
        DATA {return [dict get $transactions($object) result]}
        default {error "unmocked property $key"}
    }
}
proc create_hw_axi_txn {name axi args} {
    global transactions
    set transactions($name) [dict create {*}$args]
    return $name
}
proc run_hw_axi {name} {
    global transactions memory
    set t $transactions($name)
    scan [dict get $t -address] %x address
    set count [dict get $t -len]
    if {$count>256 || ($address&4095)+8*$count>4096} {error "burst crossed real AXI boundary"}
    set result ""
    for {set i 0} {$i<$count} {incr i} {
        set at [expr {$address+8*$i}]
        if {[dict get $t -type] eq "WRITE"} {
            set first [expr {16*($count-1-$i)}]
            set memory($at) [string range [dict get $t -data] $first [expr {$first+15}]]
        }
        if {![info exists memory($at)]} {set memory($at) 0000000000000000}
        set result "$memory($at)$result"
    }
    dict set transactions($name) result $result
}
proc delete_hw_axi_txn {name} {global transactions;unset transactions($name)}
'''
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--script',type=Path,required=True);p.add_argument('--tclsh',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    source=a.script.read_text();line='source [file join [file dirname [info script]] vio_access.tcl]';assert source.count(line)==1
    harness=a.output/'mock.tcl';harness.write_text(MOCK+'\n'+source.replace(line,''));(a.output/'source.tcl').write_text(source)
    data=hashlib.shake_256(b"RKV variable-burst regression v1").digest(16384)
    payload=''.join(f'{int.from_bytes(data[i:i+8],"little"):016x}' for i in reversed(range(0,len(data),8)))
    large=hashlib.shake_256(b'RKV 1MiB framing regression v1').digest(1<<20)
    large_payload=''.join(f'{int.from_bytes(large[i:i+8],"little"):016x}' for i in reversed(range(0,len(large),8)))
    commands=f'1 BWRITE 00000ff8 {len(data)} {payload}\n2 BREAD 00000ff8 {len(data)} -\n3 VIO\n4 VCTL aa04\n5 LOSS 3\n6 BREAD 7ffffff8 16 -\n7 VIO\n8 QSTATUS\n9 BWRITE 00100ff8 {len(large)} {large_payload}\n10 BREAD 00100ff8 {len(large)} -\n11 BWRITE 00100ff8 {len(large)} {large_payload[:-1]}z\n12 BREAD 00100ff8 {len(large)} -\n13 CLOSE\n'
    (a.output/'stdin.txt').write_text(commands)
    result=subprocess.run([str(a.tclsh),str(harness.resolve())],input=commands,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,cwd=a.output,timeout=30)
    (a.output/'stdout.log').write_text(result.stdout)
    report=dict(status='failed',returncode=result.returncode,scope=__doc__,source_sha256=hashlib.sha256(source.encode()).hexdigest())
    try:
        rows={}
        for line in result.stdout.splitlines():
            if line.startswith('RKVJTAG '):
                _,nonce,number,status,raw=line.split(' ',4);rows[int(number)]=(status,bytes.fromhex(raw).decode())
        assert rows[8]==('OK','00000009')
        assert result.returncode==0 and set(rows)==set(range(14)),result.stdout[-2000:]
        for number in (1,2):assert rows[number]==('OK',payload)
        for number in (0,3,4,7):
            values=rows[number][1].split();assert len(values)==10
            for port,raw in enumerate(values[4:],4):assert int(raw,16)==(1<<255)|(1<<128)|(port<<64)|0x123456789abcdef
        assert rows[6][0]=='ERROR' and rows[7][0]=='OK' and rows[13]==('OK','closed')
        for number in (9,10,12):assert rows[number]==('OK',large_payload)
        assert rows[11]==('ERROR','Invalid bulk payload')
        report.update(status='passed',scenarios=['cross-4KiB batch write/read and word order','256-bit snapshot high bits','control/snapshot handshake','loss control width','range error followed by valid RPC','independent DDR status sample','1MiB variable-data cross-boundary write/read','invalid final hex character rejected before any write'])
    finally:(a.output/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
if __name__=='__main__':main()
