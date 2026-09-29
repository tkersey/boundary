import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [agent,runtimePath,corpus,control,native,output]=process.argv.slice(2);
assert.equal(process.argv.length,8);
const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const hash=b=>createHash('sha256').update(b).digest('hex');
// Reuse the installed locked independent embedding without mutating Agent's
// environment or repository-local cache in a Boundary-only writable session.
const wasmtime=(runtime,input)=>spawnSync('uv',['run','--no-sync','--locked','--project',agent+'/test/agent4/independent','python',agent+'/test/agent4/independent/embedding.py',runtime.kernelPath,runtime.kernelSha256,input],{
 env:{...process.env,UV_CACHE_DIR:process.env.UV_CACHE_DIR??'/tmp/boundary-platform-uv',UV_PROJECT_ENVIRONMENT:agent+'/.agent4/cache/independent/environment',UV_PYTHON_INSTALL_DIR:agent+'/.agent4/cache/independent/python',PYTHONDONTWRITEBYTECODE:'1'},timeout:60000,maxBuffer:64<<20,
});
const fresh=async()=>{const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const report={status:'running',kernelSha256:runtime.kernelSha256,nativeSha256:hash(readFileSync(native)),scope:'P24 records on authenticated unchanged runtime; every quantum-one Node checkpoint restored; native/Wasmtime compared at initial and every 64th checkpoint request',crossEngineRequests:0,rows:[]};
for(const [r,c] of [[0,0],[1,1],[8,2],[5,7],[17,9],[20,0]])for(const arm of ['structural','control','semantic','linked','tiled']){
 const name=`${r}x${c}`,path=arm==='control'?`${control}/${name}-semantic.bpi3`:`${corpus}/${name}-${arm}.bpi3`,image=readFileSync(path),k=await fresh();
 const prepared=k.prepare(image),admission={peak:Number(k.usage().workingPeak),retained:Number(k.usage().workingLive)};k.releasePrepared(prepared);assert.equal(k.usage().workingLive,0n);
 let expected=0n;for(let i=0;i<r;i++)for(let j=0;j<c;j++)expected^=BigInt(i)^BigInt(j);
 const bytes=Buffer.alloc(8);bytes.writeBigUInt64LE(expected);const measurements={};
 for(const quantum of [null,1n]){
  const kernel=await fresh();let input={image,initialArgs:Buffer.alloc(0),...(quantum?{quantum}:{})},boundaries=0,checkpointMax=0;
  while(true){
   const request=world.encodeInput(input),result=kernel.invoke(request),out=world.decodeOutcome(result);
   if(quantum===null||boundaries%64===0){
    const inputPath=`${corpus}/${name}-${arm}-${quantum?'cycle':'fresh'}-${boundaries}.pki3`;writeFileSync(inputPath,request);
    const n=spawnSync(native,[inputPath],{timeout:60000,maxBuffer:64<<20});assert.equal(n.status,0,n.stderr.toString());assert.deepEqual(n.stdout,Buffer.from(result));
    const w=wasmtime(runtime,inputPath);assert.equal(w.status,0,w.stderr.toString());assert.deepEqual(w.stdout,Buffer.from(result));report.crossEngineRequests++;
   }
   if(out.kind==='completed'){assert.deepEqual(Buffer.from(out.value),bytes);break;}
   assert.equal(out.kind,'progressed');assert(++boundaries<4096);checkpointMax=Math.max(checkpointMax,out.state.length);input={image,state:out.state,quantum};
  }
  assert.equal(kernel.usage().workingLive,0n);measurements[quantum?'cycle1':'fresh']={peak:Number(kernel.usage().workingPeak),boundaries,checkpointMax};
 }
 report.rows.push({name,arm,imageSha256:hash(image),imageBytes:image.length,admission,...measurements});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({rows:report.rows.length,crossEngineRequests:report.crossEngineRequests}));
