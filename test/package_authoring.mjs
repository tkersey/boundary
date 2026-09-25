// Build an immutable public package in an unrelated temporary consumer directory.
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {execFileSync,spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
const [runtime,native,output]=process.argv.slice(2);
assert.ok(runtime&&native&&output,'usage: node test/package_authoring.mjs RUNTIME NATIVE OUTPUT');
const root=resolve('.');
const directory=await mkdtemp(join(tmpdir(),'boundary-package-'));
try {
  const archive=join(directory,'boundary.tar.gz');
  execFileSync('git',['archive','--format=tar.gz','-o',archive,'HEAD'],{cwd:root});
  const hash=execFileSync('zig',['fetch',archive],{encoding:'utf8'}).trim();
  await writeFile(join(directory,'build.zig.zon'),`.{ .name=.consumer, .version="0.0.0", .fingerprint=0x705b3727bb03dcc2, .dependencies=.{ .boundary=.{.url="file://${archive}",.hash="${hash}"}}, .paths=.{""} }`);
  for(const file of ['build.zig','rejection.zig','category.zig','failure_literal_category.zig','lifecycle.zig','data.zig'])
    await writeFile(join(directory,file),execFileSync('git',['show',`HEAD:test/package_authoring/${file}`],{cwd:root}));
  await writeFile(join(directory,'client.zig'),execFileSync('git',['show','HEAD:examples/authoring_client.zig'],{cwd:root}));
  const image=execFileSync('zig',['build','emit','reject','data'],{cwd:directory,maxBuffer:8<<20});
  await writeFile(output,image);
  for (const [mode,diagnostic] of [
    ['category',/expected type '\*const .*Schema', found '\*const .*Operation'/],
    ['failure_literal_category',/expected type '\*const .*FailureLiteral', found '\*const .*Value'/],
    ['lifecycle',/Body.*does not support field access/],
  ]) {
    const wrong=spawnSync('zig',['build',`-D${mode}=true`],{cwd:directory,encoding:'utf8'});
    assert.notEqual(wrong.status,0);
    assert.match(wrong.stderr,new RegExp(`${mode}\\.zig:\\d+:\\d+: error:`));
    assert.match(wrong.stderr,diagnostic);
  }
  execFileSync(process.execPath,[join(root,'test/authoring_execution.mjs'),runtime,native,'client',output],{stdio:'inherit'});
  console.log(JSON.stringify({check:'public-package',hash,categoryRejection:true,foreignRejection:true}));
} finally { await rm(directory,{recursive:true,force:true}); }
