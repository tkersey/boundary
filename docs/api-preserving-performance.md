# API-preserving performance work (in progress)

The accepted source is `pasted-text-1.txt`, supplied September 14, 2026, titled
“Boundary 2 / World 5 — API-Preserving Performance Optimization v1”. Its full
scope remains open, including World production improvements, compatibility,
experiments, final measurements, draft PR publication and review closeout.

## Inputs and isolation

- B0: `55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328` (Boundary 2.0 reference and current main).
- W0: `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c` (approved cleanup correction,
  separate from main `5175e775005ee95e141b079936be163e1e75b803`).
- Candidate branches: `perf/api-preserving-data-path` in both repositories.
- Candidate worktrees: `/Users/tk/.codex/worktrees/e38a/{boundary,world}`.
- Immutable baseline worktrees: `/Users/tk/.codex/worktrees/perf-reference/{boundary,world}`.
- Zig: 0.16.0; native macOS arm64; ReleaseSafe. Baseline and candidate global
  caches are separately rooted under `perf-reference` and `e38a`.
- Remote main references refreshed with `git fetch origin` in both repositories.

## First experiment: decoded admission lifetime

`image.decode` formerly passed its result arena to `canonical.require`, whose
own temporary arena therefore retained its backing in the decoded owner.
Pass the original caller allocator instead. `canonical.require` still executes
all admission and canonical checks and destroys its temporary arena before
returning. Records and input bytes remain duplicated into the unchanged
`Decoded.arena`; no scratch fields escape. Failure discards the result arena.
No public declaration or wire representation changes.

A standalone allocation probe uses the public builder's 64-installation example,
`program.compile`, `Compiled.encode`, and `image.decode`. A FailingAllocator over
the process allocator counts requested bytes allocated and freed; destruction
asserts equal totals. This is allocator-requested retention, not RSS or peak.

| Input | B0 | Initial dirty candidate |
|---|---:|---:|
| Image bytes | 8,971 | 8,971 |
| Retained decoder bytes | 332,384 | 135,322 |
| Decoder allocation calls | 4 | 8 |

This initial experiment reduces retention by 197,062 bytes (59.29%). It does
not establish latency, total peak, arena-backed reclamation or World capacity.
Final acceptance requires committed inputs, paired measurements and two windows.

Local exploratory artifacts (not final portable evidence):
`/Users/tk/.codex/worktrees/perf-reference/results/decode-retention.zig` and
`results/boundary-install64/baseline.json` under that same `perf-reference` root.
The latter is the existing compiler phase profiler, kind 7, five warmups and 21
samples. It predates the production edit. No performance decision relies on
compile-overlapped timings.

Baseline and initial candidate `zig build check-v2-data -Doptimize=ReleaseSafe`
passed with their isolated global caches. Existing checks include input lifetime,
canonical bytes, malformed input and allocation failure sweeps. A new focused
regression checks scratch frees before owner destruction, re-encoding after input
overwrite, and complete deallocation.

## Remaining work

Finish Boundary lifetime/codec and immutable metadata experiments, then World
direct ownership, scratch and request preparation. Compare private stable
transfers against the corrected ownership implementation; evaluate collection
cadence separately. Complete the bounded in-format compiler experiment and cold
build guard. Preserve all public APIs, formats, cleanup behavior and negative
cases. Run the full B0/B1 × W0/W1 and native/WASM/restoration matrix, final paired
measurements, package checks and review closeout. No PR has yet been created.

Primary timing set, fixed before candidate selection: short scalar invocation,
64 installations, retained DFS search, and saved response with a retained
environment and equal-looking successive requests. Include all required workload
families as additional checks; fixture scripts and full timing boundaries still
need binding before World experiments.

## Snapshot and codec continuation

Snapshot traversal maps, node order, blob indexing and reference worklists now
use an independent temporary arena. Final nodes, remapped roots, exact blob
records and one payload copy remain in the unchanged result owner. A cyclic
128-node graph measured 34,416 retained requested bytes at B0 and 26,398 after
the change. Both encoded to 986 PST2 bytes with SHA-256
`e3ac7dc05e61f3695746e414bcce92a6f157b24ecc2afb09b6ea3048a3803fb0`.
This synthetic codec workload does not claim program-relative State admission.
The failure-injection regression additionally covers duplicate blobs, distinct
nodes, cycles and caller-payload destruction.

Image encoding computes section lengths once and uses that result for both total
size and directory emission. Canonical admission, capacity and overlap checks
still precede output mutation. There is no stored or caller-asserted admission
certificate, and `Compiled.encode` still calls full public image encoding.

The full `zig build check-v2 -Doptimize=ReleaseSafe` command passed after these
production changes: data, authoring, economy, source semantics, artifact tests
and the existing Lean model/trust checks. The [wire comparison](performance/boundary-wire-equality.json)
records 41 emitted BPI2 images identical to B0, including all 37 source fixtures
and four economy workloads. No smaller-image claim is made.

The allocation probes are now retained as `test/v2/decode_retention.zig` and
`test/v2/snapshot_retention.zig`. To reproduce against either selected checkout,
set `SELECTED` to its absolute path and `CANDIDATE` to this checkout:

```sh
zig run -O ReleaseSafe --dep boundary \
  -Mroot="$CANDIDATE/test/v2/decode_retention.zig" \
  --dep boundary_data_v2 -Mboundary="$SELECTED/src/v2/root.zig" \
  -Mboundary_data_v2="$SELECTED/src/v2/data/root.zig"
zig run -O ReleaseSafe --dep boundary_data_v2 \
  -Mroot="$CANDIDATE/test/v2/snapshot_retention.zig" \
  -Mboundary_data_v2="$SELECTED/src/v2/data/root.zig"
```

All reported measurements remain exploratory dirty-candidate observations.
Committed paired latency windows, cold-build guards, immutable-metadata and
compiler-size experiment dispositions, allocator/peak coverage, complete
cross-consumption and review convergence remain open. The planned draft
publication is explicitly partial under specification sections 1 and 24.
