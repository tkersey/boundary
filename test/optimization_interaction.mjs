import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const [emitter,embedding,kernelPath,kernelSha256,output]=process.argv.slice(2);
assert.equal(process.argv.length,7);
const world=await import(pathToFileURL(embedding));
const bytes=readFileSync(kernelPath);
const sha=b=>createHash('sha256').update(b).digest('hex');
assert.match(kernelSha256,/^[a-f0-9]{64}$/);assert.equal(sha(bytes),kernelSha256);
const rows=[];
for(const mode of ['original','selected','shared']){
 const image=execFileSync(emitter,[mode]);
 for(const words of [[7n,11n,13n,42n],[0n,1n,2n,0xffffffffffffffffn],[99n,98n,97n,0n]]){
  const args=Buffer.alloc(32);words.forEach((word,i)=>args.writeBigUInt64LE(word,i*8));
  let input={image,initialArgs:args,quantum:1n},steps=0,checkpointBytes=0;
  while(true){
   const kernel=await world.Kernel.create({bytes,expectedSha256:kernelSha256});
   const outcome=world.decodeOutcome(kernel.invoke(world.encodeInput(input)));assert.equal(kernel.usage().workingLive,0n);assert(++steps<64);
   if(outcome.kind==='completed'){assert.equal(Buffer.from(outcome.value).readBigUInt64LE(),words[3]);break;}
   assert.equal(outcome.kind,'progressed');checkpointBytes=Math.max(checkpointBytes,outcome.state.length);input={image,state:outcome.state,quantum:1n};
  }
  rows.push({mode,imageBytes:image.length,imageSha256:sha(image),input:words.map(String),result:String(words[3]),steps,checkpointBytes});
 }
}
writeFileSync(output,JSON.stringify({status:'passed',kernelSha256,scope:'Independent expected scalar result for original/staged/shared images; each quantum-one checkpoint resumes in a fresh WASM instance. Cross-image step equality is not claimed.',rows},null,2)+'\n');console.log(JSON.stringify({rows:rows.length,imageBytes:rows.filter((_,i)=>i%3===0).map(r=>[r.mode,r.imageBytes]),boundaries:rows.reduce((s,r)=>s+r.steps,0)}));
