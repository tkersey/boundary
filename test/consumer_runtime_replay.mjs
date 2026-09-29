// Replays recorded PKI3 commands only; no model, experiment, approval or file tool
// is dispatched. Expected PKO3 bytes remain the independently checked fixture.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const hash=b=>createHash('sha256').update(b).digest('hex'),median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)],args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,agent,runtimePath,lockPath,manifestPath,name]=args;
 const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs')),runtime=verifyRuntime(runtimePath,{lockPath}),world=await import(pathToFileURL(runtime.entrypoint));
 const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});
 const rows=JSON.parse(readFileSync(manifestPath)).rows.filter(r=>r.name===name).map(r=>{const input=readFileSync(r.inputFile),expected=readFileSync(r.outputFile);assert.equal(hash(input),r.inputSha256);assert.equal(hash(expected),r.outputSha256);return{input,expected};});assert(rows.length);
 const samplesNs=[];let peak=0;
 for(let sample=0;sample<12;sample++){let elapsed=0;for(const {input,expected}of rows){const start=process.hrtime.bigint(),result=k.invoke(input);elapsed+=Number(process.hrtime.bigint()-start);assert.deepEqual(Buffer.from(result),expected);peak=Math.max(peak,Number(k.usage().workingPeak));assert.equal(k.usage().workingLive,0n);}if(sample>=3)samplesNs.push(elapsed);}
 console.log(JSON.stringify({samplesNs,peak,commands:rows.length,kernelSha256:runtime.kernelSha256}));
}else{
 const [agent,oldRuntime,oldLock,newRuntime,newLock,manifestPath,output,baselineManifest]=args;assert(args.length===7||args.length===8);
 const manifest=JSON.parse(readFileSync(manifestPath)),names=[...new Set(manifest.rows.map(r=>r.name))];
 if(baselineManifest){
  const old=JSON.parse(readFileSync(baselineManifest));assert.equal(old.rows.length,manifest.rows.length);
  const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs')),runtime=verifyRuntime(newRuntime,{lockPath:newLock}),world=await import(pathToFileURL(runtime.entrypoint));
  for(let i=0;i<old.rows.length;i++){const a=old.rows[i],b=manifest.rows[i];assert.equal(a.name,b.name);const left=readFileSync(a.outputFile),right=readFileSync(b.outputFile);assert.equal(hash(left),a.outputSha256);assert.equal(hash(right),b.outputSha256);const x=world.decodeOutcome(left),y=world.decodeOutcome(right);assert.equal(x.kind,y.kind);if(x.kind==='requested'){const l=await world.decodeRequest(x.request),r=await world.decodeRequest(y.request);for(const key of ['semanticIdentity','payloadSchema','resumeSchema','payload'])assert.deepEqual(l[key],r[key]);}else{assert.equal(x.kind,'completed');assert.deepEqual(x.value,y.value);}}
 }
 const report={status:'running',scope:baselineManifest?'Cumulative WASM fresh-invocation replay: original pre-cutover images/runtime versus current images/runtime. Each uses its own bound State and expected reply; semantic trace preflight matches identities, schemas, payloads and completed values. External host latency excluded.':'Paired WASM fresh-invocation trace replay, including each recorded image admission and checkpoint restore; excludes external host/model/experiment execution and is not whole-application latency.',manifestSha256:hash(readFileSync(manifestPath)),baselineManifestSha256:baselineManifest?hash(readFileSync(baselineManifest)):null,locks:{before:hash(readFileSync(oldLock)),after:hash(readFileSync(newLock))},rows:[]};
 for(const name of names){const windows=[];for(let w=0;w<5;w++){const results={};for(const arm of w%2?['after','before']:['before','after'])results[arm]=JSON.parse(execFileSync(process.execPath,[new URL(import.meta.url).pathname,'sample',agent,arm==='before'?oldRuntime:newRuntime,arm==='before'?oldLock:newLock,arm==='before'&&baselineManifest?baselineManifest:manifestPath,name],{encoding:'utf8',timeout:180000}));windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});}
  const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4;
  const memoryIncrease=windows.some(w=>w.after.peak-w.before.peak>Math.max(1024,w.before.peak*.01));report.rows.push({name,ratio,confirmedSlowdown,memoryIncrease,deltaNs:median(windows.map(w=>median(w.after.samplesNs)-median(w.before.samplesNs))),windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({name,ratio,confirmedSlowdown,memoryIncrease}));
 }report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
