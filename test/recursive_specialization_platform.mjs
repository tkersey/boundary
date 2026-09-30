import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [agent,runtimePath,corpus,control,native,output]=process.argv.slice(2);assert.equal(process.argv.length,8);
const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint)),hash=b=>createHash('sha256').update(b).digest('hex');
const fresh=async()=>{const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;};
const report={status:'running',kernelSha256:runtime.kernelSha256,nativeSha256:hash(readFileSync(native)),scope:'Original/control/shared/source-free recursive records; every effect request and every 64th quantum-one boundary compared native/Node/Wasmtime',crossEngineRequests:0,rows:[]};
for(const family of ['pure','effect'])for(const n of [0,1,7,32])for(const arm of ['structural','control','semantic','linked']){
 const image=readFileSync(arm==='control'?`${control}/${family}-semantic.bpi3`:`${corpus}/${family}-${arm}.bpi3`),args=Buffer.alloc(16);args.writeBigUInt64LE(BigInt(n));args.writeBigUInt64LE(0x12345678n,8);
 const admissionKernel=await fresh(),prepared=admissionKernel.prepare(image),admission={peak:Number(admissionKernel.usage().workingPeak),retained:Number(admissionKernel.usage().workingLive)};admissionKernel.releasePrepared(prepared);assert.equal(admissionKernel.usage().workingLive,0n);
 const measurements={};
 for(const quantum of [null,1n]){
  const k=await fresh();let input={image,initialArgs:args,...(quantum?{quantum}:{})},boundaries=0,requests=0,checkpointMax=0,expected=0x12345678n;
  while(true){
   const requestBytes=world.encodeInput(input),result=k.invoke(requestBytes),out=world.decodeOutcome(result);
   if(quantum===null||boundaries%64===0||out.kind==='requested'){
    const path=`${corpus}/${family}-${n}-${arm}-${quantum?'cycle':'fresh'}-${boundaries}.pki3`;writeFileSync(path,requestBytes);
    const nativeResult=spawnSync(native,[path],{timeout:60000,maxBuffer:64<<20});assert.equal(nativeResult.status,0,nativeResult.stderr.toString());assert.deepEqual(nativeResult.stdout,Buffer.from(result));
    const independent=spawnSync('uv',['run','--no-sync','--locked','--project',agent+'/test/agent4/independent','python',agent+'/test/agent4/independent/embedding.py',runtime.kernelPath,runtime.kernelSha256,path],{env:{...process.env,UV_CACHE_DIR:process.env.UV_CACHE_DIR??'/tmp/boundary-platform-uv',UV_PROJECT_ENVIRONMENT:agent+'/.agent4/cache/independent/environment',UV_PYTHON_INSTALL_DIR:agent+'/.agent4/cache/independent/python',PYTHONDONTWRITEBYTECODE:'1'},timeout:60000,maxBuffer:64<<20});assert.equal(independent.status,0,independent.stderr.toString());assert.deepEqual(independent.stdout,Buffer.from(result));report.crossEngineRequests++;
   }
   if(out.kind==='completed'){
    if(family==='pure')expected=n%2?BigInt.asUintN(64,~0x12345678n):0x12345678n;
    assert.equal(Buffer.from(out.value).readBigUInt64LE(),expected);assert.equal(requests,family==='effect'?n:0);break;
   }
   assert(++boundaries<4096);checkpointMax=Math.max(checkpointMax,out.state.length);
   let control='none',value=new Uint8Array();
   if(out.kind==='requested'){
    assert.equal(family,'effect');assert(requests<n);const request=await world.decodeRequest(out.request);assert.equal(request.semanticIdentity,'p29/opaque');assert.equal(Buffer.from(request.payload).readBigUInt64LE(),expected);
    const response=Buffer.alloc(8);response.writeBigUInt64LE(expected^0x55n);value=await world.encodeResult(out.request,response);control='reply';expected=BigInt.asUintN(64,~(expected^0x55n));requests++;
   }else assert.equal(out.kind,'progressed');
   input={image,state:out.state,control,value,...(quantum?{quantum}:{})};
  }
  assert.equal(k.usage().workingLive,0n);measurements[quantum?'cycle1':'fresh']={peak:Number(k.usage().workingPeak),boundaries,requests,checkpointMax};
 }
 report.rows.push({family,n,arm,imageSha256:hash(image),imageBytes:image.length,admission,...measurements});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({rows:report.rows.length,crossEngineRequests:report.crossEngineRequests}));
