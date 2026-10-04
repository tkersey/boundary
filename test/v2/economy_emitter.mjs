// Frozen migration-only BPI3 outputs, observed independently at 9e68b6e.
// Each configuration runs in its own process; no compiler state survives a call.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const [executable, ...images] = process.argv.slice(2);
assert(executable && images.length === 4);
const golden = new Map([
  ['0', '53f9215dae8de0ca177de1ae9551d314f42f79dc99c66f4a1dc149e523fbe5ae'],
  ['1', 'da381b4a20e979e6233666a7916f59f09e4d64f46be1a32604ece66bb16a2e1c'],
  ['8', '7f6a667fd48e9f280d9c672363851f81b7e901974e880202e198aec89a20676b'],
  ['64', '526e658b9d898247583bbdef60a3fffc901878b60e75012165c5f91d768d7e9d'],
]);
for (const [index, expected] of [...golden.values()].entries())
  assert.equal(createHash('sha256').update(readFileSync(images[index])).digest('hex'), expected);
for (const [args, error] of [
  [['0'], null], [['2'], 'InvalidCount'], [['64'], null],
  [[], 'MissingCount'], [['8', 'extra'], 'InvalidArguments'],
  [['garbage'], 'InvalidCharacter'], [['0'], null],
]) {
  const result = spawnSync(executable, args, { timeout: 10000, maxBuffer: 1 << 20 });
  assert.ifError(result.error);
  assert.equal(result.signal, null, `unexpected crash for ${JSON.stringify(args)}`);
  if (error) {
    assert.equal(result.status, 1, result.stderr.toString());
    assert.match(result.stderr.toString(), new RegExp(`error: ${error}\\b`));
    assert.equal(result.stdout.length, 0, 'a rejected configuration cannot emit a partial image');
  } else {
    assert.equal(result.status, 0, result.stderr.toString());
    assert.equal(createHash('sha256').update(result.stdout).digest('hex'), golden.get(args[0]));
  }
}
console.log('Economy emitter: four frozen images and interleaved rejection/isolation checks passed');
