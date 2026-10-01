import {join} from 'node:path';
import {homedir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {createInterface} from 'node:readline/promises';
import {connectAiHub, load, readKey, DEFAULT_URL} from './hac-ai-hub.mjs';

async function terminalAsk(label, {hidden=false}={}) {
  if (!process.stdin.isTTY) throw Error('Run hac setup in an interactive terminal');
  if (hidden) return readKey(true, label);
  const rl=createInterface({input:process.stdin, output:process.stderr});
  const abort=new AbortController();
  rl.once('SIGINT',()=>abort.abort());
  try {return (await rl.question(label,{signal:abort.signal})).trim();}
  catch {throw Error('Cancelled');}
  finally {rl.close();}
}
const normalize=url=>new URL(url).href.replace(/\/+$/,'');
export async function setupAiHub({root=join(homedir(),'.config','hiworks-agent-cli'),ask=terminalAsk,fetchImpl=fetch,log=console.log}={}) {
  const auth=load(root,'auth.json'), models=load(root,'models.json'), settings=load(root,'settings.json');
  const savedUrl=models.providers?.gabia?.baseUrl || DEFAULT_URL;
  const retiredUrl=`https://${['ai-hub-gabia','gabia','com'].join('.')}/v1`;
  const suggested=normalize(savedUrl)===retiredUrl ? DEFAULT_URL : savedUrl;
  log('Hiworks Agent CLI — Gabia AI Hub setup');
  const url=(await ask(`Base URL [${suggested}]: `)) || suggested;
  const endpoint=new URL(url);
  if(endpoint.protocol!=='https:'||endpoint.username||endpoint.password||endpoint.search||endpoint.hash) throw Error('Use an HTTPS base URL without credentials, query, or fragment');
  const reusable=normalize(url)===normalize(savedUrl) && auth.gabia?.type==='api_key' ? auth.gabia.key : undefined;
  const entered=await ask(reusable ? 'API Key (hidden; Enter to keep saved key): ' : 'API Key (hidden): ', {hidden:true});
  const key=entered || reusable;
  if(!key)throw Error('An API key is required for this endpoint');
  log('Fetching available models…');
  const result=await connectAiHub({root,key,url,fetchImpl,syncModels:true,selectModel:async ids=>{
    const preferred=ids.includes(settings.defaultModel) ? settings.defaultModel : ids.includes('glm') ? 'glm' : ids[0];
    ids.forEach((id,index)=>log(`${index+1}. ${id}${id===preferred?' (default)':''}`));
    while(true){
      const choice=await ask(`Default model [${preferred}] (number or model ID): `);
      const selected=!choice ? preferred : ids.includes(choice) ? choice : /^\d+$/.test(choice) ? ids[Number(choice)-1] : undefined;
      if(selected)return selected;
      log('Choose a listed model ID or number.');
    }
  }});
  log(`Saved ${result.modelCount} models. Default: ${result.provider}/${result.model}\nRun hac to start.`);
  return result;
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
  const args=process.argv.slice(2);
  if(args.length===1 && ['--help','-h'].includes(args[0])) console.log('Usage: hac setup\nConfigure Gabia AI Hub URL, API key, available models and default model interactively.');
  else if(args.length){console.error('Usage: hac setup');process.exitCode=2;}
  else setupAiHub().catch(error=>{console.error(`hac setup: ${error.message}`);process.exitCode=1;});
}
