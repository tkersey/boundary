import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,readdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const hash=b=>createHash('sha256').update(b).digest('hex'),median=a=>[...a].sort((a,b)=>a-b)[Math.floor(a.length/2)],args=process.argv.slice(2);
if(args[0]==='sample'){
 const [,agent,runtimePath,lockPath,imagePath]=args;
 const {verifyRuntime}=await import(pathToFileURL(agent+'/tools/agent4/dependencies.mjs'));
 const runtime=verifyRuntime(runtimePath,{lockPath}),world=await import(pathToFileURL(runtime.entrypoint));
 const k=await world.Kernel.create({bytes:readFileSync(runtime.kernelPath),expectedSha256:runtime.kernelSha256});k.setLimits({input:256<<20,working:256<<20,output:256<<20});
 const image=readFileSync(imagePath),samplesNs=[];let peak=0,retained=0;
 for(let i=0;i<12;i++){
  const start=process.hrtime.bigint(),p=k.prepare(image),elapsed=Number(process.hrtime.bigint()-start);
  peak=Math.max(peak,Number(k.usage().workingPeak));retained=Math.max(retained,Number(k.usage().workingLive));k.releasePrepared(p);assert.equal(k.usage().workingLive,0n);
  if(i>=3)samplesNs.push(elapsed);
 }
 console.log(JSON.stringify({kernelSha256:runtime.kernelSha256,imageSha256:hash(image),samplesNs,peak,retained}));
}else{
 const [agent,oldRuntime,oldLock,newRuntime,newLock,corpus,output,baselineCorpus]=args;assert(args.length===7||args.length===8);
 const report={status:'running',scope:baselineCorpus?'Cumulative admission: reconstructed pre-cutover images on prior authenticated runtime versus current images on e89 candidate. No execution claim.':'Same-image Agent corpus admission; previous authenticated runtime versus e89 candidate. Not execution or pre-cutover cumulative qualification.',locks:{before:hash(readFileSync(oldLock)),after:hash(readFileSync(newLock))},rows:[]};
 const names=readdirSync(corpus).filter(f=>f.endsWith('.bpi3')).sort();assert.equal(names.length,18);
 for(const name of names){const windows=[];
  for(let w=0;w<5;w++){const results={};for(const arm of w%2?['after','before']:['before','after']){const selected=arm==='before'&&baselineCorpus?baselineCorpus:corpus;results[arm]=JSON.parse(execFileSync(process.execPath,[new URL(import.meta.url).pathname,'sample',agent,arm==='before'?oldRuntime:newRuntime,arm==='before'?oldLock:newLock,`${selected}/${name}`],{encoding:'utf8',timeout:120000}));assert.equal(results[arm].imageSha256,hash(readFileSync(`${selected}/${name}`)));}if(!baselineCorpus)assert.equal(results.before.imageSha256,results.after.imageSha256);windows.push({...results,ratio:median(results.after.samplesNs)/median(results.before.samplesNs)});}
  const ratio=median(windows.map(w=>w.ratio)),confirmedSlowdown=ratio>1.05&&windows.filter(w=>w.ratio>1.05).length>=4;
  report.rows.push({name,ratio,confirmedSlowdown,deltaNs:median(windows.map(w=>median(w.after.samplesNs)-median(w.before.samplesNs))),memoryIncreases:windows.flatMap(w=>['peak','retained'].filter(key=>w.after[key]-w.before[key]>Math.max(1024,w.before[key]*0.01)).map(key=>({key,before:w.before[key],after:w.after[key]}))),windows});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({name,ratio,confirmedSlowdown}));
 }
 report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
}
