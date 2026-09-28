// Same-contract predecessor/candidate economics for the selected PRE witness.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {join,basename} from 'node:path';
import {createHash} from 'node:crypto';
import os from 'node:os';
const hash=b=>createHash('sha256').update(b).digest('hex');
const median=a=>[...a].sort((x,y)=>x-y)[Math.floor(a.length/2)];
async function load(agent,runtime){const {verifyRuntime}=await import(pathToFileURL(join(agent,'tools/agent4/dependencies.mjs')));const identity=verifyRuntime(runtime),world=await import(pathToFileURL(identity.entrypoint));return{identity,world};}
async function fresh(world,identity){const k=await world.Kernel.create({bytes:readFileSync(identity.kernelPath),expectedSha256:identity.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;}
const args=process.argv.slice(2);
if(args[0]==='--sample'){
 const [,agent,runtime,imagePath,argumentsHex,phase,expected]=args;assert(['admission','fresh','cycle'].includes(phase));
 const {identity,world}=await load(agent,runtime),k=await fresh(world,identity),image=readFileSync(imagePath),initialArgs=Buffer.from(argumentsHex,'hex');
 const input=world.encodeInput({image,initialArgs,...(phase==='cycle'?{quantum:1n}:{})}),samplesNs=[];
 for(let window=0;window<12;window++){let total=0;const batch=phase==='cycle'?1:64;for(let n=0;n<batch;n++){
  const begin=process.hrtime.bigint();
  if(phase==='admission'){const p=k.prepare(image);total+=Number(process.hrtime.bigint()-begin);k.releasePrepared(p);}
  else{let output=k.invoke(input);if(phase==='cycle'){let state=world.decodeOutcome(output),steps=1;while(state.kind==='progressed'){assert(++steps<100);output=k.invoke(world.encodeInput({image,state:state.state,quantum:1n}));state=world.decodeOutcome(output);}assert.equal(state.kind,'completed');}total+=Number(process.hrtime.bigint()-begin);assert.equal(hash(output),expected);}
  assert.equal(k.usage().workingLive,0n);
 }if(window>=3)samplesNs.push(total/batch);}
 console.log(JSON.stringify({samplesNs}));
}else{
 const [agent,runtime,controlDirectory,candidateDirectory,output,admission,freshNative,cycleNative,memoryNative]=args;assert.equal(args.length,9);
 const {identity,world}=await load(agent,runtime),kernel=await fresh(world,identity),arms={control:join(controlDirectory,'live-shared-semantic.bpi3'),candidate:join(candidateDirectory,'live-shared-semantic.bpi3')};
 const imageHashes=Object.fromEntries(Object.entries(arms).map(([arm,path])=>[arm,hash(readFileSync(path))]));assert.notEqual(imageHashes.control,imageHashes.candidate);
 const fixtures=[['reuse',7n,7n,true,false,true],['missing',7n,11n,false,true,false],['early',7n,11n,true,false,false]];
 const inputs={};
 for(const [name,x,y,first,second,expected]of fixtures){const bytes=Buffer.alloc(18);bytes.writeBigUInt64LE(x);bytes.writeBigUInt64LE(y,8);bytes[16]=+first;bytes[17]=+second;inputs[name]={argumentsHex:bytes.toString('hex'),arms:{}};for(const [arm,path]of Object.entries(arms)){const image=readFileSync(path),encoded=world.encodeInput({image,initialArgs:bytes}),result=kernel.invoke(encoded),decoded=world.decodeOutcome(result);assert.equal(decoded.kind,'completed');assert.deepEqual(Buffer.from(decoded.value),Buffer.from([+expected]));const pki=join(candidateDirectory,`timing-${name}-${arm}.pki3`);writeFileSync(pki,encoded);inputs[name].arms[arm]={path,pki,expected:hash(result),inputSha256:hash(encoded)};}}
 const memory={};
 for(const [arm,path]of Object.entries(arms)){const image=readFileSync(path),native=JSON.parse(execFileSync(memoryNative,[path],{encoding:'utf8'})),k=await fresh(world,identity),p=k.prepare(image),usage=k.usage();memory[arm]={native,wasmAdmission:{peak:Number(usage.workingPeak),retained:Number(usage.workingLive),capacity:usage.memoryBytes}};k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);}
 const executables={admission,fresh:freshNative,cycle:cycleNative};
 const report={status:'running',scope:'Selected live PRE diamond: frozen 15c5356 semantic compiler versus 77892fb semantic compiler. Complete cycle includes quantum-one checkpoint/restore, not isolated phase timing.',environment:{platform:process.platform,arch:process.arch,os:os.release(),cpu:os.cpus()[0].model,node:process.version},kernelSha256:identity.kernelSha256,imageHashes,executables:Object.fromEntries(Object.entries({...executables,memory:memoryNative}).map(([key,path])=>[key,{file:basename(path),sha256:hash(readFileSync(path))}])),memory,protocol:'Three alternating windows; three warmups/nine samples; two extra windows if an initial median ratio exceeds 1.05. No exclusive-host claim.',cells:[]};
 for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle'])for(const [name,input]of Object.entries(inputs)){
  if(phase==='admission'&&name!=='reuse')continue;
  const windows=[];for(let window=0;window<5;window++){if(window===3&&!windows.some(w=>w.ratio>1.05))break;const order=window%2?['candidate','control']:['control','candidate'],results={};for(const arm of order){const item=input.arms[arm];let command,argv,options={encoding:'utf8',timeout:120000};if(engine==='wasm'){command=process.execPath;argv=[new URL(import.meta.url).pathname,'--sample',agent,runtime,item.path,input.argumentsHex,phase,item.expected];}else{command=executables[phase];argv=phase==='admission'?[item.path]:phase==='cycle'?[item.pki,item.expected]:[item.expected];if(phase==='fresh')options.input=readFileSync(item.pki);}results[arm]=JSON.parse(execFileSync(command,argv,options));}windows.push({order,control:results.control,candidate:results.candidate,ratio:median(results.candidate.samplesNs)/median(results.control.samplesNs)});}
  const ratio=median(windows.map(w=>w.ratio));report.cells.push({engine,phase,path:name,windows,medianRatio:ratio,pairedMedianDeltaNs:median(windows.map(w=>median(w.candidate.samplesNs)-median(w.control.samplesNs))),confirmedSlowdown:windows.length===5&&ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({cells:report.cells.length,memory,confirmed:report.cells.filter(c=>c.confirmedSlowdown).map(({engine,phase,path,medianRatio,pairedMedianDeltaNs})=>({engine,phase,path,medianRatio,pairedMedianDeltaNs}))}));
}
