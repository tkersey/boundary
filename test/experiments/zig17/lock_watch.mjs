// Actual Agent lock mutation under the same pinned Linux watcher protocol.
import{spawn,spawnSync,execFileSync}from'node:child_process';
import{mkdirSync,readFileSync,writeFileSync,realpathSync}from'node:fs';
import{resolve,join}from'node:path';import assert from'node:assert/strict';import{createHash}from'node:crypto';
import{Frames,frame,completed,retire}from'./protocol_probe.mjs';import{selectZig}from'../../../tools/zig.mjs';
assert.equal(process.platform,'linux');assert.equal(process.arch,'x64');
const agent=realpathSync(process.argv[2]),compiler=selectZig([]),head=execFileSync('git',['rev-parse','HEAD'],{cwd:agent,encoding:'utf8'}).trim();
const out=resolve(process.env.RUNNER_TEMP,'zig17-lock-'+Date.now());mkdirSync(out);const root=join(out,'tree'),cache=join(out,'cache'),globalCache=join(out,'global'),prefix=join(out,'output'),reader=join(out,'reader');
const hash=b=>createHash('sha256').update(b).digest('hex');
const sync=(exe,args,options={})=>{const r=spawnSync(exe,args,{encoding:'utf8',timeout:600000,maxBuffer:16<<20,...options});assert.ifError(r.error);return r;};
let r=sync('git',['worktree','add','--detach',root,head],{cwd:agent});assert.equal(r.status,0,r.stderr);
const env={...compiler.env,ZIG_GLOBAL_CACHE_DIR:globalCache,ZIG_LOCAL_PKG_DIR:join(out,'packages')};r=sync(compiler.executable,['build-exe',resolve('test/experiments/zig17/build_config_reader.zig'),'-Odebug','-femit-bin='+reader],{env});assert.equal(r.status,0,r.stderr);
const lockPath=join(root,'conformance/agent4/dependencies.lock.json'),original=readFileSync(lockPath),lock=JSON.parse(original);lock.boundary.package.profiles['zig-managed'].inventorySha256='0'.repeat(64);const changed=JSON.stringify(lock)+'\n';
const result={experiment:'E05 actual Agent dependency-lock edit',agentSource:head,toolchain:compiler.identity,originalLockSha256:hash(original),changedLockSha256:hash(changed),watchEvents:[],watchDeadlineMs:20000};
const save=()=>writeFileSync(join(out,'result.json'),JSON.stringify(result,null,2)+'\n');save();
const args=['build','--listen=-','-fincremental','-Doptimize=debug','--cache-dir',cache,'--prefix',prefix,'-j2','--verbose'];result.command=[compiler.executable,...args];
const child=spawn(compiler.executable,args,{cwd:root,env,detached:true,stdio:['pipe','pipe','pipe']});let exit,spawnError;const closed=new Promise(resolve=>{child.once('error',e=>{spawnError=e;resolve()});child.once('close',(code,signal)=>{exit={code,signal};resolve()})});
let stderr='',graph,handshake=false,started=false,initial=true,editedAt,events=[],stopTimer,editTimer,stopped=false;
const stop=()=>{if(stopped)return;stopped=true;child.stdin.end(frame(0));};
const deadline=setTimeout(()=>{try{process.kill(-child.pid,'SIGKILL')}catch(e){if(e.code!=='ESRCH')throw e}},15*60*1000);
child.stdin.on('error',()=>{});child.stderr.on('data',b=>{stderr+=b;if(stderr.length>32<<20)stop()});const parser=new Frames();
try{
 for await(const chunk of child.stdout)for(const{tag,body}of parser.push(chunk)){
  if(!handshake){assert.equal(tag,0x80000000);assert.equal(body.readUInt32LE(0),1);assert(body.readUInt32LE(4)&1);handshake=true;continue;}
  if(tag===0x80000001){graph=JSON.parse(execFileSync(reader,[resolve(root,body.toString())],{encoding:'utf8',timeout:10000,maxBuffer:16<<20}));const selected=graph.steps.find(s=>s.kind==='top_level'&&s.name==='check-mobility-authoring')?.index;assert.notEqual(selected,undefined);const request=Buffer.alloc(12);request.writeUInt32LE(1,0);request.writeUInt32LE(1,4);request.writeUInt32LE(selected,8);child.stdin.write(frame(0x80000000,request));}
  else if(tag===0x80000002)throw Error('ConfigurationFailed');
  else if(tag===0x80000003){assert(!started);started=true;events=[];}
  else if(tag===0x80000005)assert(started);
  else if(tag===0x80000006){assert(started);events.push(completed(body,graph,[root,compiler.identity.library,cache,globalCache,root]));}
  else if(tag===0x80000004){assert(started);started=false;const row={afterEdit:editedAt!==undefined,elapsedAfterEditMs:editedAt===undefined?null:performance.now()-editedAt,events:events.map(e=>({...e,name:graph.steps[e.index].name,kind:graph.steps[e.index].kind}))};result.watchEvents.push(row);save();
   if(initial){for(const e of events)assert.equal(e.status,0,graph.steps[e.index].name);initial=false;editTimer=setTimeout(()=>{editedAt=performance.now();writeFileSync(lockPath,changed);result.editApplied=true;save();stopTimer=setTimeout(stop,20000)},1000);}
   else if(editedAt!==undefined&&events.some(e=>e.status===1)){result.watchRejected=true;stop();}
  }else throw Error('UnexpectedProtocolMessage');
 }
 await closed;parser.finish();assert.ifError(spawnError);assert(result.editApplied,'lock edit must occur');assert.equal(exit.code,0);await retire(child,closed);
 const plain=['build','check-mobility-authoring','-fno-incremental','-Doptimize=debug','--cache-dir',cache,'--prefix',prefix,'-j2','--summary','all'];r=sync(compiler.executable,plain,{cwd:root,env});writeFileSync(join(out,'fresh-reject.log'),r.stdout+r.stderr);result.fresh={command:[compiler.executable,...plain],status:r.status};assert.notEqual(r.status,0);assert.match(r.stderr,/Agent4DependencyMismatch: Boundary package inventory/);
 writeFileSync(lockPath,original);r=sync(compiler.executable,plain,{cwd:root,env});writeFileSync(join(out,'restored.log'),r.stdout+r.stderr);assert.equal(r.status,0,r.stderr);result.restoredBuildPassed=true;compiler.assertUnchanged();result.status=result.watchRejected?'passed':'failed-invalidation';if(!result.watchRejected)process.exitCode=1;
}catch(error){result.status='failed';result.error=error.stack;throw error;}
finally{clearTimeout(deadline);clearTimeout(stopTimer);clearTimeout(editTimer);await retire(child,closed);writeFileSync(lockPath,original);result.restored=hash(readFileSync(lockPath))===hash(original);result.exit=exit;writeFileSync(join(out,'watch.stderr'),stderr);save();console.log('E05 lock result',join(out,'result.json'),result.status);}
