import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import os from 'node:os';
const [agent,runtimePath,corpus,control,native,output,onlyFamily]=process.argv.slice(2);assert(process.argv.length===8||process.argv.length===9);if(onlyFamily)assert(['xor','projection','sharing'].includes(onlyFamily));
const hash=b=>createHash('sha256').update(b).digest('hex'),median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)];
const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});
const report={status:'running',kernelSha256:runtime.kernelSha256,nativeSha256:hash(readFileSync(native)),environment:{platform:process.platform,arch:process.arch,os:os.release(),cpu:os.cpus()[0].model,node:process.version},protocol:'Three alternating process windows, extended to five if any ratio exceeds 1.05; three warmups and nine samples per process. Confirmation requires median >1.05 and at least four ratios >1.05.',cells:[]};
for(const family of onlyFamily?[onlyFamily]:['xor','projection','sharing'])for(const [index,[left,right]] of [[0n,7n],[17n,64n],[0xffffffffffffffffn,0xfedcba9876543210n]].entries()){
 const args=Buffer.alloc(16);args.writeBigUInt64LE(left);args.writeBigUInt64LE(right,8);const expected=family==='sharing'?Buffer.concat([args,args]):args.subarray(8),arms={};
 for(const arm of ['control','structural','checked','semantic']){
  const path=arm==='control'?`${control}/${family}-semantic.bpi3`:`${corpus}/${family}-${arm}.bpi3`,image=readFileSync(path),request=world.encodeInput({image,initialArgs:args}),result=k.invoke(request),out=world.decodeOutcome(result);assert.equal(out.kind,'completed');assert.deepEqual(Buffer.from(out.value),expected);assert.equal(k.usage().workingLive,0n);
  const input=`${corpus}/timing-${family}-${index}-${arm}.pki3`;writeFileSync(input,request);arms[arm]={path,input,expected:hash(result),sha256:hash(image)};
 }
 for(const [before,after] of [['control','semantic'],['structural','semantic'],['structural','checked']]){
  if(arms[before].sha256===arms[after].sha256){report.cells.push({family,index,before,after,status:'identical-images',sha256:arms[before].sha256});continue;}
  for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle']){
   if(phase==='admission'&&index!==0)continue;const windows=[];
   for(let w=0;w<5;w++){
    if(w===3&&!windows.some(x=>x.ratio>1.05))break;const order=w%2?[after,before]:[before,after],results={};
    for(const arm of order){const item=arms[arm];results[arm]=JSON.parse(execFileSync(engine==='native'?native:process.execPath,engine==='native'?[phase,phase==='admission'?item.path:item.input,...(phase==='admission'?[]:[item.expected])]:[new URL('./induction_timing.mjs',import.meta.url).pathname,'sample',agent,runtimePath,item.path,args.toString('hex'),phase,item.expected],{encoding:'utf8',timeout:120000}));}
    windows.push({order,control:results[before],candidate:results[after],ratio:median(results[after].samplesNs)/median(results[before].samplesNs)});
   }
   const ratio=median(windows.map(w=>w.ratio));report.cells.push({family,index,before,after,engine,phase,images:{control:arms[before].sha256,candidate:arms[after].sha256},windows,medianRatio:ratio,pairedMedianDeltaNs:median(windows.map(w=>median(w.candidate.samplesNs)-median(w.control.samplesNs))),confirmedSlowdown:windows.length===5&&ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
  }
 }
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({cells:report.cells.length,confirmed:report.cells.filter(c=>c.confirmedSlowdown).map(({family,index,before,after,engine,phase,medianRatio,pairedMedianDeltaNs})=>({family,index,before,after,engine,phase,medianRatio,pairedMedianDeltaNs}))}));
