import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setupAiHub} from '../lib/hac-setup.mjs';
const read=(r,f)=>JSON.parse(readFileSync(join(r,f)));
function fixture(t){const r=mkdtempSync(join(tmpdir(),'hac-setup-'));t.after(()=>rmSync(r,{recursive:true,force:true}));writeFileSync(join(r,'settings.json'),JSON.stringify({packages:['npm:keep'],theme:'dark'}));return r;}
const fetchImpl=async()=>new Response(JSON.stringify({data:[{id:'z-model'},{id:'glm',max_tokens:8192},{id:'glm'}]}));
test('setup syncs complete unique catalog, selects model, and is byte-idempotent',async t=>{
 const root=fixture(t);let answers=['','test-key','2'];
 const ask=async()=>answers.shift();
 await setupAiHub({root,ask,fetchImpl,log:()=>{}});
 assert.equal(read(root,'settings.json').defaultModel,'z-model');
 assert.deepEqual(read(root,'settings.json').packages,['npm:keep']);
 assert.deepEqual(read(root,'models.json').providers.gabia.models.map(m=>m.id),['glm','z-model']);
 const files=['auth.json','models.json','settings.json'];const before=files.map(f=>readFileSync(join(root,f),'utf8'));
 answers=['','',''];await setupAiHub({root,ask,fetchImpl,log:()=>{}});
 assert.deepEqual(files.map(f=>readFileSync(join(root,f),'utf8')),before);
});
test('changed endpoint cannot silently reuse saved secret',async t=>{
 const root=fixture(t);writeFileSync(join(root,'auth.json'),JSON.stringify({gabia:{type:'api_key',key:'old'}}));
 let answers=['https://other.example/v1',''];let called=false;
 await assert.rejects(setupAiHub({root,ask:async()=>answers.shift(),fetchImpl:async()=>{called=true;},log:()=>{}}),/API key/);
 assert.equal(called,false);
});
test('lookup failure and cancellation leave existing settings untouched',async t=>{
 const root=fixture(t);const before=readFileSync(join(root,'settings.json'),'utf8');let answers=['','key'];
 await assert.rejects(setupAiHub({root,ask:async()=>answers.shift(),fetchImpl:async()=>new Response('',{status:401}),log:()=>{}}),/401/);
 assert.equal(readFileSync(join(root,'settings.json'),'utf8'),before);
 answers=['','key'];await assert.rejects(setupAiHub({root,ask:async()=>{if(!answers.length)throw Error('Cancelled');return answers.shift();},fetchImpl,log:()=>{}}),/Cancelled/);
 assert.equal(readFileSync(join(root,'settings.json'),'utf8'),before);
});

test('setup replaces the retired Gabia endpoint suggestion without reusing its key',async t=>{
 const root=fixture(t);
 const retired='https://'+'ai-hub-gabia'+'.gabia.com/v1';
 writeFileSync(join(root,'models.json'),JSON.stringify({providers:{gabia:{baseUrl:retired,models:[]}}}));
 writeFileSync(join(root,'auth.json'),JSON.stringify({gabia:{type:'api_key',key:'old-key'}}));
 let answers=['',''];let fetched=false;const prompts=[];
 await assert.rejects(setupAiHub({root,ask:async label=>{prompts.push(label);return answers.shift();},fetchImpl:async()=>{fetched=true;},log:()=>{}}),/API key/);
 assert.equal(prompts[0],'Base URL [https://ai-hub.gabia.com/v1]: ');
 assert.equal(fetched,false);
 answers=['','new-key',''];
 await setupAiHub({root,ask:async()=>answers.shift(),fetchImpl:async(url,options)=>{
  assert.equal(url,'https://ai-hub.gabia.com/v1/models');
  assert.equal(options.headers.Authorization,'Bearer new-key');
  return fetchImpl();
 },log:()=>{}});
 assert.equal(read(root,'models.json').providers.gabia.baseUrl,'https://ai-hub.gabia.com/v1');
});
