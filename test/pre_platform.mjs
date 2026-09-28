import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const [agentRoot,runtimePath,corpusPath,outputPath,emitterPath,sourceCommit]=process.argv.slice(2);
assert(sourceCommit&&/^[0-9a-f]{40}$/.test(sourceCommit));
const {verifyRuntime,sha256}=await import(pathToFileURL(join(agentRoot,'tools/agent4/dependencies.mjs')));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const {wasmtime}=await import(pathToFileURL(join(agentRoot,'test/agent4/independent/execute.mjs')));
const kernelBytes=readFileSync(runtime.kernelPath);
const fresh=async()=>{const k=await world.Kernel.create({bytes:kernelBytes,expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const rows=[];
for(const name of ['critical-checked','live-shared','live-linked']){
 const images=Object.fromEntries(['structural','semantic'].map(arm=>[arm,readFileSync(join(corpusPath,`${name}-${arm}.bpi3`))]));
 assert.notEqual(sha256(images.structural),sha256(images.semantic),'actual record transformation required');
 let comparisons=0;
 for(const words of [[1n,2n],[0n,0n],[(1n<<64n)-1n,(1n<<64n)-1n]])for(const first of [false,true])for(const second of [false,true]){
  const args=Buffer.alloc(18);args.writeBigUInt64LE(words[0]);args.writeBigUInt64LE(words[1],8);args[16]=+first;args[17]=+second;
  const expected=name==='critical-checked'?Buffer.alloc(8):Buffer.from([+(first&&words[0]!==words[1]?second:words[0]===words[1])]);
  if(name==='critical-checked')expected.writeBigUInt64LE(first||second?words[0]^words[1]:words[0]);
  for(const arm of ['structural','semantic']){const k=await fresh(),input=world.encodeInput({image:images[arm],initialArgs:args}),bytes=k.invoke(input),out=world.decodeOutcome(bytes);assert.equal(out.kind,'completed');assert.deepEqual(Buffer.from(out.value),expected);const p=join(corpusPath,`${name}-${arm}-${comparisons}.pki3`);writeFileSync(p,input);const independent=wasmtime(runtime,p);assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(bytes));assert.equal(k.usage().workingLive,0n);comparisons++;}
 }
 const k=await fresh(),other=await fresh(),before=k.prepare(images.structural),after=other.prepare(images.semantic),args=Buffer.alloc(18),session=k.start(before,args);
 assert.equal(world.decodeOutcome(k.drive(session,{quantum:1,checkpoint:true})).kind,'progressed');
 const state=k.checkpoint(session,{transfer:true});assert.throws(()=>other.restore(after,state),{code:'WORLD_KERNEL_REJECTED'});
 const restored=k.restore(before,state),resumed=world.decodeOutcome(k.drive(restored,{}));assert.equal(resumed.kind,'completed');assert.deepEqual(Buffer.from(resumed.value),name==='critical-checked'?Buffer.alloc(8):Buffer.from([1]));k.close(restored);k.releasePrepared(before);other.releasePrepared(after);assert.equal(k.usage().workingLive,0n);assert.equal(other.usage().workingLive,0n);
 for(const image of Object.values(images)){const bad=await fresh();assert.throws(()=>bad.invoke(world.encodeInput({image,initialArgs:Buffer.alloc(17)})),{code:'WORLD_KERNEL_REJECTED'});}
 rows.push({name,route:name==='critical-checked'?'standalone checked PRE':name==='live-linked'?'source-free semantic link':'shared semantic compiler',comparisons,malformedInputsRejected:2,sameImageRestore:true,wrongImageRejected:true,images:Object.fromEntries(Object.entries(images).map(([arm,bytes])=>[arm,{bytes:bytes.length,sha256:sha256(bytes)}]))});
}
writeFileSync(outputPath,JSON.stringify({sourceCommit,kernelSha256:runtime.kernelSha256,emitterSha256:sha256(readFileSync(emitterPath)),runnerSha256:sha256(readFileSync(new URL(import.meta.url))),rows},null,2)+'\n');console.log(JSON.stringify({cases:rows.length,comparisons:rows.reduce((n,r)=>n+r.comparisons,0),sameImageRestores:rows.length,wrongImageRejections:rows.length}));
