# Parse and elaborate frozen portable native system without board IP or constraints.
set_param general.maxThreads 2
set root [file normalize src]
set handle [open $root/rtl/m1/files.f r]
set files [split [read $handle] "\n"]
close $handle
foreach name $files {
    if {[string trim $name] ne ""} {read_verilog -sv [file join $root $name]}
}
synth_design -rtl -top rkv_m1_native_system -part xcvu440-flga2892-2-e \
    -mode out_of_context -generic FIRMWARE=firmware.hex
puts "M1_PORTABLE_ELABORATED_NOT_SYNTHESIZED_OR_BOARD_VALIDATED"
exit
