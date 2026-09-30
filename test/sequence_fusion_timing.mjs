import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join,basename} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import os from 'node:os';
const hash=b=>createHash('sha256').update(b).digest('hex'),median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)];
async function load(agent,path){const {verifyRuntime}=await import(pathToFileURL(join(agent,'tools/agent4/dependencies.mjs')));const identity=verifyRuntime(path),world=await import(pathToFileURL(identity.entrypoint));return {identity,world};}
async function kernel(world,identity){const k=await world.Kernel.create({bytes:readFileSync(identity.kernelPath),expectedSha256:identity.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;}
const args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,agent,runtime,path,argumentsHex,phase,expected]=args,{identity,world}=await load(agent,runtime),k=await kernel(world,identity),image=readFileSync(path),initialArgs=Buffer.from(argumentsHex,'hex');
 const input=world.encodeInput({image,initialArgs,...(phase==='cycle'?{quantum:1n}:{})}),samplesNs=[];
 for(let window=0;window<12;window++){let elapsed=0;const batch=phase==='cycle'?1:64;for(let i=0;i<batch;i++){
  const start=process.hrtime.bigint();if(phase==='admission'){const p=k.prepare(image);elapsed+=Number(process.hrtime.bigint()-start);k.releasePrepared(p);}else{
   let output=k.invoke(input);if(phase==='cycle'){let outcome=world.decodeOutcome(output),steps=1;while(outcome.kind==='progressed'){assert(++steps<4096);output=k.invoke(world.encodeInput({image,state:outcome.state,quantum:1n}));outcome=world.decodeOutcome(output);}assert.equal(outcome.kind,'completed');}
   elapsed+=Number(process.hrtime.bigint()-start);assert.equal(hash(output),expected);
  }assert.equal(k.usage().workingLive,0n);
 }if(window>=3)samplesNs.push(elapsed/batch);}
 console.log(JSON.stringify({samplesNs}));
}else{
 const [agent,runtime,control,candidate,output,native,fixture]=args;assert.equal(args.length,7);
 assert(['map-fold','map-fold-wide','unfold'].includes(fixture));const {identity,world}=await load(agent,runtime),k=await kernel(world,identity);
 const values=fixture==='unfold'?[[0,0],[1,0],[0,1]]:fixture==='map-fold-wide'?[32,64,128].map(n=>[...(n<128?[n]:[128,1]),...Array(n).fill(1),1]):[[0,1],[1,1,1],[4,1,0,1,1,1]];
 const paths={control:join(control,fixture+'-shared-semantic.bpi3'),candidate:join(candidate,fixture+'-shared-semantic.bpi3')};
 const imageHashes=Object.fromEntries(Object.entries(paths).map(([arm,path])=>[arm,hash(readFileSync(path))]));assert.notEqual(imageHashes.control,imageHashes.candidate);
 const inputs=values.map((v,i)=>{const bytes=Buffer.from(v),arms={};let reference;for(const [arm,path]of Object.entries(paths)){const image=readFileSync(path),encoded=world.encodeInput({image,initialArgs:bytes}),result=k.invoke(encoded),decoded=world.decodeOutcome(result);assert.equal(decoded.kind,'completed');if(reference)assert.deepEqual(Buffer.from(decoded.value),reference);else reference=Buffer.from(decoded.value);const pki=join(candidate,`timing-${fixture}-${i}-${arm}.pki3`);writeFileSync(pki,encoded);arms[arm]={path,pki,expected:hash(result),inputSha256:hash(encoded)};}return {name:`path-${i}`,argumentsHex:bytes.toString('hex'),arms};});
 const report={status:'running',fixture,controlCommit:'57672e765db5d13123e2141ace02e948ba533ee7',kernelSha256:identity.kernelSha256,native:{file:basename(native),sha256:hash(readFileSync(native)),worldSource:'f8a1597d4ff62ae691dfca12f7ce3a2b4e6c0727',boundaryRuntimeSource:'511fe388587b36ae37307d277e04c22b0bb6f6d9'},environment:{platform:process.platform,arch:process.arch,os:os.release(),cpu:os.cpus()[0].model,node:process.version},imageHashes,protocol:'Three independently launched alternating windows with three warmups and nine measurements per process; two additional alternating confirmation windows when any initial ratio exceeds 1.05. Native batches: admission64/fresh16/cycle1. WASM batches: admission64/fresh64/cycle1. Full cycle includes each quantum-one encoding, invocation and outcome decoding. No exclusive-host claim.',cells:[]};
 for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle'])for(const [i,input]of inputs.entries()){
  if(phase==='admission'&&i!==0)continue;const windows=[];
  for(let w=0;w<5;w++){if(w===3&&!windows.some(x=>x.ratio>1.05))break;const order=w%2?['candidate','control']:['control','candidate'],results={};for(const arm of order){const item=input.arms[arm];results[arm]=JSON.parse(execFileSync(engine==='native'?native:process.execPath,engine==='native'?[phase,phase==='admission'?item.path:item.pki,...(phase==='admission'?[]:[item.expected])]:[new URL(import.meta.url).pathname,'sample',agent,runtime,item.path,input.argumentsHex,phase,item.expected],{encoding:'utf8',timeout:120000}));}windows.push({order,...results,ratio:median(results.candidate.samplesNs)/median(results.control.samplesNs)});}
  const ratio=median(windows.map(w=>w.ratio));report.cells.push({engine,phase,path:input.name,argumentsHex:input.argumentsHex,windows,medianRatio:ratio,pairedMedianDeltaNs:median(windows.map(w=>median(w.candidate.samplesNs)-median(w.control.samplesNs))),confirmedSlowdown:windows.length===5&&ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({fixture,cells:report.cells.length,confirmed:report.cells.filter(c=>c.confirmedSlowdown).map(c=>({engine:c.engine,phase:c.phase,path:c.path,ratio:c.medianRatio,deltaNs:c.pairedMedianDeltaNs}))}));
}
