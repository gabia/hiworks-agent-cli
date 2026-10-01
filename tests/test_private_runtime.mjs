import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, stat, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';

test('hac starts Pi with private permissions for newly written session files', async t => {
 const home=await mkdtemp(join(tmpdir(),'hac-private-runtime-'));
 t.after(()=>rm(home,{recursive:true,force:true}));
 const root=join(home,'.config/hiworks-agent-cli'), release=join(root,'runtime/releases/pi-fixture');
 await mkdir(join(release,'bin'),{recursive:true});
 await mkdir(join(root,'sessions'),{recursive:true});
 await writeFile(join(root,'runtime/active.json'),JSON.stringify({executable:'runtime/releases/pi-fixture/bin/pi'}));
 await writeFile(join(release,'bin/pi'),'#!/bin/sh\nprintf "%s\\n" "nonsensitive fixture session" > "$PI_CODING_AGENT_DIR/sessions/probe.jsonl"\n',{mode:0o755});
 execFileSync('sh',['-c','umask 022; sh "$1" pi --print fixture','sh',new URL('../bin/hac',import.meta.url).pathname],{env:{...process.env,HOME:home},stdio:'pipe'});
 assert.equal((await stat(join(root,'sessions/probe.jsonl'))).mode&0o777,0o600);
});
