// Offline discovery meets the ordinary checked compiler; solver output grants no
// production authority and is never consumed by the compiler or runtime.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const [emitter,extractor,solver,search,failureEmitter,output]=process.argv.slice(2);assert.equal(process.argv.length,8);
mkdirSync(output);const hash=b=>createHash('sha256').update(b).digest('hex'),paths={};
for(const arm of ['structural','checked','semantic','linked']){const path=`${output}/${arm}.bpi3`;writeFileSync(path,execFileSync(emitter,['xor',arm]));paths[arm]=path;}
execFileSync('uv',['run','--no-project','python',search,paths.structural,'--extractor',extractor,'--solver',solver,'--output-dir',`${output}/search`],{env:{...process.env,PYTHONDONTWRITEBYTECODE:'1'},stdio:'pipe'});
const discovered=JSON.parse(readFileSync(`${output}/search/report.json`));assert.equal(discovered.status,'proved-candidates');assert.equal(discovered.image_sha256,hash(readFileSync(paths.structural)));
assert(discovered.candidates.some(c=>JSON.stringify(c.target)==='["arg",1]'&&c.solver.status==='equivalent'));
const falseRule=discovered.candidates.find(c=>JSON.stringify(c.target)==='["arg",0]');assert.equal(falseRule.solver.status,'counterexample-exists');assert.notEqual(falseRule.solver.counterexample.source,falseRule.solver.counterexample.target);
const production={};
for(const arm of ['checked','semantic','linked']){
 const extracted=JSON.parse(execFileSync(extractor,[paths[arm]],{encoding:'utf8'})),node=extracted.nodes[extracted.result];assert.equal(node.opcode,'input');assert.equal(node.input,1);assert.equal(node.bits,64);
 production[arm]={bytes:readFileSync(paths[arm]).length,sha256:hash(readFileSync(paths[arm])),extracted};
}
const failurePath=`${output}/failure.bpi3`;execFileSync(failureEmitter,[failurePath]);
const rejected=spawnSync('uv',['run','--no-project','python',search,failurePath,'--extractor',extractor,'--solver',solver,'--output-dir',`${output}/failure-search`],{env:{...process.env,PYTHONDONTWRITEBYTECODE:'1'},encoding:'utf8'});assert.equal(rejected.status,2,rejected.stderr);
const failure=JSON.parse(readFileSync(`${output}/failure-search/report.json`));assert.equal(failure.reason,'unsupported-or-invalid-source');assert.equal(failure.candidates.length,0);
const report={status:'complete',scope:'Rediscovered 64-bit XOR identity instantiated through existing registered typed laws and independent production replay; no new trusted solver path',identities:Object.fromEntries(Object.entries({emitter,extractor,solver,search,failureEmitter}).map(([name,path])=>[name,{path,sha256:hash(readFileSync(path))}])),discovery:discovered,production,failure,compilerMeasure:JSON.parse(execFileSync(emitter,['xor','measure'],{encoding:'utf8'}))};
writeFileSync(`${output}/integration.json`,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({status:report.status,productionBytes:Object.fromEntries(Object.entries(production).map(([k,v])=>[k,v.bytes])),candidates:discovered.candidates.length,falseRule:falseRule.solver.counterexample}));
