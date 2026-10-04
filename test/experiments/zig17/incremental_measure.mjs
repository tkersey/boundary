import {spawn,spawnSync,execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,statSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {cpus,loadavg,release} from 'node:os';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {Frames,frame,completed,retire} from './protocol_probe.mjs';
import {selectZig} from '../../../tools/zig.mjs';
assert.equal(process.platform,'linux'); assert.equal(process.arch,'x64');
const windowIndex=Number(process.env.E05_WINDOW); assert(Number.isInteger(windowIndex)&&windowIndex>=0&&windowIndex<5);
const compiler=selectZig([]),head=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
const out=resolve(process.env.RUNNER_TEMP,`zig17-measured-${windowIndex}-${Date.now()}`); mkdirSync(out);
const hash=b=>createHash('sha256').update(b).digest('hex');
const cpu=()=>cpus().reduce((a,c)=>({idle:a.idle+c.times.idle,total:a.total+Object.values(c.times).reduce((x,y)=>x+y,0)}),{idle:0,total:0});
const sync=(exe,args,options={})=>{const r=spawnSync(exe,args,{encoding:'utf8',timeout:190000,maxBuffer:32<<20,...options});assert.ifError(r.error);return r};
const lanes=Object.fromEntries(['fresh','incremental'].map(name=>[name,{root:join(out,name+'-tree'),cache:join(out,name+'-cache'),global:join(out,name+'-global'),prefix:join(out,name+'-output')}]));
for(const lane of Object.values(lanes)){const r=sync('git',['worktree','add','--detach',lane.root,head]);assert.equal(r.status,0,r.stderr);for(const key of ['cache','global'])mkdirSync(lane[key]);}
const paths=['src/data/coalescing.zig','src/source.zig','build.zig','src/test_root.zig','test/v2/emit_economy.zig'];
const originals=Object.fromEntries(paths.map(p=>[p,readFileSync(join(lanes.fresh.root,p),'utf8')]));
const baseline={...originals};
baseline['build.zig']=baseline['build.zig'].replace('    const economy = b.step(', '    authoring.use_llvm = false;\n    authoring.use_lld = false;\n    const economy = b.step(').replace('    const economy_reuse = b.addSystemCommand(', '    economy_emitter.use_llvm = false;\n    economy_emitter.use_lld = false;\n    const economy_reuse = b.addSystemCommand(');
const backendAssert='\ncomptime { if (@import("builtin").zig_backend != .stage2_x86_64) @compileError("E05 requires the same explicit x86 backend"); }\n';
for(const p of ['src/test_root.zig','test/v2/emit_economy.zig'])baseline[p]+=backendAssert;
function install(lane,files){for(const p of paths)if(readFileSync(join(lane.root,p),'utf8')!==files[p])writeFileSync(join(lane.root,p),files[p]);}
function identities(files){return Object.fromEntries(paths.map(p=>[p,hash(files[p])]));}
for(const lane of Object.values(lanes))install(lane,baseline);
function edit(category,n){const s={...baseline};let from,to,p;
 if(category==='optimizer'){p='src/data/coalescing.zig';from='fn mapHasMerge(map: []const @import("program.zig").Id) bool {';to=from+`\n    const edit_marker: usize = ${n};\n    if (edit_marker == 0) return false;`;}
 else if(category==='authoring'){p='src/source.zig';from='return self.arena.allocator();';to=`const edit_marker: usize = ${n};\n        if (edit_marker == 0) unreachable;\n        return self.arena.allocator();`;}
 else if(category==='type'){p='src/data/coalescing.zig';from='pub const Options = struct {';to=from+`\n    incremental_probe: [${n}]u8 = @splat(0),`;}
 else{assert.equal(category,'configuration');p='build.zig';from='"Check code and constant sharing and emit executable economy workloads"';to=`"Check code and constant sharing and emit executable economy workloads (edit ${n})"`;}
 assert(s[p].includes(from));s[p]=s[p].replace(from,to);return s;
}
const reader=join(out,'reader'),readerArgs=['build-exe',resolve('test/experiments/zig17/build_config_reader.zig'),'-Osafe','-femit-bin='+reader,'--cache-dir',join(out,'reader-cache'),'--global-cache-dir',join(out,'reader-global')];
let r=sync(compiler.executable,readerArgs,{env:compiler.env});assert.equal(r.status,0,r.stderr);
const readArtifacts=lane=>Object.fromEntries([0,1,8,64].map(n=>{const bytes=readFileSync(join(lane.prefix,`economy-${n}.bpi3`));return[n,{bytes:bytes.length,sha256:hash(bytes)}]}));
const family=pid=>{const rows=execFileSync('ps',['-eo','pid=,ppid=,rss=,comm='],{encoding:'utf8'}).trim().split('\n').map(line=>{const m=line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/);return m&&{pid:+m[1],parent:+m[2],rssBytes:+m[3]*1024,command:m[4]}}).filter(Boolean);const ids=new Set([pid]);for(let changed=true;changed;){changed=false;for(const row of rows)if(ids.has(row.parent)&&!ids.has(row.pid)){ids.add(row.pid);changed=true;}}return rows.filter(row=>ids.has(row.pid)).map(row=>{try{const s=readFileSync(`/proc/${row.pid}/stat`,'utf8'),f=s.slice(s.lastIndexOf(')')+2).split(' ');return{...row,ticks:[11,12,13,14].map(i=>Number(f[i]))}}catch{return{...row,ticks:null}}});};
const record={experiment:'E05',status:'running',window:windowIndex,source:head,toolchain:compiler.identity,host:{cpu:cpus()[0].model,cpuFlags:readFileSync('/proc/cpuinfo','utf8').split('\n').find(line=>line.startsWith('flags'))??null,os:release(),node:process.version,clockTicksPerSecond:Number(execFileSync('getconf',['CLK_TCK'],{encoding:'utf8'}))},backend:'stage2_x86_64; explicitly forced for both native artifacts and asserted at comptime',mode:'debug',regime:'Separate disposable worktrees with equal tracked contents and separate initially empty project/global caches. Both lanes are explicitly primed. Same unique edit content in each pair. Alternating order by window and sample; three warmups and nine measured edits per category. No network is included. No OS cache flush.',baseline:identities(baseline),primes:{},rows:[],incidentalCycles:[]};
const save=()=>writeFileSync(join(out,'result.json'),JSON.stringify(record,null,2)+'\n');save();console.log('E05 measurement',windowIndex,out);
const lane=lanes.incremental,env={...compiler.env,LC_ALL:'C',ZIG_GLOBAL_CACHE_DIR:lane.global};
const args=['build','--listen=-','-fincremental','-Doptimize=debug','--cache-dir',lane.cache,'--prefix',lane.prefix,'-j2','--verbose'];
const child=spawn(compiler.executable,args,{cwd:lane.root,env,detached:true,stdio:['pipe','pipe','pipe']});
let exit,spawnError;const closed=new Promise(resolve=>{child.once('error',e=>{spawnError=e;resolve()});child.once('close',(code,signal)=>{exit={code,signal};resolve()})});
let stderr='',graph,graphHash,selected,handshake=false,started=false,events=[],problem,waiting;const queue=[],statuses=new Map();
const fail=error=>{problem??=error;if(waiting){waiting.reject(problem);waiting=null;}};
const parser=new Frames();child.stdin.on('error',()=>{});child.stderr.on('data',b=>{stderr+=b;if(stderr.length>32<<20)fail(Error('DiagnosticLimit'))});
child.stdout.on('data',bytes=>{try{for(const{tag,body}of parser.push(bytes)){
 if(!handshake){assert.equal(tag,0x80000000);assert.equal(body.readUInt32LE(0),1);assert(body.readUInt32LE(4)&1);handshake=true;continue;}
 if(tag===0x80000001){graphHash=hash(readFileSync(resolve(lane.root,body.toString())));graph=JSON.parse(execFileSync(reader,[resolve(lane.root,body.toString())],{encoding:'utf8',timeout:10000,maxBuffer:16<<20}));statuses.clear();selected=graph.steps.find(s=>s.kind==='top_level'&&s.name==='check-economy')?.index;assert.notEqual(selected,undefined);const request=Buffer.alloc(12);request.writeUInt32LE(1);request.writeUInt32LE(1,4);request.writeUInt32LE(selected,8);child.stdin.write(frame(0x80000000,request));}
 else if(tag===0x80000002)throw Error('ConfigurationFailed');
 else if(tag===0x80000003){assert(!started);started=true;events=[];}
 else if(tag===0x80000005)assert(started);
 else if(tag===0x80000006){assert(started);events.push(completed(body,graph,[lane.root,compiler.identity.library,lane.cache,lane.global,lane.root]));}
 else if(tag===0x80000004){assert(started);started=false;for(const e of events)statuses.set(e.index,e.status);const closure=new Set();const visit=i=>{if(closure.has(i))return;closure.add(i);for(const d of graph.steps[i].dependencies)visit(d)};visit(selected);for(const i of closure)assert.equal(statuses.get(i),0,'step '+graph.steps[i].name);const row={configurationSha256:graphHash,events:events.map(e=>({...e,name:graph.steps[e.index].name,kind:graph.steps[e.index].kind}))};if(waiting){const w=waiting;waiting=null;w.resolve(row)}else{assert(queue.length<128);queue.push(row)}}else throw Error('UnknownProtocolMessage');
}}catch(error){fail(error)}});
child.once('close',()=>{if(waiting)fail(Error('WatcherClosedBeforeResult'))});
async function next(){if(problem)throw problem;if(queue.length)return queue.shift();let timer;try{return await new Promise((resolve,reject)=>{waiting={resolve,reject};timer=setTimeout(()=>fail(Error('EditTimeout')),180000)})}finally{clearTimeout(timer)}}
async function nextCompile(){for(;;){const row=await next();if(row.events.some(e=>e.kind==='compile'))return row;record.incidentalCycles.push(row);assert(record.incidentalCycles.length<1024);}}
const kill=()=>{if(child.pid)try{process.kill(-child.pid,'SIGKILL')}catch(e){if(e.code!=='ESRCH')throw e}};
const deadline=setTimeout(()=>{fail(Error('ExperimentTimeout'));kill()},40*60*1000);
let expected;
function checked(lane){const artifacts=readArtifacts(lane);expected??=artifacts;assert.deepEqual(artifacts,expected,'canonical outputs and native tests must preserve observations');return artifacts;}
function fresh(files,label){const l=lanes.fresh;install(l,files);const args=['-v','timeout','--kill-after=5s','180s',compiler.executable,'build','check-economy','-fno-incremental','-Doptimize=debug','--cache-dir',l.cache,'--prefix',l.prefix,'-j2','--verbose','--summary','all'];const start=performance.now();const r=sync('/usr/bin/time',args,{cwd:l.root,env:{...compiler.env,LC_ALL:'C',ZIG_GLOBAL_CACHE_DIR:l.global}});const log=r.stdout+r.stderr;writeFileSync(join(out,label+'-fresh.log'),log);assert.equal(r.status,0,r.stderr.slice(-2500));const artifacts=checked(l),elapsedMs=performance.now()-start;return{elapsedMs,command:['/usr/bin/time',...args],artifacts,logSha256:hash(log),peakRssBytes:Number(log.match(/Maximum resident set size \(kbytes\): (\d+)/)?.[1])*1024,userSeconds:Number(log.match(/User time \(seconds\): ([\d.]+)/)?.[1]),systemSeconds:Number(log.match(/System time \(seconds\): ([\d.]+)/)?.[1])};}
async function incremental(files){const before=family(child.pid),start=performance.now();install(lane,files);const cycle=await nextCompile(),artifacts=checked(lane),elapsedMs=performance.now()-start;return{elapsedMs,beforeProcesses:before,retainedProcesses:family(child.pid),artifacts,...cycle};}
try{
 const primeStart=performance.now();const initial=await nextCompile();record.primes.incremental={elapsedMs:performance.now()-primeStart,artifacts:checked(lane),retainedProcesses:family(child.pid),...initial};record.primes.fresh=fresh(baseline,'prime');save();
 const before={cpu:cpu(),load:loadavg()};
 for(const category of ['optimizer','authoring','type','configuration'])for(let sample=0;sample<12;sample++){
  const number=windowIndex*100+sample+1,files=edit(category,number),order=(windowIndex+sample)%2?['fresh','incremental']:['incremental','fresh'],arms={};
  for(const arm of order)arms[arm]=arm==='fresh'?fresh(files,`${category}-${sample}`):await incremental(files);
  for(const p of paths)assert.equal(readFileSync(join(lanes.fresh.root,p),'utf8'),readFileSync(join(lane.root,p),'utf8'));
  record.rows.push({category,sample,warmup:sample<3,order,sourceFiles:identities(files),arms});save();console.log('E05 paired',windowIndex,category,sample);
 }
 record.restoration={incremental:await incremental(baseline),fresh:fresh(baseline,'restored')};const after={cpu:cpu(),load:loadavg()};record.hostObservation={before,after,idleFraction:(after.cpu.idle-before.cpu.idle)/(after.cpu.total-before.cpu.total)};
 child.stdin.end(frame(0));await closed;parser.finish();assert.ifError(spawnError);assert.ifError(problem);assert.equal(exit.code,0);compiler.assertUnchanged();record.status='measured-and-correct';
}catch(error){record.status='failed';record.error=error.stack;throw error;}
finally{clearTimeout(deadline);await retire(child,closed);for(const l of Object.values(lanes))install(l,originals);record.originalsRestored=Object.values(lanes).every(l=>paths.every(p=>readFileSync(join(l.root,p),'utf8')===originals[p]));record.exit=exit;writeFileSync(join(out,'incremental.stderr'),stderr);record.stderrSha256=hash(stderr);record.cacheDiskKiB=Object.fromEntries(Object.entries(lanes).map(([name,l])=>[name,execFileSync('du',['-sk',l.cache,l.global],{encoding:'utf8'}).trim()]));save();console.log('E05 finished',windowIndex,record.status,out);}
