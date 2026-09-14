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

## Cleanup conformance prerequisite

World's corrected W0 source-transfer harness requires four cleanup-disposal
fixtures absent from the release Boundary base. Their public-builder definitions
and registration were taken from Boundary commit
`4be961b51f2a5720b4a86943e08c4747425e1a2e`, without any proof-branch merge,
production compiler changes or new formal dependency.

The owned-result fixture independently specifies a pending generator finalizer
writing `7`, followed by the abandoning clause's `99`; its complete log is
`[3,7,99]`. Before correction, the source oracle produced `[3,99]`, while the
unmodified approved W0 kernel produced `[3,7,99]`. The
[old oracle observation](performance/cleanup-original-oracle.json) and
[W0 observation](performance/cleanup-reference-world.json) retain that difference.
The old oracle had no owner for a normal protected result during interrupted
cleanup. Only the source-oracle cleanup/ownership correction from the same
commit was reused: retain that result through cleanup, transfer on normal
completion, and unwind it on abandonment; preserve primary failure and first
cancellation. No low-level constructor interpreter or JSON changes were imported.

The 41-fixture independent source suite now passes, retaining every previous
assertion and adding the four disposal cases plus repeated cancellation during
failing cleanup. This oracle correction is separately attributable and is not
an optimization gain. Historical corpus projection was unavailable because its
store binding was invalid; no recurrence or complete-history claim is made.

With these fixtures and the isolated oracle correction, World
`check-v2-wasmtime` passed all 41 compiled source examples and cancellation
scenarios across the source oracle, native execution, JavaScript WASM and
Wasmtime 48.0.0. The candidate kernel was
`feeb3a33602cbe86f060af4cb7266ffad8f66e0b2bf9c4a0415975f9b36faef9`.
The handwritten checkpoint, stale-result and cancellation-rebinding lanes also
passed. This closes the missing-fixture validation gap; final cross-version
matrix and performance acceptance remain separate work.

## Immutable parameter sharing experiment: rejected

A bounded prototype pooled equal uniform block-parameter vectors while preserving
all logical IDs, slice lengths, BPI2 bytes and full canonical admission. Mixed,
permuted and repeated-operand vectors used ordinary owned storage. Optional
allocation failure discarded the private decode and tried the original decoder;
no public state or authority had been committed. Data and allocation-failure
tests passed, including a new mixed/permuted-vector roundtrip.

The [prototype patch](performance/metadata-pool-prototype.patch.txt) is retained
only as experiment history; none of it remains in the production decoder.
[Measurements](performance/metadata-pool-experiment.json) used five warmups and
21 decoder samples through the existing 1 MiB World Workspace. Complete BPI2
re-encoding was checked outside timing.

| Image | Retained bytes before / pool | Peak payload before / pool | Decode median ns before / pool |
|---|---:|---:|---:|
| 1 installation | 6,178 / 6,178 | 11,416 / 11,416 | 3,875 / 3,916 |
| 8 installations | 10,322 / 10,322 | 30,476 / 30,476 | 8,167 / 7,958 |
| 64 installations | 101,024 / 101,024 | 179,898 / 179,898 | 68,458 / 71,875 |
| Local State | 17,738 / 17,738 | 48,834 / 48,834 | 15,666 / 15,375 |

These serial exploratory timing samples are not final paired acceptance results.
The deterministic allocation result already fails the retention hypothesis:
logical metadata sharing did not remove an arena backing allocation. With the
native general allocator, 64-installation retention changed only from 135,322 to
135,302 bytes and allocation calls increased from eight to nine. There is no
justified gain for the additional parser path and scratch. A future contiguous
packing experiment would need new evidence that it changes actual retained
backing or complete operation cost, rather than merely reducing logical bytes.

## Admission nesting and decoder peak

The new bounded-memory probe exposed a real peak regression in the first
lifetime change: eight installations used 30,476 peak payload bytes versus
24,692 in B0, despite lower retention. `canonical.require` still nested the
already-arena-owned admission operation inside another arena. Admission now
uses the supplied allocator directly and finishes before canonical discovery.
No validation is removed or result layout changed.

After this correction, decoder retained / peak payload bytes in the same
1 MiB Workspace are 6,178 / 9,042 (one installation), 10,322 / 16,590 (eight),
101,024 / 140,036 (64), and 17,738 / 25,906 (local State). B0 peaks were
16,856 / 24,692 / 210,002 / 48,998 respectively. Thus all four measured peaks
are below B0, with the previously established retention reduction preserved.
Raw observations are in the companion World's `docs/performance/decoder-memory-b0-b1.json`
and `decoder-memory-flat-admission.json`, produced by `build-v2-decode-probe`.
The rejected parameter-pool experiment is recorded as `NEG-000008`; the native
Ledger binding and append were validated without rewriting prior events.

## Administrative compiler experiment (rejected)

The private identity-slot jump coalescing experiment passes authoring admission
and the 41-fixture source-oracle/native/JavaScript/Wasmtime comparison, with the
unmodified corrected W0 native consumer. Borrowed operands shrinks from 9,576 to
9,501 BPI2 bytes; the generator shrinks from 808 to 796. The other 39 images are
byte-identical. [Raw image hashes and sizes](performance/compiler-coalesce-experiment.json)
record this exploratory result. These are new compilations with their own image
identities, not a codec change or permission to reuse responses across images.

The pass requires a unique incoming edge, the same function, an exact identity
argument vector, and total scalar instructions. Function entries and yield
boundaries remain intact. Focused admitted-record tests cover exact operand
indices and the ineligible permutation/yield siblings. Full pre-transform
admission and canonicalization's post-transform admission remain enabled.
An exploratory already-built generator-emitter comparison used five warmup
batches and 21 alternating paired samples, ten fresh processes per batch.
The median paired elapsed ratio was 1.018 (candidate/reference), including
process startup and output checking. This does not establish a compiler speedup
and needs attribution before selection. [Raw emitter observations](performance/compiler-coalesce-emitter.json)
retain every pair. The baseline emitter was built from `c914de1`; the candidate
used the current working tree, both with Zig 0.16.0 and ReleaseSafe for every
module.

The follow-up [uninstrumented compiler loop](performance/compiler-coalesce-loop.json)
excludes process startup and measures fresh construction, public compilation,
encoding, digest checking and destruction. Across five warmup batches and 21
alternating pairs of 100 compilations, generator medians were 124,021 ns before
and 135,407 ns after; the median paired ratio was 1.100. A 12-byte reduction
does not justify this measured compiler regression. The pass and its dedicated
tests were removed; [the prototype patch](performance/compiler-coalesce-prototype.patch.txt)
and [probe source](performance/compiler-loop-probe.zig.txt) preserve reproduction.

The existing phase observer also located additional complete admission work:
on the unchanged 64-installation image, the direct-optimization phase grew from
708 to 38,375 ns. A no-jump early exit did not help because this workload has
ineligible jumps. Both [original](performance/compiler-coalesce-phases.json) and
[filtered](performance/compiler-coalesce-filtered-phases.json) attribution runs
are retained. These instrumented fixed-buffer measurements are separate from
the deciding uninstrumented compiler-loop timing. Final compiler output remains
unchanged by this experiment; no smaller-program achievement is claimed.

The rejected pass is recorded as `NEG-000009`. After removing it, the retained
Boundary tree passed `zig build check-v2 -Doptimize=ReleaseSafe` with the isolated
global cache, including the existing Lean/trust checks and all 41 source-oracle
fixtures. The retained compiler source is identical to `c914de1`; the remaining
production delta from that head is the canonical admission scratch-lifetime fix.
