import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { certificateClosure } from '../../tools/v2/formal.mjs';

const artifact = (module, dependencies = []) => ({ module, path: `/tmp/${module}.lean`, claims: [], dependencies });
const data = artifact('BoundaryCertificateData');
const image = artifact('BoundaryCertificateImage', [data]);
const first = artifact('BoundaryCertificateFirst', [image]);
const second = artifact('BoundaryCertificateSecond', [data, image]);
assert.deepEqual(certificateClosure([first, second]), [data, image, first, second].map(
  ({ module, path, claims }) => ({ module, path: resolve(path), claims })));
assert.throws(() => certificateClosure([first, { ...image, path: '/tmp/different.lean' }]),
  /formal.conflicting_certificate_module/);
assert.throws(() => certificateClosure([image, { ...image, claims: [{ name: 'different' }] }]),
  /formal.conflicting_certificate_module/);
const cycle = artifact('BoundaryCertificateCycle'); cycle.dependencies = [cycle];
assert.throws(() => certificateClosure([cycle]), /formal.certificate_dependency_cycle/);
assert.throws(() => certificateClosure([{ ...first, dependencies: {} }]), /formal.certificate_dependencies/);
assert.throws(() => certificateClosure([artifact('Unsafe\nimport Elsewhere')]), /formal.certificate_module/);
assert.deepEqual(certificateClosure([]), []);
console.log('formal dependencies: ordered closure, shared modules, conflicting identities and cycles checked');

if (process.argv[2]) {
  const { mkdir, mkdtemp, rm, writeFile } = await import('node:fs/promises');
  const { join } = await import('node:path');
  const { randomBytes } = await import('node:crypto');
  const { checkCore } = await import('../../tools/v2/formal.mjs');
  const root = resolve(process.argv[2]);
  const parent = join(root, '.cache/dependency-controls'); await mkdir(parent, { recursive: true });
  const directory = await mkdtemp(join(parent, 'run-'));
  const stem = `BoundaryCertificateDependency${randomBytes(12).toString('hex')}`;
  const dependency = { module: `${stem}Support`, path: join(directory, `${stem}Support.lean`), claims: [] };
  const certificate = { module: stem, path: join(directory, `${stem}.lean`), claims: [], dependencies: [dependency] };
  try {
    await writeFile(dependency.path, `import BoundaryV2\ntheorem ${stem}Fact : True := .intro\n`);
    await writeFile(certificate.path, `import ${dependency.module}\ntheorem ${stem}Root : True := ${stem}Fact\n`);
    const proof = await checkCore(root, { certificates: [certificate], replay: false, quiet: true });
    assert.ok(proof.modules.some((module) => module.name === dependency.module));
    await assert.rejects(checkCore(root, { certificates: [{ ...certificate, dependencies: [] }], replay: false, quiet: true }),
      /trust\.unlisted_module/);
    await checkCore(root, { certificates: [certificate], replay: false, quiet: true, reuse: proof });
    console.log('formal dependencies: omitted checked dependency rejected; complete inventory restored');
  } finally {
    await rm(directory, { recursive: true, force: true });
    for (const module of [stem, dependency.module])
      await rm(join(root, '.lake/build/lib/lean', `${module}.olean`), { force: true });
  }
}
