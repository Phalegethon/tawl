"""Exercise live hardware UI without modifying or signalling any observed app."""
import os, pty, fcntl, termios, struct, subprocess, select, time, json, re
from pathlib import Path
from language_support import LANGUAGE, label
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'work' / ('hardware-pty' if LANGUAGE == 'en' else 'hardware-pty-' + LANGUAGE)
OUT.mkdir(parents=True, exist_ok=True)

def read(fd, seconds=.4, frame_size=None, child=None):
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
    if frame_size is not None and data:
        width, height = frame_size
        # PTY reads can split one render into several chunks. Finish only the
        # frame already being received; never resend a key or skip a bad frame.
        deadline = time.monotonic() + .75
        while child.poll() is None and time.monotonic() < deadline:
            frame = data.split(b'\x1b[1;1H')[-1]
            marker = f'\x1b[{height};1H'.encode()
            last_row = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', frame.split(marker)[-1])
            if marker in frame and len(last_row.decode('utf8', errors='replace')) >= width:
                break
            data += read(fd, .02)
    return data

def screen(data):
    """Read the latest drawn frame, retaining terminal row boundaries."""
    frame = data.split(b'\x1b[1;1H')[-1]
    rows = re.split(rb'\x1b\[\d+;1H', frame)
    return '\n'.join(re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', row).decode('utf8', errors='replace') for row in rows)

def resource_panels(frame):
    # App/process names (for example com.apple.WebKit.GPU) and footer shortcuts
    # are not evidence that the hardware panels are visible.
    panels, separator, _ = frame.partition('\n╭ ' + label('Applications').upper())
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
        output += read(master, 3, (width, height), proc)
        assert hardware_visible(screen(output)), 'hardware should be visible on launch'
        def key(value):
            global output
            os.write(master,value)
            chunk = read(master, frame_size=(width, height), child=proc)
            output += chunk
            assert b'\n' not in chunk and b'\r' not in chunk
            return screen(chunk)
        assert label('FROZEN') in key(b' ')
        hidden = key(b'g')
        summary = resource_panels(hidden)
        assert summary.startswith('╭ CPU ─') and '╭ ' + label('MEMORY') + ' ─' in summary and 'GPU' not in summary, 'g should restore summary panels'
        visible = key(b'g')
        assert hardware_visible(visible) and label('FROZEN') in visible
        assert label('PROCESS TERMINATION') in key(b'x')
        key(b'\x1b')
        assert label('HISTORY') in key(b'h')
        history = key(b'\x1b[D')
        assert hardware_visible(history) and label('HISTORY') in history
        key(b'q'); proc.wait(timeout=3)
        assert proc.returncode == 0
        assert termios.tcgetattr(slave) == original
        results.append(dict(width=width,height=height,defaultVisible=True,toggle=True,frozen=True,history=True,closurePanel=True,restored=True))
    finally:
        if proc.poll() is None:
            # A child flushing its final screen can block on a full PTY. Drain
            # while waiting so cleanup does not hide the original assertion.
            proc.terminate()
            deadline = time.monotonic() + 3
            while proc.poll() is None and time.monotonic() < deadline:
                output += read(master, .03)
            if proc.poll() is None:
                proc.kill()  # Only this test's own UI subprocess.
            proc.wait(timeout=1)
        output += read(master, .03)
        (OUT/f'{width}x{height}.ansi').write_bytes(output)
        os.close(master);os.close(slave)
(OUT/'results.json').write_text(json.dumps(results,indent=2))
print(json.dumps(results,indent=2))
