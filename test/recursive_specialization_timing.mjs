import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import os from 'node:os';
const hash=b=>createHash('sha256').update(b).digest('hex'),median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)];
async function load(agent,path){const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));const runtime=verifyRuntime(path),world=await import(pathToFileURL(runtime.entrypoint)),k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return{runtime,world,k};}
async function drive(world,k,image,initialArgs,quantum){
 let input={image,initialArgs,...(quantum?{quantum}:{})},steps=0;
 while(true){const result=k.invoke(world.encodeInput(input)),out=world.decodeOutcome(result);if(out.kind==='completed')return result;assert(++steps<4096);
  let control='none',value=new Uint8Array();if(out.kind==='requested'){const request=await world.decodeRequest(out.request);assert.equal(request.semanticIdentity,'p29/opaque');const reply=Buffer.alloc(8);reply.writeBigUInt64LE(Buffer.from(request.payload).readBigUInt64LE()^0x55n);value=await world.encodeResult(out.request,reply);control='reply';}else assert.equal(out.kind,'progressed');
  input={image,state:out.state,control,value,...(quantum?{quantum}:{})};
 }
}
const args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,agent,path,imagePath,hex,phase,expected]=args,{world,k}=await load(agent,path),image=readFileSync(imagePath),input=Buffer.from(hex,'hex'),samplesNs=[];
 const batch=phase==='admission'?64:phase==='cycle'?1:16;
 for(let window=0;window<12;window++){let elapsed=0;for(let i=0;i<batch;i++){const start=process.hrtime.bigint();if(phase==='admission'){const p=k.prepare(image);elapsed+=Number(process.hrtime.bigint()-start);k.releasePrepared(p);}else{const result=await drive(world,k,image,input,phase==='cycle'?1n:null);elapsed+=Number(process.hrtime.bigint()-start);assert.equal(hash(result),expected);}assert.equal(k.usage().workingLive,0n);}if(window>=3)samplesNs.push(elapsed/batch);}
 console.log(JSON.stringify({samplesNs,samplesPerBatch:batch}));
}else{
 const [agent,path,corpus,control,native,output]=args;assert.equal(args.length,6);const {runtime,world,k}=await load(agent,path);
 const report={status:'running',kernelSha256:runtime.kernelSha256,nativeSha256:hash(readFileSync(native)),environment:{platform:process.platform,arch:process.arch,os:os.release(),cpu:os.cpus()[0].model,node:process.version},protocol:'Three alternating process windows extended to five on any ratio >1.05; three warmups and nine samples. Native/WASM batches admission64, fresh16, cycle1. Effects receive the same local payload-XOR reply. Confirmation requires median >1.05 and four positive windows.',cells:[]};
 for(const family of ['pure','effect'])for(const n of [0,1,7,32]){
  const input=Buffer.alloc(16);input.writeBigUInt64LE(BigInt(n));input.writeBigUInt64LE(0x12345678n,8);const arms={};
  for(const arm of ['control','structural','semantic']){const imagePath=arm==='control'?`${control}/${family}-semantic.bpi3`:`${corpus}/${family}-${arm}.bpi3`,image=readFileSync(imagePath),request=world.encodeInput({image,initialArgs:input}),result=await drive(world,k,image,input,null);let expected=0x12345678n;for(let i=0;i<n;i++)expected=BigInt.asUintN(64,~(expected^(family==='effect'?0x55n:0n)));assert.equal(Buffer.from(world.decodeOutcome(result).value).readBigUInt64LE(),expected);const pki=`${corpus}/timing-${family}-${n}-${arm}.pki3`;writeFileSync(pki,request);arms[arm]={path:imagePath,pki,expected:hash(result),sha256:hash(image)};}
  for(const before of ['control','structural']){
   if(arms[before].sha256===arms.semantic.sha256){report.cells.push({family,n,before,status:'identical-images'});continue;}
   for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle']){
    if(phase==='admission'&&n!==0)continue;const windows=[];
    for(let w=0;w<5;w++){if(w===3&&!windows.some(x=>x.ratio>1.05))break;const order=w%2?['semantic',before]:[before,'semantic'],results={};for(const arm of order){const item=arms[arm];results[arm]=JSON.parse(execFileSync(engine==='native'?native:process.execPath,engine==='native'?[phase,phase==='admission'?item.path:item.pki,...(phase==='admission'?[]:[item.expected])]:[new URL(import.meta.url).pathname,'sample',agent,path,item.path,input.toString('hex'),phase,item.expected],{encoding:'utf8',timeout:120000}));}windows.push({order,control:results[before],candidate:results.semantic,ratio:median(results.semantic.samplesNs)/median(results[before].samplesNs)});}
    const ratio=median(windows.map(w=>w.ratio));report.cells.push({family,n,before,engine,phase,images:{control:arms[before].sha256,candidate:arms.semantic.sha256},windows,medianRatio:ratio,pairedMedianDeltaNs:median(windows.map(w=>median(w.candidate.samplesNs)-median(w.control.samplesNs))),confirmedSlowdown:windows.length===5&&ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
   }
  }
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({cells:report.cells.length,confirmed:report.cells.filter(c=>c.confirmedSlowdown).map(({family,n,before,engine,phase,medianRatio,pairedMedianDeltaNs})=>({family,n,before,engine,phase,medianRatio,pairedMedianDeltaNs}))}));
}
