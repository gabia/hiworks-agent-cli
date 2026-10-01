import { mkdirSync, writeFileSync, readFileSync, rmSync, rmdirSync } from 'node:fs';
import { readFile, writeFile, mkdir, mkdtemp, rename as move, rm, lstat } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';

const stable = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const newer = (a,b) => { const x=a.split('.').map(BigInt),y=b.split('.').map(BigInt); for(let i=0;i<3;i++) if(x[i]!==y[i]) return x[i]>y[i]; return false; };
async function optional(path) { try { return await readFile(path); } catch(e) { if(e.code==='ENOENT') return null; throw e; } }
async function download(url, fetchImpl, limit) {
 if(new URL(url).protocol!=='https:') throw new Error('release URLs must use HTTPS');
 const response=await fetchImpl(url,{redirect:'error',signal:AbortSignal.timeout(60000)});
 if(!response.ok) throw new Error(`release download failed: HTTP ${response.status}`);
 const chunks=[]; let size=0;
 for await(const chunk of response.body) { size+=chunk.length; if(size>limit) throw new Error('release download exceeds size limit'); chunks.push(Buffer.from(chunk)); }
 return Buffer.concat(chunks);
}
// Parse a deliberately narrow ustar subset. No tar subprocess can reinterpret
// long-name/PAX metadata or link entries after these checks.
export async function extractArchive(archive, target) {
 const data=gunzipSync(archive,{maxOutputLength:128*1024*1024}); const entries=[]; const names=new Set();
 for(let offset=0;offset+512<=data.length;) {
  const h=data.subarray(offset,offset+512); if(h.every(n=>n===0)) break;
  const str=(start,length)=>h.subarray(start,start+length).toString('utf8').split('\0')[0];
  const oct=(start,length)=>{const v=str(start,length).trim(); if(!/^[0-7]+$/.test(v)) throw new Error('invalid tar numeric field'); return parseInt(v,8);};
  const sum=h.reduce((s,n,i)=>s+(i>=148&&i<156?32:n),0); if(sum!==oct(148,8)) throw new Error('invalid tar header checksum');
  const prefix=str(345,155); const name=(prefix?prefix+'/':'')+str(0,100); const clean=name.replace(/\/$/,'');
  if(!clean.startsWith('hac/')&&clean!=='hac') throw new Error('archive must contain only hac/');
  if(clean.split('/').some(p=>!p||p==='.'||p==='..')||clean.includes('\\')||names.has(clean)) throw new Error('unsafe archive path');
  names.add(clean); const type=str(156,1); if(!['','0','5'].includes(type)) throw new Error('archive links and special entries are forbidden');
  const size=oct(124,12); if(offset+512+size>data.length) throw new Error('truncated archive');
  entries.push({name:clean,type,mode:oct(100,8)&0o777,bytes:data.subarray(offset+512,offset+512+size)});
  offset+=512+Math.ceil(size/512)*512;
 }
 if(!entries.length) throw new Error('empty archive');
 for(const e of entries) { const path=join(target,e.name); if(e.type==='5') await mkdir(path,{recursive:true}); else {await mkdir(dirname(path),{recursive:true});await writeFile(path,e.bytes,{mode:e.mode,flag:'wx'});} }
}

function acquireLock(lock, staleSeconds=0) {
 const create=()=>{mkdirSync(lock);try {writeFileSync(join(lock,'pid'),`${process.pid}\n`,{mode:0o600});writeFileSync(join(lock,'timestamp'),`${Math.floor(Date.now()/1000)}\n`,{mode:0o600});} catch(e) {rmSync(lock,{recursive:true,force:true});throw e;}};
 const stale=()=>{try {const pid=readFileSync(join(lock,'pid'),'utf8').trim(), timestamp=readFileSync(join(lock,'timestamp'),'utf8').trim();if(!/^[1-9]\d*$/.test(pid)||!/^\d+$/.test(timestamp))return false;try {process.kill(Number(pid),0);return false;} catch(e) {if(e.code!=='ESRCH')return false;}return Date.now()/1000-Number(timestamp)>=staleSeconds;} catch{return false;}};
 try {create();} catch(e) {
  if(e.code!=='EEXIST')throw e;
  const recovery=lock+'.reclaim';let reclaiming=false;
  try {if(!stale())throw new Error('held');mkdirSync(recovery);reclaiming=true;if(!stale())throw new Error('held');rmSync(lock,{recursive:true});create();}
  catch {throw new Error(`another hac update or runtime operation is running (lock held: ${lock})`);}
  finally {if(reclaiming)rmdirSync(recovery);}
 }
 return ()=>{try {if(readFileSync(join(lock,'pid'),'utf8').trim()===String(process.pid))rmSync(lock,{recursive:true,force:true});}catch(e){if(e.code!=='ENOENT')throw e;}};
}

export async function updateHac(installRoot, options={}) {
 const env=options.env??process.env;
 const locks=join(env.HOME,'.config/hiworks-agent-cli/runtime/locks');
 await mkdir(locks,{recursive:true});
 const release=acquireLock(join(locks,'hac-update'));
 // Exit cleanup handles ordinary signals; PID metadata also permits recovery
 // after SIGKILL or a machine restart, when handlers cannot run.
 const onExit=()=>release();process.once('exit',onExit);
 const interruption={protected:false,code:0};
 const stop=code=>{if(interruption.protected) interruption.code=code;else process.exit(code);};
 const onInt=()=>stop(130),onTerm=()=>stop(143);
 process.once('SIGINT',onInt);process.once('SIGTERM',onTerm);
 try {const status=await updateLocked(installRoot,{...options,interruption});return interruption.code||status;} finally {process.removeListener('exit',onExit);process.removeListener('SIGINT',onInt);process.removeListener('SIGTERM',onTerm);release();}
}

async function updateLocked(installRoot, options={}) {
 const env=options.env??process.env, fetchImpl=options.fetchImpl??fetch, log=options.log??console.log, rename=options.rename??move;
 const run=options.run??((file,args,childEnv)=>spawnSync(file,args,{env:childEnv,encoding:'utf8',stdio:args[0]==='version'?'pipe':'inherit',timeout:args[0]==='version'?15000:undefined}));
 const root=resolve(installRoot), config=join(env.HOME,'.config/hiworks-agent-cli');
 let feed=env.HAC_RELEASE_URL;
 if(!feed) {const configBytes=await optional(join(config,'updates.json')); if(configBytes) feed=JSON.parse(configBytes).hacReleaseUrl;}
 const pi=(path)=>run(join(path,'bin/hac'),['pi','update'],env).status??1;
 if(!feed) {log('hac: no release feed configured; skipping hac self-update and updating Pi');return pi(root);}
 const manifest=JSON.parse((await download(feed,fetchImpl,1024*1024)).toString());
 if(!stable.test(manifest.version)||typeof manifest.url!=='string'||!/^[a-fA-F0-9]{64}$/.test(manifest.sha256)) throw new Error('invalid stable release manifest');
 const currentBytes=await optional(join(root,'manifest/hac.json'));
 const current=currentBytes?JSON.parse(currentBytes).version:'1.0.0';
 if(!stable.test(current)) throw new Error('invalid installed hac version');
 if(!newer(manifest.version,current)) {log(`hac: ${current} is current; updating Pi`);return pi(root);}
 if((await lstat(root)).isSymbolicLink()) throw new Error('install root must be a directory, not a symlink');
 const archive=await download(manifest.url,fetchImpl,32*1024*1024);
 if(createHash('sha256').update(archive).digest('hex')!==manifest.sha256.toLowerCase()) throw new Error('release checksum mismatch');
 const staging=await mkdtemp(join(dirname(root),'.hac-update-')); const candidate=join(staging,'hac'), backup=join(staging,'previous');
 let oldMoved=false, published=false, preserveStaging=false, releaseRuntime;
 const onExitRuntime=()=>releaseRuntime?.();
 const pointers=['active.json','active.json.previous'].map(name=>join(config,'runtime',name)); let snapshots;
 const restorePointers=async()=>{if(snapshots) for(let i=0;i<pointers.length;i++) {if(snapshots[i]===null) await rm(pointers[i],{force:true});else await writeFile(pointers[i],snapshots[i]);}};
 try {
  await extractArchive(archive,staging);
  const candidateVersion=JSON.parse(await readFile(join(candidate,'manifest/hac.json'))).version;
  if(candidateVersion!==manifest.version) throw new Error('candidate manifest version mismatch');
  const probeHome=join(staging,'probe-home');await mkdir(probeHome);
  const probe=run(join(candidate,'bin/hac'),['version'],{...env,HOME:probeHome,PI_CODING_AGENT_DIR:join(probeHome,'.config/hiworks-agent-cli')});
  if(probe.status!==0||!String(probe.stdout).split(/\r?\n/).includes(`hacVersion=${manifest.version}`)) throw new Error('candidate hac version validation failed');
  releaseRuntime=acquireLock(join(config,'runtime/locks/runtime'),Number(env.HAC_LOCK_STALE_SECONDS??3600));
  process.once('exit',onExitRuntime);
  // Defer signals until publication or rollback has restored a complete install.
  options.interruption.protected=true;
  snapshots=await Promise.all(pointers.map(optional));
  const status=run(join(candidate,'bin/hac'),['pi','update'],{...env,HAC_RUNTIME_LOCK_HELD:'1'}).status??1; if(status!==0) {await restorePointers();return status;}
  await rename(root,backup);oldMoved=true;
  await rename(candidate,root);published=true;
  log(`hac: updated ${current} → ${manifest.version}`);return 0;
 } catch(error) {
  if(oldMoved&&!published) {try {await move(backup,root);} catch(rollbackError) {preserveStaging=true;throw new Error(`rollback failed; previous installation retained at ${backup}: ${rollbackError.message}`,{cause:error});}}
  if(!published) await restorePointers();
  throw error;
 } finally {options.interruption.protected=false;process.removeListener('exit',onExitRuntime);releaseRuntime?.();if(!preserveStaging) await rm(staging,{recursive:true,force:true});}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try { if(!process.argv[2]) throw new Error('install root is required');process.exitCode=await updateHac(process.argv[2]); }
 catch(error) {console.error(`hac: update failed: ${error.message}`);process.exitCode=1;}
}
