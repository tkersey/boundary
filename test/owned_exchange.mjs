import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const [worldEntry,kernelPath]=process.argv.slice(2);
const {Kernel,decodeOutcome,decodeRequest,encodeResult}=await import(pathToFileURL(resolve(worldEntry)));
const bytes=new Uint8Array(await readFile(kernelPath)),expectedSha256=createHash('sha256').update(bytes).digest('hex');
let identity=1n;const fresh=()=>Kernel.create({bytes,expectedSha256,instanceId:identity++});
const results=[];
for(const mode of ['dispose','normal','cancel']) {
 const image=new Uint8Array(await readFile(`zig-out/exchange/${mode==='normal'?'normal':'dispose'}.bpi3`));
 let k=await fresh(),p=k.prepare(image),s=k.start(p);k.releasePrepared(p);
 let control='none',value=new Uint8Array(),cancelled=false,transfers=0;const releases=[],work=[],events=[];
 for(let round=0;round<256;round++) {
  const out=decodeOutcome(k.drive(s,{control,value,quantum:7,checkpoint:true}));
  if(out.kind==='completed'||out.kind==='cancelled') {
   assert.equal(out.kind,mode==='cancel'?'cancelled':'completed');
   if(out.kind==='completed')assert.equal(new DataView(out.value.buffer,out.value.byteOffset,8).getBigUint64(0,true),42n);
   else assert.equal(out.reason.value,'global-stop');
   assert.deepEqual(releases,[5,50]);assert.deepEqual(work,mode==='cancel'?[]:mode==='normal'?[[5,7],[50,7]]:[[50,7]]);
   assert.deepEqual(events,mode==='cancel'?['release-5','release-50']:mode==='normal'?['work-5','release-5','work-50','release-50']:['release-5','work-50','release-50']);
   k.close(s);assert.equal(k.usage().workingLive,0n);
   results.push({mode,kind:out.kind,releases,work,events,transfers,imageBytes:image.length});break;
  }
  if(out.kind==='requested') {
   const request=await decodeRequest(out.request);
   if(request.semanticIdentity==='owned-exchange/work') {
    assert.equal(cancelled,false,'ordinary work cannot run after cancellation');
    const view=new DataView(request.payload.buffer,request.payload.byteOffset,request.payload.length);
    work.push([Number(view.getBigUint64(0,true)),Number(view.getBigUint64(8,true))]);
    events.push('work-'+work.at(-1)[0]);control='reply';value=await encodeResult(out.request,new Uint8Array());
   } else {
   assert.equal(request.semanticIdentity,'owned-exchange/release');
   const resource=Number(new DataView(request.payload.buffer,request.payload.byteOffset,8).getBigUint64(0,true));
   if(mode==='cancel'&&!cancelled) {cancelled=true;control='cancel_text';value=new TextEncoder().encode('global-stop');}
   else {releases.push(resource);events.push('release-'+resource);control='reply';value=await encodeResult(out.request,new Uint8Array());}
   }
  } else {assert.equal(out.kind,'progressed');control='none';value=new Uint8Array();}
  const state=k.checkpoint(s,{transfer:true});assert.deepEqual(state,out.state);assert.equal(k.usage().workingLive,0n);
  k=await fresh();p=k.prepare(image);s=k.restore(p,state);k.releasePrepared(p);transfers++;
 }
}
assert.equal(results.length,3);
console.log(JSON.stringify({results,kernelSha256:expectedSha256}));
