// Copyright (c) 2026 Boundary contributors. MIT license.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { execute } from "./source_oracle.mjs";
import { parseExactJson } from "../../tools/v2/exact_json.mjs";

const cases = JSON.parse(await readFile(process.argv[2], "utf8"));
assert.deepEqual(cases.map(({ mode }) => mode), ["yielding", "requesting", "disposing"]);
for (const { mode, source } of cases) {
  const trace = mode === "yielding" ? [{ kind: "Yielded" }] : mode === "requesting"
    ? [{ kind: "Requested", identity: "regression/cleanup-pause", payload: [] }] : [];
  const responses = mode === "requesting" ? [[]] : [];
  assert.deepEqual(execute(source, [], responses), { trace, kind: "Completed", value: [] });
  if (mode === "disposing") continue;
  for (const repeated of [false, true]) {
    const controls = [{ at: 0, reason: "stop" }];
    if (repeated) controls.push({ at: 0, reason: "later" });
    assert.deepEqual(execute(source, [], [], controls), {
      trace, kind: "Cancelled", reason: "stop", cleanupFailures: [],
    });
  }
}
console.log("source oracle preserves cleanup handlers across yield, request, and disposal");

const emitter = process.argv[3];
assert.ok(emitter, "authoring fixture emitter required for nested-memory regression");
const word = value => { const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(value)); return [...b]; };
for (const [kind, values] of [
  ["state_recursive_local", [2, 2, 2, 2]],
  ["state_recursive_shared", [2, 3, 5, 6]],
]) {
  const source = parseExactJson(execFileSync(emitter, [kind, "json"], {encoding: "utf8"}));
  assert.deepEqual(execute(source, [], []), {
    trace: [], kind: "Completed", value: [4, ...values.flatMap(word)],
  }, kind);
}
console.log("source oracle preserves nested owned snapshots and deliberately shared cells");
