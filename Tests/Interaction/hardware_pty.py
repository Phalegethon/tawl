"""Exercise live hardware UI without modifying or signalling any observed app."""
import os, pty, fcntl, termios, struct, subprocess, select, time, json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'work' / 'hardware-pty'
OUT.mkdir(parents=True, exist_ok=True)

def read(fd, seconds=.4):
    end = time.monotonic() + seconds
    data = b''
    while time.monotonic() < end:
        ready, _, _ = select.select([fd], [], [], .03)
        if ready:
            try:
                part = os.read(fd, 65536)
            except OSError:
                break
            if not part:
                break
            data += part
    return data

def screen(data):
    """Read the latest drawn frame, retaining terminal row boundaries."""
    frame = data.split(b'\x1b[1;1H')[-1]
    rows = re.split(rb'\x1b\[\d+;1H', frame)
    return '\n'.join(re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', row).decode('utf8', errors='replace') for row in rows)

def resource_panels(frame):
    # App/process names (for example com.apple.WebKit.GPU) and footer shortcuts
    # are not evidence that the hardware panels are visible.
    panels, separator, _ = frame.partition('\n╭ UYGULAMALAR')
    assert separator, 'expected the monitoring screen with its workload table'
    return '\n'.join(panels.splitlines()[3:])

def hardware_visible(frame):
    panels = resource_panels(frame)
    return panels.startswith('╭ CPU · ') and 'GPU' in panels

results = []
for width, height in [(80,24),(100,30),(157,43)]:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH',height,width,0,0))
    original = termios.tcgetattr(slave)
    proc = subprocess.Popen([str(ROOT/'tawl')], stdin=slave, stdout=slave, stderr=slave,
                            cwd=ROOT, env=dict(os.environ, TERM='xterm-256color', NO_COLOR='1'))
    output = b''
    try:
        output += read(master, 3)
        assert hardware_visible(screen(output)), 'hardware should be visible on launch'
        def key(value):
            global output
            os.write(master,value)
            chunk = read(master)
            output += chunk
            assert b'\n' not in chunk and b'\r' not in chunk
            return screen(chunk)
        assert 'SABİT' in key(b' ')
        hidden = key(b'g')
        summary = resource_panels(hidden)
        assert summary.startswith('╭ CPU ─') and '╭ BELLEK ─' in summary and 'GPU' not in summary, 'g should restore summary panels'
        visible = key(b'g')
        assert hardware_visible(visible) and 'SABİT' in visible
        assert 'SÜREÇ KAPATMA' in key(b'x')
        key(b'\x1b')
        assert 'GEÇMİŞ' in key(b'h')
        history = key(b'\x1b[D')
        assert hardware_visible(history) and 'GEÇMİŞ' in history
        key(b'q'); proc.wait(timeout=3)
        assert proc.returncode == 0
        assert termios.tcgetattr(slave) == original
        (OUT/f'{width}x{height}.ansi').write_bytes(output)
        results.append(dict(width=width,height=height,defaultVisible=True,toggle=True,frozen=True,history=True,closurePanel=True,restored=True))
    finally:
        if proc.poll() is None:
            proc.terminate();proc.wait(timeout=3)
        os.close(master);os.close(slave)
(OUT/'results.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2))
