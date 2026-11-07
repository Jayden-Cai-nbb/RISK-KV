"""Export the existing buffered reference and MMCM lock from an isolated MIG copy."""
from pathlib import Path
import difflib,hashlib,json,sys,re

def patch(root):
    root=Path(root).resolve()
    marker=dict(x.split('\t') for x in (root/'user-management-state.tsv').read_text().splitlines())
    assert marker=={'IS_LOCKED':'1','GENERATE_SYNTH_CHECKPOINT':'0'}
    base=list((root/'project/example').glob('*.srcs/sources_1/ip/rkv_ddr_candidate/rtl/ip_top'))
    assert len(base)==1
    changes=[]
    for name in ('rkv_ddr_candidate_ddr4.sv','rkv_ddr_candidate.sv'):
        p=base[0]/name;old=p.read_text();assert 'rkv_ref_clock' not in old
        new,n=re.subn(r'(\s+input\s+c0_sys_clk_p\s*,)',r'\n   output rkv_ref_clock,\n   output rkv_mmcm_locked,\1',old,count=1);assert n==1
        if name=='rkv_ddr_candidate_ddr4.sv':
            assert re.search(r'wire\s+sys_clk_in\s*;',old) and re.search(r'wire\s+mmcm_lock\s*;',old)
            new=new.replace('endmodule','\n// Observational clock exports; existing input buffer and MMCM remain unchanged.\nassign rkv_ref_clock = sys_clk_in;\nassign rkv_mmcm_locked = mmcm_lock;\nendmodule')
        else:
            new,n=re.subn(r'(\.c0_sys_clk_p\s*\(c0_sys_clk_p\),)',r'.rkv_ref_clock(rkv_ref_clock),\n   .rkv_mmcm_locked(rkv_mmcm_locked),\n   \1',new,count=1);assert n==1
        changes.append((p,old,new))
    backup=root/'reference-export-originals';backup.mkdir(exist_ok=False)
    records=[];diff=[]
    for p,old,new in changes:
        (backup/p.name).write_text(old);p.write_text(new)
        records.append(dict(path=str(p.relative_to(root)),before_sha256=hashlib.sha256(old.encode()).hexdigest(),after_sha256=hashlib.sha256(new.encode()).hexdigest()))
        diff.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='original/'+p.name,tofile='exported/'+p.name))
    (root/'reference-export.diff').write_text(''.join(diff))
    (root/'reference-export.json').write_text(json.dumps(records,indent=2)+'\n')

if __name__=='__main__':patch(sys.argv[1])
