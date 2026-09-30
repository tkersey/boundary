// Same-image runtime comparison; local candidate bytes are not a delivered bundle.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const hash=b=>createHash('sha256').update(b).digest('hex');
const median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)];
const args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,embedding,kernelPath,imagePath,inputPath,phase,expected,argumentsHex]=args;
 const world=await import(pathToFileURL(embedding)),kernelBytes=readFileSync(kernelPath);
 const k=await world.Kernel.create({bytes:kernelBytes,expectedSha256:hash(kernelBytes)});
 k.setLimits({input:256<<20,working:256<<20,output:256<<20});
 const image=readFileSync(imagePath),request=readFileSync(inputPath),initialArgs=Buffer.from(argumentsHex,'hex');
 const samplesNs=[];
 for(let window=0;window<12;window++){
  const batch=phase==='cycle'?1:64;let elapsed=0;
  for(let i=0;i<batch;i++){
   const start=process.hrtime.bigint();
   if(phase==='admission'){const p=k.prepare(image);elapsed+=Number(process.hrtime.bigint()-start);k.releasePrepared(p);}
   else{
    let out=k.invoke(phase==='cycle'?world.encodeInput({image,initialArgs,quantum:1n}):request),decoded=world.decodeOutcome(out),count=0;
    while(decoded.kind==='progressed'){
     assert(phase==='cycle'&&++count<4096);
     out=k.invoke(world.encodeInput({image,state:decoded.state,quantum:1n}));decoded=world.decodeOutcome(out);
    }
    elapsed+=Number(process.hrtime.bigint()-start);assert.equal(hash(out),expected);
   }
   assert.equal(k.usage().workingLive,0n);
  }
  if(window>=3)samplesNs.push(elapsed/batch);
 }
 console.log(JSON.stringify({samplesNs,peakBytes:Number(k.usage().workingPeak)}));
}else{
 const [embedding,oldKernel,newKernel,oldNative,newNative,corpus,output]=args;
 assert.equal(args.length,7);
 const kernels={control:oldKernel,candidate:newKernel},natives={control:oldNative,candidate:newNative};
 const report={status:'running',scope:'Same-image local runtime tuning; candidate is not an authenticated delivered artifact',embeddingSha256:hash(readFileSync(embedding)),kernels:Object.fromEntries(Object.entries(kernels).map(([k,p])=>[k,{path:p,sha256:hash(readFileSync(p))}])),natives:Object.fromEntries(Object.entries(natives).map(([k,p])=>[k,{path:p,sha256:hash(readFileSync(p))}])),protocol:'Alternating independent processes; 3 warmups, 9 samples; 3 windows, extended to 5 if any ratio exceeds 1.05; confirmed only with median >1.05 and >=4/5 ratios >1.05',cells:[]};
 for(const family of ['affine','guard','access'])for(const n of [0,1,7,50]){
  const image=`${corpus}/${family}-semantic.bpi3`,input=`${corpus}/${family}-${n}-semantic-fresh-0.pki3`;
  const world=await import(pathToFileURL(embedding)),oldBytes=readFileSync(oldKernel),k=await world.Kernel.create({bytes:oldBytes,expectedSha256:hash(oldBytes)});
  k.setLimits({input:256<<20,working:256<<20,output:256<<20});
  const expected=hash(k.invoke(readFileSync(input)));
  const initialArgs=Buffer.alloc(family==='affine'?1:family==='access'?17:24);
  if(family==='guard')initialArgs.writeBigUInt64LE(BigInt(n));else initialArgs[0]=n;
  if(family!=='affine'){const offset=family==='access'?1:8;initialArgs.writeBigUInt64LE(5n,offset);initialArgs.writeBigUInt64LE(3n,offset+8);}
  assert.deepEqual(Buffer.from(world.encodeInput({image:readFileSync(image),initialArgs})),readFileSync(input));
  for(const engine of ['native','wasm'])for(const phase of ['admission','fresh','cycle']){
   if(phase==='admission'&&n!==0)continue;const windows=[];
   for(let w=0;w<5;w++){
    if(w===3&&!windows.some(x=>x.ratio>1.05))break;
    const order=w%2?['candidate','control']:['control','candidate'],results={};
    for(const arm of order)results[arm]=JSON.parse(execFileSync(engine==='native'?natives[arm]:process.execPath,engine==='native'?[phase,phase==='admission'?image:input,...(phase==='admission'?[]:[expected])]:[new URL(import.meta.url).pathname,'sample',embedding,kernels[arm],image,input,phase,expected,initialArgs.toString('hex')],{encoding:'utf8',timeout:120000}));
    windows.push({order,...results,ratio:median(results.candidate.samplesNs)/median(results.control.samplesNs)});
   }
   const ratio=median(windows.map(w=>w.ratio));
   report.cells.push({family,n,engine,phase,imageSha256:hash(readFileSync(image)),inputSha256:hash(readFileSync(input)),windows,medianRatio:ratio,pairedMedianDeltaNs:median(windows.map(w=>median(w.candidate.samplesNs)-median(w.control.samplesNs))),confirmedSlowdown:windows.length===5&&ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4});
   writeFileSync(output,JSON.stringify(report,null,2)+'\n');
  }
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({cells:report.cells.length,confirmed:report.cells.filter(c=>c.confirmedSlowdown).length}));
}
