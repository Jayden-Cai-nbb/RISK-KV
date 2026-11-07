# 三条单调复位握手只跨到第一级ASYNC_REG；跨域延迟限制为较快域的一拍。
# 本文件含校验循环，须对已打开网表使用source，不能作为read_xdc输入。
# 下游二、三级仍按所属时钟正常STA；不设置整域false_path或clock_groups。
# 最终集成层级改变时需显式调整匹配并重核，匹配为空/多项必须失败。
foreach {src dst} {
    {reset_coord/core_hold_reg[15]/C} {reset_coord/core_done_in_ddr_reg[0]/D}
    {reset_coord/ddr_hold_reg[15]/C} {reset_coord/ddr_done_in_core_reg[0]/D}
    {reset_coord/ddr_aresetn_reg/C} {reset_coord/ddr_release_in_core_reg[0]/D}
} {
    set from_pin [get_pins -quiet $src]
    set to_pin [get_pins -quiet $dst]
    if {[llength $from_pin] != 1 || [llength $to_pin] != 1} {error "Reset CDC pin mismatch: $src -> $dst"}
    set_max_delay -datapath_only 5.208 -from $from_pin -to $to_pin
}
