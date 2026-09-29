import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import os from 'node:os';
const [agent,runtimePath,corpus,native,probe,output]=process.argv.slice(2);
assert.equal(process.argv.length,8);
const hash=b=>createHash('sha256').update(b).digest('hex');
const median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)];
const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));
const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});
k.setLimits({input:256<<20,working:256<<20,output:256<<20});
const paths=[['training',5n,3n,false,false],['held-out-first',17n,64n,true,false],['held-out-second',0n,0xffffffffffffffffn,false,true],['held-out-both',101n,202n,true,true]];
const report={status:'running',kernelSha256:runtime.kernelSha256,nativeSha256:hash(readFileSync(native)),probeSha256:hash(readFileSync(probe)),profileSha256:hash(readFileSync(corpus+'/training.bpf1')),scope:'One local complement-path training invocation; three held-out identity paths; explicit one-variant pass budget compared separately from ordinary full shared compilation',protocol:'Three alternating process windows, extended to five if any ratio exceeds 1.05; three warmups and nine samples per process; confirmation requires median >1.05 and at least four ratios >1.05',collection:[],cells:[],images:{}};
report.environment={platform:process.platform,arch:process.arch,os:os.release(),cpu:os.cpus()[0].model,node:process.version};
for(let w=0;w<5;w++){
 const order=w%2?['enabled','disabled']:['disabled','enabled'],samples={};
 for(const mode of order)samples[mode]=JSON.parse(execFileSync(probe,['collect',mode],{encoding:'utf8',timeout:120000}));
 assert.equal(samples.enabled.logicalSteps,samples.disabled.logicalSteps);
 report.collection.push({order,...samples,ratio:median(samples.enabled.samplesNs)/median(samples.disabled.samplesNs)});
}
const inputs=[];
for(const [name,x,y,first,second] of paths){
 const args=Buffer.alloc(18);args.writeBigUInt64LE(x);args.writeBigUInt64LE(y,8);args[16]=+first;args[17]=+second;
 const expected=Buffer.alloc(8);expected.writeBigUInt64LE(first||second?x|y:BigInt.asUintN(64,(~x)|(~y)));
 const arms={};
 for(const arm of ['structural','limited','profiled','ordinary','shared']){
  const path=`${corpus}/${arm}.bpi3`,image=readFileSync(path),request=world.encodeInput({image,initialArgs:args}),result=k.invoke(request),out=world.decodeOutcome(result);
  assert.equal(out.kind,'completed');assert.deepEqual(Buffer.from(out.value),expected);assert.equal(k.usage().workingLive,0n);
  const input=`${corpus}/${name}-${arm}.pki3`;writeFileSync(input,request);
  report.images[arm]={sha256:hash(image),bytes:image.length};arms[arm]={path,input,expected:hash(result)};
 }
 inputs.push({name,argumentsHex:args.toString('hex'),arms});
}
for(const [control,candidate] of [['limited','profiled'],['ordinary','shared'],['structural','shared']]){
 if(report.images[control].sha256===report.images[candidate].sha256){report.cells.push({control,candidate,status:'identical-images'});continue;}
 for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle'])for(const input of inputs){
  if(phase==='admission'&&input!==inputs[0])continue;const windows=[];
  for(let w=0;w<5;w++){
   if(w===3&&!windows.some(x=>x.ratio>1.05))break;
   const order=w%2?[candidate,control]:[control,candidate],results={};
   for(const arm of order){const item=input.arms[arm];results[arm]=JSON.parse(execFileSync(engine==='native'?native:process.execPath,engine==='native'?[phase,phase==='admission'?item.path:item.input,...(phase==='admission'?[]:[item.expected])]:[new URL('./induction_timing.mjs',import.meta.url).pathname,'sample',agent,runtimePath,item.path,input.argumentsHex,phase,item.expected],{encoding:'utf8',timeout:120000}));}
   windows.push({order,control:results[control],candidate:results[candidate],ratio:median(results[candidate].samplesNs)/median(results[control].samplesNs)});
  }
  const ratio=median(windows.map(w=>w.ratio));
  report.cells.push({control,candidate,engine,phase,path:input.name,windows,medianRatio:ratio,pairedMedianDeltaNs:median(windows.map(w=>median(w.candidate.samplesNs)-median(w.control.samplesNs))),confirmedSlowdown:windows.length===5&&ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4});
  writeFileSync(output,JSON.stringify(report,null,2)+'\n');
 }
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({cells:report.cells.length,confirmed:report.cells.filter(c=>c.confirmedSlowdown).length,collectionMedianRatio:median(report.collection.map(c=>c.ratio))}));
