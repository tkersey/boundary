import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const [agentRoot,runtimePath,corpus,output,emitter,baseCommit,native]=process.argv.slice(2);
const {verifyRuntime,sha256}=await import(pathToFileURL(join(agentRoot,'tools/agent4/dependencies.mjs')));
const {wasmtime}=await import(pathToFileURL(join(agentRoot,'test/agent4/independent/execute.mjs')));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const fresh=async()=>{const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const word=n=>{const b=Buffer.alloc(8);b.writeBigUInt64LE(BigInt(n));return b;};
function fixtures(name){
 if(['identity','ignored-peer','ignored-fault','configured'].includes(name))return [0,1].map(v=>({args:Buffer.from([v]),value:Buffer.from(name==='configured'?[v,1-v]:[v]),kind:'completed',yields:0}));
 if(name==='black-hole')return [{args:Buffer.alloc(0),value:Buffer.alloc(0),kind:'failed',yields:0}];
 const value=name.startsWith('memo-')?Buffer.concat((name==='memo-shared'?[1,1,1,1]:[1,1,2,2]).map(word)):word(name==='reentrant'?145:42);
 return [{args:Buffer.alloc(0),value,kind:'completed',yields:['reentrant','suspended'].includes(name)?1:0}];
}
function verify(out,expected){assert.equal(out.kind,expected.kind);assert.deepEqual(Buffer.from(out.value),expected.value);}
function continuation(image,out,quantum){assert(['progressed','yielded'].includes(out.kind));assert(out.state);return {image,state:out.state,control:out.kind==='yielded'?'resume_yield':'none',quantum};}
const rows=[];
for(const name of ['identity','ignored-peer','ignored-fault','reciprocal','suspended','configured','reentrant','memo-separate','memo-shared','black-hole']){
 const arms=name==='reentrant'?['structural','checked','shared-semantic']:['structural','checked','shared-semantic','linked'];
 const images=Object.fromEntries(arms.map(arm=>[arm,readFileSync(join(corpus,`${name}-${arm}.bpi3`))])),row={name,images:{},cases:[],sourceFreeExcluded:name==='reentrant'?'Original fresh-region write is rejected by existing component borrow-summary inference':null};
 for(const [arm,image]of Object.entries(images)){const k=await fresh(),p=k.prepare(image),usage=k.usage();row.images[arm]={bytes:image.length,sha256:sha256(image),admissionPeak:Number(usage.workingPeak),retained:Number(usage.workingLive)};k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);}
 for(const [index,fixture]of fixtures(name).entries()){
  const entry={input:fixture.args.toString('hex'),value:fixture.value.toString('hex'),kind:fixture.kind,yields:fixture.yields,arms:{}};
  for(const [arm,image]of Object.entries(images)){
   const k=await fresh();let invocation={image,initialArgs:fixture.args,quantum:64n},boundaries=0,yields=0,nativePeak=0;
   while(true){assert(boundaries<128);const input=world.encodeInput(invocation),bytes=k.invoke(input),out=world.decodeOutcome(bytes),path=join(corpus,`${name}-${arm}-${index}-${boundaries}.pki3`);writeFileSync(path,input);
    const actual=spawnSync(native,[path,'--statistics'],{timeout:30000});assert.equal(actual.status,0,actual.stderr.toString());assert.deepEqual(actual.stdout,Buffer.from(bytes));nativePeak=Math.max(nativePeak,JSON.parse(actual.stderr.toString()).peakWorkingBytes);
    const independent=wasmtime(runtime,path);assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(bytes));boundaries++;assert.equal(k.usage().workingLive,0n);
    if(out.kind==='completed'||out.kind==='failed'){verify(out,fixture);break;}yields+=+(out.kind==='yielded');invocation=continuation(image,out,64n);
   }assert.equal(yields,fixture.yields);
   const cycle=await fresh();let state=world.decodeOutcome(cycle.invoke(world.encodeInput({image,initialArgs:fixture.args,quantum:1n}))),steps=1,checkpointMax=0,cycleYields=0;
   while(state.kind==='progressed'||state.kind==='yielded'){assert(++steps<2048);checkpointMax=Math.max(checkpointMax,state.state.length);cycleYields+=+(state.kind==='yielded');state=world.decodeOutcome(cycle.invoke(world.encodeInput(continuation(image,state,1n))));}
   verify(state,fixture);assert.equal(cycleYields,fixture.yields);assert.equal(cycle.usage().workingLive,0n);
   entry.arms[arm]={boundaries,nativeChunkPeak:nativePeak,wasmChunkPeak:Number(k.usage().workingPeak),cyclePeak:Number(cycle.usage().workingPeak),checkpointMax,steps,yields:cycleYields};
  }row.cases.push(entry);
 }
 row.malformed=0;row.restores=0;row.wrongImages=0;
 for(const [arm,image]of Object.entries(images)){
  const fixture=fixtures(name)[0],k=await fresh(),bad=fixture.args.length?fixture.args.subarray(1):Buffer.from([0]);assert.throws(()=>k.invoke(world.encodeInput({image,initialArgs:bad})),{code:'WORLD_KERNEL_REJECTED'});row.malformed++;
  const p=k.prepare(image),session=k.start(p,fixture.args);assert.equal(world.decodeOutcome(k.drive(session,{quantum:1,checkpoint:true})).kind,'progressed');const checkpoint=k.checkpoint(session,{transfer:true});
  const other=await fresh(),otherImage=images[arm==='structural'?'shared-semantic':'structural'],otherPrepared=other.prepare(otherImage);
  if(sha256(image)!==sha256(otherImage)){assert.throws(()=>other.restore(otherPrepared,checkpoint),{code:'WORLD_KERNEL_REJECTED'});row.wrongImages++;}
  const restored=k.restore(p,checkpoint);let out=world.decodeOutcome(k.drive(restored,{})),yields=0;
  while(out.kind==='yielded'){assert(++yields<16);out=world.decodeOutcome(k.drive(restored,{control:'resume_yield'}));}
  verify(out,fixture);assert.equal(yields,fixture.yields);row.restores++;
  k.close(restored);k.releasePrepared(p);other.releasePrepared(otherPrepared);assert.equal(k.usage().workingLive,0n);assert.equal(other.usage().workingLive,0n);
 }rows.push(row);
}
const report={status:'complete',scope:'Generated identity, reciprocal/suspended control, ignored divergent peer/failing argument, two same-host-type configured emissions, reentrant force, shared/separate memo cells and authored busy-cell failure. Native/Node WASM/Wasmtime at every 64-step/public boundary; separate quantum-one cycles.',sourceBaseCommit:baseCommit,unpublishedWorkingTree:true,kernelSha256:runtime.kernelSha256,emitterSha256:sha256(readFileSync(emitter)),nativeSha256:sha256(readFileSync(native)),runnerSha256:sha256(readFileSync(new URL(import.meta.url))),rows};
writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({cases:rows.reduce((n,r)=>n+r.cases.length*Object.keys(r.images).length,0),boundaries:rows.reduce((n,r)=>n+r.cases.reduce((n,c)=>n+Object.values(c.arms).reduce((n,a)=>n+a.boundaries,0),0),0),malformed:rows.reduce((n,r)=>n+r.malformed,0),restores:rows.reduce((n,r)=>n+r.restores,0),wrongImages:rows.reduce((n,r)=>n+r.wrongImages,0)}));
