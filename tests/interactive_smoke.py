"""Verify a real terminal UI without credentials or a model request."""
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

launcher, home = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(home)
    os.environ['TERM'] = 'xterm-256color'
    for key in list(os.environ):
        if key.endswith(('_API_KEY', '_AUTH_TOKEN', '_ACCESS_TOKEN')):
            os.environ.pop(key, None)
    os.execv(launcher, [launcher])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 110, 0, 0))
os.set_blocking(fd, False)
output = b''
alive = True
try:
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if select.select([fd], [], [], 0.2)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError as error:
                if error.errno not in (errno.EIO, errno.EAGAIN):
                    raise
                chunk = b''
            output += chunk
            # Reply to terminal capability queries, never enter a prompt.
            if b'\x1b[6n' in chunk:
                try: os.write(fd, b'\x1b[1;1R')
                except BlockingIOError: pass
            if b'\x1b[c' in chunk:
                try: os.write(fd, b'\x1b[?1;2c')
                except BlockingIOError: pass
        if os.waitpid(pid, os.WNOHANG)[0]:
            alive = False
            break
    # Plain text from a no-op fixture is insufficient: require terminal UI.
    if not alive or b'\x1b[' not in output or len(output) < 100:
        raise RuntimeError('Pi did not render a persistent terminal UI: ' + repr(output[-1500:]))
    if b'Hiworks Agent CLI' not in output or b'Work together. Build better.' not in output:
        raise RuntimeError('Hiworks branding missing from terminal output')
    print('PASS: real Pi interactive PTY startup with Hiworks branding')
finally:
    if alive:
        os.kill(pid, signal.SIGTERM)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if os.waitpid(pid, os.WNOHANG)[0]:
                break
            time.sleep(0.1)
        else:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, os.WNOHANG)
    os.close(fd)
