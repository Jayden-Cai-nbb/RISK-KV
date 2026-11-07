"""Record only a new, isolated display showing the real local console; no access to existing desktops."""
import argparse,ctypes,json,os,select,signal,subprocess,time,urllib.request
from pathlib import Path
import host

def resize_own_browser(display):
    # Xvfb没有窗口管理器；仅调整刚创建的专用显示中的RISK-KV窗口，不触碰其他桌面。
    x=ctypes.CDLL('libX11.so.6');ptr=ctypes.c_void_p;win=ctypes.c_ulong
    x.XOpenDisplay.argtypes=[ctypes.c_char_p];x.XOpenDisplay.restype=ptr
    x.XDefaultRootWindow.argtypes=[ptr];x.XDefaultRootWindow.restype=win
    x.XQueryTree.argtypes=[ptr,win,ctypes.POINTER(win),ctypes.POINTER(win),ctypes.POINTER(ctypes.POINTER(win)),ctypes.POINTER(ctypes.c_uint)]
    x.XFetchName.argtypes=[ptr,win,ctypes.POINTER(ctypes.c_char_p)]
    x.XMoveResizeWindow.argtypes=[ptr,win,ctypes.c_int,ctypes.c_int,ctypes.c_uint,ctypes.c_uint]
    x.XSync.argtypes=[ptr,ctypes.c_int];x.XCloseDisplay.argtypes=[ptr];x.XFree.argtypes=[ptr]
    d=x.XOpenDisplay(display.encode());assert d,'Dedicated X display unavailable'
    try:
        root=x.XDefaultRootWindow(d);r=win();parent=win();children=ctypes.POINTER(win)();count=ctypes.c_uint()
        assert x.XQueryTree(d,root,ctypes.byref(r),ctypes.byref(parent),ctypes.byref(children),ctypes.byref(count))
        found=[]
        try:
            for i in range(count.value):
                name=ctypes.c_char_p()
                if x.XFetchName(d,children[i],ctypes.byref(name)) and name.value:
                    if b'RISK-KV' in name.value:found.append(children[i])
                    x.XFree(ctypes.cast(name,ptr))
            assert len(found)==1,'Expected one own console browser window'
            x.XMoveResizeWindow(d,found[0],0,0,1440,1080);x.XSync(d,0)
        finally:
            if children:x.XFree(ctypes.cast(children,ptr))
    finally:x.XCloseDisplay(d)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tools',type=Path,required=True,help='Verified isolated media-tool summary.json')
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--port',type=int,default=8765);p.add_argument('--seconds',type=int,default=600)
    p.add_argument('--preview',action='store_true',help='Explicit unbound UI/tool check; cannot become a hardware video')
    a=p.parse_args();assert 1<=a.seconds<=14400 and 1024<=a.port<=65535
    tools=json.loads(a.tools.read_text());assert tools['status']=='isolated_tools_verified' and tools['system_install'] is False
    url=f'http://127.0.0.1:{a.port}'
    def status():
        with urllib.request.urlopen(url+'/api/status',timeout=5) as r:return json.load(r)
    initial=status()
    if not a.preview:assert initial.get('device') and not initial['stale'],'No live hardware session to record'
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    report=dict(status='recording',run_id=initial['run_id'],scope='unbound UI preview, no hardware acceptance' if a.preview else 'unedited screen recording of dedicated console display; acceptance checked separately',preview=a.preview,started_ns=time.time_ns(),board_acceptance_passed=False,tools_summary_sha256=host.sha(a.tools),initial_status=initial)
    host.save(out/'recording.json',report)
    env=dict(os.environ);env['LD_LIBRARY_PATH']=tools['library_path']
    processes=[];logs=[]
    try:
        xvlog=(out/'xvfb.log').open('wb');logs.append(xvlog)
        cmd=[tools['xvfb'],'-displayfd','1','-screen','0','1440x1080x24','-nolisten','tcp','-noreset']
        xv=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=xvlog,env=env,start_new_session=True);processes.append(xv)
        assert select.select([xv.stdout],[],[],15)[0],'Dedicated display failed to start'
        number=xv.stdout.readline().decode().strip();assert number.isdigit() and xv.poll() is None
        display=':'+number;report['dedicated_display']=display
        browser_env=dict(os.environ);browser_env['DISPLAY']=display
        profile=out/'firefox-profile';profile.mkdir()
        log=(out/'firefox.log').open('wb');logs.append(log)
        firefox=subprocess.Popen(['/usr/bin/firefox','--no-remote','--new-instance','--profile',str(profile),'--kiosk',url],stdout=log,stderr=subprocess.STDOUT,env=browser_env,start_new_session=True);processes.append(firefox)
        time.sleep(5);assert firefox.poll() is None,'Dedicated Firefox exited'
        resize_own_browser(display);time.sleep(.5)
        video=out/('preview-not-hardware.mp4' if a.preview else 'unedited-console.mp4')
        cmd=[tools['ffmpeg'],'-nostdin','-n','-f','x11grab','-framerate','15','-video_size','1440x1080','-i',display+'.0','-t',str(a.seconds),'-c:v','libx264','-preset','ultrafast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
        log=(out/'ffmpeg.log').open('wb');logs.append(log)
        encoder=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True);processes.append(encoder)
        host.save(out/'capture-command.json',dict(command=cmd,display_created_by_this_process=True,existing_displays_accessed=False))
        deadline=time.monotonic()+a.seconds+30
        with (out/'observations.jsonl').open('w') as stream:
            while encoder.poll() is None:
                row=dict(time_ns=time.time_ns())
                try:
                    row['state']=status();assert row['state']['run_id']==initial['run_id'],'Console identity changed during recording'
                except AssertionError:raise
                except Exception as e:row['read_error']=repr(e)
                stream.write(json.dumps(row,ensure_ascii=False)+'\n');stream.flush()
                if time.monotonic()>deadline:raise TimeoutError('Recorder did not finish')
                time.sleep(1)
        assert encoder.returncode==0 and video.stat().st_size>0,'Screen encoding failed'
        probe=Path(tools['ffmpeg']).with_name('ffprobe')
        r=subprocess.run([str(probe),'-v','error','-show_format','-show_streams','-of','json',str(video)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=20)
        assert r.returncode==0;metadata=json.loads(r.stdout);host.save(out/'media.json',metadata)
        stream=next(x for x in metadata['streams'] if x['codec_type']=='video')
        assert (stream['width'],stream['height'])==(1440,1080) and abs(float(metadata['format']['duration'])-a.seconds)<2
        report.update(status='recorded_preview_not_acceptance' if a.preview else 'recorded_real_console_not_acceptance',video=video.name,video_sha256=host.sha(video),duration_seconds=float(metadata['format']['duration']))
    except BaseException as e:report.update(status='failed',error=repr(e));raise
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid,signal.SIGTERM)
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
        for log in logs:log.close()
        report['finished_ns']=time.time_ns();host.save(out/'recording.json',report)
if __name__=='__main__':main()
