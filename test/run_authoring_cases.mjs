import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
const [runtime,native,emitter]=process.argv.slice(2);
assert.ok(runtime&&native&&emitter,'usage: node test/run_authoring_cases.mjs RUNTIME NATIVE EMITTER');
const directory=await mkdtemp(join(tmpdir(),'boundary-authoring-cases-'));
try {
  for(const kind of ['deep','shallow','transform_deep','transform_shallow','bypass','twice',
      'cleanup','lazy','demanded','failure_before','failure_after','match','configuration']) {
    const image=join(directory,kind+'.bpi3');
    await writeFile(image,execFileSync(resolve(emitter),[kind,'bpi3']));
    await writeFile(join(directory,kind+'.json'),execFileSync(resolve(emitter),[kind,'json']));
    execFileSync(process.execPath,[resolve('test/authoring_execution.mjs'),runtime,native,kind,image],
      {stdio:'inherit',env:process.env});
  }
} finally { await rm(directory,{recursive:true,force:true}); }
