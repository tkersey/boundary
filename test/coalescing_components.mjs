import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, copyFile, writeFile, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const [emitter, linker, inspector, runtime, digest, native] = process.argv.slice(2);
assert.ok(emitter && linker && inspector);
const directory = await mkdtemp(join(tmpdir(), 'boundary-coalescing-components-'));
try {
  const first = execFileSync(emitter, ['off', 'leaf']);
  const second = execFileSync(emitter, ['off', 'leaf']);
  const client = execFileSync(emitter, ['off', 'client']);
  assert.deepEqual(execFileSync(emitter, ['safe', 'leaf']), first);
  assert.deepEqual(execFileSync(emitter, ['safe', 'client']), client);
  for (const [key, bytes] of [['a', first], ['b', second], ['client', client]]) {
    assert.equal(bytes.subarray(0, 8).toString(), 'ABL_BMO1');
    await writeFile(join(directory, `${key}.bmo1`), bytes);
  }
  await copyFile(linker, join(directory, 'link'));
  assert.deepEqual((await readdir(directory)).sort(), ['a.bmo1', 'b.bmo1', 'client.bmo1', 'link']);
  const manifest = {
    instances: ['a', 'b', 'client'].map(key => ({key, path: `${key}.bmo1`})),
    bindings: ['a', 'b'].map(key => ({required: {instance: 'client', symbol: key},
      supplied: {instance: key, symbol: 'main'}})),
    entry: {instance: 'client', symbol: 'main'},
  };
  const images = [];
  for (const coalescing of ['off', 'safe']) {
    await writeFile(join(directory, 'link.json'), JSON.stringify({...manifest, coalescing}));
    const bytes = execFileSync(join(directory, 'link'), ['link.json'], {cwd: directory});
    const path = join(directory, `${coalescing}.bpi3`);
    await writeFile(path, bytes); images.push(path);
  }
  const counts = execFileSync(inspector, images, {encoding: 'utf8'}).trim().split('\n').map(JSON.parse);
  const [off, safe] = counts;
  await writeFile(join(directory, 'link.json'), JSON.stringify(manifest));
  const ordinary = execFileSync(join(directory, 'link'), ['link.json'], {cwd: directory});
  assert.deepEqual(ordinary, await readFile(images[1]));
  assert.ok(safe.bytes < off.bytes);
  assert.equal(off.functions, 5); assert.equal(safe.functions, 3);
  assert.equal(off.constructors, 2); assert.equal(safe.constructors, 1);
  assert.equal(off.captures, 2); assert.equal(safe.captures, 1);
  let execution = 'not-requested';
  if (runtime || digest || native) {
    assert.ok(runtime && digest && native);
    const harness = fileURLToPath(new URL('./coalescing_execution.mjs', import.meta.url));
    execution = JSON.parse(execFileSync(process.execPath,
      [harness, '-', resolve(runtime), digest, resolve(native), ...images], {encoding: 'utf8'}));
  }
  console.log(JSON.stringify({check: 'source-free cross-object code and constructor coalescing',
    emitterProcesses: 5, linkerProcesses: 3, defaultMatchesSafe: true,
    off: {...off, path: 'off.bpi3'}, safe: {...safe, path: 'safe.bpi3'}, execution}));
} finally {
  await rm(directory, {recursive: true, force: true});
}
