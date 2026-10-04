// Cache admission is diagnostic, not qualification. Never delete build outputs.
import { lstatSync, readdirSync, appendFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

export function inspectCache(root, limitBytes = 4 * 1024 ** 3) {
  if (!Number.isSafeInteger(limitBytes) || limitBytes <= 0) throw new Error('positive cache budget required');
  const groups = Object.create(null), report = { bytes: 0, files: 0, unsupported: 0, groups, limitBytes };
  function visit(path, group) {
    const stat = lstatSync(path);
    if (stat.isDirectory()) for (const name of readdirSync(path)) visit(join(path, name), group ?? name);
    else if (stat.isFile()) {
      report.bytes += stat.size; report.files++;
      groups[group ?? '.'] = (groups[group ?? '.'] ?? 0) + stat.size;
    } else report.unsupported++;
  }
  try { visit(resolve(root)); }
  catch (error) { if (error.code !== 'ENOENT') throw error; report.unsupported++; }
  // Object bytes distinguish useful compiler output from an empty/metadata-only cache.
  report.save = report.unsupported === 0 && (groups.o ?? 0) > 0 && report.bytes <= limitBytes;
  report.reason = report.save ? 'nonempty compiler objects within budget' :
    report.unsupported ? 'absent or unsupported cache entries' :
    report.bytes > limitBytes ? 'over budget; retain the previous remote cache without deleting local data' : 'no compiler objects';
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [root = '.zig-cache', phase = 'final'] = process.argv.slice(2);
  const report = { phase, restoredKey: process.env.RESTORED_CACHE_KEY || null, ...inspectCache(root) };
  console.log(JSON.stringify(report, null, 2));
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `save=${report.save}\nbytes=${report.bytes}\n`);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `### Zig cache: ${phase}\n\n\`\`\`json\n${JSON.stringify(report, null, 2)}\n\`\`\`\n`);
}
