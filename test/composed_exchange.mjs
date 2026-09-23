import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
const [entry,path,nativeTool,peerModule,browserModule,browserTools]=process.argv.slice(2);
const {Kernel,decodeOutcome,decodeRequest,encodeResult,encodeInput}=await import(pathToFileURL(resolve(entry)));
const bytes=await readFile(path),expectedSha256=createHash('sha256').update(bytes).digest('hex');let identity=1n;const results=[];
const peer=peerModule?await(await import(pathToFileURL(resolve(peerModule)))).wasmtimePeer(resolve(path),expectedSha256):null;
const browser=browserModule?await(await import(pathToFileURL(resolve(browserModule)))).browserPeer({worldEntry:entry,kernelPath:path,tools:browserTools,engine:'chromium',sha256:expectedSha256}):null;
try {
for(const mode of ['dispose','finish','right-finish','cancel']){
 const image=await readFile(`zig-out/composed/${mode==='cancel'?'dispose':mode}.bpi3`);
 const fresh=()=>Kernel.create({bytes,expectedSha256,instanceId:identity++});let k=await fresh(),p=k.prepare(image),s=k.start(p);k.releasePrepared(p);
 let control='none',value=new Uint8Array(),cancelled=false,transfers=0;const observed=[],released=[];
 for(let n=0;;n++){
  assert.ok(n<512);const invocation={image,state:k.checkpoint(s),control,value,quantum:7};
  const node=k.drive(s,{control,value,quantum:7,checkpoint:true});let returned=node;
  if(peer){const command=encodeInput(invocation),native=new Uint8Array(execFileSync(nativeTool,['invoke'],{input:command,maxBuffer:16<<20})),independent=(await peer.call('invoke',{bytes:command})).bytes;assert.deepEqual(node,native);assert.deepEqual(independent,native);const choices=[node,native,independent];if(browser){const worker=await browser.invoke(invocation);assert.deepEqual(worker,native);choices.unshift(worker);}returned=choices[n%choices.length];}
  const out=decodeOutcome(returned);
  if(out.kind==='completed'||out.kind==='cancelled'){
   assert.equal(out.kind,mode==='cancel'?'cancelled':'completed');
   if(out.kind==='completed')assert.equal(new DataView(out.value.buffer,out.value.byteOffset,8).getBigUint64(0,true),42n);
   assert.deepEqual(observed,mode==='cancel'?[4n]:mode==='right-finish'?[4n,7n]:[4n,5n,6n,7n]);assert.deepEqual([...released].sort(),[1,2,3,4]);
   k.close(s);assert.equal(k.usage().workingLive,0n);results.push({mode,observed:observed.map(String),released,transfers,imageBytes:image.length});break;
  }
  if(out.kind==='requested'){
   const request=await decodeRequest(out.request);const x=new DataView(request.payload.buffer,request.payload.byteOffset,8).getBigUint64(0,true);
   if(request.semanticIdentity==='pipe/observe'){
    assert.equal(cancelled,false,'ordinary work cannot resume after cancellation');
    if(x===7n)assert.deepEqual([...released].sort(),[1,2,3],'the sibling resumes only after composite cleanup');
    if(mode==='cancel'&&x===5n){cancelled=true;control='cancel_text';value=new TextEncoder().encode('whole execution');}
    else{observed.push(x);const reply=new Uint8Array(8);new DataView(reply.buffer).setBigUint64(0,2n*x,true);control='reply';value=await encodeResult(out.request,reply);}
   }else{assert.equal(request.semanticIdentity,'pipe/release');released.push(Number(x));control='reply';value=await encodeResult(out.request,new Uint8Array());}
  }else{assert.equal(out.kind,'progressed');control='none';value=new Uint8Array();}
  assert.deepEqual(k.checkpoint(s,{transfer:true}),out.state);assert.equal(k.usage().workingLive,0n);
  k=await fresh();p=k.prepare(image);s=k.restore(p,out.state);k.releasePrepared(p);transfers++;
 }
}
console.log(JSON.stringify({results,kernelSha256:expectedSha256,independent:!!peer,browser:browser?.identity,workersDestroyed:browser?.workersDestroyed}));
}finally{if(browser)await browser.close();if(peer)await peer.close();}
