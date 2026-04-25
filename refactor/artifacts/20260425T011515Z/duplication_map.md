# Duplication Map

Run ID: `20260425T011515Z`

## Accepted Candidate

| Candidate | Type | Evidence | LOC | Confidence | Risk | Score | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| Collapse benchmark `preserveValue` clones into `src/bench_support.zig` where the benchmark already imports the private `ability` facade | I exact clone | `rg -n "fn preserveValue\\(value: anytype\\)" bench src` found eight byte-identical helper bodies; seven live under the facade-backed benchmark import shape. | 3 | 5 | 1 | 15.0 | Accept |

## Rejected / Deferred

| Candidate | Reason |
| --- | --- |
| Collapse `bench/runtime_backend_matrix_bench.zig` into the shared helper | Rejected after proof: adding the facade import makes Zig report duplicate file ownership between modules `ability` and `ability_shared`. Keeping the local helper preserves the existing build graph. |
| Benchmark `sortAscending` / `summarizeSamples` clones | Same family, but return shapes differ between median-only and min/median/max summaries. Defer until a separate proof lane is worth the coupling. |
| `public_ir` / `public_lowering` / lexical executor deletion | Active `$st` item and higher semantic risk. Not part of this small isomorphic pass. |
