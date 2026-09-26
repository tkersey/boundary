// Real browser Workers receive only the authenticated runtime and portable bytes.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const [emitter,runtime,digest,native,browserTools]=process.argv.slice(2);
assert.ok(emitter&&runtime&&/^[a-f0-9]{64}$/.test(digest??'')&&native&&browserTools);
assert.equal(process.argv.length,7);
const {chromium,firefox}=await import(pathToFileURL(resolve(browserTools,
  'node_modules/playwright-core/index.mjs')));
const version=JSON.parse(await readFile(join(browserTools,'node_modules/playwright-core/package.json'))).version;
const lock=JSON.parse(await readFile(join(browserTools,'package-lock.json')));
assert.equal(version,lock.packages['node_modules/playwright-core'].version);
const {encodeInput,decodeOutcome,decodeRequest,encodeResult}=await import(
  pathToFileURL(resolve(runtime,'src/embedding/index.mjs')));
const kernel=await readFile(join(runtime,'world-kernel.wasm'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
assert.equal(hash(kernel),digest);
const worker=`import {Kernel} from '/src/embedding/index.mjs';
self.onmessage=async({data})=>{
  try {
    const bytes=new Uint8Array(await(await fetch('/kernel.wasm')).arrayBuffer());
    const kernel=await Kernel.create({bytes,expectedSha256:data.digest});
    kernel.setLimits({input:2<<20,working:8<<20,output:2<<20});
    const output=kernel.invoke(new Uint8Array(data.input));
    self.postMessage({output:Array.from(output)});
  } catch(error) {self.postMessage({error:error.code??error.message,diagnostic:error.details?.diagnostic});}
};`;
const served=new Set();
const server=createServer(async(request,response)=>{
  try {
    const path=new URL(request.url,'http://localhost').pathname;
    served.add(path);
    if(path==='/'){response.end('<!doctype html><title>Coalescing transfer checks</title>');return;}
    if(path==='/kernel.wasm'){response.setHeader('Content-Type','application/wasm');response.end(kernel);return;}
    if(path==='/worker.mjs'){response.setHeader('Content-Type','text/javascript');response.end(worker);return;}
    if(!/^\/src\/embedding\/[a-z-]+\.mjs$/.test(path)){response.writeHead(404);response.end();return;}
    response.setHeader('Content-Type','text/javascript');
    response.end(await readFile(join(runtime,path.slice(1))));
  } catch {response.writeHead(500);response.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url=`http://127.0.0.1:${server.address().port}/`;
const words=values=>{
  const bytes=new Uint8Array(values.length*8),view=new DataView(bytes.buffer);
  values.forEach((value,i)=>view.setBigUint64(i*8,BigInt(value),true));return bytes;
};
const empty=new Uint8Array();
const cases=[
  {kind:'cells_independent',args:empty,result:words([1,1,2])},
  {kind:'cells_shared',args:empty,result:words([1,2,3])},
  {kind:'memo_independent',args:empty,result:words([1,1,2,2])},
  {kind:'memo_shared',args:empty,result:words([1,1,1,1])},
  {kind:'hyper_duplicate',args:words([3,7]),result:words([13,17])},
  {kind:'hyper_configured',args:words([3,7]),result:words([13,18])},
  {kind:'hyper_lazy',args:words([3,7]),result:words([3,7])},
  {kind:'state_local',args:empty,result:Uint8Array.of(2,...words([1,1]))},
  {kind:'state_shared',args:empty,result:Uint8Array.of(2,...words([1,2]))},
  {kind:'cleanup',args:empty,result:words([20]),requests:[
    {identity:'case/lookup',payload:words([19]),reply:words([19])},
    {identity:'case/release',payload:empty,reply:empty},
  ]},
];
for(const item of cases) {
  item.images={};
  for(const mode of ['off','safe']) {
    const child=spawnSync(emitter,[item.kind,'bpi3',mode],{maxBuffer:16<<20});
    assert.equal(child.status,0,child.stderr.toString());
    item.images[mode]=new Uint8Array(child.stdout);
  }
  assert.ok(item.images.safe.length<=item.images.off.length);
}
async function drive(page,fixture,mode) {
  const image=fixture.images[mode],boundaries=[],requests=[];
  let state,control='none',value=empty,firstState;
  for(let step=0;step<1024;step++) {
    const input=encodeInput({image,initialArgs:state?undefined:fixture.args,state,control,value,quantum:1});
    const observed=await page.evaluate(data=>window.invokeWorker(data),{digest,input:Array.from(input)});
    assert.equal(observed.error,undefined,JSON.stringify(observed));
    const nativeOutput=spawnSync(native,['invoke'],{input,maxBuffer:16<<20});
    assert.equal(nativeOutput.status,0,nativeOutput.stderr.toString());
    assert.deepEqual(new Uint8Array(observed.output),new Uint8Array(nativeOutput.stdout));
    const outcome=decodeOutcome(new Uint8Array(observed.output));boundaries.push(outcome.kind);
    if(outcome.kind==='completed') {
      assert.deepEqual(outcome.value,fixture.result);
      assert.equal(requests.length,fixture.requests?.length??0);
      return {boundaries,requests,value:Buffer.from(outcome.value).toString('hex'),firstState};
    }
    assert.ok(['progressed','yielded','requested'].includes(outcome.kind));
    assert.ok(outcome.state?.length);state=outcome.state;firstState??=state;
    if(outcome.kind==='requested') {
      const request=await decodeRequest(outcome.request), expected=fixture.requests?.[requests.length];
      assert.ok(expected,'unexpected request');assert.equal(request.semanticIdentity,expected.identity);
      assert.deepEqual(request.payload,expected.payload);
      requests.push({identity:request.semanticIdentity,effect:request.effect.toString(),
        payload:Buffer.from(request.payload).toString('hex'),
        payloadSchema:Buffer.from(request.payloadSchema).toString('hex'),
        resumeSchema:Buffer.from(request.resumeSchema).toString('hex')});
      value=await encodeResult(outcome.request,expected.reply);control='reply';
    } else {control=outcome.kind==='yielded'?'resume_yield':'none';value=empty;}
  }
  throw Error('finite fixture exceeded declared step bound');
}
const results=[];
try {
  for(const [engine,type] of [['chromium',chromium],['firefox',firefox]]) {
    const browser=await type.launch({headless:true});
    try {
      const page=await browser.newPage();await page.goto(url);
      await page.evaluate(()=>{
        window.workersDestroyed=0;
        window.invokeWorker=data=>new Promise((resolve,reject)=>{
          const worker=new Worker('/worker.mjs',{type:'module'});
          worker.onmessage=event=>{worker.terminate();window.workersDestroyed++;resolve(event.data);};
          worker.onerror=event=>{worker.terminate();reject(new Error(event.message));};
          worker.postMessage(data);
        });
      });
      const rows=[];
      const rejected=await page.evaluate(data=>window.invokeWorker(data),{digest:'0'.repeat(64),input:[]});
      assert.equal(rejected.error,'WORLD_KERNEL_IDENTITY_INVALID');
      for(const fixture of cases) {
        const off=await drive(page,fixture,'off'),safe=await drive(page,fixture,'safe');
        const {firstState:offState,...left}=off,{firstState:safeState,...right}=safe;
        assert.deepEqual(right,left);
        let wrongProgram='same-image';
        if(hash(fixture.images.off)!==hash(fixture.images.safe)) {
          const input=encodeInput({image:fixture.images.safe,state:offState,quantum:1});
          const mismatch=await page.evaluate(data=>window.invokeWorker(data),{digest,input:Array.from(input)});
          assert.equal(mismatch.error,'WORLD_KERNEL_REJECTED');assert.equal(mismatch.diagnostic,'InvalidState');
          wrongProgram='rejected';
        }
        rows.push({fixture:fixture.kind,offBytes:fixture.images.off.length,safeBytes:fixture.images.safe.length,
          offSha256:hash(fixture.images.off),safeSha256:hash(fixture.images.safe),wrongProgram,...right});
      }
      results.push({engine,version:browser.version(),rows,
        workersDestroyed:await page.evaluate(()=>window.workersDestroyed)});
    } finally {await browser.close();}
  }
} finally {await new Promise(resolve=>server.close(resolve));}
console.log(JSON.stringify({scope:'Real Chromium/Firefox Worker/native/fresh Worker transfer for off/safe images',
  runtimeSha256:digest,playwright:version,emitterSha256:hash(await readFile(emitter)),
  nativeSha256:hash(await readFile(native)),servedPaths:[...served].sort(),results},null,2));
