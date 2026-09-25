import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFile, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [linker, emitter] = process.argv.slice(2);
const directory = await mkdtemp(join(tmpdir(), "boundary-components-"));
try {
  const transportedLinker = join(directory, "boundary-link");
  await copyFile(linker, transportedLinker);
  const sizes = {};
  const emitterCalls = {};
  let linkerCalls = 0;
  for (const [key, kind] of [["call", "call"], ["state", "state"], ["suspend", "suspended"], ["double", "double"]]) {
    const object = execFileSync(emitter, [kind]);
    emitterCalls[key] = (emitterCalls[key] ?? 0) + 1;
    assert.equal(object.subarray(0, 8).toString(), "ABL_BMO1");
    sizes[key] = object.length;
    await writeFile(join(directory, `${key}.bmo1`), object);
  }
  assert.deepEqual((await readdir(directory)).sort(), ["boundary-link", "call.bmo1", "double.bmo1", "state.bmo1", "suspend.bmo1"]);
  const binding = (from, name, to, target = name) => ({ required: { instance: from, symbol: name }, supplied: { instance: to, symbol: target } });
  const bindings = [binding("call", "read", "state"), binding("state", "twice", "call"), binding("suspend", "compute", "state"), binding("suspend", "read", "state")];
  const manifest = {
    instances: ["call", "state", "suspend"].map(key => ({ key, path: `${key}.bmo1` })),
    bindings,
    entry: { instance: "suspend", symbol: "main" },
  };
  async function link(manifest) {
    await writeFile(join(directory, "link.json"), JSON.stringify(manifest));
    linkerCalls++;
    return execFileSync(transportedLinker, ["link.json"], { cwd: directory });
  }
  const first = await link(manifest);
  assert.equal(first.subarray(0, 8).toString(), "ABL_BPI3");
  assert.deepEqual(await link({ ...manifest, instances: [...manifest.instances].reverse(), bindings: [...bindings].reverse() }), first);
  const second = await link({
    instances: [...manifest.instances, { key: "double", path: "double.bmo1" }],
    bindings: [...bindings, ...["main", "read", "release"].map(name => binding("double", name, "suspend"))],
    entry: { instance: "double", symbol: "main" },
  });
  assert.notDeepEqual(first, second);
  const safe = await link({...manifest, coalescing: "safe"});
  assert.equal(safe.subarray(0, 8).toString(), "ABL_BPI3");
  assert.ok(safe.length <= first.length);
  assert.deepEqual(await link({...manifest, coalescing: "safe",
    instances: [...manifest.instances].reverse(), bindings: [...bindings].reverse()}), safe);
  assert.deepEqual(emitterCalls, { call: 1, state: 1, suspend: 1, double: 1 });
  assert.equal(linkerCalls, 5);
  console.log(JSON.stringify({ check: "source-independent BMO1 composition", emitterCalls,
    linkerCalls, objectBytes: sizes, linkedBytes: [first.length, second.length], safeBytes: safe.length }));
} finally {
  await rm(directory, { recursive: true, force: true });
}
