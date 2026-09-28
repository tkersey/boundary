// Paired frozen-image admission, invocation, and checkpoint/restore observations.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {join,basename} from 'node:path';
import {pathToFileURL} from 'node:url';
import os from 'node:os';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const hash=path=>sha(readFileSync(path));
const median=a=>[...a].sort((x,y)=>x-y)[Math.floor(a.length/2)];
const argumentsFor=n=>{const args=Buffer.alloc((n+1)*8+1);for(let i=0;i<n;i++)args.writeBigUInt64LE(BigInt(i+1),i*8);args.writeBigUInt64LE(0xa5n,n*8);args[args.length-1]=1;return args;};
async function runtimeAt(agent,runtime){const {verifyRuntime}=await import(pathToFileURL(join(agent,'tools/agent4/dependencies.mjs')));const identity=verifyRuntime(runtime);return{identity,world:await import(pathToFileURL(identity.entrypoint))};}
async function kernelAt(world,identity){const k=await world.Kernel.create({bytes:readFileSync(identity.kernelPath),expectedSha256:identity.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});return k;}
const argv=process.argv.slice(2);
if(argv[0]==='--wasm-sample'){
 const [,agent,runtime,imagePath,count,phase,expected]=argv,n=Number(count);assert([8,32,128].includes(n));assert(['admission','fresh','cycle'].includes(phase));
 const {world,identity}=await runtimeAt(agent,runtime),k=await kernelAt(world,identity),image=readFileSync(imagePath),initialArgs=argumentsFor(n);
 const input=world.encodeInput({image,initialArgs,...(phase==='cycle'?{quantum:1n}:{})});
 const samplesNs=[];let transitions=0;
 for(let i=0;i<12;i++){let elapsed=0;const batch=phase==='cycle'?1:64;for(let repeat=0;repeat<batch;repeat++){
  const start=process.hrtime.bigint();
  if(phase==='admission'){const p=k.prepare(image);elapsed+=Number(process.hrtime.bigint()-start);k.releasePrepared(p);}
  else{let output=k.invoke(input),steps=1;if(phase==='cycle'){let outcome=world.decodeOutcome(output);while(outcome.kind==='progressed'){assert(++steps<=10000);output=k.invoke(world.encodeInput({image,state:outcome.state,quantum:1n}));outcome=world.decodeOutcome(output);}assert.equal(outcome.kind,'completed');}
   elapsed+=Number(process.hrtime.bigint()-start);assert.equal(sha(output),expected);if(transitions)assert.equal(steps,transitions);transitions=steps;
  }
  assert.equal(k.usage().workingLive,0n);
 }if(i>=3)samplesNs.push(elapsed/batch);}
 console.log(JSON.stringify({samplesNs,transitions}));
}else{
 const [agent,runtime,corpus,output,admission,fresh,cycle,previousCostPath,currentCostPath]=argv;assert(argv.length===9,'agent runtime corpus output native-admission native-fresh native-cycle previous-cost current-cost');
 const previousCost=JSON.parse(readFileSync(previousCostPath)),currentCost=JSON.parse(readFileSync(currentCostPath));
 const {world,identity}=await runtimeAt(agent,runtime),kernel=await kernelAt(world,identity),cases=[];
 for(const n of [8,32,128]){const arms={};for(const arm of ['structural','semantic']){const imagePath=join(corpus,`parameters-${n}-${arm}.bpi3`),image=readFileSync(imagePath);const pki=join(corpus,`parameters-${n}-${arm}-${arm==='structural'?1:3}.pki3`);const input=world.encodeInput({image,initialArgs:argumentsFor(n)});assert.deepEqual(Buffer.from(input),readFileSync(pki));const result=kernel.invoke(input),decoded=world.decodeOutcome(result);assert.equal(decoded.kind,'completed');let parity=0n;for(let i=1;i<=n;i++)parity^=BigInt(i);assert.equal(Buffer.from(decoded.value).readBigUInt64LE(),parity^0xa5n);
  const cost=(arm==='structural'?previousCost:currentCost).rows.find(r=>r.case===`direct-parity-${n}`&&r.mode==='semantic-pipeline');assert(cost);assert.equal(Buffer.from(cost.image_digest).toString('hex'),sha(image),'same-contract image identity');
  arms[arm]={imagePath,pki,imageSha256:sha(image),inputSha256:sha(input),expected:sha(result)};
 }cases.push({n,arms});}
 const executables={admission,fresh,cycle};const executableHashes=Object.fromEntries(Object.entries(executables).map(([key,path])=>[key,{file:basename(path),sha256:hash(path)}]));
 const report={status:'running',scope:'Direct parameter fixtures: exact previous semantic compiler images versus current semantic images; admission, fresh invocation, and complete quantum-one checkpoint/restore cycles. Cycle timings do not isolate checkpoint encoding.',environment:{platform:process.platform,arch:process.arch,os:os.release(),cpu:os.cpus()[0].model,node:process.version},kernelSha256:identity.kernelSha256,executableHashes,protocol:'Three alternating windows, three warmups and nine samples; two further confirmation windows if an initial median ratio exceeds 1.05. Ordinary host, no exclusive-host claim.',inputs:cases.map(({n,arms})=>({n,arms:Object.fromEntries(Object.entries(arms).map(([key,a])=>[key,{imageSha256:a.imageSha256,inputSha256:a.inputSha256}]))})),cells:[]};
 for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle'])for(const {n,arms}of cases){const windows=[];for(let w=0;w<5;w++){
  if(w===3&&!windows.some(x=>x.ratio>1.05))break;const order=w%2?['semantic','structural']:['structural','semantic'],results={};
  for(const arm of order){const a=arms[arm];let command,args,options={encoding:'utf8',timeout:120000};if(engine==='wasm'){command=process.execPath;args=[new URL(import.meta.url).pathname,'--wasm-sample',agent,runtime,a.imagePath,String(n),phase,a.expected];}else{command=executables[phase];args=phase==='admission'?[a.imagePath]:phase==='cycle'?[a.pki,a.expected]:[a.expected];if(phase==='fresh')options.input=readFileSync(a.pki);}results[arm]=JSON.parse(execFileSync(command,args,options));}
  windows.push({order,control:results.structural,candidate:results.semantic,ratio:median(results.semantic.samplesNs)/median(results.structural.samplesNs)});
 }const ratio=median(windows.map(x=>x.ratio));report.cells.push({engine,phase,n,windows,medianRatio:ratio,pairedMedianDeltaNs:median(windows.map(w=>median(w.candidate.samplesNs)-median(w.control.samplesNs))),confirmedSlowdown:windows.length===5&&ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4});writeFileSync(output,JSON.stringify(report,null,2)+'\n');}
 for(const [key,path]of Object.entries(executables))assert.equal(hash(path),executableHashes[key].sha256);await runtimeAt(agent,runtime);report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({status:report.status,cells:report.cells.length,confirmed:report.cells.filter(x=>x.confirmedSlowdown).map(({engine,phase,n,medianRatio,pairedMedianDeltaNs})=>({engine,phase,n,medianRatio,pairedMedianDeltaNs}))}));
}
