// Copyright (c) 2026 Boundary contributors. MIT license.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { execute } from "./source_oracle.mjs";

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
