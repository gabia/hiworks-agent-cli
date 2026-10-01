"""Capture a real isolated Pi TUI in light/dark modes without a model request."""
import os,sys,pty,subprocess,select,time,tempfile,json,fcntl,termios,struct,pathlib
repo=pathlib.Path(__file__).resolve().parents[1]
pi=sys.argv[1]
extension=pathlib.Path(sys.argv[3]) if len(sys.argv)>3 else repo/'resources/hac-branding/hiworks-theme.mjs'
output=pathlib.Path(sys.argv[2]);output.mkdir(parents=True,exist_ok=True)
for appearance in ['light','dark']:
 with tempfile.TemporaryDirectory(prefix='hac-theme-') as home:
  config=pathlib.Path(home)/'.config/hiworks-agent-cli';config.mkdir(parents=True)
  (config/'settings.json').write_text(json.dumps({'theme':appearance,'defaultProvider':'anthropic','defaultModel':'claude-sonnet-4-5'}))
  master,slave=pty.openpty();fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',36,110,0,0));os.set_blocking(master,False)
  env={**os.environ,'HOME':home,'PI_CODING_AGENT_DIR':str(config),'HAC_THEME':appearance,'TERM':'xterm-256color','COLORTERM':'truecolor'}
  process=subprocess.Popen([pi,'--no-session','--no-skills','--extension',str(extension)],stdin=slave,stdout=slave,stderr=slave,env=env,cwd=home,start_new_session=True)
  os.close(slave);data=b''
  try:
   end=time.monotonic()+7
   while time.monotonic()<end:
    if select.select([master],[],[],.1)[0]:
     try:chunk=os.read(master,65536)
     except OSError:break
     data+=chunk
     for request,response in [(b'\x1b[6n',b'\x1b[1;1R'),(b'\x1b[c',b'\x1b[?1;2c')]:
      if request in chunk:
       try:os.write(master,response)
       except BlockingIOError:pass
    if process.poll() is not None:break
   (output/f'{appearance}.ansi').write_bytes(data)
   assert process.poll() is None,repr(data[-1800:])
   assert b'Hiworks Agent CLI' in data and b'Work together. Build better.' in data,repr(data[-1800:])
   assert b'Failed to load extension' not in data and b'Unknown theme' not in data and b'Hiworks theme:' not in data,repr(data[-1800:])
   assert b'hiworks-theme.mjs' in data, 'Named extension missing from startup resources'
   expected=b'38;2;29;122;189' if appearance=='light' else b'38;2;114;186;255'
   assert expected in data, 'Hiworks accent color was not rendered'
   target='dark' if appearance=='light' else 'light'
   os.write(master, f'/hiworks-theme {target}\r'.encode())
   deadline=time.monotonic()+3
   while time.monotonic()<deadline:
    if select.select([master],[],[],.1)[0]:
     try: os.read(master,65536)
     except OSError: break
   assert json.loads((config/'hiworks-theme.json').read_text())['appearance']==target
   assert process.poll() is None
   print(f'PASS: real {appearance} Hiworks TUI and switch to {target}')
  finally:
   process.terminate()
   try:process.wait(timeout=2)
   except subprocess.TimeoutExpired:process.kill()
   os.close(master)
