"""PTY regression: a key pasted as soon as the prompt appears must not echo."""
import os
import pathlib
import pty
import select
import subprocess
import tempfile
import time

repo = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='hac-key-input-') as home:
    master, slave = pty.openpty()
    env = {**os.environ, 'HOME': home}
    process = subprocess.Popen(
        [str(repo / 'bin/hac'), 'ai-hub', 'connect', '--url', 'http://localhost/v1'],
        stdin=slave, stdout=slave, stderr=slave, env=env,
    )
    os.close(slave)
    output = b''
    sent = False
    try:
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    output += os.read(master, 65536)
                except OSError:
                    break
                if b'(hidden):' in output and not sent:
                    os.write(master, b'fake-key-never-echoed\n')
                    sent = True
            if process.poll() is not None:
                break
        process.wait(timeout=2)
        assert sent and b'fake-key-never-echoed' not in output, repr(output)
        assert process.returncode == 1
        print('PASS: terminal API key input is hidden; insecure endpoint rejected')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
