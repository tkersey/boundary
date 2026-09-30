import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const [rowsControl,rowsCandidate,fieldsControl,fieldsCandidate,output]=process.argv.slice(2);
assert.equal(process.argv.length,7);
const hash=b=>createHash('sha256').update(b).digest('hex');
const median=a=>a.toSorted((a,b)=>a-b)[Math.floor(a.length/2)];
const cases={rows:{control:rowsControl,candidate:rowsCandidate},fields:{control:fieldsControl,candidate:fieldsCandidate}};
const report={status:'running',protocol:'Five independently launched alternating paired windows; three warmups and nine samples per size in each process. Source-construction timings only; no World timing gate.',cases:{}};
for(const [name,paths] of Object.entries(cases)){
 const windows=[];
 for(let w=0;w<5;w++){
  const order=w%2?['candidate','control']:['control','candidate'],row={order};
  for(const arm of order)row[arm]=execFileSync(paths[arm],[],{encoding:'utf8',timeout:120000}).trim().split('\n').map(JSON.parse);
  assert.deepEqual(row.control.map(r=>r.n),row.candidate.map(r=>r.n));windows.push(row);
 }
 const keys=name==='rows'?['samples_ns']:['declaration_ns','assembly_ns'],cells=[];
 for(let i=0;i<windows[0].control.length;i++)for(const phase of keys){
  const pairedRatios=windows.map(w=>median(w.candidate[i][phase])/median(w.control[i][phase]));
  cells.push({n:windows[0].control[i].n,phase,pairedRatios,medianRatio:median(pairedRatios),controlMedianNs:median(windows.map(w=>median(w.control[i][phase]))),candidateMedianNs:median(windows.map(w=>median(w.candidate[i][phase])))});
 }
 report.cases[name]={binarySha256:Object.fromEntries(Object.entries(paths).map(([arm,path])=>[arm,hash(readFileSync(path))])),windows,cells};
}
report.status='complete';writeFileSync(output,JSON.stringify(report,null,2)+'\n');
