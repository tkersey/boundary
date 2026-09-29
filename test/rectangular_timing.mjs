import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import os from 'node:os';
const [agent,runtimePath,corpus,control,native,output]=process.argv.slice(2);assert.equal(process.argv.length,8);
const hash=b=>createHash('sha256').update(b).digest('hex'),median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)];
const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});
const report={status:'running',kernelSha256:runtime.kernelSha256,nativeSha256:hash(readFileSync(native)),environment:{platform:process.platform,arch:process.arch,os:os.release(),cpu:os.cpus()[0].model,node:process.version},protocol:'Alternating independent processes; three warmups and nine samples; three windows extended to five if any ratio exceeds 1.05. Confirmation: median ratio >1.05 and at least four windows >1.05.',scope:'P24 selected shared schedules versus P23 control and structural baseline; rejected raw tiled candidates are a separate experiment',cells:[]};
for(const [r,c] of [[0,0],[1,1],[8,2],[5,7],[17,9],[20,0]]){
 const name=`${r}x${c}`,arms={};let expected=0n;for(let i=0;i<r;i++)for(let j=0;j<c;j++)expected^=BigInt(i)^BigInt(j);
 for(const arm of ['control','structural','semantic','tiled']){
  const path=arm==='control'?`${control}/${name}-semantic.bpi3`:`${corpus}/${name}-${arm}.bpi3`,image=readFileSync(path),request=world.encodeInput({image,initialArgs:Buffer.alloc(0)}),result=k.invoke(request),decoded=world.decodeOutcome(result);
  assert.equal(decoded.kind,'completed');assert.equal(Buffer.from(decoded.value).readBigUInt64LE(),expected);assert.equal(k.usage().workingLive,0n);
  const input=`${corpus}/timing-${name}-${arm}.pki3`;writeFileSync(input,request);arms[arm]={path,input,expected:hash(result),imageSha256:hash(image)};
 }
 for(const [before,after] of [['control','semantic'],['structural','semantic'],...(name==='5x7'?[['structural','tiled']]:[])]){
  if(arms[before].imageSha256===arms[after].imageSha256){report.cells.push({name,before,after,status:'identical-images',imageSha256:arms[before].imageSha256});continue;}
  for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle']){
   const windows=[];
   for(let w=0;w<5;w++){
    if(w===3&&!windows.some(x=>x.ratio>1.05))break;const order=w%2?[after,before]:[before,after],results={};
    for(const arm of order){const item=arms[arm];results[arm]=JSON.parse(execFileSync(engine==='native'?native:process.execPath,engine==='native'?[phase,phase==='admission'?item.path:item.input,...(phase==='admission'?[]:[item.expected])]:[new URL('./induction_timing.mjs',import.meta.url).pathname,'sample',agent,runtimePath,item.path,'',phase,item.expected],{encoding:'utf8',timeout:120000}));}
    windows.push({order,control:results[before],candidate:results[after],ratio:median(results[after].samplesNs)/median(results[before].samplesNs)});
   }
   const ratio=median(windows.map(w=>w.ratio));report.cells.push({name,before,after,engine,phase,images:{control:arms[before].imageSha256,candidate:arms[after].imageSha256},windows,medianRatio:ratio,pairedMedianDeltaNs:median(windows.map(w=>median(w.candidate.samplesNs)-median(w.control.samplesNs))),confirmedSlowdown:windows.length===5&&ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
  }
 }
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({cells:report.cells.length,confirmed:report.cells.filter(c=>c.confirmedSlowdown).map(({name,before,after,engine,phase,medianRatio,pairedMedianDeltaNs})=>({name,before,after,engine,phase,medianRatio,pairedMedianDeltaNs}))}));
