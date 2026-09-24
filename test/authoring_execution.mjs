// Fixed-runtime differential execution; no generated control is reconstructed here.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const [runtime, native, kind, ...images] = process.argv.slice(2);
assert.ok(runtime && native && images.length);
const {Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult} =
  await import(pathToFileURL(resolve(runtime, 'src/embedding/index.mjs')));
const bytes = new Uint8Array(await readFile(resolve(runtime,'world-kernel.wasm')));
const expectedSha256 = 'df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084';
const u64 = n => {const b=new Uint8Array(8);new DataView(b.buffer).setBigUint64(0,BigInt(n),true);return b;};
const u32 = n => {const b=new Uint8Array(4);new DataView(b.buffer).setUint32(0,n,true);return b;};
const max=(1n<<64n)-1n;
async function execute(image, initialArgs, replies) {
  let state, control='none', value=new Uint8Array(), requests=[], transfers=0;
  for(let round=0;round<1024;round++) {
    const input=encodeInput({image,initialArgs:state ? undefined : initialArgs,state,control,value,quantum:1});
    const kernel=await Kernel.create({bytes,expectedSha256});
    kernel.setLimits({input:2<<20,working:8<<20,output:2<<20});
    const node=kernel.invoke(input);
    const peer=spawnSync(native,['invoke'],{input,maxBuffer:8<<20});
    assert.equal(peer.status,0,peer.stderr.toString());
    assert.deepEqual(node,new Uint8Array(peer.stdout));
    const outcome=decodeOutcome(round%2 ? new Uint8Array(peer.stdout) : node);
    if(['completed','failed'].includes(outcome.kind))
      return {kind:outcome.kind,value:Buffer.from(outcome.value).toString('hex'),requests,transfers};
    assert.ok(outcome.state?.length,'real portable State required');
    state=outcome.state;transfers++;
    if(outcome.kind==='requested') {
      // Obtain the pending request from the new destination before binding a reply.
      const fresh=await Kernel.create({bytes,expectedSha256});
      fresh.setLimits({input:2<<20,working:8<<20,output:2<<20});
      const restored=decodeOutcome(fresh.invoke(encodeInput({image,state,quantum:1})));
      assert.equal(restored.kind,'requested');
      const request=await decodeRequest(restored.request);
      requests.push({identity:request.semanticIdentity,payload:Buffer.from(request.payload).toString('hex')});
      assert.ok(requests.length<=replies.length,'unexpected external request');
      value=await encodeResult(restored.request,replies[requests.length-1]);control='reply';
    } else {
      assert.ok(['progressed','yielded'].includes(outcome.kind));
      control=outcome.kind==='yielded'?'resume_yield':'none';value=new Uint8Array();
    }
  }
  throw Error('finite observation horizon exceeded');
}
const cases = kind==='hyper' ? [
  {args:new Uint8Array(),replies:[u64(19)],value:u64(42),payload:u64(19),identity:'hyper/reference'},
  {args:new Uint8Array(),replies:[u64(29)],value:u64(52),payload:u64(19),identity:'hyper/reference'},
  {args:new Uint8Array(),replies:[u64(max)],failure:true,payload:u64(19),identity:'hyper/reference'},
] : kind==='one' ? [
  {args:u32(7),replies:[u32(31)],value:u32(31),payload:u32(7),identity:'example.lookup.v2'},
  {args:u32(19),replies:[u32(5)],value:u32(5),payload:u32(19),identity:'example.lookup.v2'},
] : kind==='client' ? [
  {args:Uint8Array.of(0,...u64(19),...u64(3)),replies:[],value:u64(22)},
  {args:Uint8Array.of(1,...u64(19),...u64(3)),replies:[u64(7),u64(11)],value:u64(21),payload:u64(19),identity:'client/lookup'},
  {args:Uint8Array.of(1,...u64(19),...u64(3)),replies:[u64(23),u64(5)],value:u64(31),payload:u64(19),identity:'client/lookup'},
  {args:Uint8Array.of(0,...u64(max),...u64(1)),replies:[],failure:true},
  {args:Uint8Array.of(1,...u64(19),...u64(1)),replies:[u64(max),u64(2)],failure:true,payload:u64(19),identity:'client/lookup'},
] : (()=>{throw Error('unknown case');})();
let baseline;
for(const path of images){
  const image=new Uint8Array(await readFile(path));const observations=[];
  for(const test of cases){
    const result=await execute(image,test.args,test.replies);
    assert.equal(result.kind,test.failure?'failed':'completed');
    assert.equal(result.value,Buffer.from(test.failure?new Uint8Array():test.value).toString('hex'));
    assert.equal(result.requests.length,test.replies.length);
    for(const request of result.requests){
      assert.equal(request.identity,test.identity);
      assert.equal(request.payload,Buffer.from(test.payload).toString('hex'));
    }
    observations.push({kind:result.kind,value:result.value,requests:result.requests});
    console.log(JSON.stringify({path,imageBytes:image.length,...result}));
  }
  if(baseline)assert.deepEqual(observations,baseline);else baseline=observations;
}
