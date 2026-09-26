// Fixed-runtime differential execution; no generated control is reconstructed here.
import assert from 'node:assert/strict';
import {execute as oracle} from './v2/source_oracle.mjs';
import {parseExactJson} from '../tools/v2/exact_json.mjs';
import {readFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const [runtime, native, kind, ...images] = process.argv.slice(2);
assert.ok(runtime && native && images.length);
const {Kernel, encodeInput, decodeOutcome, decodeRequest, encodeResult} =
  await import(pathToFileURL(resolve(runtime, 'src/embedding/index.mjs')));
const bytes = new Uint8Array(await readFile(resolve(runtime,'world-kernel.wasm')));
const expectedSha256 = process.env.WORLD_KERNEL_SHA256 ??
  'df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084';
assert.match(expectedSha256,/^[a-f0-9]{64}$/);
const wasmtime = process.env.WORLD_WASMTIME_PEER
  ? await (await import(pathToFileURL(resolve(process.env.WORLD_WASMTIME_PEER))))
      .wasmtimePeer(resolve(runtime,'world-kernel.wasm'),expectedSha256) : null;
const u64 = n => {const b=new Uint8Array(8);new DataView(b.buffer).setBigUint64(0,BigInt(n),true);return b;};
const i64 = n => {const b=new Uint8Array(8);new DataView(b.buffer).setBigInt64(0,BigInt(n),true);return b;};
const u32 = n => {const b=new Uint8Array(4);new DataView(b.buffer).setUint32(0,n,true);return b;};
const max=(1n<<64n)-1n;
async function execute(image, initialArgs, replies) {
  let state, control='none', value=new Uint8Array(), requests=[], transfers=0;
  const requestContracts=[], boundaries=[];
  for(let round=0;round<1024;round++) {
    const input=encodeInput({image,initialArgs:state ? undefined : initialArgs,state,control,value,quantum:1});
    const kernel=await Kernel.create({bytes,expectedSha256});
    kernel.setLimits({input:2<<20,working:8<<20,output:2<<20});
    const node=kernel.invoke(input);
    const peer=spawnSync(native,['invoke'],{input,maxBuffer:8<<20});
    assert.equal(peer.status,0,peer.stderr.toString());
    assert.deepEqual(node,new Uint8Array(peer.stdout));
    const guest = wasmtime ? (await wasmtime.call('invoke',{bytes:input})).bytes : node;
    assert.deepEqual(guest,node);
    const outcome=decodeOutcome(round%3 === 0 ? guest : round%3 === 1 ? new Uint8Array(peer.stdout) : node);
    boundaries.push(outcome.kind);
    if(['completed','failed'].includes(outcome.kind)) {
      if(outcome.kind==='failed') assert.deepEqual(outcome.cleanupFailures,[]);
      return {kind:outcome.kind,value:Buffer.from(outcome.value).toString('hex'),requests,
        requestContracts,transfers,boundaries,cleanupFailures:outcome.cleanupFailures??[],
        cancellation:outcome.cancellation??null};
    }
    assert.ok(outcome.state?.length,'real portable State required');
    state=outcome.state;transfers++;
    if(outcome.kind==='requested') {
      // Obtain the pending request from the new destination before binding a reply.
      const fresh=await Kernel.create({bytes,expectedSha256});
      fresh.setLimits({input:2<<20,working:8<<20,output:2<<20});
      const restored=decodeOutcome(fresh.invoke(encodeInput({image,state,quantum:1})));
      assert.equal(restored.kind,'requested');
      const request=await decodeRequest(restored.request);
      requestContracts.push({effect:request.effect.toString(),
        identity:Buffer.from(request.semanticIdentityBytes).toString('hex'),
        payloadSchema:Buffer.from(request.payloadSchema).toString('hex'),
        resumeSchema:Buffer.from(request.resumeSchema).toString('hex'),
        payload:Buffer.from(request.payload).toString('hex')});
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
const empty=new Uint8Array();
const fixtureCases = {
  handler_duplicate:[{args:Uint8Array.of(...u64(3),...u64(7)),replies:[],
    value:Uint8Array.of(...u64(13),...u64(17))},
    {args:Uint8Array.of(...u64(3),...u64(max)),replies:[],failure:true}],
  handler_mixed_mode:[{args:Uint8Array.of(...u64(3),...u64(7)),replies:[],
    value:Uint8Array.of(...u64(13),...u64(17))}],
  handler_effect_duplicate:[{args:Uint8Array.of(...u64(3),...u64(7)),replies:[],
    value:Uint8Array.of(...u64(13),...u64(17))}],
  capture_order:[{args:Uint8Array.of(...i64(7),...i64(3)),replies:[],
    value:Uint8Array.of(...i64(4),...i64(-4))},
    {args:Uint8Array.of(...i64(-2),...i64(5)),replies:[],
      value:Uint8Array.of(...i64(-7),...i64(7))},
    {args:Uint8Array.of(...i64(-(1n<<63n)),...i64(1)),replies:[],failure:true}],
  hyper_duplicate:[{args:Uint8Array.of(...u64(3),...u64(7)),replies:[],value:Uint8Array.of(...u64(13),...u64(17))},
    {args:Uint8Array.of(...u64(max),...u64(7)),replies:[],failure:true}],
  hyper_configured:[{args:Uint8Array.of(...u64(3),...u64(7)),replies:[],value:Uint8Array.of(...u64(13),...u64(18))},
    {args:Uint8Array.of(...u64(3),...u64(max-10n)),replies:[],failure:true}],
  hyper_lazy:[{args:Uint8Array.of(...u64(3),...u64(7)),replies:[],value:Uint8Array.of(...u64(3),...u64(7))}],
  cells_independent:[{args:empty,replies:[],value:Uint8Array.of(...u64(1),...u64(1),...u64(2))}],
  cells_shared:[{args:empty,replies:[],value:Uint8Array.of(...u64(1),...u64(2),...u64(3))}],
  memo_independent:[{args:empty,replies:[],value:Uint8Array.of(...u64(1),...u64(1),...u64(2),...u64(2))}],
  memo_shared:[{args:empty,replies:[],value:Uint8Array.of(...u64(1),...u64(1),...u64(1),...u64(1))}],
  state_local:[{args:empty,replies:[],value:Uint8Array.of(2,...u64(1),...u64(1))}],
  state_shared:[{args:empty,replies:[],value:Uint8Array.of(2,...u64(1),...u64(2))}],
  obligations:[{args:empty,replies:[empty],value:u64(42),payload:empty,identity:'case/release'}],
  imported_scoped:[{args:empty,replies:[],value:u64(42)}],
  cleanup_named:[{args:Uint8Array.of(1,...u64(17),0,0),replies:[],value:u64(17)},
    {args:Uint8Array.of(0,0,0),replies:[],value:u64(0)}],
  imported_sequence:[{args:Uint8Array.of(3),replies:[],value:Uint8Array.of(3)}],
  reusable_body:[{args:empty,replies:[],value:u64(200)}],
  arithmetic:[{args:empty,replies:[],value:Uint8Array.of(...u64(7),...u64(3),...u64(10),...u64(2),...u64(1))}],
  arithmetic_fail:[{args:empty,replies:[],failure:true}],
  dispose:[{args:empty,replies:[],value:u64(18)}],
  region:[{args:empty,replies:[],value:u64(42)}],
  configuration:[{args:empty,replies:[],value:Uint8Array.of(...u64(7),...u64(11))}],
  deep:[{args:empty,replies:[],value:u64(100)}],
  shallow:[{args:empty,replies:[],value:u64(43)}],
  transform_deep:[{args:empty,replies:[],value:u64(100)}],
  transform_shallow:[{args:empty,replies:[],value:u64(43)}],
  bypass:[{args:empty,replies:[],value:u64(18)}],
  twice:[{args:empty,replies:[u64(7),u64(11)],value:Uint8Array.of(...u64(7),...u64(11)),
    payload:u64(19),identity:'case/lookup'},
    {args:empty,replies:[u64(23),u64(5)],value:Uint8Array.of(...u64(23),...u64(5)),
    payload:u64(19),identity:'case/lookup'}],
  cleanup:[{args:empty,replies:[u64(19),empty],value:u64(20),trace:[
    {identity:'case/lookup',payload:Buffer.from(u64(19)).toString('hex')},
    {identity:'case/release',payload:''}]}],
  lazy:[{args:empty,replies:[],value:u64(42)}],
  demanded:[{args:empty,replies:[],failure:true}],
  failure_before:[{args:empty,replies:[],failure:true}],
  failure_after:[{args:empty,replies:[u64(19)],failure:true,payload:u64(19),identity:'case/lookup'}],
  match:[{args:Uint8Array.of(0,...u64(7)),replies:[],value:u64(7)},
    {args:Uint8Array.of(1,...u64(7)),replies:[],value:u64(8)}],
};
const cases = kind==='hyper' ? [
  {args:new Uint8Array(),replies:[u64(19)],value:u64(42),payload:u64(19),identity:'hyper/reference'},
  {args:new Uint8Array(),replies:[u64(29)],value:u64(52),payload:u64(19),identity:'hyper/reference'},
  {args:new Uint8Array(),replies:[u64(max)],failure:true,payload:u64(19),identity:'hyper/reference'},
] : kind==='one' ? [
  {args:u32(7),replies:[u32(31)],value:u32(31),payload:u32(7),identity:'example.lookup.v2'},
  {args:u32(19),replies:[u32(5)],value:u32(5),payload:u32(19),identity:'example.lookup.v2'},
] : kind==='client' ? [
  {args:Uint8Array.of(0,...u64(7),...u64(5)),replies:[],value:u64(12)},
  {args:Uint8Array.of(1,...u64(7),...u64(5)),replies:[u64(19),u64(23)],value:u64(47),payload:u64(7),identity:'client/lookup'},
  {args:Uint8Array.of(0,...u64(max),...u64(1)),replies:[],failure:true},
  {args:Uint8Array.of(1,...u64(7),...u64(1)),replies:[u64(max)],failure:true,payload:u64(7),identity:'client/lookup'},
  {args:Uint8Array.of(1,...u64(7),...u64(0)),replies:[u64(max),u64(1)],failure:true,payload:u64(7),identity:'client/lookup'},
  {args:Uint8Array.of(1,...u64(7),...u64(5)),replies:[u64(23),u64(19)],value:u64(47),payload:u64(7),identity:'client/lookup'},
] : fixtureCases[kind] ?? (()=>{throw Error('unknown case');})();
let baseline;
try {
for(const path of images){
  const image=new Uint8Array(await readFile(path));const observations=[];
  for(const test of cases){
    const result=await execute(image,test.args,test.replies);
    assert.equal(result.kind,test.failure?'failed':'completed');
    assert.equal(result.value,Buffer.from(test.failure?new Uint8Array():test.value).toString('hex'));
    assert.equal(result.requests.length,test.replies.length);
    if(test.trace) assert.deepEqual(result.requests,test.trace);
    else for(const request of result.requests){
      assert.equal(request.identity,test.identity);
      assert.equal(request.payload,Buffer.from(test.payload).toString('hex'));
    }
    if(fixtureCases[kind]) {
      const source=parseExactJson(await readFile(path.replace(/\.bpi3$/,'.json'),'utf8'));
      const reference=oracle(source,Array.from(test.args),test.replies.map(x=>Array.from(x)));
      assert.equal(reference.kind.toLowerCase(),result.kind);
      assert.equal(Buffer.from(reference.value).toString('hex'),result.value);
      assert.deepEqual(reference.trace.filter(x=>x.kind==='Requested').map(x=>({
        identity:x.identity,payload:Buffer.from(x.payload).toString('hex')})),result.requests);
    }
    observations.push(result);
    console.log(JSON.stringify({path,imageBytes:image.length,...result}));
  }
  if(baseline)assert.deepEqual(observations,baseline);else baseline=observations;
}

} finally { if(wasmtime) { console.log(JSON.stringify(wasmtime.identity)); await wasmtime.close(); } }
