import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
const [agent,runtimePath,corpus,reportPath,native,control]=process.argv.slice(2);
assert.equal(process.argv.length,8);
const {wasmtime}=await import(pathToFileURL(agent+'/test/agent4/independent/execute.mjs'));
const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
const runtime=verifyRuntime(runtimePath);
const world=await import(pathToFileURL(runtime.entrypoint));
const fresh=async()=>{const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const nat=n=>{const out=[];do{let byte=n&127;n>>>=7;out.push(byte|(n?128:0));}while(n);return Buffer.from(out);};
function input(family,n){
 const args=Buffer.alloc(family==='guarded'?32:24),expected=Buffer.alloc(8);args.writeBigUInt64LE(BigInt(n));
 let value=0n;
 if(family==='guarded'){args.writeBigUInt64LE(0x1234n,8);args.writeBigUInt64LE(0xabcn,16);args.writeBigUInt64LE(99n,24);value=n===0?99n:0x1234n^0xabcn;}
 else if(family==='counted'){args.writeBigUInt64LE(0x1234n,8);args.writeBigUInt64LE(0xabcn,16);if(n%2)value=0x1234n^0xabcn;}
 else{args.writeBigUInt64LE(3n,8);args.writeBigUInt64LE(0x1234n,16);for(let i=0;i<n;i++)value^=BigInt(i)^0x1234n;}
 expected.writeBigUInt64LE(value);return{args,expected};
}
const rows=[];
for(const family of ['counted','nested','guarded']) for(const n of [1,16,256,4096]){
 const {args,expected}=input(family,n),row={family,n,arms:{}};
 for(const arm of ['structural','control','semantic','linked']){
  const image=readFileSync(arm==='control'?`${control}/${family}-semantic.bpi3`:`${corpus}/${family}-${arm}.bpi3`),admit=await fresh(),prepared=admit.prepare(image),admission={peak:Number(admit.usage().workingPeak),retained:Number(admit.usage().workingLive)};admit.releasePrepared(prepared);assert.equal(admit.usage().workingLive,0n);
  const measurements={};for(const quantum of [null,64n]){
   const k=await fresh();let out=world.decodeOutcome(k.invoke(world.encodeInput({image,initialArgs:args,...(quantum?{quantum}:{})}))),boundaries=0,checkpointMax=0;
   while(out.kind==='progressed'){boundaries++;assert(boundaries<65536);checkpointMax=Math.max(checkpointMax,out.state.length);out=world.decodeOutcome(k.invoke(world.encodeInput({image,state:out.state,...(quantum?{quantum}:{})})));}
   assert.equal(out.kind,'completed');assert.deepEqual(Buffer.from(out.value),expected);assert.equal(k.usage().workingLive,0n);
   measurements[quantum?'cycle64':'fresh']={peak:Number(k.usage().workingPeak),boundaries,checkpointMax};
  }
  const k=await fresh(),other=await fresh(),p=k.prepare(image),session=k.start(p,args);
  assert.equal(world.decodeOutcome(k.drive(session,{quantum:1,checkpoint:true})).kind,'progressed');
  const checkpoint=k.checkpoint(session,{transfer:true});
  const otherImage=readFileSync(`${corpus}/${family}-${arm==='structural'?'semantic':'structural'}.bpi3`),otherPrepared=other.prepare(otherImage);
  assert.throws(()=>other.restore(otherPrepared,checkpoint),{code:'WORLD_KERNEL_REJECTED'});
  const restored=k.restore(p,checkpoint),completed=world.decodeOutcome(k.drive(restored,{}));
  assert.equal(completed.kind,'completed');assert.deepEqual(Buffer.from(completed.value),expected);
  k.close(restored);k.releasePrepared(p);other.releasePrepared(otherPrepared);
  assert.equal(k.usage().workingLive,0n);assert.equal(other.usage().workingLive,0n);
  assert.throws(()=>k.invoke(world.encodeInput({image,initialArgs:Buffer.concat([args,Buffer.from([255])])})),{code:'WORLD_KERNEL_REJECTED'});
  let invocation={image,initialArgs:args,quantum:n>256?4096n:64n},boundaries=0;
  while(true){
   const request=world.encodeInput(invocation),output=k.invoke(request),decoded=world.decodeOutcome(output),path=`${corpus}/${family}-${n}-${arm}-${boundaries}.pki3`;
   writeFileSync(path,request);
   const nativeResult=spawnSync(native,[path],{timeout:60000,maxBuffer:64<<20});
   assert.equal(nativeResult.status,0,nativeResult.stderr.toString());assert.deepEqual(nativeResult.stdout,Buffer.from(output));
   const independent=wasmtime(runtime,path);assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(output));
   assert(++boundaries<512);if(decoded.kind==='completed'){assert.deepEqual(Buffer.from(decoded.value),expected);break;}
   assert.equal(decoded.kind,'progressed');invocation={image,state:decoded.state,quantum:invocation.quantum};
  }
  row.arms[arm]={crossEngineBoundaries:boundaries,sameImageRestore:true,wrongImageRejected:true,malformedRejected:true,sha256:createHash('sha256').update(image).digest('hex'),bytes:image.length,admission,...measurements};
 }
 rows.push(row);console.log(JSON.stringify(row));
}
writeFileSync(reportPath,JSON.stringify({kernelSha256:runtime.kernelSha256,scope:'Native/Node/Wasmtime byte equality at quantum64 (length4096: quantum4096), fresh and quantum64 memory; same-image and wrong-image restoration; malformed inputs; no timings',rows},null,2)+'\n');
