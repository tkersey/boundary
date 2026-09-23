import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const [worldEntry,kernelPath,nativeTool,peerPath,browserModule,browserTools,mode='clone']=process.argv.slice(2);
assert(worldEntry&&kernelPath);assert(['clone','reentrant'].includes(mode));assert.equal(!!nativeTool,!!peerPath);assert(!browserTools||peerPath&&browserModule);
const world=await import(pathToFileURL(resolve(worldEntry))),bytes=await readFile(kernelPath),image=await readFile(mode==='clone'?'zig-out/hyper-multishot.bpi3':'zig-out/hyper-reentrant.bpi3');
const sha256=createHash('sha256').update(bytes).digest('hex');let identity=1n,peer,browser;
const area=await mkdtemp(join(tmpdir(),'hyper-clone-'));await writeFile(join(area,'observation'),'permitted observation');
const row=(branch,local,shared,answer)=>{const b=new Uint8Array(25);b[0]=Number(branch);for(const [i,n]of [local,shared,answer].entries())new DataView(b.buffer).setBigUint64(1+i*8,BigInt(n),true);return b;};
const expected=[row(false,1,1,39),row(true,1,2,40)];
const expectedValue=mode==='clone'?new Uint8Array([2,...expected[0],...expected[1]]):new Uint8Array([145,0,0,0,0,0,0,0]);
try{
 if(peerPath)peer=await(await import(pathToFileURL(resolve(peerPath)))).wasmtimePeer(resolve(kernelPath),sha256);
 if(browserTools)browser=await(await import(pathToFileURL(resolve(browserModule)))).browserPeer({worldEntry:resolve(worldEntry),kernelPath:resolve(kernelPath),tools:browserTools,engine:'chromium',sha256});
 const fresh=()=>world.Kernel.create({bytes,expectedSha256:sha256,instanceId:identity++});
 let k=await fresh(),p=k.prepare(image),s=k.start(p,new Uint8Array());k.releasePrepared(p);
 let control='none',value=new Uint8Array(),observations=0,transfers=0,yields=0;const engines=[];
 for(let i=0;;i++){
  assert(i<256);const invocation={image,state:k.checkpoint(s),control,value,quantum:11};
  const node=k.drive(s,{control,value,quantum:11,checkpoint:true});let returned=node,engine='Node';
  if(peer){const command=world.encodeInput(invocation),native=new Uint8Array(execFileSync(nativeTool,['invoke'],{input:command,maxBuffer:16<<20})),other=(await peer.call('invoke',{bytes:command})).bytes;assert.deepEqual(node,native);assert.deepEqual(other,native);const choices=[[node,'Node'],[native,'native'],[other,'Wasmtime']];if(browser){const actual=await browser.invoke(invocation);assert.deepEqual(actual,native);choices.unshift([actual,'Chromium Worker']);}[returned,engine]=choices[i%choices.length];}
  engines.push(engine);const out=world.decodeOutcome(returned);
  if(out.kind==='completed'){assert.deepEqual(out.value,expectedValue);assert.equal(observations,mode==='clone'?2:0);assert.equal(yields,mode==='clone'?0:1);k.close(s);assert.equal(k.usage().workingLive,0n);break;}
  if(out.kind==='requested'){
   const request=await world.decodeRequest(out.request);assert.equal(request.semanticIdentity,'hyper/clone-observe');assert(observations<2);assert.deepEqual(request.payload,expected[observations]);
   assert.equal(await readFile(join(area,'observation'),'utf8'),'permitted observation');observations++;
   control='reply';value=await world.encodeResult(out.request,new Uint8Array());
  }else if(out.kind==='yielded'){yields++;control='resume_yield';value=new Uint8Array();}
  else{assert.equal(out.kind,'progressed');control='none';value=new Uint8Array();}
  assert.deepEqual(k.checkpoint(s,{transfer:true}),out.state);k=await fresh();p=k.prepare(image);s=k.restore(p,out.state);k.releasePrepared(p);transfers++;
 }
 console.log(JSON.stringify({mode,yields,imageBytes:image.length,observations,transfers,engines,browser:browser?.identity,workersDestroyed:browser?.workersDestroyed,kernel:sha256}));
}finally{if(browser)await browser.close();if(peer)await peer.close();await rm(area,{recursive:true,force:true});}
