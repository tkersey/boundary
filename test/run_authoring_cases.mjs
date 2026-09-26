import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [runtime,native,emitter,comparison,reportPath]=process.argv.slice(2);
assert.ok(runtime&&native&&emitter,'usage: node test/run_authoring_cases.mjs RUNTIME NATIVE EMITTER');
assert.ok(comparison===undefined||comparison==='coalescing');
assert.ok(!reportPath||comparison==='coalescing');
assert.ok(process.argv.slice(2).length<=5);
const sha256=bytes=>createHash('sha256').update(bytes).digest('hex');
const observations=[], fixtures=[], peers=[];
const directory=await mkdtemp(join(tmpdir(),'boundary-authoring-cases-'));
try {
  for(const kind of ['deep','shallow','transform_deep','transform_shallow','bypass','twice',
      'cleanup','obligations','lazy','demanded','failure_before','failure_after','match','configuration','region','arithmetic','arithmetic_fail','dispose','reusable_body','imported_scoped','cleanup_named','imported_sequence',
      'cells_independent','cells_shared','memo_independent','memo_shared','state_local','state_shared',
      'hyper_duplicate','hyper_configured','hyper_lazy','capture_order']) {
    const images=[];
    const source=execFileSync(resolve(emitter),[kind,'json']);
    const subjects=new Map();
    let baselineBytes;
    for(const mode of comparison ? ['off','safe'] : ['off']) {
      const stem=join(directory,kind+'-'+mode);
      const bytes=execFileSync(resolve(emitter),[kind,'bpi3',mode]);
      if(mode==='off')baselineBytes=bytes.length;
      else assert.ok(bytes.length<=baselineBytes,'selected image grew');
      await writeFile(stem+'.bpi3',bytes);
      await writeFile(stem+'.json',source);
      images.push(stem+'.bpi3');
      subjects.set(stem+'.bpi3',{fixture:kind,mode,imageSha256:sha256(bytes)});
    }
    const output=execFileSync(process.execPath,
      [resolve('test/authoring_execution.mjs'),runtime,native,kind,...images],
      {encoding:'utf8',env:process.env,maxBuffer:16<<20,stdio:['ignore','pipe','inherit']});
    process.stdout.write(output);
    const counts=new Map();
    for(const row of output.trim().split('\n').map(JSON.parse)) {
      if(row.ready){peers.push(row);continue;}
      const {path,...result}=row, subject=subjects.get(path);
      assert.ok(subject,'unbound runtime observation');
      const index=counts.get(path)??0;counts.set(path,index+1);
      observations.push({...subject,inputCase:index,...result});
    }
    fixtures.push({name:kind,sourceSha256:sha256(source)});
  }
  if(reportPath) await writeFile(reportPath,JSON.stringify({
    scope:'Existing authored semantic fixtures, off/safe, independent source oracle and requested runtimes',
    kernelSha256:sha256(await readFile(join(runtime,'world-kernel.wasm'))),
    emitterSha256:sha256(await readFile(emitter)),nativeSha256:sha256(await readFile(native)),
    harnessSha256:sha256(await readFile('test/authoring_execution.mjs')),
    fixtures,executions:observations.length,
    wasmtime:peers.length?peers[0]:{status:'NOT_RUN'},rows:observations,
  },null,2)+'\n');
} finally { await rm(directory,{recursive:true,force:true}); }
