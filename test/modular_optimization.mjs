import assert from 'node:assert/strict';
import {spawnSync,execFileSync} from 'node:child_process';
import {mkdtempSync,copyFileSync,writeFileSync,readFileSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const [emitter,linker,agent,runtimePath,native,reportPath]=process.argv.slice(2);assert.equal(process.argv.length,8);
const directory=mkdtempSync(join(tmpdir(),'boundary-modular-optimization-')),hash=b=>createHash('sha256').update(b).digest('hex');
const report={status:'running',directory,emitterSha256:hash(readFileSync(emitter)),linkerSha256:hash(readFileSync(linker)),contracts:{},executions:0,rejections:[]};
for(const [name,mode] of [['provider','constructor-provider'],['client','constructor-client']])writeFileSync(join(directory,name+'.bmo1'),execFileSync(emitter,[mode]));
copyFileSync(linker,join(directory,'boundary-link'));
assert.deepEqual(readdirSync(directory).sort(),['boundary-link','client.bmo1','provider.bmo1']);
const manifest={instances:[{key:'provider',path:'provider.bmo1'},{key:'client',path:'client.bmo1'}],bindings:[{required:{instance:'client',symbol:'factory'},supplied:{instance:'provider',symbol:'factory'}}],entry:{instance:'client',symbol:'main'}};
const images={direct:execFileSync(emitter,['direct'])};
for(const contract of ['structural','semantic']){
 writeFileSync(join(directory,'link.json'),JSON.stringify({...manifest,contract}));
 const result=spawnSync(join(directory,'boundary-link'),['link.json'],{cwd:directory});assert.equal(result.status,0,result.stderr.toString());images[contract]=result.stdout;
 const path=join(directory,contract+'.bpi3');writeFileSync(path,result.stdout);report.contracts[contract]={sha256:hash(result.stdout),...JSON.parse(execFileSync(emitter,['inspect',path],{encoding:'utf8'}))};
}
assert.equal(report.contracts.structural.applies,1);assert.equal(report.contracts.structural.captureOperands,2);
assert.equal(report.contracts.structural.deadCaptureWitnesses,1);
assert.equal(report.contracts.semantic.applies,0);assert.equal(report.contracts.semantic.captureOperands,0);
assert(report.contracts.semantic.bytes<report.contracts.structural.bytes);
report.policy=[];
for(const policy of [{work_limit:0},{round_limit:0}]){
 writeFileSync(join(directory,'link.json'),JSON.stringify({...manifest,contract:'semantic',...policy}));
 const output=execFileSync(join(directory,'boundary-link'),['link.json'],{cwd:directory});assert.deepEqual(output,images.structural);
 report.policy.push({policy,result:'checked structural baseline',sha256:hash(output)});
}
for(const objective of ['size','balanced','speed']){
 writeFileSync(join(directory,'link.json'),JSON.stringify({...manifest,contract:'semantic',objective,image_growth_bytes:0,max_image_bytes:images.structural.length}));
 const output=execFileSync(join(directory,'boundary-link'),['link.json'],{cwd:directory});assert(output.length<=images.structural.length);
 report.policy.push({policy:{objective,image_growth_bytes:0,max_image_bytes:images.structural.length},bytes:output.length,sha256:hash(output)});
}
for(const contract of ['structural','semantic'])for(const policy of [{max_image_bytes:1},{profile:{record:{image_identity:Array(32).fill(0),block_counts:[],total:0}}}]){
 writeFileSync(join(directory,'link.json'),JSON.stringify({...manifest,contract,...policy}));
 const result=spawnSync(join(directory,'boundary-link'),['link.json'],{cwd:directory});assert.notEqual(result.status,0);assert.equal(result.stdout.length,0);
 const expected=policy.profile?'InvalidOptimizationProfile':'Capacity';assert(result.stderr.toString().includes(expected));
 report.policy.push({contract,policy,result:expected});
}
const {verifyRuntime}=await import(pathToFileURL(resolve(agent,'tools/agent4/dependencies.mjs')));const runtime=verifyRuntime(runtimePath),world=await import(pathToFileURL(runtime.entrypoint));report.kernelSha256=runtime.kernelSha256;
for(const [name,image] of Object.entries(images))for(const [x,y,z]of [[10n,99n,3n],[0n,0n,7n],[0xffffffffffffffffn,17n,0xfedcba9876543210n]]){
 const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});const args=Buffer.alloc(24);args.writeBigUInt64LE(x);args.writeBigUInt64LE(y,8);args.writeBigUInt64LE(z,16);
 let input={image,initialArgs:args,quantum:1n},boundaries=0;
 while(true){const request=world.encodeInput(input),result=k.invoke(request),out=world.decodeOutcome(result),path=join(directory,`${name}-${report.executions}-${boundaries}.pki3`);writeFileSync(path,request);const checked=spawnSync(native,[path],{timeout:60000,maxBuffer:64<<20});assert.equal(checked.status,0,checked.stderr.toString());assert.deepEqual(checked.stdout,Buffer.from(result));
  if(out.kind==='completed'){assert.equal(Buffer.from(out.value).readBigUInt64LE(),x^z);break;}
  assert.equal(out.kind,'progressed');assert(++boundaries<64);input={image,state:out.state,quantum:1n};
 }
 report.executions++;
}
// The imported wrapper body, rather than a source name, exposes the forwarding law.
for(const [name,mode] of [['provider','thunk-provider'],['client','thunk-client']])writeFileSync(join(directory,name+'.bmo1'),execFileSync(emitter,[mode]));
const lawManifest={...manifest,bindings:[{required:{instance:'client',symbol:'wrapper'},supplied:{instance:'provider',symbol:'wrapper'}}]};
report.law={};
for(const contract of ['structural','semantic']){
 writeFileSync(join(directory,'link.json'),JSON.stringify({...lawManifest,contract}));const image=execFileSync(join(directory,'boundary-link'),['link.json'],{cwd:directory}),path=join(directory,`law-${contract}.bpi3`);writeFileSync(path,image);
 report.law[contract]={sha256:hash(image),...JSON.parse(execFileSync(emitter,['inspect',path],{encoding:'utf8'}))};
 for(const x of [0n,41n,0xffffffffffffffffn]){
  const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});const args=Buffer.alloc(8);args.writeBigUInt64LE(x);let input={image,initialArgs:args,quantum:1n},steps=0;
  while(true){const request=world.encodeInput(input),result=k.invoke(request),out=world.decodeOutcome(result),requestPath=join(directory,`law-${contract}-${x}-${steps}.pki3`);writeFileSync(requestPath,request);const checked=spawnSync(native,[requestPath],{timeout:60000,maxBuffer:64<<20});assert.equal(checked.status,0,checked.stderr.toString());assert.deepEqual(checked.stdout,Buffer.from(result));if(out.kind==='completed'){assert.equal(Buffer.from(out.value).readBigUInt64LE(),x);break;}assert.equal(out.kind,'progressed');assert(++steps<64);input={image,state:out.state,quantum:1n};}
  report.executions++;
 }
}
assert(report.law.semantic.constructions<report.law.structural.constructions);
assert.equal(report.law.structural.forwardingLawWitnesses,1);
assert(report.law.semantic.bytes<report.law.structural.bytes);
// Both separately emitted objects have a private XOR body. Structural final
// linking must share those bodies without changing the logical call sequence.
for(const [name,mode] of [['provider','sharing-provider'],['client','sharing-client']])writeFileSync(join(directory,name+'.bmo1'),execFileSync(emitter,[mode]));
const sharingObjects=Object.fromEntries(['provider','client'].map(name=>{const path=join(directory,name+'.bmo1');return [name,{sha256:hash(readFileSync(path)),...JSON.parse(execFileSync(emitter,['inspect-object',path],{encoding:'utf8'}))}];}));
assert.equal(sharingObjects.provider.xorInstructions,1);assert.equal(sharingObjects.client.xorInstructions,1);
const recordedProfile=JSON.parse(execFileSync(emitter,['sharing-profile'],{encoding:'utf8'}));
const providerManifest={instances:[{key:'provider',path:'provider.bmo1'}],bindings:[],entry:{instance:'provider',symbol:'compute'},contract:'semantic'};
writeFileSync(join(directory,'link.json'),JSON.stringify(providerManifest));
const unprofiled=execFileSync(join(directory,'boundary-link'),['link.json'],{cwd:directory});
writeFileSync(join(directory,'link.json'),JSON.stringify({...providerManifest,profile:{record:recordedProfile}}));
const profiled=execFileSync(join(directory,'boundary-link'),['link.json'],{cwd:directory});assert.deepEqual(profiled,unprofiled);
report.policy.push({policy:{profile:'valid original provider profile; all counts zero'},result:'accepted; reachable behavior retained',sha256:hash(profiled)});
const sharingManifest={...manifest,contract:'structural',bindings:[{required:{instance:'client',symbol:'compute'},supplied:{instance:'provider',symbol:'compute'}}]};
writeFileSync(join(directory,'link.json'),JSON.stringify(sharingManifest));
const shared=execFileSync(join(directory,'boundary-link'),['link.json'],{cwd:directory}),sharedPath=join(directory,'sharing.bpi3');writeFileSync(sharedPath,shared);
report.sharing={objects:sharingObjects,sha256:hash(shared),...JSON.parse(execFileSync(emitter,['inspect',sharedPath],{encoding:'utf8'}))};
assert.equal(report.sharing.functions,3);assert.equal(report.sharing.xorInstructions,1);
writeFileSync(join(directory,'link.json'),JSON.stringify({...sharingManifest,contract:'semantic',work_limit:0}));
assert.deepEqual(execFileSync(join(directory,'boundary-link'),['link.json'],{cwd:directory}),shared);
report.policy.push({policy:{contract:'semantic',work_limit:0},result:'P01 still shares two private bodies',sha256:hash(shared)});
for(const [x,y] of [[0n,0n],[41n,77n],[0xffffffffffffffffn,0x123456789abcdef0n]]){
 const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});const args=Buffer.alloc(16);args.writeBigUInt64LE(x);args.writeBigUInt64LE(y,8);let input={image:shared,initialArgs:args,quantum:1n},steps=0;
 while(true){const request=world.encodeInput(input),result=k.invoke(request),out=world.decodeOutcome(result),requestPath=join(directory,`sharing-${x}-${steps}.pki3`);writeFileSync(requestPath,request);const checked=spawnSync(native,[requestPath],{timeout:60000,maxBuffer:64<<20});assert.equal(checked.status,0,checked.stderr.toString());assert.deepEqual(checked.stdout,Buffer.from(result));if(out.kind==='completed'){assert.equal(Buffer.from(out.value).readBigUInt64LE(),x);break;}assert.equal(out.kind,'progressed');assert(++steps<64);input={image:shared,state:out.state,quantum:1n};}
 report.executions++;
}
// A summary bound to the wrong function must reject before either optimizer contract.
writeFileSync(join(directory,'provider.bmo1'),execFileSync(emitter,['false-summary']));
writeFileSync(join(directory,'client.bmo1'),execFileSync(emitter,['client']));
for(const contract of ['structural','semantic','off','safe']){
 writeFileSync(join(directory,'link.json'),JSON.stringify({...manifest,contract}));const result=spawnSync(join(directory,'boundary-link'),['link.json'],{cwd:directory});assert.notEqual(result.status,0);assert.equal(result.stdout.length,0);report.rejections.push({contract,error:result.stderr.toString().trim()});
}
report.status='complete';writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({contracts:report.contracts,executions:report.executions,rejections:report.rejections}));
