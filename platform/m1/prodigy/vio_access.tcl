# VIO helpers: reconstruct split probes by physical port bits, never by display order.
proc vio_expect_ports {vio input_ports output_ports} {
    set observed_in {}
    set observed_out {}
    foreach probe [get_hw_probes -of_objects $vio] {
        set kind [get_property TYPE $probe]
        if {$kind eq "vio_input"} {lappend observed_in [get_property PROBE_PORT $probe]
        } elseif {$kind eq "vio_output"} {lappend observed_out [get_property PROBE_PORT $probe]
        } else {error "Unexpected VIO probe type"}
    }
    if {[lsort -integer -unique $observed_in] ne $input_ports || [lsort -integer -unique $observed_out] ne $output_ports} {
        error "Unexpected diagnostic port geometry; UUID alone is not a bitstream identity"
    }
}

proc vio_read_port {vio port width} {
    set value 0
    set mask 0
    foreach probe [get_hw_probes -of_objects $vio] {
        if {[get_property TYPE $probe] ne "vio_input" || [get_property PROBE_PORT $probe] != $port} {continue}
        set bits [string trim [get_property PROBE_PORT_BITS $probe] {[]}]
        if {[regexp {^([0-9]+):([0-9]+)$} $bits -> high low]} {
        } elseif {[regexp {^[0-9]+$} $bits]} {
            # Vivado2022.2 exposes the starting port bit, even for a multi-bit probe.
            set low $bits
            set high [expr {$low + [get_property WIDTH $probe] - 1}]
        } else {error "Unexpected VIO bit range $bits"}
        set n [expr {$high - $low + 1}]
        if {$n < 1 || $high >= $width || $n != [get_property WIDTH $probe]} {error "Invalid VIO width"}
        set_property INPUT_VALUE_RADIX BINARY $probe
        set raw [get_property INPUT_VALUE $probe]
        if {![regexp {^[01]+$} $raw] || [string length $raw] != $n} {error "Invalid VIO value $raw"}
        set slice [expr {((1 << $n) - 1) << $low}]
        if {$mask & $slice} {error "Overlapping VIO probes"}
        set mask [expr {$mask | $slice}]
        set parsed [expr "0b$raw"]
        set value [expr {$value | ($parsed << $low)}]
    }
    if {$mask != (1 << $width) - 1} {error "Incomplete VIO port $port"}
    return $value
}

proc vio_output_probe {vio port width} {
    set found {}
    foreach probe [get_hw_probes -of_objects $vio] {
        if {[get_property TYPE $probe] eq "vio_output" && [get_property PROBE_PORT $probe] == $port} {
            lappend found $probe
        }
    }
    if {[llength $found] != 1 || [get_property WIDTH $found] != $width} {error "Unexpected VIO output geometry"}
    return [lindex $found 0]
}

proc vio_write_port {vio port width value} {
    if {$value < 0 || $value >= (1 << $width)} {error "VIO output value out of range"}
    set probe [vio_output_probe $vio $port $width]
    set raw ""
    for {set bit [expr {$width - 1}]} {$bit >= 0} {incr bit -1} {append raw [expr {($value >> $bit) & 1}]}
    set_property OUTPUT_VALUE_RADIX BINARY $probe
    set_property OUTPUT_VALUE $raw $probe
    commit_hw_vio $probe
}

proc spd_refresh {vio} {
    refresh_hw_vio $vio
    if {[vio_read_port $vio 1 32] != 0x53504431} {error "Not the SPD1 diagnostic"}
    return [vio_read_port $vio 0 32]
}
