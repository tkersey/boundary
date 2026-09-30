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
 if(name.startsWith('argument-'))return [0n,1n,0xffffffffffffffffn].flatMap(word=>[false,true].flatMap(flag=>{const callable=name.startsWith('argument-callable');if(callable&&!flag&&word!==0n)return [];const args=Buffer.alloc(9),expected=Buffer.alloc(8);if(callable){args[0]=Number(flag);args.writeBigUInt64LE(word,1);}else{args.writeBigUInt64LE(word);args[8]=Number(flag);}expected.writeBigUInt64LE(callable||name==='argument-variant_after'?0n:word);return [{args,expected}];}));
 if(name.startsWith('capture-'))return [[0n,0n,0n,0n],[1n,2n,4n,8n],[0x123456789abcdef0n,0xfedcba9876543210n,0xffffffffffffffffn,23n]].flatMap(words=>[false,true].map(rotate=>{const args=Buffer.alloc(33);words.forEach((word,index)=>args.writeBigUInt64LE(word,index*8));args[32]=Number(rotate);const expected=Buffer.alloc(8);expected.writeBigUInt64LE(rotate?words[1]^words[2]:words[0]^words[1]);return {args,expected};}));
 if(name==='empty')return [0n,7n,(1n<<64n)-1n].map(value=>{const args=Buffer.alloc(16);args.writeBigUInt64LE(value);args.writeBigUInt64LE(42n,8);return {args,expected:args.subarray(0,8)};});
 const width=name==='empty-composed'?3:4;
 return Array.from({length:1<<width},(_,i)=>{const args=Buffer.from(Array.from({length:width},(_,j)=>(i>>j)&1));
  if(width===3)return {args,expected:Buffer.from([(args[0]|args[2])^args[1]])};
  const [left,right,first,second]=args,one=first?left:right,two=second?left:right;
  return {args,expected:Buffer.from([name.startsWith('reader-composed')?(one|right)^left:one,two])};
 });
}
const rows=[];
for(const name of ['empty','empty-composed','reader','reader-composed','reader-reversed','reader-composed-reversed','capture-closure','capture-indirect','capture-worker','capture-before','capture-after','argument-callable','argument-callable_compatible','argument-callable_indirect','argument-callable_after','argument-callable_multiple','argument-callable_multiple_compatible','argument-variant','argument-variant_compatible','argument-variant_indirect','argument-variant_after']){
 const arms=name.startsWith('capture-')?['structural','shared-semantic','linked']:['structural','checked','shared-semantic','linked'];
 const images=Object.fromEntries(arms.map(arm=>[arm,readFileSync(join(corpus,`${name}-${arm}.bpi3`))]));
 const row={name,images:{},cases:[]};
 for(const [arm,image] of Object.entries(images)){
  const k=await fresh(),prepared=k.prepare(image),usage=k.usage();
  row.images[arm]={bytes:image.length,sha256:sha256(image),admissionPeak:Number(usage.workingPeak),retained:Number(usage.workingLive)};
  k.releasePrepared(prepared);assert.equal(k.usage().workingLive,0n);
 }
 for(const [index,{args,expected}] of fixtures(name).entries()){
  const entry={input:args.toString('hex'),expected:expected.toString('hex'),arms:{}};
  for(const [arm,image]of Object.entries(images)){
   const k=await fresh(),input=world.encodeInput({image,initialArgs:args}),bytes=k.invoke(input),result=world.decodeOutcome(bytes);
   assert.equal(result.kind,'completed');assert.deepEqual(Buffer.from(result.value),expected);assert.equal(k.usage().workingLive,0n);
   const path=join(corpus,`${name}-${arm}-${index}.pki3`);writeFileSync(path,input);
   const nativeResult=spawnSync(native,[path,'--statistics']);assert.equal(nativeResult.status,0,nativeResult.stderr.toString());assert.deepEqual(nativeResult.stdout,Buffer.from(bytes));
   const independent=wasmtime(runtime,path);assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(bytes));
   const cycle=await fresh();let state=world.decodeOutcome(cycle.invoke(world.encodeInput({image,initialArgs:args,quantum:1n}))),steps=1,checkpointMax=0;
   while(state.kind==='progressed'){assert(++steps<128);checkpointMax=Math.max(checkpointMax,state.state.length);state=world.decodeOutcome(cycle.invoke(world.encodeInput({image,state:state.state,quantum:1n})));}
   assert.equal(state.kind,'completed');assert.deepEqual(Buffer.from(state.value),expected);assert.equal(cycle.usage().workingLive,0n);
   entry.arms[arm]={native:JSON.parse(nativeResult.stderr.toString()),wasmFreshPeak:Number(k.usage().workingPeak),cyclePeak:Number(cycle.usage().workingPeak),checkpointMax,steps};
  }
  row.cases.push(entry);
 }
 let malformed=0,restores=0,wrongImages=0;
 for(const [arm,image]of Object.entries(images)){
  const {args,expected}=fixtures(name)[0],k=await fresh();assert.throws(()=>k.invoke(world.encodeInput({image,initialArgs:args.subarray(1)})),{code:'WORLD_KERNEL_REJECTED'});malformed++;
  const prepared=k.prepare(image),session=k.start(prepared,args);assert.equal(world.decodeOutcome(k.drive(session,{quantum:1,checkpoint:true})).kind,'progressed');
  const state=k.checkpoint(session,{transfer:true}),other=await fresh(),otherImage=images[arm==='structural'?'shared-semantic':'structural'],otherPrepared=other.prepare(otherImage);
  if(sha256(image)!==sha256(otherImage)){assert.throws(()=>other.restore(otherPrepared,state),{code:'WORLD_KERNEL_REJECTED'});wrongImages++;}
  const restored=k.restore(prepared,state),result=world.decodeOutcome(k.drive(restored,{}));assert.equal(result.kind,'completed');assert.deepEqual(Buffer.from(result.value),expected);restores++;
  k.close(restored);k.releasePrepared(prepared);other.releasePrepared(otherPrepared);assert.equal(k.usage().workingLive,0n);assert.equal(other.usage().workingLive,0n);
 }
 row.malformed=malformed;row.restores=restores;row.wrongImages=wrongImages;rows.push(row);
}
const report={status:'complete',scope:'All prior handler/Reader/capture cases retained. Ten argument-retention cases cover callable/variant carriers, narrow/permitting bounds, multiple captures, indirect effects and effects after last use. Three u64 values and both flags where terminating; the native Zig harness separately checks bounded nontermination. Native, Node WASM, Wasmtime, and quantum-one same-image checkpoints.',sourceBaseCommit:baseCommit,unpublishedWorkingTree:true,kernelSha256:runtime.kernelSha256,emitterSha256:sha256(readFileSync(emitter)),nativeSha256:sha256(readFileSync(native)),runnerSha256:sha256(readFileSync(new URL(import.meta.url))),rows};
writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({comparisons:rows.reduce((n,r)=>n+r.cases.length*Object.keys(r.images).length,0),malformed:rows.reduce((n,r)=>n+r.malformed,0),restores:rows.reduce((n,r)=>n+r.restores,0),wrongImages:rows.reduce((n,r)=>n+r.wrongImages,0)}));
