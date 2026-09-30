import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [agent,runtimePath,corpus,output,control]=process.argv.slice(2);
assert.equal(process.argv.length,7);
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
for(const family of ['counted','nested','guarded']) for(const n of [0,1,16,256]){
 const {args,expected}=input(family,n),row={family,n,arms:{}};
 for(const arm of ['structural','control','semantic']){
  const image=readFileSync(arm==='control'?`${control}/${family}-semantic.bpi3`:`${corpus}/${family}-${arm}.bpi3`),admit=await fresh(),prepared=admit.prepare(image),admission={peak:Number(admit.usage().workingPeak),retained:Number(admit.usage().workingLive)};admit.releasePrepared(prepared);assert.equal(admit.usage().workingLive,0n);
  const measurements={};for(const quantum of [1n]){
   const k=await fresh();let out=world.decodeOutcome(k.invoke(world.encodeInput({image,initialArgs:args,...(quantum?{quantum}:{})}))),boundaries=0,checkpointMax=0;
   while(out.kind==='progressed'){boundaries++;assert(boundaries<65536);checkpointMax=Math.max(checkpointMax,out.state.length);out=world.decodeOutcome(k.invoke(world.encodeInput({image,state:out.state,...(quantum?{quantum}:{})})));}
   assert.equal(out.kind,'completed');assert.deepEqual(Buffer.from(out.value),expected);assert.equal(k.usage().workingLive,0n);
   measurements[quantum?'cycle1':'fresh']={peak:Number(k.usage().workingPeak),boundaries,checkpointMax};
  }
  row.arms[arm]={sha256:createHash('sha256').update(image).digest('hex'),bytes:image.length,admission,...measurements};
 }
 rows.push(row);console.log(JSON.stringify(row));
}
writeFileSync(output,JSON.stringify({kernelSha256:runtime.kernelSha256,scope:'Authenticated WASM quantum-one same-image restore; working payload, not RSS; no timings',rows},null,2)+'\n');
