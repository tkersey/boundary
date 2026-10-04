// Disposable Linux correctness pilot. No production workflow is selected here.
import {spawn,spawnSync,execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,realpathSync,readdirSync} from 'node:fs';
import {resolve,join} from 'node:path';import {cpus,release} from 'node:os';
import {createHash} from 'node:crypto';import assert from 'node:assert/strict';
import {Frames,frame,completed,retire} from './protocol_probe.mjs';
import {selectZig} from '../../../tools/zig.mjs';
assert.equal(process.platform,'linux');assert.equal(process.arch,'x64');
const repo=process.cwd(),out=resolve(process.env.RUNNER_TEMP??'.tmp','zig17-incremental-'+Date.now());mkdirSync(out,{recursive:true});
const sha=x=>createHash('sha256').update(x).digest('hex'),compiler=selectZig([]),head=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
const root=join(out,'tree'),cache=join(out,'incremental-cache'),freshCache=join(out,'fresh-cache'),globalCache=join(out,'global-cache'),prefix=join(out,'incremental-output'),freshPrefix=join(out,'fresh-output');
const reader=join(out,'build-config-reader');
const run=(exe,args,options={})=>{const r=spawnSync(exe,args,{encoding:'utf8',timeout:600000,maxBuffer:16<<20,...options});assert.ifError(r.error);return r;};
let r=run('git',['worktree','add','--detach',root,head]);assert.equal(r.status,0,r.stderr);
const env={...compiler.env,ZIG_GLOBAL_CACHE_DIR:globalCache};
r=run(compiler.executable,['build-exe',resolve('test/experiments/zig17/build_config_reader.zig'),'-Odebug','-femit-bin='+reader],{env});assert.equal(r.status,0,r.stderr);
for(const p of [cache,freshCache,globalCache])mkdirSync(p,{recursive:true});
const files=['src/data/coalescing.zig','src/source.zig','build.zig','build.zig.zon'];
const originals=Object.fromEntries(files.map(p=>[p,readFileSync(join(root,p),'utf8')]));
const replace=(path,from,to)=>{assert(originals[path].includes(from),path);return {[path]:originals[path].replace(from,to)}};
const edits=[
 {name:'initial',files:{}},
 {name:'private-optimizer',files:replace('src/data/coalescing.zig','if (representative != id) return true;','if (id != representative) return true;')},
 {name:'restore-private',files:{}},
 {name:'authoring-helper',files:replace('src/source.zig','return self.arena.allocator();','const result = self.arena.allocator();\n        return result;')},
 {name:'restore-helper',files:{}},
 {name:'exported-type',files:replace('src/data/coalescing.zig','pub const Options = struct {','pub const Options = struct {\n    incremental_probe: bool = false,')},
 {name:'restore-type',files:{}},
 {name:'build-configuration',files:replace('build.zig','"Check code and constant sharing and emit executable economy workloads"','"Check code and constant sharing and emit executable economy workloads (incremental probe)"')},
 {name:'restore-build',files:{}},
];
const record={experiment:'E05',status:'running correctness pilot; no speedup claim',source:head,toolchain:compiler.identity,host:{platform:process.platform,arch:process.arch,cpu:cpus()[0].model,os:release()},regime:'Same native debug/default backend, incremental persistent process versus fresh nonincremental invocation; separate project caches, initially empty and then retained. First cycle includes project compilation, subsequent rows are edits. Global support cache shared and already used to compile the protocol reader; no OS cache flush.',missing:['Actual Agent dependency-lock change','Five paired measurement windows if correctness pilot passes'],rows:[]};
const save=()=>writeFileSync(join(out,'result.json'),JSON.stringify(record,null,2)+'\n');save();console.log('E05 output',out);
const artifacts=dir=>Object.fromEntries([0,1,8,64].map(n=>{const b=readFileSync(join(dir,`economy-${n}.bpi3`));return[n,{bytes:b.length,sha256:sha(b)}]}));
const memory=pid=>{const table=execFileSync('ps',['-eo','pid=,ppid=,rss=,comm='],{encoding:'utf8'}).trim().split('\n').map(x=>{const m=x.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/);return m&&{pid:+m[1],parent:+m[2],rssBytes:+m[3]*1024,command:m[4]}}).filter(Boolean);const keep=new Set([pid]);for(let changed=true;changed;){changed=false;for(const p of table)if(keep.has(p.parent)&&!keep.has(p.pid)){keep.add(p.pid);changed=true;}}return table.filter(p=>keep.has(p.pid));};
const args=['build','--listen=-','-fincremental','-Doptimize=debug','--cache-dir',cache,'--prefix',prefix,'-j2','--verbose'];
record.command=[compiler.executable,...args];const child=spawn(compiler.executable,args,{cwd:root,env,detached:true,stdio:['pipe','pipe','pipe']});
let exit,spawnError;const closed=new Promise(resolve=>{child.once('error',e=>{spawnError=e;resolve()});child.once('close',(code,signal)=>{exit={code,signal};resolve()})});let stderr=Buffer.alloc(0),aborted=false;
const kill=()=>{aborted=true;try{process.kill(-child.pid,'SIGKILL')}catch(e){if(e.code!=='ESRCH')throw e}};const timer=setTimeout(kill,30*60*1000);
child.stderr.on('data',b=>{stderr=Buffer.concat([stderr,b]);if(stderr.length>32<<20)kill()});child.stdin.on('error',()=>{});
const parser=new Frames();let handshake=false,graph,graphHash,selected,started=false,events=[],cycle=0,clock=performance.now(),done=false,statuses=new Map();
try{
 for await(const chunk of child.stdout)for(const {tag,body}of parser.push(chunk)){
  if(!handshake){assert.equal(tag,0x80000000);assert.equal(body.readUInt32LE(0),1);assert(body.readUInt32LE(4)&1,'Linux file watching must be supported');handshake=true;continue;}
  if(tag===0x80000001){const path=resolve(root,body.toString());graphHash=sha(readFileSync(path));statuses.clear();graph=JSON.parse(execFileSync(reader,[path],{encoding:'utf8',maxBuffer:16<<20,timeout:10000}));selected=graph.steps.find(s=>s.kind==='top_level'&&s.name==='check-economy')?.index;assert.notEqual(selected,undefined);const request=Buffer.alloc(12);request.writeUInt32LE(1,0);request.writeUInt32LE(1,4);request.writeUInt32LE(selected,8);child.stdin.write(frame(0x80000000,request));}
  else if(tag===0x80000002)throw Error('BuildConfigurationFailed');
  else if(tag===0x80000003){assert(!started);started=true;events=[];}
  else if(tag===0x80000005){assert(started);}
  else if(tag===0x80000006){assert(started);events.push(completed(body,graph,[root,compiler.identity.library,cache,globalCache,root]));}
  else if(tag===0x80000004){assert(started);started=false;const elapsedMs=performance.now()-clock,retainedProcesses=memory(child.pid);if(!events.some(e=>graph.steps[e.index].kind==='compile')){for(const e of events)assert.equal(e.status,0,'incidental rebuild must succeed');record.incidentalCycles??=[];assert(record.incidentalCycles.length<1024);record.incidentalCycles.push({awaitingEdit:edits[cycle].name,elapsedMs,configurationSha256:graphHash,events:events.map(e=>({...e,name:graph.steps[e.index].name,kind:graph.steps[e.index].kind}))});save();continue;}const row={name:edits[cycle].name,elapsedMs,configurationSha256:graphHash,sourceFiles:Object.fromEntries(files.map(p=>[p,sha(readFileSync(join(root,p)))])),retainedProcesses,events:events.map(e=>({...e,name:graph.steps[e.index].name,kind:graph.steps[e.index].kind}))};record.rows.push(row);save();
   for(const e of events)statuses.set(e.index,e.status);const closure=new Set();const visit=i=>{if(closure.has(i))return;closure.add(i);for(const d of graph.steps[i].dependencies)visit(d)};visit(selected);for(const i of closure)assert.equal(statuses.get(i),0,'step '+graph.steps[i].name);
   row.artifacts=artifacts(prefix);const freshArgs=['build','check-economy','-fno-incremental','-Doptimize=debug','--cache-dir',freshCache,'--prefix',freshPrefix,'-j2','--verbose','--summary','all'];const time=performance.now();const fresh=run(compiler.executable,freshArgs,{cwd:root,env});row.fresh={command:[compiler.executable,...freshArgs],elapsedMs:performance.now()-time,status:fresh.status};writeFileSync(join(out,`fresh-${cycle}.log`),fresh.stdout+fresh.stderr);assert.equal(fresh.status,0,fresh.stderr.slice(-2000));row.fresh.artifacts=artifacts(freshPrefix);assert.deepEqual(row.artifacts,row.fresh.artifacts,'incremental/fresh canonical byte agreement');save();console.log('E05 passed',row.name,elapsedMs,'ms',retainedProcesses.length,'processes');
   if(++cycle===edits.length){done=true;child.stdin.end(frame(0));continue;}
   clock=performance.now();for(const p of files){const next=edits[cycle].files[p]??originals[p];if(readFileSync(join(root,p),'utf8')!==next)writeFileSync(join(root,p),next);}
  }else throw Error('UnexpectedProtocolMessage:'+tag);
 }
 await closed;parser.finish();assert.ifError(spawnError);assert(!aborted);assert(done,'Missing cycles');assert.equal(exit.code,0);compiler.assertUnchanged();record.status='correctness pilot passed; sampling and Agent lock case remain';
}catch(error){record.status='failed';record.error=error.stack;throw error;}
finally{clearTimeout(timer);await retire(child,closed);for(const[p,body]of Object.entries(originals))writeFileSync(join(root,p),body);record.restored=files.every(p=>readFileSync(join(root,p),'utf8')===originals[p]);record.exit=exit;writeFileSync(join(out,'incremental.stderr'),stderr);record.stderrSha256=sha(stderr);save();console.log('E05 record',join(out,'result.json'));}
