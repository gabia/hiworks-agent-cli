#!/usr/bin/env node
import { mkdtemp, mkdir, cp, readFile, writeFile, rm, lstat, readdir } from 'node:fs/promises';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const [url,output]=process.argv.slice(2);
if(!url||!output||new URL(url).protocol!=='https:') throw new Error('usage: node scripts/package-release.mjs HTTPS_ARCHIVE_URL OUTPUT_DIR');
const {version}=JSON.parse(await readFile(join(root,'manifest/hac.json')));
if(!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('stable version required');
const temporary=await mkdtemp(join(tmpdir(),'hac-package-'));
async function check(path) {const st=await lstat(path);if(st.isSymbolicLink()||(!st.isDirectory()&&!st.isFile()))throw new Error(`unsupported archive file: ${path}`);if(st.isDirectory())for(const name of await readdir(path)){if(name==='.git'||name==='.env'||name.startsWith('.env.'))throw new Error(`private file in release tree: ${path}/${name}`);await check(join(path,name));}}
try {
 const dest=join(temporary,'hac'); await mkdir(dest);
 for(const name of ['bin','lib','manifest','resources','install.sh','LICENSE','THIRD_PARTY_NOTICES.md','README.md']) {await check(join(root,name));await cp(join(root,name),join(dest,name),{recursive:true});}
 await mkdir(join(dest,'docs'));
 for(const name of ['USER-MANUAL.md','DEVELOPMENT.md']) {const source=join(root,'docs',name);await check(source);await cp(source,join(dest,'docs',name));}
 const out=resolve(output);await mkdir(out,{recursive:true});const archive=join(out,`hac-${version}.tar.gz`);
 execFileSync('tar',['--format=ustar','-czf',archive,'-C',temporary,'hac'],{env:{...process.env,COPYFILE_DISABLE:'1'}});
 const sha256=createHash('sha256').update(await readFile(archive)).digest('hex');
 await writeFile(join(out,'hac-release.json'),JSON.stringify({version,url,sha256},null,2)+'\n');
 console.log(archive);console.log(join(out,'hac-release.json'));
} finally {await rm(temporary,{recursive:true,force:true});}
