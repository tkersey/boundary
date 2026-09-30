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
function fixtures(name){
 if(name==='unfold')return [0,1].flatMap(state=>[0,1].map(seed=>({args:Buffer.from([state,seed]),kind:'completed',value:Buffer.from([1-seed])})));
 if(name==='map-failure-order')return [{args:Buffer.from([2,0,1,1]),kind:'failed',value:Buffer.from([1])}];
 if(name==='map-fold-wide')return [32,64,128].map(n=>({args:Buffer.from([...(n<128?[n]:[128,1]),...Array(n).fill(1),1]),kind:'completed',value:Buffer.from([1])}));
 const cases=[];for(let n=0;n<=4;n++)for(let bits=0;bits<1<<n;bits++)for(let seed=0;seed<2;seed++){
  const values=Array.from({length:n},(_,i)=>(bits>>i)&1);cases.push({args:Buffer.from([n,...values,seed]),kind:'completed',value:Buffer.from([values.reduce((a,b)=>a&b,seed)])});
 }return cases;
}
function verify(result,fixture){assert.equal(result.kind,fixture.kind);const value=result.value;assert.deepEqual(Buffer.from(value),fixture.value);}
const rows=[];
for(const name of ['map-fold','map-fold-wide','unfold','map-failure-order']){
 const images=Object.fromEntries(['structural','checked','shared-semantic','linked'].map(arm=>[arm,readFileSync(join(corpus,`${name}-${arm}.bpi3`))]));
 const row={name,images:{},cases:[]};
 for(const [arm,image]of Object.entries(images)){
  const k=await fresh(),prepared=k.prepare(image),usage=k.usage();row.images[arm]={bytes:image.length,sha256:sha256(image),admissionPeak:Number(usage.workingPeak),retained:Number(usage.workingLive)};
  k.releasePrepared(prepared);assert.equal(k.usage().workingLive,0n);
 }
 for(const [index,fixture]of fixtures(name).entries()){
  const entry={input:fixture.args.toString('hex'),kind:fixture.kind,value:fixture.value.toString('hex'),arms:{}};
  for(const [arm,image]of Object.entries(images)){
   const k=await fresh(),input=world.encodeInput({image,initialArgs:fixture.args}),bytes=k.invoke(input),result=world.decodeOutcome(bytes);verify(result,fixture);assert.equal(k.usage().workingLive,0n);
   const path=join(corpus,`${name}-${arm}-${index}.pki3`);writeFileSync(path,input);
   const nativeRun=spawnSync(native,[path,'--statistics']);assert.equal(nativeRun.status,0,nativeRun.stderr.toString());assert.deepEqual(nativeRun.stdout,Buffer.from(bytes));
   const independent=wasmtime(runtime,path);assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(bytes));
   const cycle=await fresh();let state=world.decodeOutcome(cycle.invoke(world.encodeInput({image,initialArgs:fixture.args,quantum:1n}))),steps=1,checkpointMax=0;
   while(state.kind==='progressed'){assert(++steps<4096);checkpointMax=Math.max(checkpointMax,state.state.length);state=world.decodeOutcome(cycle.invoke(world.encodeInput({image,state:state.state,quantum:1n})));}
   verify(state,fixture);assert.equal(cycle.usage().workingLive,0n);
   entry.arms[arm]={native:JSON.parse(nativeRun.stderr.toString()),wasmFreshPeak:Number(k.usage().workingPeak),cyclePeak:Number(cycle.usage().workingPeak),checkpointMax,steps};
  }row.cases.push(entry);
 }
 row.malformed=0;row.restores=0;row.wrongImages=0;
 for(const [arm,image]of Object.entries(images)){
  const fixture=fixtures(name)[0],k=await fresh();assert.throws(()=>k.invoke(world.encodeInput({image,initialArgs:fixture.args.subarray(1)})),{code:'WORLD_KERNEL_REJECTED'});row.malformed++;
  if(name==='map-fold'){assert.throws(()=>k.invoke(world.encodeInput({image,initialArgs:Buffer.from([5,1,1,1,1,1,1])})),{code:'WORLD_KERNEL_REJECTED'});row.malformed++;}
  const prepared=k.prepare(image),session=k.start(prepared,fixture.args);assert.equal(world.decodeOutcome(k.drive(session,{quantum:1,checkpoint:true})).kind,'progressed');
  const state=k.checkpoint(session,{transfer:true}),other=await fresh(),otherImage=images[arm==='structural'?'shared-semantic':'structural'],otherPrepared=other.prepare(otherImage);
  if(sha256(image)!==sha256(otherImage)){assert.throws(()=>other.restore(otherPrepared,state),{code:'WORLD_KERNEL_REJECTED'});row.wrongImages++;}
  const restored=k.restore(prepared,state);verify(world.decodeOutcome(k.drive(restored,{})),fixture);row.restores++;
  k.close(restored);k.releasePrepared(prepared);other.releasePrepared(otherPrepared);assert.equal(k.usage().workingLive,0n);assert.equal(other.usage().workingLive,0n);
 }rows.push(row);
}
const report={status:'complete',scope:'All Boolean vectors of length 0..4 and seeds; 32/64/128-element map/fold samples; all Boolean unfold states/seeds; late mapper versus early folder failure. Native/Node WASM/Wasmtime plus quantum-one checkpoint cycles.',sourceBaseCommit:baseCommit,unpublishedWorkingTree:true,kernelSha256:runtime.kernelSha256,emitterSha256:sha256(readFileSync(emitter)),nativeSha256:sha256(readFileSync(native)),runnerSha256:sha256(readFileSync(new URL(import.meta.url))),rows};
writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({comparisons:rows.reduce((n,r)=>n+r.cases.length*4,0),malformed:rows.reduce((n,r)=>n+r.malformed,0),restores:rows.reduce((n,r)=>n+r.restores,0),wrongImages:rows.reduce((n,r)=>n+r.wrongImages,0)}));
