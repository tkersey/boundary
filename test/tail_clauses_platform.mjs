import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const [agentRoot,runtimePath,corpus,output,emitter,baseCommit]=process.argv.slice(2);
const {verifyRuntime,sha256}=await import(pathToFileURL(join(agentRoot,'tools/agent4/dependencies.mjs')));
const {wasmtime}=await import(pathToFileURL(join(agentRoot,'test/agent4/independent/execute.mjs')));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const kernelBytes=readFileSync(runtime.kernelPath),fresh=async()=>{const k=await world.Kernel.create({bytes:kernelBytes,expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const rows=[];
for(const name of ['tail-checked','tail-shared','tail-linked']){
 const images=Object.fromEntries(['structural','semantic'].map(arm=>[arm,readFileSync(join(corpus,name+'-'+arm+'.bpi3'))]));let comparisons=0,malformed=0;
 for(const value of [0n,7n,(1n<<64n)-1n])for(const arm of ['structural','semantic']){
  const args=Buffer.alloc(8);args.writeBigUInt64LE(value);const k=await fresh(),input=world.encodeInput({image:images[arm],initialArgs:args}),bytes=k.invoke(input),result=world.decodeOutcome(bytes);
  assert.equal(result.kind,'completed');assert.equal(Buffer.from(result.value).readBigUInt64LE(),BigInt.asUintN(64,~value));
  const path=join(corpus,`${name}-${arm}-${comparisons}.pki3`);writeFileSync(path,input);const independent=wasmtime(runtime,path);assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(bytes));assert.equal(k.usage().workingLive,0n);comparisons++;
 }
 for(const arm of ['structural','semantic']){const k=await fresh();assert.throws(()=>k.invoke(world.encodeInput({image:images[arm],initialArgs:Buffer.alloc(7)})),{code:'WORLD_KERNEL_REJECTED'});malformed++;}
 const k=await fresh(),other=await fresh(),before=k.prepare(images.structural),after=other.prepare(images.semantic),session=k.start(before,Buffer.alloc(8));
 assert.equal(world.decodeOutcome(k.drive(session,{quantum:1,checkpoint:true})).kind,'progressed');const state=k.checkpoint(session,{transfer:true});
 assert.throws(()=>other.restore(after,state),{code:'WORLD_KERNEL_REJECTED'});const restored=k.restore(before,state),result=world.decodeOutcome(k.drive(restored,{}));assert.equal(result.kind,'completed');assert.equal(Buffer.from(result.value).readBigUInt64LE(),(1n<<64n)-1n);
 k.close(restored);k.releasePrepared(before);other.releasePrepared(after);assert.equal(k.usage().workingLive,0n);assert.equal(other.usage().workingLive,0n);
 rows.push({name,comparisons,malformedInputsRejected:malformed,sameImageRestore:true,wrongImageRejected:true,images:Object.fromEntries(Object.entries(images).map(([key,bytes])=>[key,{bytes:bytes.length,sha256:sha256(bytes)}]))});
}
const report={sourceBaseCommit:baseCommit,unpublishedWorkingTree:true,kernelSha256:runtime.kernelSha256,emitterSha256:sha256(readFileSync(emitter)),runnerSha256:sha256(readFileSync(new URL(import.meta.url))),rows};writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({comparisons:rows.reduce((n,r)=>n+r.comparisons,0),malformed:rows.reduce((n,r)=>n+r.malformedInputsRejected,0),restores:rows.length,wrongImage:rows.length}));
