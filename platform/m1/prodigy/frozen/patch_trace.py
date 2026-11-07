from pathlib import Path
import difflib,hashlib,json,sys
root=Path(sys.argv[1]).resolve()
files=list((root/'project/example').glob('*.srcs/sources_1/ip/rkv_ddr_candidate/rtl/ip_top/rkv_ddr_candidate_ddr4_mem_intfc.sv'))
assert len(files)==1
p=files[0];old=p.read_text();assert old.count('endmodule')==1
instance="""
// RISK-KV observational-only boot recorder; fixed 17/2/2/1 geometry.
rkv_ddr_init_trace rkv_initialization_history (
    .clk(div_clk),
    .command_address(mcal_ADR),
    .command_bank(mcal_BA),
    .command_group(mcal_BG),
    .command_act_n(mcal_ACT_n),
    .command_cs_n(mcal_CS_n),
    .command_cke(mcal_CKE),
    .command_reset_n(cal_RESET_n),
    .command_odt(mcal_ODT),
    .status({6'd0, div_clk_rst, 1'b0})
);
"""
new=old.replace('endmodule',instance+'\nendmodule')
(root/'trace-original.sv').write_text(old)
p.write_text(new)
(root/'trace-patch.diff').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='original',tofile='observed')))
report=dict(path=str(p.relative_to(root)),before_sha256=hashlib.sha256(old.encode()).hexdigest(),after_sha256=hashlib.sha256(new.encode()).hexdigest(),scope='added passive instance only; no functional parameter change')
(root/'trace-patch.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
