// Build an immutable public package in an unrelated temporary consumer directory.
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {execFileSync,spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {selectZig} from '../tools/zig.mjs';
const compiler=selectZig(process.argv.slice(2));
const authoringOnly=compiler.args[0]==='--authoring-only';
const [runtime,native,output]=compiler.args;
assert.ok(authoringOnly ? compiler.args.length===1 : compiler.args.length===3&&runtime&&native&&output,
  'usage: node test/package_authoring.mjs [--zig-exe ABSOLUTE_PATH] (--authoring-only | RUNTIME NATIVE OUTPUT)');
const root=resolve('.');
const directory=await mkdtemp(join(tmpdir(),'boundary package Ω '));
try {
  const env={...compiler.env,ZIG_GLOBAL_CACHE_DIR:join(directory,'global'),
    ZIG_LOCAL_CACHE_DIR:join(directory,'local'),ZIG_LOCAL_PKG_DIR:join(directory,'packages')};
  const git=(...args)=>execFileSync('git',['--no-replace-objects',...args],{cwd:root,maxBuffer:64<<20});
  const commit=git('rev-parse','HEAD').toString().trim();
  const archive=join(directory,'boundary.tar.gz');
  git('archive','--format=tar.gz','-o',archive,commit);
  const hash=execFileSync(compiler.executable,['fetch',archive],{encoding:'utf8',env,timeout:120000}).trim();
  await writeFile(join(directory,'build.zig.zon'),`.{ .name=.consumer, .version="0.0.0", .fingerprint=0x705b3727bb03dcc2, .dependencies=.{ .boundary=.{.url=${JSON.stringify(pathToFileURL(archive).href)},.hash="${hash}"}}, .paths=.{""} }`);
  for(const file of ['build.zig','rejection.zig','category.zig','failure_literal_category.zig','lifecycle.zig','data.zig'])
    await writeFile(join(directory,file),git('show',`${commit}:test/package_authoring/${file}`));
  await writeFile(join(directory,'client.zig'),git('show',`${commit}:examples/authoring_client.zig`));
  const image=execFileSync(compiler.executable,['build','emit','reject','data'],{cwd:directory,env,maxBuffer:8<<20,timeout:600000});
  for (const [mode,diagnostic] of [
    ['category',/expected type '\*const .*Schema', found '\*const .*Operation'/],
    ['failure_literal_category',/expected type '\*const .*FailureLiteral', found '\*const .*Value'/],
    ['lifecycle',/Body.*does not support field access/],
  ]) {
    const wrong=spawnSync(compiler.executable,['build',`-D${mode}=true`],{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:8<<20});
    assert.ifError(wrong.error);
    assert.notEqual(wrong.status,0);
    assert.match(wrong.stderr,new RegExp(`${mode}\\.zig:\\d+:\\d+: error:`));
    assert.match(wrong.stderr,diagnostic);
  }
  compiler.assertUnchanged();
  if(!authoringOnly){
    await writeFile(output,image);
    execFileSync(process.execPath,[join(root,'test/authoring_execution.mjs'),runtime,native,'client',output],{stdio:'inherit',env,timeout:600000});
  }
  compiler.assertUnchanged();
  console.log(JSON.stringify({check:'public-package',commit,hash,toolchain:compiler.identity,
    imageBytes:image.length,categoryRejection:true,foreignRejection:true,runtimeExecution:!authoringOnly}));
} finally { await rm(directory,{recursive:true,force:true}); }
