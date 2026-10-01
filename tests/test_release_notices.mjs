import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, cp, writeFile, readFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { extractArchive } from '../lib/hac-update.mjs';

async function fixture(t) {
 const dir=await mkdtemp(join(tmpdir(),'hac-release-notices-'));
 t.after(()=>rm(dir,{recursive:true,force:true}));
 const root=join(dir,'source'), output=join(dir,'output');
 for(const name of ['scripts','bin','lib','manifest','resources/hac-branding','resources/licenses','docs']) await mkdir(join(root,name),{recursive:true});
 await cp(new URL('../scripts/package-release.mjs',import.meta.url),join(root,'scripts/package-release.mjs'));
 await writeFile(join(root,'manifest/hac.json'),JSON.stringify({version:'1.1.0'}));
 for(const name of ['install.sh','README.md','LICENSE','THIRD_PARTY_NOTICES.md','resources/hac-branding/LICENSE','resources/licenses/pi.LICENSE','docs/USER-MANUAL.md','docs/DEVELOPMENT.md']) await writeFile(join(root,name),`fixture contents: ${name}\n`);
 return {dir,root,output,build:()=>execFileSync(process.execPath,[join(root,'scripts/package-release.mjs'),'https://example.test/hac-1.1.0.tar.gz',output],{encoding:'utf8',stdio:'pipe'})};
}

test('generated release preserves notices through the updater archive reader',async t=>{
 const f=await fixture(t);f.build();
 const target=join(f.dir,'extracted');
 await extractArchive(await readFile(join(f.output,'hac-1.1.0.tar.gz')),target);
 for(const name of ['LICENSE','THIRD_PARTY_NOTICES.md','resources/hac-branding/LICENSE','resources/licenses/pi.LICENSE']) assert.deepEqual(await readFile(join(target,'hac',name)),await readFile(join(f.root,name)));
});

test('release packaging fails when third-party notices are missing',async t=>{
 const f=await fixture(t);await rm(join(f.root,'THIRD_PARTY_NOTICES.md'));
 assert.throws(f.build,/THIRD_PARTY_NOTICES\.md/);
 await assert.rejects(access(join(f.output,'hac-1.1.0.tar.gz')),error=>error.code==='ENOENT');
});

test('release includes public documents and excludes local mail, screenshots and private notes',async t=>{
 const f=await fixture(t);
 await mkdir(join(f.root,'docs/images'),{recursive:true});
 await mkdir(join(f.root,'docs/superpowers/plans'),{recursive:true});
 const privateFiles=['docs/USER-MANUAL.eml','docs/USER-MANUAL.html','docs/images/login-screen.png','docs/internal-notes.md','docs/LICENSE-REVIEW.md','docs/license-inventory.json','docs/superpowers/plans/private-plan.md'];
 for(const name of privateFiles)await writeFile(join(f.root,name),'nonsensitive private fixture');
 f.build();
 const target=join(f.dir,'extracted');
 await extractArchive(await readFile(join(f.output,'hac-1.1.0.tar.gz')),target);
 for(const name of ['docs/USER-MANUAL.md','docs/DEVELOPMENT.md'])await access(join(target,'hac',name));
 for(const name of privateFiles)await assert.rejects(access(join(target,'hac',name)),error=>error.code==='ENOENT');
});
