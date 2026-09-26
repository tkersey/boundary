// Paired independent process windows. Does not decide production promotion.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const [executable,output]=process.argv.slice(2);
assert.ok(executable&&output&&process.argv.length===4);
const median=values=>[...values].sort((a,b)=>a-b)[Math.floor(values.length/2)];
const fixtures=['arithmetic','deep','shallow','cleanup','twice','cells_independent',
  'memo_independent','hyper_duplicate','hyper_configured','hyper_lazy'];
const phases=['source','compile','encode','cold_admit'];
const measurements=[];
for(const fixture of fixtures) {
  const windows=[];
  function window(index) {
    const order=index%2===0?['off','safe']:['safe','off'];
    const arms={};
    for(const mode of order) {
      arms[mode]=JSON.parse(execFileSync(resolve(executable),[fixture,mode],
        {encoding:'utf8',maxBuffer:16<<20}));
      assert.equal(arms[mode].warmups,3);assert.equal(arms[mode].samples.length,9);
      assert.equal(arms[mode].optimization,'ReleaseSafe');
      for(const row of arms[mode].samples)assert.equal(row.sha256,arms[mode].samples[0].sha256);
    }
    assert.ok(arms.safe.samples[0].bytes<=arms.off.samples[0].bytes);
    const medians={},ratios={};
    for(const phase of phases) {
      medians[phase]=Object.fromEntries(['off','safe'].map(mode=>
        [mode,median(arms[mode].samples.map(row=>row[phase].ns))]));
      ratios[phase]=medians[phase].safe/medians[phase].off;
    }
    windows.push({index,order,medians,ratios,arms});
  }
  for(let i=0;i<3;i++)window(i);
  const suspected=windows.some(w=>w.ratios.cold_admit>1.05);
  if(suspected)for(let i=3;i<5;i++)window(i);
  for(const mode of ['off','safe'])for(const w of windows)
    assert.equal(w.arms[mode].samples[0].sha256,windows[0].arms[mode].samples[0].sha256);
  const summary={};
  for(const phase of phases) {
    summary[phase]={pairedMedianRatio:median(windows.map(w=>w.ratios[phase])),
      offMedianNs:median(windows.map(w=>w.medians[phase].off)),
      safeMedianNs:median(windows.map(w=>w.medians[phase].safe)),
      peakRequestedBytes:Object.fromEntries(['off','safe'].map(mode=>[mode,
        Math.max(...windows.flatMap(w=>w.arms[mode].samples.map(r=>r[phase].peak_requested_bytes)))])),
      medianAllocatedBytes:Object.fromEntries(['off','safe'].map(mode=>[mode,
        median(windows.flatMap(w=>w.arms[mode].samples.map(r=>r[phase].allocated_bytes)))]))};
  }
  const coldAdmissionRegression=windows.length===5&&
    summary.cold_admit.pairedMedianRatio>1.05&&windows.filter(w=>w.ratios.cold_admit>1.05).length>=4;
  measurements.push({fixture,confirmationWindows:suspected,summary,coldAdmissionRegression,windows});
  process.stderr.write(`${fixture}: compile ${summary.compile.pairedMedianRatio.toFixed(2)}x; `+
    `cold admission ${summary.cold_admit.pairedMedianRatio.toFixed(2)}x\n`);
}
const hash=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const result={scope:'Synthetic compiler and cold Boundary admission B1/B2; not World runtime or Agent qualification',
  protocol:'Three independently launched alternating windows; three warmups and nine samples per process. Two confirmation windows when any initial cold-admission ratio exceeds 1.05.',
  clock:'std.Io.Clock.awake; measured operations exclude process startup and report formatting',
  allocationScope:'Requested bytes observed at source/lowering/encoding/admission allocator boundaries; excludes allocator metadata, RSS and runtime live memory',
  caveats:['Source construction includes any validation performed by the public typed module builder.',
    'No B0 control or runtime execution timing is included.',
    'Host contention is not controlled; raw per-window ratios are retained.'],
  executableSha256:hash(executable),harnessSha256:hash(new URL(import.meta.url)),measurements};
writeFileSync(output,JSON.stringify(result,null,2)+'\n');
