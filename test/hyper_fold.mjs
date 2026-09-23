import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const [worldEntry,kernelPath]=process.argv.slice(2);
const {Kernel,decodeOutcome}=await import(pathToFileURL(resolve(worldEntry)));
const bytes=new Uint8Array(await readFile(kernelPath));
const expectedSha256=createHash('sha256').update(bytes).digest('hex');
const images=await Promise.all(['hyper','direct','materialized'].map(async name=>[name,new Uint8Array(await readFile(`zig-out/fold/${name}`))]));
const max=(1n<<64n)-1n;
function checked(n){if(n<0n||n>max)throw Error('overflow');return n;}
// Independent numerical meaning: no production callbacks or dispatcher.
function reference(xs,ys,limit){
  const pairs=[];
  for(let i=0;i<Math.min(xs.length,ys.length,Number(limit));i++) {
    const y=checked(ys[i]*2n),x=checked(xs[i]+1n);pairs.push([x,y]);
  }
  let result=0n;
  for(let i=pairs.length-1;i>=0;i--)result=checked(checked(pairs[i][0]+pairs[i][1])+result);
  return result;
}
function encode(xs,ys,limit){
  const out=[];const nat=n=>{do{const byte=n&127;n=Math.floor(n/128);out.push(byte|(n?128:0));}while(n);};
  const integer=n=>{for(let i=0;i<8;i++){out.push(Number(n&255n));n>>=8n;}};
  for(const values of [xs,ys]){nat(values.length);for(const value of values)integer(value);}integer(limit);
  return Uint8Array.from(out);
}
const cases=[
  [[],[],0n],[[max],[max],0n],[[max],[],10n],[[],[max],10n],
  [[1n,2n,max],[3n,4n,max],2n],[[1n,max],[2n],9n],[[1n],[2n,max],9n],
  [[max],[0n],1n],[[0n],[max],1n],[[max-1n],[1n],1n],
  [[2n,4n],[3n,5n],9n],
];
let seed=0x61c88647;const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;};
for(let i=0;i<64;i++){const array=()=>Array.from({length:random()%13},()=>random()%19===0?max:BigInt(random()%97));cases.push([array(),array(),BigInt(random()%15)]);}
for(const length of [31,127,128,255,256,512])cases.push([Array(length).fill(1n),Array(length+1).fill(2n),BigInt(length)]);
let identity=1n;const records=[],scaling=[];
for(const [name,image] of images){
 let successful=0,failed=0,transfers=0,peakCheckpoint=0;
 for(let index=0;index<cases.length;index++){
  const args=cases[index];let wanted;
  try{wanted={kind:'completed',value:reference(...args)};}catch(error){assert.equal(error.message,'overflow');wanted={kind:'failed'};}
  let kernel=await Kernel.create({bytes,expectedSha256,instanceId:identity++});
  kernel.setLimits({input:4<<20,working:32<<20,output:8<<20});
  let program=kernel.prepare(image),session=kernel.start(program,encode(...args));kernel.releasePrepared(program);
  const transfer=index<11,series=index>=75,quantum=transfer?7:series?256:10000;
  let sampledCheckpoint=series?kernel.checkpoint(session).length:0,peakWorking=Number(kernel.usage().workingPeak),quanta=0;
  for(let round=0;;round++){
   assert.ok(round<4096,`${name} case ${index}: observation budget`);
   const out=decodeOutcome(kernel.drive(session,{quantum,checkpoint:transfer||series}));
   quanta++;peakWorking=Math.max(peakWorking,Number(kernel.usage().workingPeak));
   if(out.kind==='completed'||out.kind==='failed'){
    if(series)scaling.push({name,length:args[0].length,inputBytes:encode(...args).length,peakWorking,sampledCheckpoint,quanta});
    assert.equal(out.kind,wanted.kind,`${name} case ${index}`);
    if(out.kind==='completed'){assert.equal(new DataView(out.value.buffer,out.value.byteOffset,8).getBigUint64(0,true),wanted.value);successful++;}else{assert.deepEqual(out.value,new Uint8Array());failed++;}
    kernel.close(session);assert.equal(kernel.usage().workingLive,0n);break;
   }
   assert.equal(out.kind,'progressed');if(series)sampledCheckpoint=Math.max(sampledCheckpoint,out.state.length);
   if(transfer){
    peakCheckpoint=Math.max(peakCheckpoint,out.state.length);
    assert.deepEqual(kernel.checkpoint(session,{transfer:true}),out.state);assert.equal(kernel.usage().workingLive,0n);
    kernel=await Kernel.create({bytes,expectedSha256,instanceId:identity++});kernel.setLimits({input:4<<20,working:32<<20,output:8<<20});
    program=kernel.prepare(image);session=kernel.restore(program,out.state);kernel.releasePrepared(program);transfers++;
   }
  }
 }
 records.push({name,cases:cases.length,successful,failed,transfers,peakCheckpoint,imageBytes:image.length,sha256:createHash('sha256').update(image).digest('hex')});
}
const definitions=Object.fromEntries(await Promise.all(['hyper','direct','materialized'].map(async name=>[name,JSON.parse(await readFile('zig-out/fold/'+(name==='hyper'?'stats':'stats-'+name),'utf8'))])));
assert.equal(definitions.hyper.sequenceBuilders,0);assert.equal(definitions.direct.sequenceBuilders,0);assert.ok(definitions.materialized.sequenceBuilders>0);
console.log(JSON.stringify({records,definitions,scaling,seed:'0x61c88647',kernelSha256:expectedSha256}));
