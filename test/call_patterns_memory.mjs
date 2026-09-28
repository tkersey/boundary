// Native fresh-invocation and WASM checkpoint-cycle memory for P09 fixtures.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const [agent,runtimePath,control,candidate,output,native,fixture='variant-total']=process.argv.slice(2);
const {verifyRuntime,sha256}=await import(pathToFileURL(join(agent,'tools/agent4/dependencies.mjs')));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const fresh=async()=>{const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const rows=[];
for(const [name,first,second] of ((fixture==='constant'||fixture==='word')?[['first',true,false],['second',false,false]]:[['first',true,false],['second',false,true],['third',false,false]])){
 const args=Buffer.alloc(fixture==='word'?9:fixture==='constant'?17:18);args.writeBigUInt64LE(7n);if(fixture==='word'){args[8]=+first;}else{args.writeBigUInt64LE(11n,8);args[16]=+first;if(fixture!=='constant')args[17]=+second;}
 const row={name};let reference;
 for(const [arm,directory] of Object.entries({control,candidate})){
  const image=readFileSync(join(directory,`${fixture}-shared-semantic.bpi3`)),input=world.encodeInput({image,initialArgs:args}),inputPath=join(candidate,`memory-${name}-${arm}.pki3`);writeFileSync(inputPath,input);
  const nativeRun=spawnSync(native,[inputPath,'--statistics']);assert.equal(nativeRun.status,0,nativeRun.stderr.toString());const nativeStats=JSON.parse(nativeRun.stderr.toString());
  const k=await fresh(),whole=k.invoke(input),decoded=world.decodeOutcome(whole);assert.equal(decoded.kind,'completed');assert.deepEqual(Buffer.from(whole),nativeRun.stdout);if(reference)assert.deepEqual(Buffer.from(decoded.value),reference);else reference=Buffer.from(decoded.value);assert.equal(k.usage().workingLive,0n);
  const cycles=[];
  for(let repetition=0;repetition<3;repetition++){
   const kernel=await fresh();let state=world.decodeOutcome(kernel.invoke(world.encodeInput({image,initialArgs:args,quantum:1n}))),checkpointMax=0,steps=1;
   while(state.kind==='progressed'){assert(++steps<100);checkpointMax=Math.max(checkpointMax,state.state.length);state=world.decodeOutcome(kernel.invoke(world.encodeInput({image,state:state.state,quantum:1n})));}
   assert.equal(state.kind,'completed');assert.deepEqual(Buffer.from(state.value),reference);assert.equal(kernel.usage().workingLive,0n);cycles.push({peak:Number(kernel.usage().workingPeak),checkpointMax,invocations:steps});
  }
  row[arm]={imageSha256:sha256(image),native:nativeStats,wasmFreshPeak:Number(k.usage().workingPeak),wasmCycles:cycles};
 }
 rows.push(row);
}
const report={scope:'Native fresh invocation and three fresh WASM quantum-one cycles per path; working payload excludes host buffers/RSS',fixture,kernelSha256:runtime.kernelSha256,nativeSha256:sha256(readFileSync(native)),runnerSha256:sha256(readFileSync(new URL(import.meta.url))),rows};
writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(rows.map(r=>({path:r.name,native:[r.control.native.peakWorkingBytes,r.candidate.native.peakWorkingBytes],wasm:[r.control.wasmFreshPeak,r.candidate.wasmFreshPeak],checkpoint:[r.control.wasmCycles[0].checkpointMax,r.candidate.wasmCycles[0].checkpointMax]}))));
