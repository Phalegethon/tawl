"""End-to-end terminal confirmation tests. All closure calls use ClosureSpy.
The only OS signal below is cleanup of this script's own UI subprocess.
"""
import os, pty, fcntl, termios, struct, subprocess, select, time, signal, json, re, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[2]
outdir=root/os.environ.get('CLOSURE_OUTPUT','work/control-pty');outdir.mkdir(parents=True,exist_ok=True)
binary=root/'work/closure-pty-harness'
effects=os.environ.get('CLOSURE_EFFECTS')=='1'

def screen(data):
    """Return the last full frame, preserving rows instead of ANSI cursor codes."""
    frame=data.split(b'\x1b[1;1H')[-1]
    rows=re.split(rb'\x1b\[\d+;1H',frame)
    return '\n'.join(re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]',b'',row).decode('utf8',errors='replace') for row in rows)

def assert_effect(data,pid=42):
    visible=screen(data)
    assert 'SON KAPATMA' in visible,visible
    assert f'PID {pid}' in visible,visible
    assert 'CPU' in visible and 'SWAP' in visible,visible
    assert request_stamp(visible),visible
    return visible

def request_stamp(visible):
    match=re.search(r'İstek (\d{2}:\d{2}:\d{2})',visible)
    return match.group(1) if match else None

def drain(fd, seconds=.22):
    end=time.monotonic()+seconds; data=b''
    while time.monotonic()<end:
        ready,_,_=select.select([fd],[],[],min(.03,max(0,end-time.monotonic())))
        if ready:
            try: chunk=os.read(fd,65536)
            except OSError: break
            if not chunk: break
            data+=chunk
    return data

class UI:
    def __init__(self,name,width=100,height=30,mode='normal',start_detail=True,input_flags=0):
        self.name=name;self.width=width;self.height=height;self.data=b''
        self.log=outdir/(name+'.jsonl');self.control=outdir/(name+'.mode')
        self.cwd=Path(tempfile.mkdtemp(prefix=name+'-',dir=outdir))
        self.mode(mode)
        self.master,self.slave=pty.openpty();self.resize(width,height)
        configured=termios.tcgetattr(self.slave)
        configured[0] |= input_flags
        termios.tcsetattr(self.slave,termios.TCSANOW,configured)
        self.before=termios.tcgetattr(self.slave)
        self.proc=subprocess.Popen([str(binary),str(self.log),str(self.control)],stdin=self.slave,stdout=self.slave,stderr=self.slave,cwd=self.cwd,env=dict(os.environ,TERM='xterm-256color',NO_COLOR='1'))
        try:
            self.read(.6)
            assert b'TAWL' in self.data,(name,self.data[-500:])
            if start_detail: self.key(b'\r','AYRINTI')
        except BaseException:
            self.cleanup();raise
    def mode(self,value):
        temp=self.control.with_suffix('.new');temp.write_text(value);temp.replace(self.control)
    def read(self,seconds=.22):
        data=drain(self.master,seconds);self.data+=data
        # A timed PTY read may end part-way through a frame. Finish that frame
        # before asserting against its contents; do not confuse truncation with UI loss.
        deadline=time.monotonic()+.5
        while data and self.proc.poll() is None and time.monotonic()<deadline:
            frame=self.data.split(b'\x1b[1;1H')[-1]
            end_marker=f'\x1b[{self.height};1H'.encode()
            last_row=re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]',b'',frame.split(end_marker)[-1])
            if end_marker in frame and len(last_row.decode('utf8',errors='replace'))>=self.width: break
            more=drain(self.master,.01);data+=more;self.data+=more
        return data
    def key(self,key,expected=None):
        os.write(self.master,key);data=self.read()
        if expected: assert expected.encode() in data,(self.name,expected,data[-800:])
        return data
    def resize(self,width,height):
        self.width=width;self.height=height
        fcntl.ioctl(self.slave,termios.TIOCSWINSZ,struct.pack('HHHH',height,width,0,0))
    def events(self,kind):
        return [json.loads(line) for line in self.log.read_text().splitlines() if json.loads(line)['event']==kind]
    def manager(self):
        previous=len(self.events('prepare'))
        self.key(b'x','SÜREÇ KAPATMA')
        assert len(self.events('prepare'))==previous,'opening the manager must not prepare a native action'
    def preview(self):
        previous=len(self.events('prepare'))
        self.manager();self.key(b'\r','ONAY BEKLİYOR')
        assert len(self.events('prepare'))==previous+1
    def leave_manager(self):
        self.key(b'\x1b','AYRINTI')
    def confirm(self):
        self.key(b'\x1b[C');return self.key(b'\r')
    def finish(self):
        self.key(b'q');code=self.proc.wait(timeout=3)
        assert code==0,(self.name,code)
        assert termios.tcgetattr(self.slave)==self.before
        for mode in (b'\x1b[?1006l',b'\x1b[?1000l',b'\x1b[?7h',b'\x1b[?1049l'):
            assert mode in self.data,(self.name,mode)
        if os.environ.get('CLOSURE_FINAL_FEATURES')=='1':
            assert b'\x1b[?2004h' in self.data and b'\x1b[?2004l' in self.data
            assert b'1006;2004s' in self.data and b'1006;2004r' in self.data
        assert self.events('clear')
        (outdir/(self.name+'.ansi')).write_bytes(self.data)
    def cleanup(self):
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            deadline=time.monotonic()+3
            # The child may be waiting to flush its last screen; keep draining.
            while self.proc.poll() is None and time.monotonic()<deadline:
                self.data+=drain(self.master,.03)
            self.proc.wait(timeout=1)
        os.close(self.master);os.close(self.slave)

results=[]
def trial(name,body,**kwargs):
    requested=os.environ.get('CLOSURE_CASES','')
    if requested and name not in requested.split(','): return
    ui=UI(name,**kwargs)
    try:
        body(ui);ui.finish()
        results.append(dict(scenario=name,passed=True,prepares=len(ui.events('prepare')),submits=len(ui.events('submit')),restored=True))
    finally:
        (outdir/(name+'.ansi')).write_bytes(ui.data)
        ui.cleanup()

def default_cancel(ui):
    ui.preview();ui.key(b'\r','SÜREÇ KAPATMA');assert not ui.events('submit');ui.leave_manager()
def escape(ui):
    ui.preview();ui.key(b'\x1b','SÜREÇ KAPATMA');assert not ui.events('submit');ui.leave_manager()
def confirm_once(ui):
    ui.preview();data=ui.confirm()
    if effects: assert_effect(data)
    else: assert b'BEKLEN' in data
    assert [x['processID'] for x in ui.events('submit')]==['42:100']
    ui.key(b'\r');ui.key(b'\r\r\r');assert len(ui.events('submit'))==1

def queued_preview(ui):
    ui.key(b'x\t\r','SÜREÇ KAPATMA')
    assert not ui.events('prepare') and not ui.events('submit')
    data=ui.key(b'\r\t\r','ONAY BEKLİYOR')
    assert '› Vazgeç'.encode() in data
    assert len(ui.events('prepare'))==1 and not ui.events('submit')
    ui.key(b'\r','SÜREÇ KAPATMA');assert not ui.events('submit')
def small_view(ui):
    ui.preview();ui.resize(79,23);ui.read();ui.key(b'\x1b[C');ui.key(b'\r')
    assert not ui.events('submit')
    ui.resize(100,30);data=ui.read();assert '› Vazgeç'.encode() in data
    ui.key(b'\x1b','SÜREÇ KAPATMA');ui.leave_manager()
    ui.resize(79,23);ui.read();ui.key(b'x');assert len(ui.events('prepare'))==1
    ui.resize(100,30);ui.read()
def selection_update(ui):
    ui.preview();ui.mode('resort');ui.read(.45);ui.key(b'2\x1b[B\t')
    ui.confirm();assert [x['processID'] for x in ui.events('submit')]==['42:100']
def stale_prepare(ui):
    ui.manager();ui.key(b'\r','Ölçüm güncel değil');assert not ui.events('prepare') and not ui.events('submit')
def rejected_confirmation(ui,mode,text):
    ui.preview();ui.mode(mode);ui.read(.35);data=ui.confirm()
    assert text.encode() in data,(mode,data[-1200:])
    assert not ui.events('submit')
def split_paste(ui):
    # Deliberately deliver a paste across separate reads, including candidate x.
    ui.key(b'\x1b[200~x');ui.key(b'\t');ui.key(b'\r');ui.key(b'\x1b[201~')
    assert not ui.events('prepare') and not ui.events('submit')
    ui.preview()
    ui.key(b'\x1b[200~\x1b[C');ui.key(b'\r');ui.key(b'\x1b[201~')
    assert not ui.events('submit')
    data=ui.key(b'\r','SÜREÇ KAPATMA');assert not ui.events('submit')
def long_notice(ui):
    ui.preview();ui.key(b'\x1b[C');data=ui.key(b'\r')
    assert not ui.events('submit'), 'unread mandatory impact must block confirmation'
    # Reveal all mandatory impact text; this still invokes only the fake.
    for _ in range(8): ui.key(b'\x1b[6~')
    ui.key(b'\r')
    assert [x['processID'] for x in ui.events('submit')]==['42:100']

def effect_reopen(ui):
    ui.preview();request=request_stamp(assert_effect(ui.confirm()))
    first=ui.events('sent')[0]
    ui.key(b'\x1b','SÜREÇ KAPATMA')
    count=len(ui.events('sample'));ui.mode('improved');ui.read(.65)
    assert len(ui.events('sample'))>count,'collection stopped when comparison was hidden'
    visible=assert_effect(ui.key(b'e'))
    assert request_stamp(visible)==request,'reopening changed the request boundary'
    assert 'ÇIKIŞI DOĞRULANDI' not in visible,'metric improvement cannot prove native exit'
    assert ui.events('sent')==[first],'reopening comparison must not submit again'
    ui.key(b'\x1b','SÜREÇ KAPATMA');ui.leave_manager()
    ui.key(b'h','GEÇMİŞ');ui.read(.35)
    assert_effect(ui.key(b'e'))
    assert ui.events('sent')==[first],'history navigation cannot create a new comparison request'

def effect_cancel_without_previous(ui):
    ui.preview();ui.key(b'\r','SÜREÇ KAPATMA');ui.leave_manager()
    assert 'SON KAPATMA' not in screen(ui.key(b'e'))
    assert not ui.events('sent')

def effect_rejected_without_previous(ui):
    ui.mode('reject');ui.preview();ui.confirm()
    assert len(ui.events('rejected'))==1 and not ui.events('sent')
    ui.key(b'\x1b','SÜREÇ KAPATMA');ui.leave_manager()
    assert 'SON KAPATMA' not in screen(ui.key(b'e'))

def effect_preserved_after_other_preview(ui,reject=False):
    ui.preview();request=request_stamp(assert_effect(ui.confirm()))
    original=ui.events('sent')[0]
    ui.key(b'\x1b','SÜREÇ KAPATMA');ui.leave_manager();ui.key(b'j')
    ui.mode('reject' if reject else 'normal')
    ui.preview()
    assert ui.events('prepare')[-1]['processID']=='43:100'
    # While a confirmation is pending, e must not hide it or reopen old report.
    pending=screen(ui.key(b'e'));assert 'ONAY BEKLİYOR' in pending
    if reject:
        ui.confirm();assert len(ui.events('rejected'))==1
        ui.key(b'\x1b','SÜREÇ KAPATMA')
    else: ui.key(b'\r','SÜREÇ KAPATMA')
    ui.leave_manager()
    assert request_stamp(assert_effect(ui.key(b'e'),pid=42))==request
    assert ui.events('sent')==[original]

def effect_missing_then_resume(ui):
    ui.preview();assert_effect(ui.confirm())
    ui.mode('missing');data=ui.read(.65)
    missing=assert_effect(data)
    assert any(word in missing.lower() for word in ('eksik','bilinmiyor','ölçüm yok','—')),missing
    ui.mode('worse');assert_effect(ui.read(.65))
    assert len(ui.events('sent'))==1

def effect_native_observation_is_independent(ui):
    ui.preview();assert_effect(ui.confirm())
    ui.key(b'\x1b','SÜREÇ KAPATMA');observed=len(ui.events('observe'))
    ui.mode('exited');ui.read(.65)
    assert len(ui.events('observe'))>observed,'native observation stopped while comparison hidden'
    assert 'ÇIKIŞI DOĞRULANDI' in assert_effect(ui.key(b'e'))

def effect_next_accepted_replaces_previous(ui):
    ui.preview();assert_effect(ui.confirm())
    ui.key(b'\x1b','SÜREÇ KAPATMA');ui.leave_manager();ui.key(b'j')
    ui.preview();assert_effect(ui.confirm(),pid=43)
    assert [x['processID'] for x in ui.events('sent')]==['42:100','43:100']
    ui.key(b'\x1b','SÜREÇ KAPATMA');assert_effect(ui.key(b'e'),pid=43)

def effect_real_window(ui):
    ui.preview();assert_effect(ui.confirm());ui.mode('improved')
    deadline=time.monotonic()+61.5
    print('Checking the unchanged production 60-second window with the fake controller...',flush=True)
    while time.monotonic()<deadline: ui.read(.5)
    before=assert_effect(ui.read(.3))
    assert 'Ölçüm tamamlandı' in before,'the production window did not complete'
    count=len(ui.events('sample'));ui.mode('worse');after=assert_effect(ui.read(.65))
    assert len(ui.events('sample'))>count,'normal measurement must continue after comparison completes'
    assert '92.0%' not in after and '92%' not in after,'completed comparison incorporated a later metric'
    ui.key(b'\x1b','SÜREÇ KAPATMA');reopened=assert_effect(ui.key(b'e'))
    assert '92.0%' not in reopened and '92%' not in reopened,'reopening reset the completed comparison window'
    assert len(ui.events('sent'))==1


def manager_from_root(ui):
    ui.manager()
    visible=screen(ui.data)
    assert 'Fixture Editor' in visible and 'Fixture Worker A' in visible,visible
    assert not ui.events('prepare') and not ui.events('submit')
    ui.key(b'\r','ONAY BEKLİYOR')
    assert ui.events('prepare')[-1]['pid']==42
    ui.key(b'\x1b','SÜREÇ KAPATMA');ui.key(b'\x1b','UYGULAMALAR')

def manager_no_recommendation(ui):
    ui.manager();visible=screen(ui.data)
    assert 'MANUEL' in visible and 'otomatik öneri yok' in visible,visible
    assert not ui.events('prepare') and not ui.events('submit')
    visible=screen(ui.key(b'\r'))
    assert 'ONAY BEKLİYOR' in visible and 'Manuel seçim' in visible,visible
    assert len(ui.events('prepare'))==1 and not ui.events('submit')
    assert_effect(ui.confirm())
    assert [e['pid'] for e in ui.events('submit')]==[42]

def changed_advice_does_not_revoke_choice(ui):
    ui.preview();ui.mode('withdrawn');ui.read(.4)
    assert_effect(ui.confirm())
    assert [e['pid'] for e in ui.events('submit')]==[42]

def manager_frozen(ui):
    ui.key(b' ');ui.manager();visible=screen(ui.key(b'\r'))
    assert 'yalnız canlı ölçümde' in visible,visible
    assert not ui.events('prepare') and not ui.events('submit')
    # Follow the displayed recovery route: leave the modal, then resume live data.
    ui.leave_manager();ui.key(b' ');ui.preview()
    assert len(ui.events('prepare'))==1 and not ui.events('submit')

def manager_other_workload(ui):
    # Name sort selects Fixture Editor, whose workers have no recommendation.
    ui.key(b'1');ui.key(b'\x1b[H');ui.key(b'\r','AYRINTI');ui.manager()
    visible=screen(ui.data)
    assert 'Fixture Worker A' in visible and 'Outside Worker' not in visible,visible
    ui.key(b'\t');visible=screen(ui.data)
    assert 'Outside Worker' in visible and 'Zulu Editor' in visible,visible
    ui.key(b'\r','ONAY BEKLİYOR')
    assert ui.events('prepare')[-1]['pid']==44
    ui.confirm();assert_effect(ui.data,pid=44)
    assert [entry['pid'] for entry in ui.events('submit')]==[44]

def manager_prepare_failure(ui):
    ui.manager();visible=screen(ui.key(b'\r'))
    assert 'Sentetik yerel hazırlık başarısız.' in visible,visible
    assert 'SÜREÇ KAPATMA' in visible and 'ONAY BEKLİYOR' not in visible
    assert len(ui.events('prepare'))==1 and not ui.events('submit')

def manager_enter_encoding(ui, parts):
    # Different terminals/keyboards encode Return or keypad Enter differently.
    # Exercise the real decoder at the user's 118x46 viewport with a log-only
    # controller: opening this preview must never submit a termination request.
    ui.manager()
    assert 'MANUEL' in screen(ui.data),screen(ui.data)
    for part in parts: ui.key(part)
    visible=screen(ui.data)
    assert 'ONAY BEKLİYOR' in visible,visible
    assert '› Vazgeç' in visible,visible
    assert len(ui.events('prepare'))==1 and not ui.events('submit')
    ui.key(b'\x1b','SÜREÇ KAPATMA')

def effect_export(ui):
    ui.preview();request=request_stamp(assert_effect(ui.confirm()))
    ui.mode('improved');ui.read(.65)
    ui.key(b'd')
    exported=list((ui.cwd/'raporlar').glob('*.html'))
    assert len(exported)==1,(exported,screen(ui.data))
    report=exported[0].read_text()
    for text in ('Fixture Worker A','Fixture Editor','42','CPU','SWAP'):
        assert text.lower() in report.lower(),text
    assert report.count('<svg')>=4,'all four system metrics need standalone charts'
    visible=screen(ui.data)
    assert 'HTML RAPOR KAYDEDİLDİ' in visible,visible
    assert exported[0].name in ''.join(visible.replace('│','').split()),visible
    assert request_stamp(assert_effect(ui.key(b'\x1b')))==request
    assert len(ui.events('sent'))==1,'export must not repeat the closure action'
    assert exported[0].read_text()==report,'an exported report is a stable snapshot'
    # A second export is a distinct snapshot, leaving the previous file unchanged.
    ui.key(b'd');assert len(list((ui.cwd/'raporlar').glob('*.html')))==2
    assert exported[0].read_text()==report
    assert request_stamp(assert_effect(ui.key(b'\r')))==request


def effect_export_error_retry(ui):
    ui.preview();request=request_stamp(assert_effect(ui.confirm()))
    blocker=ui.cwd/'raporlar'
    blocker.write_text('This case owns this regular-file export-directory blocker.')
    visible=screen(ui.key(b'd'))
    assert blocker.is_file(),'the failed export must preserve the existing file'
    assert 'kaydedilemedi' in visible.lower(),visible
    assert len(ui.events('sent'))==1
    blocker.unlink()  # Only this case's synthetic blocker; no user files are touched.
    ui.key(b'd')  # Retry directly from the error overlay, without Escape first.
    exported=list((ui.cwd/'raporlar').glob('*.html'))
    assert len(exported)==1,(exported,screen(ui.data))
    assert exported[0].read_text().count('<svg')>=4
    visible=screen(ui.data)
    assert 'HTML RAPOR KAYDEDİLDİ' in visible,visible
    assert request_stamp(assert_effect(ui.key(b'\x1b')))==request
    assert len(ui.events('sent'))==1,'export retries must not repeat the closure action'

def manager_keyboard_fallback(ui):
    ui.manager();ui.key(b'i','ONAY BEKLİYOR')
    assert len(ui.events('prepare'))==1 and not ui.events('submit')
    # Space on the default cancel is harmless.
    ui.key(b' ','SÜREÇ KAPATMA');assert not ui.events('submit')
    ui.key(b'i','ONAY BEKLİYOR');ui.key(b'\x1b[C')
    assert_effect(ui.key(b' '))
    assert len(ui.events('submit'))==1

trial('default-cancel',default_cancel)
trial('escape-cancel',escape)
trial('confirm-once',confirm_once)
trial('queued-preview-keys',queued_preview)
trial('small-viewport',small_view)
trial('selection-update-bound-target',selection_update)
trial('stale-prepare',stale_prepare,mode='stale')
trial('stale-confirmation',lambda ui:rejected_confirmation(ui,'stale','Ölçüm güncel değil'))
trial('changed-advice-keeps-explicit-choice',changed_advice_does_not_revoke_choice)
trial('changed-owner-rejected',lambda ui:rejected_confirmation(ui,'unowned','uygulama süreci doğrulanamadı'))
trial('changed-app-rejected',lambda ui:rejected_confirmation(ui,'changed-app','Etkilenecek uygulama değişti'))
trial('replaced-identity',lambda ui:rejected_confirmation(ui,'replaced','kimliği değişmiş'))
if os.environ.get('CLOSURE_FINAL_FEATURES')=='1':
    trial('split-bracketed-paste',split_paste)
    trial('long-mandatory-info',long_notice,width=80,height=24,mode='long')
if effects:
    trial('effect-auto-open-and-reopen',effect_reopen)
    trial('effect-cancel-without-comparison',effect_cancel_without_previous)
    trial('effect-native-rejection-without-comparison',effect_rejected_without_previous)
    trial('effect-cancel-keeps-previous',lambda ui:effect_preserved_after_other_preview(ui))
    trial('effect-rejection-keeps-previous',lambda ui:effect_preserved_after_other_preview(ui,reject=True))
    trial('effect-missing-then-resume',effect_missing_then_resume)
    trial('effect-native-status-while-hidden',effect_native_observation_is_independent)
    trial('effect-next-accepted-replaces-previous',effect_next_accepted_replaces_previous)
    if os.environ.get('CLOSURE_EFFECT_WINDOW')=='1':
        trial('effect-real-sixty-second-window',effect_real_window)
if os.environ.get('CLOSURE_CONTROLS')=='1':
    trial('manager-from-main',manager_from_root,start_detail=False)
    trial('manager-no-recommendation',manager_no_recommendation,mode='withdrawn')
    trial('manager-frozen-reason',manager_frozen)
    trial('manager-other-workload-recommendation',manager_other_workload,mode='outside-group',start_detail=False)
    trial('manager-native-prepare-failure',manager_prepare_failure,mode='prepare-failure')
    trial('manager-return-cr',lambda ui:manager_enter_encoding(ui,[b'\r']),width=118,height=46,start_detail=False,mode='withdrawn')
    trial('manager-return-lf',lambda ui:manager_enter_encoding(ui,[b'\n']),width=118,height=46,start_detail=False,mode='withdrawn')
    trial('manager-return-crlf',lambda ui:manager_enter_encoding(ui,[b'\r\n']),width=118,height=46,start_detail=False,mode='withdrawn')
    trial('manager-return-split-crlf',lambda ui:manager_enter_encoding(ui,[b'\r',b'\n']),width=118,height=46,start_detail=False,mode='withdrawn')
    trial('manager-return-inherited-igncr',lambda ui:manager_enter_encoding(ui,[b'\r']),width=118,height=46,start_detail=False,mode='withdrawn',input_flags=termios.IGNCR | termios.INLCR)
    trial('manager-keyboard-fallback',manager_keyboard_fallback,width=118,height=46,start_detail=False,mode='withdrawn')
    trial('manager-keypad-enter',lambda ui:manager_enter_encoding(ui,[b'\x1bOM']),width=118,height=46,start_detail=False,mode='withdrawn')
    trial('manager-keypad-enter-split',lambda ui:manager_enter_encoding(ui,[b'\x1bO',b'M']),width=118,height=46,start_detail=False,mode='withdrawn')
    trial('effect-export-standalone-html',effect_export)
    trial('effect-export-error-direct-retry',effect_export_error_retry)
(outdir/'results.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2))
