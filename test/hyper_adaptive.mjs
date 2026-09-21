import assert from 'node:assert/strict';
import {readFile,writeFile,copyFile,mkdtemp,readdir,chmod,rm,access} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {execFileSync,spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {reference,ObservationLimit} from './hyperfunction_reference.mjs';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
if(process.argv[2]==='--run'){
 const [entry,kernelPath]=process.argv.slice(3);
 const {Kernel,decodeOutcome}=await import(pathToFileURL(resolve(entry)));
 const bytes=await readFile(kernelPath),expectedSha256=hash(bytes),max=(1n<<64n)-1n;
 const checked=n=>{if(n>max)throw Error('overflow');return n;};
 function expected(input,invert){
  const r=reference(1024),[seed,a,b,ignore]=input;
  const producer=(s,query)=>r.delay(()=>{
   if(s.stage!==0)return s.stage===1?s.seed:checked(s.seed+(s.stage===2?10n:20n));
   const first=r.force(query({stage:1,seed:s.seed}));
   const second=r.force(query({stage:first?2:3,seed:s.seed}));
   return (first?10n:20n)+(second?1n:2n);
  });
  const consumer=(state,query)=>r.delay(()=>{
   if(state.ignore)return true;
   const value=checked(r.force(query(state))+1n),matches=value===state.a||value===state.b;
   return invert?!matches:matches;
  });
  return r.force(r.invoke(r.ana(producer,{stage:0,seed}),r.delay(()=>r.ana(consumer,{a,b,ignore}))));
 }
 const cases=[[4n,5n,15n,false],[4n,25n,99n,false],[4n,15n,99n,false],[4n,0n,1n,false],[max,0n,0n,true],[max,0n,0n,false],[max-1n,max,0n,false]];
 let seed=0x71c3a19f;const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;};
 for(let i=0;i<64;i++)cases.push([BigInt(random()%21),BigInt(random()%42),BigInt(random()%42),i%17===0]);
 for(const invert of [false,true])assert.deepEqual(cases.slice(0,5).map(input=>expected(input,invert)),invert?[21n,11n,12n,11n,11n]:[11n,21n,22n,22n,11n]);
 const results=[];let identity=1n;
 for(const name of ['normal','invert']){
  const image=new Uint8Array(await readFile(name+'.bpi3'));let completed=0,failed=0,transfers=0;
  for(const input of cases){
   let wanted;try{wanted={kind:'completed',value:expected(input,name==='invert')};}catch(error){assert(!(error instanceof ObservationLimit),'reference budget is not an answer');assert.equal(error.message,'overflow');wanted={kind:'failed'};}
   const encoded=new Uint8Array(25),view=new DataView(encoded.buffer);for(let i=0;i<3;i++)view.setBigUint64(i*8,input[i],true);encoded[24]=Number(input[3]);
   const fresh=()=>Kernel.create({bytes,expectedSha256,instanceId:identity++});
   let k=await fresh(),p=k.prepare(image),s=k.start(p,encoded);k.releasePrepared(p);
   for(let round=0;;round++){
    assert.ok(round<256);const out=decodeOutcome(k.drive(s,{quantum:7,checkpoint:true}));
    if(out.kind==='completed'||out.kind==='failed'){
     assert.equal(out.kind,wanted.kind,`${name}: ${input}`);
     if(out.kind==='completed'){assert.equal(new DataView(out.value.buffer,out.value.byteOffset,8).getBigUint64(0,true),wanted.value);completed++;}else{assert.equal(out.value.length,0);failed++;}
     k.close(s);assert.equal(k.usage().workingLive,0n);break;
    }
    assert.equal(out.kind,'progressed');assert.deepEqual(k.checkpoint(s,{transfer:true}),out.state);
    k=await fresh();p=k.prepare(image);s=k.restore(p,out.state);k.releasePrepared(p);transfers++;
   }
  }
  results.push({name,cases:cases.length,completed,failed,transfers,imageBytes:image.length,imageSha256:hash(image)});
 }
 console.log(JSON.stringify({results,kernelSha256:expectedSha256,seed:'0x71c3a19f'}));
}else{
 const [linker,objects,world,kernel]=process.argv.slice(2);assert(linker&&objects&&world&&kernel);
 if(process.platform!=='darwin')throw Error('source-access denial witness requires the existing macOS sandbox-exec facility');
 const sourceRoot=resolve(import.meta.dirname,'..'),sourceFile=join(sourceRoot,'examples/hyper_adaptive.zig');await access(sourceFile);
 const directory=await mkdtemp(join(tmpdir(),'hyper-source-free-'));
 try{
  const tool=join(directory,'boundary-link');await copyFile(resolve(linker),tool);await chmod(tool,0o755);
  const digests={};for(const name of ['producer','producer-reversed','consumer','consumer-invert','support','entry']){const bytes=await readFile(join(objects,name+'.bmo1'));digests[name]=hash(bytes);await writeFile(join(directory,name+'.bmo1'),bytes);}
  assert.deepEqual((await readdir(directory)).sort(),['boundary-link','consumer-invert.bmo1','consumer.bmo1','entry.bmo1','producer-reversed.bmo1','producer.bmo1','support.bmo1']);
  // This is a source-access test for trusted tooling, not a candidate-code sandbox.
  const profile=`(version 1)(allow default)(deny file-read* (subpath ${JSON.stringify(sourceRoot)}))(deny process-exec (subpath ${JSON.stringify(sourceRoot)}))`;
  const denied=spawnSync('/usr/bin/sandbox-exec',['-p',profile,'/bin/cat',sourceFile],{encoding:'utf8'});
  assert.notEqual(denied.status,0);assert.match(denied.stderr,/Operation not permitted/);
  const manifest=invert=>({instances:['producer','consumer','support','entry'].map(key=>({key,path:(key==='consumer'&&invert?'consumer-invert':key)+'.bmo1'})),bindings:[['producer','create'],['consumer','create'],['support','invoke']].map(([symbol,target])=>({required:{instance:'entry',symbol},supplied:{instance:symbol,symbol:target}})),entry:{instance:'entry',symbol:'main'}});
  for(const invert of [false,true]){
   await writeFile(join(directory,'link.json'),JSON.stringify(manifest(invert)));
   const image=execFileSync('/usr/bin/sandbox-exec',['-p',profile,tool,'link.json'],{cwd:directory,maxBuffer:1<<20});
   await writeFile(join(directory,(invert?'invert':'normal')+'.bpi3'),image);
  }
  for(const kind of ['unresolved','reversed']){
   const bad=manifest(false);if(kind==='unresolved')bad.bindings.pop();else bad.instances[0].path='producer-reversed.bmo1';
   await writeFile(join(directory,'bad.json'),JSON.stringify(bad));
   const rejected=spawnSync('/usr/bin/sandbox-exec',['-p',profile,tool,'bad.json'],{cwd:directory,encoding:'utf8'});
   assert.notEqual(rejected.status,0);assert.equal(rejected.stdout,'');assert.match(rejected.stderr,kind==='unresolved'?/UnresolvedImport/:/IncompatibleInterface/);
  }
  for(const[name,digest]of Object.entries(digests))assert.equal(hash(await readFile(join(directory,name+'.bmo1'))),digest);
  await copyFile(new URL(import.meta.url),join(directory,'hyper_adaptive.mjs'));
  await copyFile(new URL('./hyperfunction_reference.mjs',import.meta.url),join(directory,'hyperfunction_reference.mjs'));
  const output=execFileSync('/usr/bin/sandbox-exec',['-p',profile,process.execPath,join(directory,'hyper_adaptive.mjs'),'--run',resolve(world),resolve(kernel)],{cwd:directory,encoding:'utf8',timeout:60000,maxBuffer:1<<20});
  console.log(JSON.stringify({sourceAccess:'denied while linking and executing',emitterAvailable:false,objects:digests,execution:JSON.parse(output)}));
 }finally{await rm(directory,{recursive:true,force:true});}
}
