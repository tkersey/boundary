import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';
import { sourceAnalysis } from '../../tools/v2/source_analysis.mjs';

const root = resolve(new URL('../..', import.meta.url).pathname);
const fixtureDirectory = resolve(process.argv[2] ?? join(root, 'zig-out'));
const temporary = await mkdtemp(join(tmpdir(), 'boundary-source-analysis-'));
try {
  const fixtures = (await readdir(fixtureDirectory)).filter((file) => /^source-.*\.json$/.test(file)).sort();
  assert.equal(fixtures.length, 37);
  let negative = false;
  for (const fixture of fixtures) {
    const path = join(fixtureDirectory, fixture);
    const source = parseExactJson(await readFile(path));
    const facts = sourceAnalysis(source);
    const witness = join(temporary, basename(fixture));
    await writeFile(witness, JSON.stringify(facts));
    const args = ['env', 'lean', '--run', '../../tools/v2/source_analysis_conformance.lean', path, witness];
    execFileSync('lake', args, { cwd: join(root, 'semantics/v2'), stdio: 'pipe' });
    if (!negative) {
      const row = [...facts.values, ...facts.terms, ...facts.functions].find((row) => row.length && row[0][1] > 0);
      if (row) {
        const rank = row[0][1];
        row[0][1] = 0;
        await writeFile(witness, JSON.stringify(facts));
        assert.throws(() => execFileSync('lake', args, { cwd: join(root, 'semantics/v2'), stdio: 'pipe' }),
          (error) => String(error.stdout).includes('source capture witness rejected') || String(error.stderr).includes('source capture witness rejected'));
        row[0][1] = rank;
        const removed = row.shift();
        await writeFile(witness, JSON.stringify(facts));
        assert.throws(() => execFileSync('lake', args, { cwd: join(root, 'semantics/v2'), stdio: 'pipe' }),
          (error) => String(error.stdout).includes('source capture witness rejected') || String(error.stderr).includes('source capture witness rejected'));
        row.unshift(removed);
        await writeFile(witness, JSON.stringify(facts));
        execFileSync('lake', args, { cwd: join(root, 'semantics/v2'), stdio: 'pipe' });
        negative = true;
      }
    }
  }
  assert.ok(negative);
  console.log('source analysis: all 37 staged programs accepted; forged rank and omitted capture rejected');
} finally {
  await rm(temporary, { recursive: true, force: true });
}
