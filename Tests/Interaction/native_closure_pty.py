"""Actual keyboard → native SIGTERM → live comparison → exported HTML.
Only a disposable child created by NativeClosurePTYHarness can be signalled.
Existing user processes are observed but never targeted. No synthetic metrics.
Compile the harness after the current debug build (see README).
"""
import os, pty, fcntl, termios, struct, subprocess, select, time, signal, json, re, tempfile
from pathlib import Path
from language_support import LANGUAGE, label
root=Path(__file__).resolve().parents[2]
fallback=os.environ.get('TAWL_TEST_KEYBOARD_FALLBACK')=='1'
base=root/('work/native-closure-fallback-pty' if fallback else 'work/native-closure-pty');base.mkdir(parents=True,exist_ok=True)
out=Path(tempfile.mkdtemp(prefix='run-',dir=base))
master,slave=pty.openpty()
fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',45,143,0,0))
before=termios.tcgetattr(slave)
proc=subprocess.Popen([str(root/'work/native-closure-pty-harness'),str(out),str(root)],cwd=out,stdin=slave,stdout=slave,stderr=slave,env=dict(os.environ,TERM='xterm-256color',NO_COLOR='1'))
data=b''
def read(seconds=.3):
    global data
    finish=time.monotonic()+seconds;chunk=b''
    while time.monotonic()<finish:
        ready,_,_=select.select([master],[],[],min(.03,max(0,finish-time.monotonic())))
        if ready:
            try:piece=os.read(master,65536)
            except OSError:break
            if not piece:break
            chunk+=piece
    data+=chunk
    return chunk

def key(value):
    os.write(master,value);return read()

def events():
    path=out/'native-events.jsonl'
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

def screen():
    frame=data.split(b'\x1b[1;1H')[-1]
    return re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]',b'',frame).decode('utf8',errors='replace')

try:
    deadline=time.monotonic()+8
    while not any(e['event']=='sample' for e in events()) and time.monotonic()<deadline:read(.2)
    fixture=next(e for e in events() if e['event']=='fixture');pid=fixture['pid']
    read(.8)
    key(b'/');key(fixture['app'].encode());key(b'\r')
    key(b'x')
    assert label('PROCESS TERMINATION') in screen() and label('MANUAL') in screen(),screen()
    assert not any(e['event'] in ('prepare','sent') for e in events())
    key(b'i' if fallback else b'\r')
    assert label('AWAITING CONFIRMATION') in screen() and label('Manual selection · no automatic termination recommendation.').split(" · ")[0] in screen(),screen()
    assert label('› Cancel') in screen() and fixture['app'] in screen()
    assert not any(e['event']=='sent' for e in events())
    key(b'\x1b[C');key(b' ' if fallback else b'\r')
    read(.8)
    assert label(' TAWL / LAST TERMINATION · SYSTEM COMPARISON') in screen(),screen()
    assert label('SELECTED PROCESS EXIT VERIFIED') in screen(),screen()
    assert f'PID {pid}' in screen()
    read(1.0)
    assert label('SYSTEM CPU') in screen() and label('MEMORY PRESSURE') in screen() and label('SWAP STOCK') in screen()
    key(b'd')
    assert label('HTML REPORT SAVED') in screen(),screen()
    files=sorted((out/'reports').glob(f'*-pid{pid}-*.html'))
    if not files:files=[p for p in (out/'reports').glob('*.html') if f'PID {pid}' in p.read_text()]
    assert len(files)==1,files
    html=files[0].read_text();assert html.count('<svg')==4 and fixture['app'] in html
    assert label('Process exit confirmed') in html,html[:1000]
    key(b'\x1b');key(b'q');proc.wait(timeout=5)
    assert proc.returncode==0
    assert termios.tcgetattr(slave)==before
    records=events();samples=[e for e in records if e['event']=='sample']
    assert samples and all(e['canReview'] and e['recommendations']==0 and e['footprint']<2_147_483_648 for e in samples)
    assert any(isinstance(e['systemCPU'],(int,float)) and e['swap'] is not None for e in samples)
    assert len([e for e in records if e['event']=='sent'])==1
    assert all(e.get('pid')==pid for e in records)
    assert any(e['event']=='childExit' and e['signal']==15 and e['uncaughtSignal'] for e in records)
    result={'passed':True,'target':'own disposable native child','pid':pid,'app':fixture['app'],
            'inputMethod':'i / Right / Space' if fallback else 'Enter / Right / Enter','manualWithoutRecommendation':True,'signal':15,'comparisonOpened':True,'htmlCharts':4,
            'systemMetrics':'real NativeCollector values, no expected improvement assumed','report':str(files[0]),'restored':True}
    (out/'result.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
    (base/'result.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps(result,ensure_ascii=False))
finally:
    (out/'terminal.ansi').write_bytes(data)
    if proc.poll() is None:
        proc.send_signal(signal.SIGTERM)
        deadline=time.monotonic()+3
        while proc.poll() is None and time.monotonic()<deadline:read(.05)
        proc.wait(timeout=2)
    os.close(master);os.close(slave)
