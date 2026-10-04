// Separate native build cost, already-built compiler phases, and component CLI cost.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,mkdtemp} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';
import {createHash} from 'node:crypto';
import {selectZig} from '../tools/zig.mjs';
const compiler=selectZig(process.argv.slice(2));
const [binArg,outputArg,...flags]=compiler.args;assert(binArg&&outputArg);
const root=resolve(import.meta.dirname,'..'),sha=b=>createHash('sha256').update(b).digest('hex');
const bin=resolve(binArg),output=resolve(outputArg);
let images=join(root,'zig-out/fold'),coldBuilds=false;
for(let i=0;i<flags.length;i++){
 if(flags[i]==='--cold-builds'){assert(!coldBuilds);coldBuilds=true;}
 else if(flags[i]==='--images'){assert(flags[i+1]);images=resolve(flags[++i]);}
 else assert.fail(`unknown option: ${flags[i]}`);
}
await mkdir(output,{recursive:true});
const modes=['hyper','direct','materialized'],rows=Object.fromEntries(modes.map(x=>[x,{profile:[],cliNs:[]}]));
for(let i=0;i<12;i++)for(let offset=0;offset<modes.length;offset++){
 const mode=modes[(i+offset)%modes.length];
 const before=performance.now(),image=execFileSync(join(bin,'hyper-fold'),[mode],{maxBuffer:1<<20}),ns=(performance.now()-before)*1e6;
 const profile=JSON.parse(execFileSync(join(bin,'hyper-compile-bench'),[mode],{encoding:'utf8'}));
 assert.equal(profile.imageSha256,sha(image));assert.deepEqual(image,await readFile(join(images,mode)));
 if(i>=3){rows[mode].profile.push(profile);rows[mode].cliNs.push(ns);}
}
const objects=join(output,'objects');await mkdir(objects,{recursive:true});const components=[];
for(const mode of ['producer','consumer','consumer-invert','support','entry']){
 const samples=[];let bytes;
 for(let i=0;i<12;i++){const before=performance.now(),next=execFileSync(join(bin,'hyper-adaptive'),[mode],{maxBuffer:1<<20});const ns=(performance.now()-before)*1e6;if(bytes)assert.deepEqual(next,bytes);bytes=next;if(i>=3)samples.push(ns);}
 await writeFile(join(objects,mode+'.bmo1'),bytes);components.push({mode,bytes:bytes.length,sha256:sha(bytes),cliNs:samples});
}
const links=[];
for(const invert of [false,true]){
 const manifest={instances:['producer','consumer','support','entry'].map(key=>({key,path:(key==='consumer'&&invert?'consumer-invert':key)+'.bmo1'})),bindings:[['producer','create'],['consumer','create'],['support','invoke']].map(([symbol,target])=>({required:{instance:'entry',symbol},supplied:{instance:symbol,symbol:target}})),entry:{instance:'entry',symbol:'main'}};
 const path=join(objects,invert?'invert.json':'normal.json');await writeFile(path,JSON.stringify(manifest));const samples=[];let bytes;
 for(let i=0;i<12;i++){const before=performance.now(),next=execFileSync(join(bin,'boundary-link'),[path],{cwd:objects,maxBuffer:1<<20}),ns=(performance.now()-before)*1e6;if(bytes)assert.deepEqual(next,bytes);bytes=next;if(i>=3)samples.push(ns);}
 await writeFile(join(objects,invert?'invert.bpi3':'normal.bpi3'),bytes);links.push({invert,bytes:bytes.length,sha256:sha(bytes),cliNs:samples});
}
const builds=[];
if(coldBuilds)for(let i=0;i<3;i++){
 const directory=await mkdtemp(join(output,'build-'+i+'-'));
 const args=['build','--build-file','test/build_hyper_compiler.zig','emitter','-Dsource='+root,'--prefix',join(directory,'out'),'--cache-dir',join(directory,'local'),'-j2'];
 const before=performance.now();execFileSync(compiler.executable,args,{cwd:root,maxBuffer:1<<20,timeout:600000,
   env:{...compiler.env,ZIG_GLOBAL_CACHE_DIR:join(directory,'global'),ZIG_LOCAL_PKG_DIR:join(directory,'packages')}});builds.push({ns:(performance.now()-before)*1e6,args});
 assert.equal(sha(execFileSync(join(directory,'out/bin/hyper-fold'),['hyper'])),rows.hyper.profile[0].imageSha256);
}
compiler.assertUnchanged();
const result={format:'hyper-compiler-economy/v1',toolchain:compiler.identity,stageOrder:['source_copy','source_check','lowering','target_check','direct_optimization','canonicalization','complete'],nativeMode:'safe',samplePolicy:'three warmups, nine rotated measured compiler processes; CLI clocks include process startup; phase clocks are separately instrumented',coldPolicy:'three fresh local/global Zig caches; OS filesystem cache and host load uncontrolled',rows,components,links,builds};
await writeFile(join(output,'results.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify({modes:Object.keys(rows),components:components.length,links:links.length,coldBuilds:builds.length}));
