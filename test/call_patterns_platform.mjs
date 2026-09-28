import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const [agentRoot,runtimePath,corpusPath,outputPath,emitterPath,sourceCommit,mode]=process.argv.slice(2);
assert(sourceCommit&&/^[0-9a-f]{40}$/.test(sourceCommit));
const {verifyRuntime,sha256}=await import(pathToFileURL(join(agentRoot,'tools/agent4/dependencies.mjs')));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const {wasmtime}=await import(pathToFileURL(join(agentRoot,'test/agent4/independent/execute.mjs')));
const kernelBytes=readFileSync(runtime.kernelPath);
const fresh=async()=>{const k=await world.Kernel.create({bytes:kernelBytes,expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const variants=mode==='variants',constants=mode==='constants',wordMode=mode==='words',joins=mode==='joins'||mode==='recursive',recursive=mode==='recursive';assert(!mode||variants||constants||wordMode||joins);
const names=recursive?['recursive-checked','recursive-shared','recursive-linked']:joins?['join-checked','join-shared','join-linked']:wordMode?['word-checked','word-shared','word-linked']:constants?['constant-checked','constant-shared','constant-linked']:variants?['fallback','total','overwritten'].flatMap(kind=>['checked','shared','linked'].map(route=>`variant-${kind}-${route}`)):['callable-checked','callable-shared','callable-linked'];
function expectedOutcome(name,words,first,second){
 if(joins){const swapped=recursive?(!first||second):(first===second);const bytes=Buffer.alloc(16);bytes.writeBigUInt64LE(words[+swapped]);bytes.writeBigUInt64LE(words[+!swapped],8);return{kind:'completed',value:bytes};}
 if(variants&&!name.includes('-total-')&&!first&&!second)return{kind:'failed',value:Buffer.alloc(0)};
 const value=wordMode?BigInt.asUintN(64,first?words[0]:~words[0]):constants?(first?words[0]:words[1]):variants?(first||!second?words[0]:words[1]):BigInt.asUintN(64,first||second?words[0]|words[1]:(~words[0])|(~words[1]));
 const bytes=Buffer.alloc(8);bytes.writeBigUInt64LE(value);return{kind:'completed',value:bytes};
}
const rows=[];
for(const name of names){
 const images=Object.fromEntries(['structural','semantic'].map(arm=>[arm,readFileSync(join(corpusPath,`${name}-${arm}.bpi3`))]));
 assert.notEqual(sha256(images.structural),sha256(images.semantic),'actual record transformation required');
 let comparisons=0;
 for(const words of [[1n,2n],[0n,0n],[(1n<<64n)-1n,(1n<<64n)-1n]])for(const first of [false,true])for(const second of (wordMode?[false]:[false,true])){
  const args=Buffer.alloc(wordMode?9:constants?17:18);args.writeBigUInt64LE(words[0]);if(wordMode){args[8]=+first;}else{args.writeBigUInt64LE(words[1],8);args[16]=+first;if(!constants)args[17]=+second;}
  const expected=expectedOutcome(name,words,first,second);
  for(const arm of ['structural','semantic']){const k=await fresh(),input=world.encodeInput({image:images[arm],initialArgs:args}),bytes=k.invoke(input),out=world.decodeOutcome(bytes);assert.equal(out.kind,expected.kind);assert.deepEqual(Buffer.from(out.value),expected.value);const p=join(corpusPath,`${name}-${arm}-${comparisons}.pki3`);writeFileSync(p,input);const independent=wasmtime(runtime,p);assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(bytes));assert.equal(k.usage().workingLive,0n);comparisons++;}
 }
 const k=await fresh(),other=await fresh(),before=k.prepare(images.structural),after=other.prepare(images.semantic),args=Buffer.alloc(wordMode?9:constants?17:18),session=k.start(before,args);
 assert.equal(world.decodeOutcome(k.drive(session,{quantum:1,checkpoint:true})).kind,'progressed');
 const state=k.checkpoint(session,{transfer:true});assert.throws(()=>other.restore(after,state),{code:'WORLD_KERNEL_REJECTED'});
 const restored=k.restore(before,state),resumed=world.decodeOutcome(k.drive(restored,{}));const resumedExpected=expectedOutcome(name,[0n,0n],false,false);assert.equal(resumed.kind,resumedExpected.kind);assert.deepEqual(Buffer.from(resumed.value),resumedExpected.value);k.close(restored);k.releasePrepared(before);other.releasePrepared(after);assert.equal(k.usage().workingLive,0n);assert.equal(other.usage().workingLive,0n);
 for(const image of Object.values(images)){const bad=await fresh();assert.throws(()=>bad.invoke(world.encodeInput({image,initialArgs:Buffer.alloc(wordMode?8:constants?16:17)})),{code:'WORLD_KERNEL_REJECTED'});}
 rows.push({name,route:name.endsWith('-checked')?'standalone checked call patterns':name.endsWith('-linked')?'source-free semantic link':'shared semantic compiler',comparisons,malformedInputsRejected:2,sameImageRestore:true,wrongImageRejected:true,images:Object.fromEntries(Object.entries(images).map(([arm,bytes])=>[arm,{bytes:bytes.length,sha256:sha256(bytes)}]))});
}
writeFileSync(outputPath,JSON.stringify({sourceBaseCommit:sourceCommit,unpublishedWorkingTree:true,kernelSha256:runtime.kernelSha256,emitterSha256:sha256(readFileSync(emitterPath)),runnerSha256:sha256(readFileSync(new URL(import.meta.url))),rows},null,2)+'\n');console.log(JSON.stringify({cases:rows.length,comparisons:rows.reduce((n,r)=>n+r.comparisons,0),sameImageRestores:rows.length,wrongImageRejections:rows.length}));
