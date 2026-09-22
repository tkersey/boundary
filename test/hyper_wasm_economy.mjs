// Warm-process generic-kernel timing with explicit matched checkpoint obligations.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {execFileSync} from 'node:child_process';
const [entry,oldPath,newPath,output]=process.argv.slice(2);assert(output);
const world=await import(pathToFileURL(resolve(entry))),sha=b=>createHash('sha256').update(b).digest('hex');
const kernels={baseline:await readFile(oldPath),current:await readFile(newPath)};let identity=1n;
await mkdir(output,{recursive:true});
const int=n=>{const b=new Uint8Array(8);new DataView(b.buffer).setBigUint64(0,BigInt(n),true);return b;};
function fold(n){const a=[];const nat=n=>{do{const b=n&127;n=Math.floor(n/128);a.push(b|(n?128:0));}while(n);};for(const x of [1,2]){nat(n);for(let i=0;i<n;i++)a.push(...int(x));}a.push(...int(n));return new Uint8Array(a);}
const cases=[];for(const name of ['hyper','direct'])for(const count of [0,127,512])cases.push({family:'tail',name,count});for(const name of ['hyper','direct','materialized'])cases.push({family:'fold',name,count:128});
const rows=[];
for(const item of cases){
 const image=await readFile(`zig-out/${item.family}/${item.name}`),args=item.family==='tail'?int(item.count):fold(item.count),expected=item.family==='tail'?42n:6n*BigInt(item.count);
 for(const mode of ['uninterrupted','resident','fresh']){
  const row={...item,mode,imageBytes:image.length,imageSha256:sha(image),baseline:[],current:[]};
  async function run(side){
   const bytes=kernels[side],digest=sha(bytes);let checkpoints=0,checkpointBytes=0;
   const fresh=()=>world.Kernel.create({bytes,expectedSha256:digest,instanceId:identity++});
   const started=performance.now();let k=await fresh();k.setLimits({input:8<<20,working:32<<20,output:8<<20});
   let p=k.prepare(image),s=k.start(p,args);k.releasePrepared(p);
   let value;
   for(let step=0;;step++){
    assert(step<10000);const result=world.decodeOutcome(k.drive(s,{quantum:mode==='uninterrupted'?null:97,checkpoint:false}));
    if(result.kind==='completed'){value=result.value;k.close(s);break;}
    assert.equal(result.kind,'progressed');const state=k.checkpoint(s,{transfer:mode==='fresh'});checkpoints++;checkpointBytes+=state.length;
    if(mode==='fresh'){k=await fresh();k.setLimits({input:8<<20,working:32<<20,output:8<<20});p=k.prepare(image);s=k.restore(p,state);k.releasePrepared(p);}
   }
   const ns=(performance.now()-started)*1e6;
   assert.equal(new DataView(value.buffer,value.byteOffset,8).getBigUint64(0,true),expected);assert.equal(k.usage().workingLive,0n);
   return{ns,checkpoints,checkpointBytes};
  }
  for(let i=0;i<8;i++)for(const side of i%2?['current','baseline']:['baseline','current']){const r=await run(side);if(i>=3)row[side].push(r);}
  for(const side of ['baseline','current']){const p=join(output,`${item.family}-${item.name}-${item.count}-${mode}-${side}.txt`);await writeFile(p,row[side].map(x=>x.ns).join('\n'));row[side+'Summary']=JSON.parse(execFileSync('bench_stats',['--input',p,'--json','--unit','ns'],{encoding:'utf8'}));assert.equal(new Set(row[side].map(x=>x.checkpoints+':'+x.checkpointBytes)).size,1);}
  row.ratio=row.currentSummary.median/row.baselineSummary.median;rows.push(row);console.log(JSON.stringify({family:item.family,name:item.name,count:item.count,mode,baselineNs:row.baselineSummary.median,currentNs:row.currentSummary.median,ratio:row.ratio}));
 }
}
for(const item of cases)for(const side of ['baseline','current']){const matched=rows.filter(r=>r.family===item.family&&r.name===item.name&&r.count===item.count&&r.mode!=='uninterrupted').map(r=>r[side][0]);assert.deepEqual(matched[0]&&[matched[0].checkpoints,matched[0].checkpointBytes],matched[1]&&[matched[1].checkpoints,matched[1].checkpointBytes]);}
await writeFile(join(output,'results.json'),JSON.stringify({format:'hyper-wasm-economy/v1',kernelHashes:Object.fromEntries(Object.entries(kernels).map(([k,v])=>[k,sha(v)])),scope:'Node warm-process end-to-end Kernel.create/prepare/run/encode; fresh also readmit/restore at every quantum; no disk durability, cold compilation, service percentile or native inference',warmups:3,pairedSamples:5,rows},null,2)+'\n');
