// Boundary owns source expectations and complete program data, never execution.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFileSync,spawnSync } from 'node:child_process';
import { invalidImages } from '../../test/v2/invalid_images.mjs';
import { execute } from '../../test/v2/source_oracle.mjs';
import { programNames, cases } from '../../test/v2/semantic_cases.mjs';
import { sha256, json, indexedBundle, tarGzip, readTarGzip, sourceIdentity, writeAssets } from './assets.mjs';

const [fixturesArg,outputArg,inspectPath]=process.argv.slice(2);
if(process.argv.length!==5)throw new Error('expected emitted fixtures, release output directory and pure image inspector');
const root=resolve(import.meta.dirname,'../..'),fixtures=resolve(fixturesArg),output=resolve(outputArg);
const zon=await readFile(join(root,'build.zig.zon'),'utf8');
const version=/\.version\s*=\s*"([^"]+)"/.exec(zon)?.[1];
if(!/^2\.0\.0(?:-dev\.0)?$/.test(version??''))throw new Error('unexpected Boundary release version');
const entries=[],sources=new Map(),programs=[];
for(const name of programNames) {
  const source=await readFile(join(fixtures,`source-${name}.json`));
  const image=await readFile(join(fixtures,`source-${name}.bpi2`));
  assert.equal(image.subarray(0,8).toString(),'ABL_BPI2');
  sources.set(name,JSON.parse(source));
  const row={name,source:`sources/${name}.json`,image:`programs/${name}.bpi2`};programs.push(row);
  entries.push({name:row.source,bytes:source},{name:row.image,bytes:image});
}
const scripts=[];
for(const item of cases) {
  const expected=execute(sources.get(item.program),item.initial,item.responses,item.cancellations);
  if(!['Completed','Failed','Cancelled'].includes(expected.kind))throw new Error(`incomplete source script: ${item.name}`);
  const initial=`cases/${item.name}/initial.bin`;
  entries.push({name:initial,bytes:Buffer.from(item.initial)});
  const responses=item.responses.map((value,index)=>{
    const name=`cases/${item.name}/result-${String(index).padStart(2,'0')}.bin`;
    entries.push({name,bytes:Buffer.from(value)});return name;
  });
  scripts.push({name:item.name,program:item.program,initial,responses,cancellations:item.cancellations,expected});
}
const negatives=[];
for(const item of invalidImages()) {
  const result=spawnSync(inspectPath,[],{input:item.bytes,maxBuffer:1<<20,timeout:10000});
  assert.equal(result.status,1,item.name);assert.ok(result.stderr.toString().includes(item.rejection),item.name+': '+result.stderr.toString());
  const file=`invalid/${item.name}.bpi2`;entries.push({name:file,bytes:item.bytes});negatives.push({name:item.name,image:file,rejection:item.rejection});
}
const bundle=indexedBundle(entries);
const manifest={format:'boundary-v2-semantic-fixtures/v1',boundaryVersion:version,profile:1,
  binary:'boundary-v2-semantic-fixtures.bin',binarySha256:sha256(bundle.bytes),programs,cases:scripts,negatives,files:bundle.files};
const manifestBytes=json(manifest);
const examplesReadme=`# Boundary ${version} portable examples\n\nUnpack the matching Boundary compiler source into a sibling directory named\n\`boundary\`. This package contains source, BPI2, canonical InitialArgs and typed\nresponse scripts; it contains no interpreter or effect relay.\n\nRun \`zig build emit -Dexample=14 > queens.bpi2\` to compile the public four-queens\nDFS source. \`-Dsource=true\` emits its independent source terms.\n\nThe source program ordinals are:\n\n${programNames.map((name,index)=>`${index}. ${name}`).join('\n')}\n\n\`fixtures.json\` names each program, initial argument file and sequence of\ncanonical typed result files. Its expected traces come from Boundary's independent\nsource oracle. Cancellations refer to observable positions in those traces,\nnot future request identities. The matching binary release asset concatenates\nthe same named files using the offsets and digests in this manifest.\n\nRun BPI2 with World 5. Encode each typed result against the actual returned ERQ2;\nretain PST2 to transfer an invocation. A cancellation during cleanup may rebind\nERQ2 without repeating the environmental operation.\n`;
const archiveEntries=[...entries,{name:'fixtures.json',bytes:manifestBytes},{name:'README.md',bytes:Buffer.from(examplesReadme)},
  {name:'LICENSE',bytes:await readFile(join(root,'LICENSE'))},{name:'main.zig',bytes:await readFile(join(root,'test/v2/emit_source.zig'))},
  {name:'build.zig',bytes:await readFile(join(root,'tools/v2/examples/build.zig'))},
  {name:'build.zig.zon',bytes:await readFile(join(root,'tools/v2/examples/build.zig.zon'))}];
const archive=tarGzip(archiveEntries);
assert.deepEqual(readTarGzip(archive).map(({name,bytes})=>({name,sha256:sha256(bytes)})),archiveEntries.map(({name,bytes})=>({name,sha256:sha256(bytes)})).sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0));
const assets=[{name:'boundary-v2-semantic-fixtures.json',bytes:manifestBytes},{name:'boundary-v2-semantic-fixtures.bin',bytes:bundle.bytes},
  {name:'boundary-v2-examples.tar.gz',bytes:archive}];
const receipt={format:'boundary-v2-release-receipt/v1',version,profile:1,source:await sourceIdentity(root),
  toolchain:{zig:execFileSync('zig',['version'],{encoding:'utf8'}).trim(),node:process.version},
  protected:JSON.parse(await readFile(join(root,'conformance/protected-delivery.json'),'utf8')),
  assets:assets.map(({name,bytes})=>({name,length:bytes.length,sha256:sha256(bytes)}))};
assets.push({name:'boundary-v2-release-receipt.json',bytes:json(receipt)});
await writeAssets(output,assets);
console.log(`emitted Boundary ${version}: ${programs.length} programs, ${scripts.length} typed source scripts, ${negatives.length} rejected images`);
