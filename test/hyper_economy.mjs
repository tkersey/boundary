// Matched native fresh invocation/restore measurements; existing Zig replay owns clocks.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const [entry,kernelPath,baseline,current,output]=process.argv.slice(2);assert(output);
const world=await import(pathToFileURL(resolve(entry)));
const bytes=await readFile(kernelPath),sha=b=>createHash('sha256').update(b).digest('hex');
const kernel=await world.Kernel.create({bytes,expectedSha256:sha(bytes),instanceId:1n});
kernel.setLimits({input:8<<20,working:32<<20,output:8<<20});
await mkdir(output,{recursive:true});
const integer=n=>{const b=new Uint8Array(8);new DataView(b.buffer).setBigUint64(0,BigInt(n),true);return b;};
function foldInput(n){const out=[];const nat=n=>{do{const b=n&127;n=Math.floor(n/128);out.push(b|(n?128:0));}while(n);};for(const value of [1,2]){nat(n);for(let i=0;i<n;i++)out.push(...integer(value));}out.push(...integer(n));return new Uint8Array(out);}
const records=[];
for(const [family,names,counts]of [['tail',['hyper','direct'],[0,31,127,512]],['fold',['hyper','direct','materialized'],[0,31,128,512]]]){
 for(const name of names)for(const count of counts){
  const image=await readFile(`zig-out/${family}/${name}`),args=family==='tail'?integer(count):foldInput(count),wanted=family==='tail'?42n:6n*BigInt(count);
  // Independent numerical meaning verifies the actual complete portable result.
  const expected=kernel.invoke(world.encodeInput({image,initialArgs:args})),decoded=world.decodeOutcome(expected);
  assert.equal(decoded.kind,'completed');assert.equal(new DataView(decoded.value.buffer,decoded.value.byteOffset,8).getBigUint64(0,true),wanted);
  const expectedHash=sha(expected);
  const p=kernel.prepare(image),s=kernel.start(p,args),state=kernel.checkpoint(s,{transfer:true});kernel.releasePrepared(p);assert.equal(kernel.usage().workingLive,0n);
  for(const mode of ['initial','restore']){
   const input=world.encodeInput({image,...(mode==='initial'?{initialArgs:args}:{state})}),id=`${family}-${name}-${count}-${mode}`;
   const inputPath=join(output,id+'.pki3');await writeFile(inputPath,input);
   const row={id,family,name,count,mode,imageBytes:image.length,imageSha256:sha(image),inputBytes:input.length,inputSha256:sha(input),checkpointBytes:state.length,expectedHash,baseline:[],current:[]};
   for(let pair=0;pair<3;pair++){
    for(const [label,tool]of pair%2?[['current',current],['baseline',baseline]]:[['baseline',baseline],['current',current]]){
     const result=JSON.parse(execFileSync(tool,[expectedHash],{input,maxBuffer:1<<20,encoding:'utf8'}));
     assert.equal(result.inputSha256,row.inputSha256);assert.equal(result.outputSha256,expectedHash);
     row[label].push(result);
    }
   }
   for(const label of ['baseline','current']){
    const samples=row[label].map(r=>[...r.samplesNs].sort((a,b)=>a-b)[4]);
    const path=join(output,id+'-'+label+'.txt');await writeFile(path,samples.join('\n')+'\n');
    row[label+'Summary']=JSON.parse(execFileSync('bench_stats',['--input',path,'--unit','ns','--json'],{encoding:'utf8'}));
   }
   row.ratio=row.currentSummary.median/row.baselineSummary.median;
   records.push(row);console.log(JSON.stringify({id,baselineNs:row.baselineSummary.median,currentNs:row.currentSummary.median,ratio:row.ratio}));
  }
 }
}
await writeFile(join(output,'results.json'),JSON.stringify({format:'hyper-native-economy/v1',sampleUnit:'median of nine in-process fresh invocations, three paired processes, three warmups each',preservation:'exact complete outcome bytes after independent numerical result check',limits:'no tail percentile, service load, resident timing or WASM timing claim',baselineBinary:sha(await readFile(baseline)),currentBinary:sha(await readFile(current)),oracleKernel:sha(bytes),records},null,2)+'\n');
