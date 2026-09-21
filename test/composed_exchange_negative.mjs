import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const result=spawnSync(process.argv[2],['duplicate'],{encoding:'utf8',maxBuffer:1<<20});
assert.ifError(result.error);assert.notEqual(result.status,0);assert.equal(result.stdout,'');
assert.match(result.stderr,/error: UnavailableSlot/);
console.log('duplicate composite owner: rejected');
