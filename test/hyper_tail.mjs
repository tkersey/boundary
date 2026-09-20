import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const [entry,kernelPath]=process.argv.slice(2);
const {Kernel,decodeOutcome}=await import(pathToFileURL(resolve(entry)));
const bytes=new Uint8Array(await readFile(kernelPath));
const expectedSha256=createHash('sha256').update(bytes).digest('hex');
const rows=[];let instanceId=1n;
for(const name of ['hyper','direct']){
 const image=new Uint8Array(await readFile(`zig-out/tail/${name}`));
 for(const count of [0,1,7,31,127,512,1024]){
  const kernel=await Kernel.create({bytes,expectedSha256,instanceId:instanceId++});
  kernel.setLimits({input:8<<20,working:32<<20,output:8<<20});
  const program=kernel.prepare(image),input=new Uint8Array(8);new DataView(input.buffer).setBigUint64(0,BigInt(count),true);
  const session=kernel.start(program,input);kernel.releasePrepared(program);
  let checkpoint=kernel.checkpoint(session).length,steps=0;
  for(;;){
   assert.ok(++steps<10000);
   const out=decodeOutcome(kernel.drive(session,{quantum:97,checkpoint:true}));
   if(out.kind==='completed'){
    assert.equal(new DataView(out.value.buffer,out.value.byteOffset,8).getBigUint64(0,true),42n);break;
   }
   assert.equal(out.kind,'progressed');checkpoint=Math.max(checkpoint,out.state.length);
  }
  const peak=Number(kernel.usage().workingPeak);kernel.close(session);assert.equal(kernel.usage().workingLive,0n);
  rows.push({name,count,imageBytes:image.length,peakWorking:peak,sampledCheckpoint:checkpoint,quanta:steps});
 }
}
console.log(JSON.stringify({kernelSha256:expectedSha256,quantum:97,rows}));
