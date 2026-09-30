import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';

const [agent,runtimePath,corpus,reportPath,native,control]=process.argv.slice(2);
assert(process.argv.length===7||process.argv.length===8);
const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
const {wasmtime}=await import(pathToFileURL(agent+'/test/agent4/independent/execute.mjs'));
const runtime=verifyRuntime(runtimePath);
const world=await import(pathToFileURL(runtime.entrypoint));
const hash=b=>createHash('sha256').update(b).digest('hex');
const fresh=async()=>{
 const kernel=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});
 kernel.setLimits({input:256<<20,working:256<<20,output:256<<20});
 return kernel;
};
const rows=[];
for(const family of ['affine','guard','access'])for(const n of [0,1,7,50]){
 const args=Buffer.alloc(family==='affine'?1:family==='access'?17:24),expected=Buffer.alloc(8);
 if(family==='guard')args.writeBigUInt64LE(BigInt(n));else args[0]=n;
 if(family!=='affine'){const offset=family==='access'?1:8;args.writeBigUInt64LE(5n,offset);args.writeBigUInt64LE(3n,offset+8);}
 let result=0n;if(family==='affine'){for(let i=0;i<n;i++)result^=3n+5n*BigInt(i);}else if(n%2)result=6n;
 expected.writeBigUInt64LE(result);
 for(const arm of [...(control?['control']:[]),'structural','semantic','linked']){
  const image=readFileSync(arm==='control'?`${control}/${family}-semantic.bpi3`:`${corpus}/${family}-${arm}.bpi3`),k=await fresh();
  const prepared=k.prepare(image),admission={peak:Number(k.usage().workingPeak),retained:Number(k.usage().workingLive)};
  k.releasePrepared(prepared);assert.equal(k.usage().workingLive,0n);
  const measurements={};
  for(const quantum of [null,1n]){
   const kernel=await fresh();let input={image,initialArgs:args,...(quantum?{quantum}:{})},boundaries=0,checkpointMax=0;
   while(true){
    const request=world.encodeInput(input),output=kernel.invoke(request),out=world.decodeOutcome(output);
    if(quantum===null||boundaries%17===0){
     const path=`${corpus}/${family}-${n}-${arm}-${quantum?'cycle':'fresh'}-${boundaries}.pki3`;
     writeFileSync(path,request);
     const actual=spawnSync(native,[path],{timeout:60000,maxBuffer:64<<20});
     assert.equal(actual.status,0,actual.stderr.toString());assert.deepEqual(actual.stdout,Buffer.from(output));
     const independent=wasmtime(runtime,path);assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(output));
    }
    if(out.kind==='completed'){assert.deepEqual(Buffer.from(out.value),expected);break;}
    assert.equal(out.kind,'progressed');assert(++boundaries<4096);
    checkpointMax=Math.max(checkpointMax,out.state.length);input={image,state:out.state,quantum};
   }
   assert.equal(kernel.usage().workingLive,0n);
   measurements[quantum?'cycle1':'fresh']={peak:Number(kernel.usage().workingPeak),boundaries,checkpointMax};
  }
  rows.push({family,n,arm,imageSha256:hash(image),imageBytes:image.length,admission,...measurements});
 }
}
const report={kernelSha256:runtime.kernelSha256,nativeSha256:hash(readFileSync(native)),scope:'P20 compiler fixtures on authenticated unchanged WASM runtime; native outcomes compared at initial and every seventeenth checkpoint request; no timing claims',rows};
writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({rows:rows.length,kernelSha256:runtime.kernelSha256}));
