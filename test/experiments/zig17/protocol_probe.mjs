import { spawn, execFileSync } from 'node:child_process';
import { readFile, stat, realpath, mkdir } from 'node:fs/promises';
import { resolve, relative, isAbsolute, sep } from 'node:path';
import { createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { selectZig } from '../../../tools/zig.mjs';

const BASE = 0x80000000;
const MAX_FRAME = 16 << 20, MAX_TOTAL = 96 << 20, MAX_EVENTS = 65536;
const utf8 = new TextDecoder('utf-8', {fatal:true});
const hash = b => createHash('sha256').update(b).digest('hex');
const inside = (root, path) => { const p=relative(root,path); return p==='' || (!isAbsolute(p)&&p!=='..'&&!p.startsWith('..'+sep)); };
export class Frames {
  buffer = Buffer.alloc(0); total = 0; count = 0;
  push(chunk) {
    this.total += chunk.length;
    if (this.total > MAX_TOTAL) throw Error('ProtocolOutputLimit');
    this.buffer = Buffer.concat([this.buffer,chunk]);
    const out=[];
    while(this.buffer.length>=8) {
      const tag=this.buffer.readUInt32LE(0), size=this.buffer.readUInt32LE(4);
      if(size>MAX_FRAME)throw Error('ProtocolFrameLimit');
      if(tag<BASE||tag>BASE+6)throw Error('UnknownBuildProtocolTag');
      if(this.buffer.length<8+size)break;
      if(++this.count>MAX_EVENTS)throw Error('ProtocolEventLimit');
      out.push({tag,body:this.buffer.subarray(8,8+size)});
      this.buffer=this.buffer.subarray(8+size);
    }
    return out;
  }
  finish(){if(this.buffer.length)throw Error('TruncatedProtocolFrame');}
}
export function frame(tag,body=Buffer.alloc(0)){const h=Buffer.alloc(8);h.writeUInt32LE(tag,0);h.writeUInt32LE(body.length,4);return Buffer.concat([h,body]);}
function completed(body,graph,prefixes) {
  if(body.length<20)throw Error('MalformedStepCompletion');
  const index=body.readUInt32LE(0),status=body.readUInt32LE(4),extra=body.readUInt32LE(8),strings=body.readUInt32LE(12),count=body.readUInt32LE(16);
  if(index>=graph.steps.length||status>3||count>graph.generated_files)throw Error('InvalidStepCompletion');
  const records=20+extra*4+strings;
  let offset=records+count*8;
  if(offset>body.length)throw Error('MalformedStepCompletion');
  const artifacts=[];
  for(let i=0;i<count;i++){
    const id=body.readUInt32LE(records+i*8),size=body.readUInt32LE(records+i*8+4);
    if(id>=graph.generated_files||size>32768||offset+1+size>body.length)throw Error('MalformedGeneratedPath');
    const prefix=body[offset++],root=prefixes[prefix];
    if(!root)throw Error('UnknownGeneratedPathPrefix');
    const name=utf8.decode(body.subarray(offset,offset+size));offset+=size;
    if(name.includes('\0')||isAbsolute(name))throw Error('InvalidGeneratedPath');
    const path=resolve(root,name);
    if(!inside(root,path))throw Error('EscapingGeneratedPath');
    artifacts.push({id,path});
  }
  if(offset!==body.length)throw Error('TrailingStepCompletion');
  return {index,status,diagnosticBytes:extra*4+strings,artifacts};
}
function groupExists(pid){
  try{process.kill(-pid,0);return true;}catch(error){
    if(error.code==='ESRCH')return false;
    // Confirm absence after a raced signal check; a live permission failure
    // must never be treated as successful cleanup.
    if(error.code==='EPERM'){
      try{return execFileSync('ps',['-g',String(pid),'-o','pid='],{encoding:'utf8'}).trim().length>0;}
      catch(observation){if(observation.status===1&&!observation.stdout?.toString().trim())return false;}
    }
    throw error;
  }
}
function signalGroup(pid,signal){try{process.kill(-pid,signal);}catch(error){if(!['ESRCH','EPERM'].includes(error.code)||groupExists(pid))throw error;}}

async function waitForClose(closed,ms){
  let timer;
  try { await Promise.race([closed,new Promise(resolve=>{timer=setTimeout(resolve,ms);})]); }
  finally { clearTimeout(timer); }
}
async function retire(child,closed){
  if(!child.pid)return;
  await waitForClose(closed,25);
  if(groupExists(child.pid)){signalGroup(child.pid,'SIGTERM');await waitForClose(closed,500);}
  if(groupExists(child.pid))signalGroup(child.pid,'SIGKILL');
  await waitForClose(closed,1000);
  for(let i=0;i<20&&groupExists(child.pid);i++)await delay(50);
  if(groupExists(child.pid))throw Error('BuildProcessGroupSurvived');
}
export async function probe({root,cache,globalCache,prefix,reader,step='emit-capacity-fixture',timeout=120000,signal}) {
  const compiler=selectZig([]);root=await realpath(root);cache=resolve(cache);globalCache=resolve(globalCache);prefix=resolve(prefix);
  await mkdir(cache,{recursive:true});await mkdir(globalCache,{recursive:true});
  cache=await realpath(cache);globalCache=await realpath(globalCache);
  const args=['build','--listen=-','-Doptimize=safe','--cache-dir',cache,'--prefix',prefix];
  const child=spawn(compiler.executable,args,{cwd:root,env:{...compiler.env,ZIG_GLOBAL_CACHE_DIR:globalCache},detached:true,stdio:['pipe','pipe','pipe']});
  let exited,spawnError,stderrBytes=0,reason;
  const closed=new Promise(resolve=>{child.once('error',e=>{spawnError=e;resolve();});child.once('close',(code,signal)=>{exited={code,signal};resolve();});});
  let escalation;
  const stop=why=>{
    if(reason)return;reason=why;
    try{if(child.pid&&groupExists(child.pid))signalGroup(child.pid,'SIGTERM');}
    catch(error){child.stdout.destroy(error);}
    escalation=setTimeout(()=>{
      try{if(child.pid&&groupExists(child.pid))signalGroup(child.pid,'SIGKILL');}
      catch(error){child.stdout.destroy(error);}
    },500);
  };
  const timer=setTimeout(()=>stop('BuildProtocolTimeout'),timeout);
  const abort=()=>stop('BuildProtocolCancelled');signal?.addEventListener('abort',abort,{once:true});if(signal?.aborted)abort();
  child.stderr.on('data',bytes=>{stderrBytes+=bytes.length;if(stderrBytes>MAX_FRAME)stop('ProtocolDiagnosticsLimit');});
  const stream=new Frames(),events=[],artifacts=new Map();let handshake=false,graph,graphIdentity,requested,started=false,done=false;
  child.stdin.on('error', () => { if (!done) stop('BuildProtocolInputFailure'); });
  try {
    for await(const chunk of child.stdout)for(const message of stream.push(chunk)) {
      const {tag,body}=message;
      if(!handshake){if(tag!==BASE||body.length!==8)throw Error('MissingBuildHandshake');if(body.readUInt32LE(0)!==1)throw Error('UnsupportedBuildProtocolVersion');if(body.readUInt32LE(4)&~1)throw Error('UnknownHandshakeFlags');handshake=true;continue;}
      if(tag===BASE+1){
        if(graph||body.length>32768)throw Error('UnexpectedConfigurationChange');
        const path=resolve(root,utf8.decode(body));const actual=await realpath(path);
        if(!inside(cache,actual))throw Error('ConfigurationOutsideSelectedCache');
        const bytes=await readFile(actual);if(bytes.length>MAX_FRAME)throw Error('ConfigurationLimit');graphIdentity=hash(bytes);
        graph=JSON.parse(execFileSync(reader,[actual],{encoding:'utf8',maxBuffer:MAX_FRAME,timeout:10000}));
        requested=graph.steps.find(s=>s.kind==='top_level'&&s.name===step)?.index;if(requested===undefined)throw Error('UnknownBuildStep');
        const request=Buffer.alloc(12);request.writeUInt32LE(1,0);request.writeUInt32LE(requested,8);child.stdin.write(frame(BASE,request));
      } else if(tag===BASE+2)throw Error('BuildConfigurationFailed');
      else if(tag===BASE+3){if(!graph||started||done||body.length)throw Error('UnexpectedBuildStart');started=true;}
      else if(tag===BASE+4){if(!started||done||body.length)throw Error('UnexpectedBuildCompletion');done=true;child.stdin.end(frame(0));}
      else if(tag===BASE+5){if(!started||done||body.length!==4||body.readUInt32LE(0)>=graph.steps.length)throw Error('InvalidStepStart');}
      else if(tag===BASE+6){
        if(!started||done)throw Error('UnexpectedStepCompletion');
        const event=completed(body,graph,[root,compiler.identity.library,cache,globalCache,root]);events.push(event);
        for(const a of event.artifacts){const prior=artifacts.get(a.id);if(prior&&prior.path!==a.path)throw Error('GeneratedPathChanged');artifacts.set(a.id,a);}
      } else throw Error('UnexpectedBuildHandshake');
    }
    await closed;stream.finish();
    if(spawnError)throw spawnError;if(reason)throw Error(reason);
    if(exited?.code!==0)throw Error('BuildProtocolNonzeroExit');if(!done)throw Error('MissingBuildTerminalEvent');
    const statuses=new Map(events.map(e=>[e.index,e.status])),closure=new Set();
    function visit(i){if(closure.has(i))return;closure.add(i);for(const dep of graph.steps[i].dependencies)visit(dep);}visit(requested);
    for(const index of closure)if(statuses.get(index)!==0)throw Error('BuildStepDidNotSucceed:'+index);
    const files=[];let verifiedBytes=0;
    for(const item of artifacts.values()){
      const actual = await realpath(item.path);
      if (![root,compiler.identity.library,cache,globalCache].some(base=>inside(base,actual))) throw Error('GeneratedArtifactOutsideRoots');
      const info=await stat(actual);
      if(info.isDirectory()){files.push({...item,kind:'directory'});continue;}
      if(!info.isFile()||info.size>64<<20)throw Error('GeneratedArtifactLimit');
      verifiedBytes+=info.size;if(verifiedBytes>256<<20)throw Error('GeneratedArtifactTotalLimit');
      const bytes=await readFile(actual);files.push({...item,kind:'file',bytes:bytes.length,sha256:hash(bytes)});
    }
    compiler.assertUnchanged();
    return {status:'passed',version:1,toolchain:compiler.identity,environment:{ZIG_GLOBAL_CACHE_DIR:globalCache,ZIG_LOCAL_PKG_DIR:compiler.env.ZIG_LOCAL_PKG_DIR??null},command:[compiler.executable,...args],root,configurationSha256:graphIdentity,configuredSteps:graph.steps,requested,events,artifacts:files,exit:exited,stderrBytes};
  } finally {clearTimeout(timer);clearTimeout(escalation);signal?.removeEventListener('abort',abort);await retire(child,closed);}
}
if(process.argv[1]?.endsWith('protocol_probe.mjs')){
  const base=resolve('.tmp/bwa-z17');const result=await probe({root:process.cwd(),cache:base+'/protocol-local',globalCache:base+'/cache-u1',prefix:base+'/protocol-output',reader:base+'/build-config-reader'});console.log(JSON.stringify(result));
}

export { completed, retire };
