// Build and inspect the entire formal source tree. This is development tooling;
// importing the compiler or pure data package never invokes it.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { cp, mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const allowlist = new Set(['propext', 'Quot.sound', 'Classical.choice']);
// Only an actual result from this process can identify an earlier compilation.
// Reuse never skips declaration audit, exact claim checking, or fresh replay.
const compiledChecks = new WeakMap();
const hashBytes = (bytes) => createHash('sha256').update(bytes).digest('hex');

async function objectHash(path) {
  try { return hashBytes(await readFile(path)); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

export async function command(file, args, cwd, { quiet = false } = {}) {
  return new Promise((accept, reject) => {
    const child = spawn(file, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    const chunks = [];
    let retained = 0;
    const collect = (chunk) => {
      if (!quiet) process.stderr.write(chunk);
      // Diagnostic retention only; never an execution or proof horizon.
      chunks.push(chunk); retained += chunk.length;
      while (retained > 1024 * 1024 && chunks.length > 1) retained -= chunks.shift().length;
    };
    child.stdout.on('data', collect); child.stderr.on('data', collect);
    child.once('error', reject);
    child.once('close', (code, signal) => accept({ code, signal, text: Buffer.concat(chunks).toString() }));
  });
}

async function requireCommand(file, args, cwd, options) {
  const result = await command(file, args, cwd, options);
  if (result.code !== 0 || result.signal) {
    throw new Error(`formal.command_failed: ${file} ${args.join(' ')} (${result.code ?? result.signal})\n${result.text}`);
  }
  return result;
}

export async function discover(root) {
  const modules = [];
  async function visit(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (entry.name === '.lake' || entry.name === '.cache') continue;
      const path = join(directory, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`formal.symlink: ${path}`);
      if (entry.isDirectory()) await visit(path);
      else if (entry.name.endsWith('.lean')) {
        const bytes = await readFile(path); // Unreadable sources cannot disappear.
        const local = relative(root, path).replaceAll('\\', '/');
        const name = local.slice(0, -5).replaceAll('/', '.');
        if (!/^[A-Za-z_][A-Za-z_0-9]*(\.[A-Za-z_][A-Za-z_0-9]*)*$/.test(name)) {
          throw new Error(`formal.module_name: ${local}`);
        }
        modules.push({ name, kind: local === 'Trust.lean' ? 'tooling' : 'semantic',
          sha256: createHash('sha256').update(bytes).digest('hex') });
      }
    }
  }
  await visit(root);
  modules.sort((a, b) => a.name.localeCompare(b.name, 'en'));
  if (modules.filter((m) => m.kind === 'semantic').length === 0) {
    throw new Error('formal.empty_inventory: no semantic sources');
  }
  if (!modules.some((m) => m.name === 'BoundaryV2') || !modules.some((m) => m.name === 'Trust')) {
    throw new Error('formal.missing_root: BoundaryV2 and Trust are required');
  }
  return { format: 'boundary.formal-inventory/v1', modules, roots: ['BoundaryV2', 'Trust'], claims: [] };
}

export function validateReport(report, inventory) {
  assert.equal(report.format, 'boundary.trust-audit/v1', 'formal.report_format');
  assert.equal(report.status, 'passed', 'formal.report_status');
  assert.deepEqual(report.modules, inventory.modules, 'formal.report_inventory');
  assert.deepEqual(report.claims, inventory.claims, 'formal.report_claims');
  assert.deepEqual(new Set(report.allowed_axioms), allowlist, 'formal.report_allowlist');
  assert.ok(Array.isArray(report.declarations) && report.declarations.length, 'formal.empty_report');
  assert.equal(report.declarations.length, report.declaration_count, 'formal.omitted_declarations');
  const names = new Set();
  const modules = new Set(inventory.modules.map((m) => m.name));
  const semantics = new Set(inventory.modules.filter((m) => m.kind !== 'tooling').map((m) => m.name));
  let proofs = 0;
  let semanticDeclarations = 0;
  for (const declaration of report.declarations) {
    assert.ok(typeof declaration.name === 'string' && declaration.name.length, 'formal.report_name');
    assert.ok(!names.has(declaration.name), 'formal.report_duplicate'); names.add(declaration.name);
    assert.ok(modules.has(declaration.module), 'formal.report_provenance');
    assert.equal(typeof declaration.proof, 'boolean', 'formal.report_kind');
    assert.ok(Array.isArray(declaration.axioms), 'formal.report_axioms');
    for (const axiom of declaration.axioms) assert.ok(allowlist.has(axiom), 'formal.report_axiom');
    proofs += Number(declaration.proof);
    semanticDeclarations += Number(semantics.has(declaration.module));
  }
  assert.ok(proofs > 0, 'formal.no_proofs');
  assert.ok(semanticDeclarations > 0, 'formal.empty_semantics');
  assert.equal(semanticDeclarations, report.semantic_declaration_count, 'formal.omitted_semantics');
}

// Dependency order comes from fixed proof templates. Every dependency is an
// ordinary audited certificate module, including those with no public claim.
export function certificateClosure(certificates) {
  const ordered = [], known = new Map(), active = new Set();
  function visit(certificate) {
    assert.ok(certificate && typeof certificate === 'object', 'formal.certificate_record');
    assert.match(certificate.module, /^BoundaryCertificate[A-Za-z0-9_]+$/, 'formal.certificate_module');
    assert.equal(typeof certificate.path, 'string', 'formal.certificate_path');
    assert.ok(Array.isArray(certificate.claims), 'formal.certificate_claims');
    const dependencies = certificate.dependencies ?? [];
    assert.ok(Array.isArray(dependencies), 'formal.certificate_dependencies');
    const identity = { module: certificate.module, path: resolve(certificate.path), claims: certificate.claims };
    const prior = known.get(certificate.module);
    if (prior) {
      assert.deepEqual(identity, prior, 'formal.conflicting_certificate_module');
      assert.ok(!active.has(certificate.module), 'formal.certificate_dependency_cycle');
      return;
    }
    known.set(certificate.module, identity);
    active.add(certificate.module);
    for (const dependency of dependencies) visit(dependency);
    active.delete(certificate.module);
    ordered.push(identity);
  }
  for (const certificate of certificates) visit(certificate);
  return ordered;
}

export async function checkCore(root, { replay = true, quiet = false, certificates = [], reuse = null } = {}) {
  root = resolve(root);
  certificates = certificateClosure(certificates);
  const sources = await discover(root);
  const inventory = structuredClone(sources);
  const parent = join(root, '.cache', 'formal');
  await mkdir(parent, { recursive: true });
  const output = await mkdtemp(join(parent, 'run-'));
  const compiledCertificates = [...certificates];
  let replayRoot = 'Trust';
  if (certificates.length) {
    for (const certificate of certificates)
      assert.match(certificate.module, /^BoundaryCertificate[A-Za-z0-9_]+$/, 'formal.certificate_module');
    const source = ['import Trust', ...certificates.map((certificate) => `import ${certificate.module}`), ''].join('\n');
    const digest = createHash('sha256').update(source).digest('hex');
    replayRoot = `BoundaryCertificateReplay${digest}`;
    const path = join(output, `${replayRoot}.lean`);
    await writeFile(path, source);
    compiledCertificates.push({ module: replayRoot, path, claims: [] });
  }
  // Audit and fresh replay import the same root. The audit rejects any listed
  // module absent from that environment, including an omitted certificate.
  // Shared imports are consequently replayed once without reducing coverage.
  inventory.roots = [replayRoot];
  for (const certificate of compiledCertificates) {
    assert.match(certificate.module, /^BoundaryCertificate[A-Za-z0-9_]+$/, 'formal.certificate_module');
    const bytes = await readFile(certificate.path);
    inventory.modules.push({ name: certificate.module, kind: 'certificate',
      sha256: createHash('sha256').update(bytes).digest('hex') });
    inventory.claims.push(...certificate.claims);
  }
  const configuration = await Promise.all(['lean-toolchain', 'lakefile.toml', 'lake-manifest.json']
    .map(async (path) => hashBytes(await readFile(join(root, path)))));
  const compilationInput = { root, sources, configuration,
    certificates: certificates.map((certificate) => ({ module: certificate.module, path: certificate.path,
      sha256: inventory.modules.find((entry) => entry.name === certificate.module).sha256 })) };
  const inventoryFile = join(output, 'inventory.json');
  const reportFile = join(output, 'audit.json');
  const temporaryReport = join(output, 'audit.pending.json');
  // Remove prior acceptance before doing any fallible verification work.
  await rm(reportFile, { force: true }); await rm(temporaryReport, { force: true });
  await writeFile(inventoryFile, `${JSON.stringify(inventory)}\n`);
  await requireCommand('lake', ['build', 'BoundaryV2', 'boundary-trust'], root, { quiet });
  const dependencies = [];
  for (const module of sources.modules)
    dependencies.push([module.name, await objectHash(join(root, '.lake/build/lib/lean',
      `${module.name.replaceAll('.', '/')}.olean`))]);
  const compilationKey = JSON.stringify({ ...compilationInput, dependencies });
  const previous = compiledChecks.get(reuse);
  const reusable = previous?.key === compilationKey ? previous.objects : new Map();
  const objects = new Map();
  for (const certificate of compiledCertificates) {
    const path = join(root, '.lake/build/lib/lean', `${certificate.module}.olean`);
    const priorHash = reusable.get(certificate.module);
    if (!priorHash || await objectHash(path) !== priorHash) {
      await requireCommand('lake', ['env', 'lean', '-M', '8192', '-DwarningAsError=true',
        `--root=${dirname(certificate.path)}`, '-o', path, certificate.path], root, { quiet });
    }
    objects.set(certificate.module, await objectHash(path));
  }
  await requireCommand('lake', ['exe', 'boundary-trust', inventoryFile, temporaryReport], root, { quiet });
  const report = JSON.parse(await readFile(temporaryReport, 'utf8'));
  validateReport(report, inventory);
  if (replay) {
    // The pinned --fresh implementation replays every imported declaration,
    // including private declarations, into an empty environment.
    await requireCommand('lake', ['env', 'leanchecker', '--fresh', replayRoot], root, { quiet });
  }
  assert.deepEqual(await discover(root), sources, 'formal.source_changed_during_check');
  for (const certificate of compiledCertificates) {
    const entry = inventory.modules.find((m) => m.name === certificate.module);
    const hash = createHash('sha256').update(await readFile(certificate.path)).digest('hex');
    assert.equal(hash, entry.sha256, 'formal.certificate_changed_during_check');
    assert.equal(await objectHash(join(root, '.lake/build/lib/lean', `${certificate.module}.olean`)),
      objects.get(certificate.module), 'formal.certificate_object_changed_during_check');
  }
  for (const [module, hash] of dependencies)
    assert.equal(await objectHash(join(root, '.lake/build/lib/lean', `${module.replaceAll('.', '/')}.olean`)),
      hash, 'formal.core_object_changed_during_check');
  await rename(temporaryReport, reportFile);
  compiledChecks.set(report, { key: compilationKey, objects });
  return report;
}

const controls = [
  ['direct-sorry', 'theorem directAdmission : True := by sorry', /declaration uses.*sorry|trust\.forbidden_axiom/],
  ['transitive-sorry', 'namespace ForeignHelper\n theorem admitted : True := by sorry\nend ForeignHelper\ntheorem transitiveAdmission : True := ForeignHelper.admitted', /declaration uses.*sorry|trust\.forbidden_axiom/],
  ['used-axiom', 'axiom customAssumption : True\ntheorem usesAssumption : True := customAssumption', /trust\.(project_axiom|forbidden_axiom)/],
  ['unused-axiom', 'axiom unusedAssumption : False', /trust\.project_axiom/],
  ['private-admission', 'private def hiddenProof : True := by sorry', /declaration uses.*sorry|trust\.forbidden_axiom/],
  ['suppressed-admission', 'set_option warningAsError false in\nprivate def hiddenAdmittedProof : True := by sorry', /trust\.(placeholder|forbidden_axiom)/],
  ['proposition-definition', 'def admittedProposition : True := by sorry', /declaration uses.*sorry|trust\.forbidden_axiom/],
  ['native-decision', 'theorem nativeAdmission : (1 : Nat) + 1 = 2 := by decide +native', /trust\.(project_axiom|forbidden_axiom)/],
  ['unsafe-semantics', 'unsafe def uncheckedTransition (x : Nat) : Nat := x', /trust\.unsafe_semantics/],
  ['partial-semantics', 'partial def loopingMeaning (x : Nat) : Nat := loopingMeaning x', /trust\.(unsafe_semantics|opaque_semantics)/],
  ['opaque-semantics', 'opaque hiddenMeaning : Nat := 0', /trust\.opaque_semantics/],
];

async function isolatedCopy(root) {
  const directory = await mkdtemp(join(tmpdir(), 'boundary-formal-'));
  const copy = join(directory, 'semantics');
  await cp(root, copy, { recursive: true, mode: constants.COPYFILE_FICLONE,
    filter: (path) => !relative(root, path).split(/[\\/]/).includes('.cache') });
  return { directory, copy };
}

export async function mutations(root) {
  for (const [name, source, expected] of controls) {
    const { directory, copy } = await isolatedCopy(root);
    try {
      const target = join(copy, 'BoundaryV2', 'Ownership.lean');
      await writeFile(target, `${await readFile(target, 'utf8')}\n${source}\n`);
      await assert.rejects(checkCore(copy, { replay: false, quiet: true }), expected, name);
      process.stdout.write(`formal mutation: ${name} rejected\n`);
    } finally { await rm(directory, { recursive: true, force: true }); }
  }
  for (const name of ['orphan', 'missing-module', 'generated-assumption']) {
    const { directory, copy } = await isolatedCopy(root);
    try {
      if (name === 'orphan') {
        await writeFile(join(copy, 'Unimported.lean'), 'theorem unseen : True := .intro\n');
      } else if (name === 'missing-module') {
        await rm(join(copy, 'BoundaryV2', 'Ownership.lean'));
      } else {
        await mkdir(join(copy, 'BoundaryV2', 'Generated'), { recursive: true });
        await writeFile(join(copy, 'BoundaryV2', 'Generated', 'Artifact.lean'),
          'axiom generatedAssumption : True\ntheorem generatedCertificate : True := generatedAssumption\n');
        const umbrella = join(copy, 'BoundaryV2.lean');
        await writeFile(umbrella, `${await readFile(umbrella, 'utf8')}\nimport BoundaryV2.Generated.Artifact\n`);
      }
      const expected = name === 'orphan' ? /trust\.module_not_built/ : name === 'missing-module'
        ? /no such file|does not exist|not found|trust\.unlisted_module/i
        : /trust\.(project_axiom|forbidden_axiom)/;
      await assert.rejects(checkCore(copy, { replay: false, quiet: true }), expected, name);
      process.stdout.write(`formal mutation: ${name} rejected\n`);
    } finally { await rm(directory, { recursive: true, force: true }); }
  }
  const generated = await mkdtemp(join(tmpdir(), 'boundary-generated-control-'));
  try {
    const module = 'BoundaryCertificateUnsafeHelper';
    const path = join(generated, `${module}.lean`);
    await writeFile(path, `import BoundaryV2\nnamespace ${module}\n` +
      'def innocent (n : Nat) := n\nunsafe def innocent._unsafe_rec (n : Nat) : Nat := n\n' +
      `end ${module}\n`);
    // Generated proofs are elaborated without C emission, so a compiler error
    // from native compilation cannot substitute for this audit rejection.
    await assert.rejects(checkCore(root, { replay: false, quiet: true,
      certificates: [{ module, path, claims: [] }] }), /trust\.unsafe_semantics/,
    'a handwritten unsafe declaration cannot impersonate a compiler companion');
    process.stdout.write('formal mutation: generated unsafe helper impersonation rejected\n');
  } finally { await rm(generated, { recursive: true, force: true }); }
  const clean = await checkCore(root, { replay: false, quiet: true });
  const inventory = await discover(root);
  for (const mutation of [
    { ...clean, declarations: [] }, { ...clean, status: 'rejected' },
    { ...clean, modules: clean.modules.slice(1) }, { ...clean, format: 'unknown' },
    { ...clean, declarations: [{ ...clean.declarations[0], axioms: ['unknownAxiom'] }] },
    { ...clean, declarations: clean.declarations.slice(1) },
  ]) assert.throws(() => validateReport(mutation, inventory));
  const { directory, copy } = await isolatedCopy(root);
  try {
    for (const entry of await readdir(copy)) await rm(join(copy, entry), { recursive: true, force: true });
    await assert.rejects(discover(copy), /formal\.empty_inventory/);
  } finally { await rm(directory, { recursive: true, force: true }); }
  process.stdout.write('formal mutation: empty inventory and malformed/omitted reports rejected\n');
}

export async function semanticMutations(root) {
  const cases = [
    ['colliding-initialization', 'Effects.lean', '(freshAbove capabilities.toList)', '0',
      /Effects\.lean[\s\S]*(Type mismatch|Application type mismatch)/],
    ['dormant-template-remapping', 'Effects.lean', '.repeat (template.rename rename) heap arguments acc fold env',
      '.repeat template heap arguments acc fold env',
      /EffectsActivation\.lean[\s\S]*(unsolved goals|Type mismatch|Tactic)/],
    ['parked-poll-event', 'EffectsEvents.lean', '| .running _, .pending pending =>',
      '| _, .pending pending =>', /EffectsEvents\.lean[\s\S]*(unsolved goals|Type mismatch|Tactic)/],
    ['source-running-identity-tick', 'SourceMachine.lean', '| .running => tickRunning state context',
      '| .running => let _ := context; .ok ⟨state, []⟩',
      /SourceCellExecution\.lean[\s\S]*Application type mismatch/],
  ];
  for (const [name, file, before, after, diagnostic] of cases) {
    const { directory, copy } = await isolatedCopy(root);
    try {
      const path = join(copy, 'BoundaryV2', file);
      const source = await readFile(path, 'utf8');
      assert.equal(source.split(before).length, 2, `formal.mutation_setup: ${name}`);
      await writeFile(path, source.replace(before, after));
      await assert.rejects(checkCore(copy, { replay: false, quiet: true }), diagnostic, name);
      process.stdout.write(`formal semantic mutation: ${name} rejected\n`);
    } finally { await rm(directory, { recursive: true, force: true }); }
  }
  await checkCore(root, { replay: false, quiet: true });
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length) throw new Error('usage: node tools/v2/formal.mjs');
  const root = join(repository, 'semantics', 'v2');
  const version = await requireCommand('lake', ['env', 'lean', '--version'], root);
  assert.match(version.text, /version 4\.33\.1[, ]/, 'formal.toolchain_mismatch');
  await checkCore(root);
  await mutations(root);
  await semanticMutations(root);
  process.stdout.write('formal gate: discovery, trust, fresh replay, and negative controls passed\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
