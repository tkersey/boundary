import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const result=spawnSync(process.argv[2],['duplicate'],{encoding:'utf8'});
assert.equal(result.status,1);
assert.match(result.stderr,/UnavailableSlot/);
assert.equal(result.stdout,'');
console.log('consumed owned exchange package rejects before image publication');
