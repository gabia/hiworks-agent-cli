import os, pathlib, signal, subprocess, tempfile, time
repo=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='hac-signal-') as d:
    home=pathlib.Path(d); source=home/'candidate'; (source/'bin').mkdir(parents=True)
    (source/'metadata.json').write_text('{"piVersion":"0.85.1","executable":"bin/pi"}')
    pi=source/'bin/pi'
    pi.write_text('#!/bin/sh\ncase "${1:-}" in\n--version) echo 0.85.1;;\n--help) echo "Usage: pi --help --version";;\nesac\n')
    pi.chmod(0o755)
    env=os.environ.copy();env.update(HOME=d,HAC_PI_SOURCE=str(source))
    subprocess.run([str(repo/'bin/hac'),'install'],env=env,check=True)
    release=home/'.config/hiworks-agent-cli/runtime/releases/pi-0.85.1'
    (release/'marker').write_text('original')
    (source/'marker').write_text('replacement')
    # Signal every member while reconciliation is running, as terminal Ctrl-C does.
    pi.write_text(pi.read_text()+f'if [ "${{1:-}}" = list ]; then touch "{home}/ready"; sleep 30; fi\n')
    process=subprocess.Popen([str(repo/'bin/hac'),'install','--repair'],env=env,start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        deadline=time.monotonic()+15
        while not (home/'ready').exists() and time.monotonic()<deadline:
            time.sleep(.1)
        assert (home/'ready').exists(), 'reconciliation did not start'
        os.killpg(process.pid,signal.SIGTERM)
        process.communicate(timeout=10)
        assert process.returncode != 0
        assert (release/'marker').read_text() == 'original', 'old release lost after signal'
        print('PASS: signal-interrupted repair restores previous release')
    finally:
        if process.poll() is None:
            os.killpg(process.pid,signal.SIGKILL);process.communicate()
