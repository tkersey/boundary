import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [agent,runtimePath,corpus,control,native,output,onlyFamily]=process.argv.slice(2);assert(process.argv.length===8||process.argv.length===9);if(onlyFamily)assert(['xor','projection','sharing'].includes(onlyFamily));
const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const hash=b=>createHash('sha256').update(b).digest('hex');
const fresh=async()=>{const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const report={status:'running',kernelSha256:runtime.kernelSha256,nativeSha256:hash(readFileSync(native)),scope:'Every fresh and quantum-one request compared across native, Node and installed locked Wasmtime; same-image checkpoint restoration',crossEngineRequests:0,rows:[]};
const inputs=[[0n,7n],[17n,64n],[0xffffffffffffffffn,0xfedcba9876543210n]];
for(const family of onlyFamily?[onlyFamily]:['xor','projection','sharing'])for(const [index,[left,right]] of inputs.entries())for(const arm of ['structural','control','checked','semantic','linked']){
 const image=readFileSync(arm==='control'?`${control}/${family}-semantic.bpi3`:`${corpus}/${family}-${arm}.bpi3`),args=Buffer.alloc(16);args.writeBigUInt64LE(left);args.writeBigUInt64LE(right,8);
 const expected=family==='sharing'?Buffer.concat([args,args]):args.subarray(8),k=await fresh(),p=k.prepare(image),admission={peak:Number(k.usage().workingPeak),retained:Number(k.usage().workingLive)};k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);
 const measurements={};
 for(const quantum of [null,1n]){
  const kernel=await fresh();let input={image,initialArgs:args,...(quantum?{quantum}:{})},boundaries=0,checkpointMax=0;
  while(true){
   const request=world.encodeInput(input),result=kernel.invoke(request),out=world.decodeOutcome(result),path=`${corpus}/${family}-${index}-${arm}-${quantum?'cycle':'fresh'}-${boundaries}.pki3`;writeFileSync(path,request);
   const n=spawnSync(native,[path],{timeout:60000,maxBuffer:64<<20});assert.equal(n.status,0,n.stderr.toString());assert.deepEqual(n.stdout,Buffer.from(result));
   const w=spawnSync('uv',['run','--no-sync','--locked','--project',agent+'/test/agent4/independent','python',agent+'/test/agent4/independent/embedding.py',runtime.kernelPath,runtime.kernelSha256,path],{env:{...process.env,UV_CACHE_DIR:process.env.UV_CACHE_DIR??'/tmp/boundary-platform-uv',UV_PROJECT_ENVIRONMENT:agent+'/.agent4/cache/independent/environment',UV_PYTHON_INSTALL_DIR:agent+'/.agent4/cache/independent/python',PYTHONDONTWRITEBYTECODE:'1'},timeout:60000,maxBuffer:64<<20});assert.equal(w.status,0,w.stderr.toString());assert.deepEqual(w.stdout,Buffer.from(result));report.crossEngineRequests++;
   if(out.kind==='completed'){assert.deepEqual(Buffer.from(out.value),expected);break;}
   assert.equal(out.kind,'progressed');assert(++boundaries<32);checkpointMax=Math.max(checkpointMax,out.state.length);input={image,state:out.state,quantum};
  }
  assert.equal(kernel.usage().workingLive,0n);measurements[quantum?'cycle1':'fresh']={peak:Number(kernel.usage().workingPeak),boundaries,checkpointMax};
 }
 report.rows.push({family,index,arm,imageSha256:hash(image),imageBytes:image.length,admission,...measurements});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({rows:report.rows.length,crossEngineRequests:report.crossEngineRequests}));
