"""Local KV management console backed exclusively by the configured hardware driver."""
import argparse,hashlib,importlib.util,json,secrets,threading,time,uuid
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit,parse_qs,quote
import host

class Console:
    def __init__(self,config,reference,output,mode):
        self.config=config;self.reference=reference;self.output=output;self.mode=mode
        output.mkdir(parents=True,exist_ok=False)
        self.cfg=json.loads(config.read_text());self.layout=json.loads((host.ROOT/'configs/m1/layout.json').read_text())
        self.lock=threading.RLock();self.driver=None;self.client=None;self.jobs={};self.busy=False
        self.token=secrets.token_hex(24)
        self.stop=threading.Event()
        self.state=dict(run_id=output.name+'-'+uuid.uuid4().hex[:12],phase='unloaded',prefix_builds=0,connected=False,mode=mode,busy=False,events=[],
                        validation='完整KV/logits读回' if mode=='acceptance' else '演示模式：token检查；本次未进行全部数值读回',
                        profile='M1-experimental-demo',board_acceptance_passed=False,last_observation_ns=None)
        host.save(output/'run-identity.json',dict(run_id=self.state['run_id'],mode=mode,started_ns=time.time_ns(),platform_sha256=host.sha(config)))
        threading.Thread(target=self.monitor,daemon=True).start()
    def monitor(self):
        while not self.stop.wait(1):
            if self.driver and not self.busy:
                try:self.observe()
                except BaseException:
                    with self.lock:self.state['connected']=False
    def event(self,message,**fields):
        with self.lock:
            item=dict(time_ns=time.time_ns(),message=message,**fields);self.state['events'].append(item)
            with (self.output/'events.jsonl').open('a') as f:f.write(json.dumps(item,ensure_ascii=False)+'\n')
    def snapshot(self):
        with self.lock:
            state=json.loads(json.dumps(self.state));state['busy']=self.busy
            state['stale']=not state['connected'] or state['last_observation_ns'] is None or time.time_ns()-state['last_observation_ns']>5_000_000_000
            state['jobs']=list(self.jobs.values());return state
    def observe(self):
        obs=self.driver.observe()
        with self.lock:self.state.update(observation=obs,connected=True,last_observation_ns=time.time_ns())
        return obs
    def connect(self):
        if self.driver:return
        if self.cfg.get('state')!='bound':raise RuntimeError('整机位流尚未绑定；当前不能启动硬件演示')
        cfg=dict(self.cfg);cfg['session_output']=str(self.output/'vivado-session')
        spec=importlib.util.spec_from_file_location('rkv_live_driver',Path(cfg['driver']).resolve())
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        self.driver=module.open(cfg);info=self.driver.describe();host.validate_platform(cfg,info,self.layout)
        self.state['device']=dict(device_id=info['device_id'],part=info['part'],bit_sha256=info['bit_sha256'],experiment_id=cfg.get('experiment_id'),core_hz=info['core_hz'],fast_hz=info['fast_hz'])
        self.observe()
    def submit(self,action,request_id):
        if action not in ('inspect','load','build','query-a','query-b','release','cancel-recover','retire'):
            raise ValueError('未知操作')
        uuid.UUID(request_id)
        with self.lock:
            if request_id in self.jobs:
                if self.jobs[request_id]['action']!=action:raise ValueError('同一请求编号不能改变操作')
                return self.jobs[request_id]
            if self.busy:raise RuntimeError('设备正在执行上一项操作')
            phase=self.state['phase']
            allowed={'inspect':True,'load':phase=='unloaded','build':phase=='empty','query-a':phase=='sealed',
                     'query-b':phase=='sealed','release':phase=='bound','cancel-recover':phase in ('sealed','bound'),
                     'retire':phase in ('sealed','bound')}
            if not allowed[action]:raise RuntimeError('当前生命周期阶段不允许此操作')
            job=dict(id=request_id,action=action,status='running',started_ns=time.time_ns());self.jobs[request_id]=job;self.busy=True
            host.save(self.output/'jobs.json',self.jobs)
            threading.Thread(target=self.run,args=(job,),daemon=True).start();return dict(job)
    def run(self,job):
        path=self.output/job['id'];path.mkdir()
        self.event('开始操作',action=job['action'],job=job['id'])
        try:
            self.connect();action=job['action'];validate=self.mode=='acceptance'
            if action=='inspect':self.observe()
            elif action=='load':
                host.load_and_verify(self.driver,self.layout,path,progress=lambda name,done,total:(self.observe(),self.event(f'镜像校验 {name}: {done}/{total} 字节')))
                self.client=host.Mailbox(self.driver,self.layout,progress=self.observe);self.client.operation('BOOT');self.state['phase']='empty'
            elif not self.client:raise RuntimeError('本连接尚未装载并校验镜像')
            elif action=='build':
                host.build_prefix(self.client,self.reference,path,validate=validate);self.state['phase']='sealed';self.state['prefix_builds']+=1
            elif action.startswith('query-'):
                import numpy as np
                ref=host.checked_reference(self.reference);group=ref['pairs'][int(action=='query-b')]
                self.client.operation('BIND');self.state['phase']='bound';tokens=group['seeds'];steps=[]
                for step,gold in enumerate(group['steps']):
                    result=self.client.command('DECODE',tokens)
                    assert result['cq']['status']==0 and result['cq']['tokens']==gold['output_tokens']
                    if validate:
                        expected=np.load(self.reference/gold['logits_file'],allow_pickle=False).tobytes()
                        host.checked_read(self.driver,self.layout['logits_address'],expected,path/f'logits-{step}.bin')
                        if step==2:
                            data=self.driver.memory_read(self.layout['kv_base'],self.layout['object_bytes']);(path/'context.bin').write_bytes(data)
                            assert hashlib.sha256(data).hexdigest()==group['context_sha256']
                    self.event('查询步完成',step=step+1,tokens=result['cq']['tokens'],full_logits_checked=validate)
                    self.observe();self.client.consume(result);tokens=result['cq']['tokens'];steps.append(result)
                host.save(path/'query.json',dict(steps=steps,full_numeric_checked=validate))
            elif action=='release':
                result=self.client.command('RELEASE');assert result['cq']['status']==0
                if validate:
                    expected=(self.reference/'reference-prefix.bin').read_bytes()+bytes(self.layout['object_bytes']-self.layout['prefix_bytes'])
                    host.checked_read(self.driver,self.layout['kv_base'],expected,path/'cleared-object.bin')
                self.client.consume(result);self.state['phase']='sealed'
            elif action=='retire':self.client.operation('RETIRE');self.state['phase']='empty'
            elif action=='cancel-recover':
                # 明确的在途取消演示：退役旧对象，取消新对象首个真实四-token任务，然后恢复重建。
                self.client.operation('RETIRE');self.client.operation('REGISTER');before=self.observe()
                result=self.client.command('BUILD',intervention='cancel');after=self.observe()
                assert result['cq']['status']==1 and after['committed_tasks']==before['committed_tasks']
                host.save(path/'cancel.json',dict(before=before,result=result,after=after))
                self.event('真实在途任务已取消，逻辑提交增量为零',generation=after['generation'])
                self.client.consume(result);self.client.operation('RECOVER');self.state['phase']='empty'
                recovered=path/'recovered';recovered.mkdir()
                host.build_prefix(self.client,self.reference,recovered,validate=validate);self.state['phase']='sealed';self.state['prefix_builds']+=1
                self.event('清理后新代际恢复服务',generation=self.client.generation)
            self.observe();job['status']='completed';self.event('操作完成',action=action,job=job['id'])
        except BaseException as e:
            job.update(status='failed',error=f'{type(e).__name__}: {e}')
            self.event('操作失败，保留现场',error=job['error'])
            with self.lock:
                self.state['connected']=False
                if self.driver and job['action']!='inspect':self.state['phase']='requires_recovery'
        finally:
            with self.lock:
                job['finished_ns']=time.time_ns();self.busy=False
                host.save(self.output/'jobs.json',self.jobs);host.save(self.output/'status.json',self.snapshot())

    def export_report(self):
        state=self.snapshot();files=[]
        # 仅列已结束job的不可变结果。运行中的事务日志稍后归档，不拼接成完整验收。
        for job in state['jobs']:
            if job['status']=='running':continue
            for file in sorted((self.output/job['id']).rglob('*')):
                if file.is_file():
                    relative=file.relative_to(self.output).as_posix()
                    files.append(dict(path=relative,bytes=file.stat().st_size,sha256=host.sha(file),download='/api/file?path='+quote(relative)))
        report=dict(scope='本次演示运行记录，不代替M1总验收',state=state,files=files,board_acceptance_passed=False)
        return report

class Handler(BaseHTTPRequestHandler):
    def send_json(self,status,data):
        raw=json.dumps(data,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(raw)
    def do_GET(self):
        if self.path=='/api/status':self.send_json(200,self.server.console.snapshot())
        elif self.path=='/api/report':
            self.send_json(200,self.server.console.export_report())
        elif urlsplit(self.path).path=='/api/file':
            try:
                relative=parse_qs(urlsplit(self.path).query,strict_parsing=True)['path'][0]
                root=self.server.console.output.resolve();file=(root/relative).resolve()
                if not file.is_relative_to(root) or not file.is_file():raise ValueError('invalid artifact')
                job_id=file.relative_to(root).parts[0]
                job=self.server.console.jobs.get(job_id)
                if not job or job['status']=='running':raise ValueError('artifact is not finalized')
                self.send_response(200);self.send_header('Content-Type','application/octet-stream');self.send_header('Content-Length',str(file.stat().st_size));self.end_headers()
                with file.open('rb') as stream:
                    while data:=stream.read(1<<20):self.wfile.write(data)
            except (KeyError,ValueError,OSError):self.send_json(404,dict(error='not a completed run artifact'))
        elif self.path=='/':
            raw=(Path(__file__).parent/'demo_ui/index.html').read_text().replace('__TOKEN__',self.server.console.token).encode()
            self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(raw)
        else:self.send_json(404,dict(error='not found'))
    def do_POST(self):
        if self.path!='/api/action':self.send_json(404,dict(error='not found'));return
        if self.headers.get('X-RKV-Token')!=self.server.console.token:self.send_json(403,dict(error='invalid request token'));return
        try:
            n=int(self.headers.get('Content-Length','0'))
            if not 0<n<=4096:raise ValueError('invalid payload length')
            body=json.loads(self.rfile.read(n));job=self.server.console.submit(body['action'],body['request_id']);self.send_json(202,job)
        except (ValueError,KeyError,RuntimeError) as e:self.send_json(409,dict(error=str(e)))
    def log_message(self,*args):pass

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--platform',type=Path,required=True);p.add_argument('--reference',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--port',type=int,default=8765);p.add_argument('--mode',choices=('acceptance','demo'),default='demo');a=p.parse_args()
    console=Console(a.platform,a.reference,a.output,a.mode)
    server=ThreadingHTTPServer(('127.0.0.1',a.port),Handler);server.console=console
    print(f'RISK-KV console: http://127.0.0.1:{server.server_port} / {a.output}',flush=True)
    try:server.serve_forever()
    finally:
        console.stop.set()
        if console.driver:console.driver.close()
        server.server_close()
if __name__=='__main__':main()
