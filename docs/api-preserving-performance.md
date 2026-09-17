# API-preserving performance results

This is historical Boundary 2 / World 5 evidence. The maintained retention probes
now use BPI3/PST3; reconstruct the predecessor probes from the commits recorded
below when reproducing these measurements. Their results do not qualify the
successor's performance.

Boundary retains less decoder and snapshot memory and avoids repeated image
section sizing. The combined Boundary/World implementation improves the measured
installation and saved-response workloads. **BPI2 images are unchanged:** this
work does not make the quadratic continuation-interface representation smaller.
The attempted compiler reduction was rejected on measured cost.

Delivery: [Boundary #150](https://github.com/tkersey/boundary/pull/150) and
[World #52](https://github.com/tkersey/world/pull/52). The accepted September 14,
2026 “Boundary 2 / World 5 — API-Preserving Performance Optimization v1” remains
the scope. The [validation summary](performance/validation.md) identifies checked
commits, commands, outcomes and selected records; it distinguishes production,
harness, packaging and measurement evidence.

## Inputs and retained implementation

| Role | Immutable commit |
|---|---|
| B0: Boundary 2.0 public-contract and performance reference | `55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328` |
| W0: approved World cleanup correctness successor | `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c` |
| Released World 5.0 reference | `5175e775005ee95e141b079936be163e1e75b803` |
| B1: original final timing input | `b599e664c57ca455395038bd28b703837f870030` |
| W1: original final timing input | `24867d20afd2076136c0cb14d64fee3a951d0f96` |

W0 includes the approved running-cleanup disposal correction and is separate
from the released-line reference. That correctness correction is not a speedup.
Later fixture, packaging and report corrections preserve the measured production
files; exact comparisons and the new cold-harness input are in the validation summary.

The retained Boundary mechanisms are:

- Decoder admission uses the caller allocator for temporary work, outside the
  returned arena. Admission finishes before canonical-discovery scratch is
  allocated. Returned records and payloads remain owned by `Decoded.arena`.
- Snapshot traversal maps, order, blob indexes and worklists use a temporary
  arena. Exact durable arrays and one payload copy remain in the returned owner.
- Image encoding computes section lengths once per operation. Full canonical
  admission, capacity and overlap checks still precede output mutation;
  `Compiled.encode` gains no trusted-input bypass.

The public layouts, ownership/deinitialization contracts, errors, admission,
capacity semantics, ABI, protocols, BPI2/PST2 bytes and identities are preserved.
Lifetime, aliasing, cycle, canonical-byte and allocation-failure regressions remain.
World's retained direct ownership, scratch reuse and request preparation changes
are explained once in the [companion report](https://github.com/tkersey/world/blob/main/docs/api-preserving-performance.md).
Combined runtime gains belong to B1/W1 together; they do not isolate Boundary's codec contribution.

## Size and memory

For the same canonical Program or State, the old and new encoders produce the
same bytes. The [wire comparison](performance/validation/correction-wire.json)
records 41 identical images. The 64-installation image remains 8,971 bytes; the
128-installation image remains 30,141 bytes. Repeated parameter and edge-argument
vectors still grow quadratically in this family.

| Observation | Baseline | Candidate | Scope |
|---|---:|---:|---|
| Initial 64-installation decoder retention | 332,384 B | 135,322 B | Exploratory general-allocator owner backing; not peak or RSS |
| Final 64-installation decoder retained / peak | 210,002 / 210,002 B | 101,024 / 140,036 B | Allocator-requested bytes in a fixed 1 MiB Workspace |
| Synthetic cyclic snapshot retention | 34,416 B | 26,398 B | Owner backing; both emit 986 PST2 bytes |

The initial retention probe used an uncommitted candidate; it is mechanism
exploration, not the committed acceptance window. Probe sources remain in
[`decode_retention.zig`](../test/v2/decode_retention.zig) and
[`snapshot_retention.zig`](../test/v2/snapshot_retention.zig).
The snapshot is a synthetic codec graph, not a claim of program-relative State
admission; its PST2 SHA-256 is
`e3ac7dc05e61f3695746e414bcce92a6f157b24ecc2afb09b6ea3048a3803fb0`.

Final decoder and full-invocation observations, including the 128-installation
capacity result and the large-constant scratch increase, are retained in the
[World memory results](https://github.com/tkersey/world/blob/main/docs/api-preserving-performance.md#memory).
Retained owner bytes, allocator-requested working peak, fixed reservations and
RSS are different quantities. No RSS reduction or universal memory reduction was measured.

To rerun the exploratory probes, set `SELECTED` to the selected source checkout
and `CANDIDATE` to this checkout (absolute paths):

```sh
zig run -O ReleaseSafe --dep boundary \
  -Mroot="$CANDIDATE/test/v2/decode_retention.zig" \
  --dep boundary_data_v2 -Mboundary="$SELECTED/src/v2/root.zig" \
  -Mboundary_data_v2="$SELECTED/src/v2/data/root.zig"
zig run -O ReleaseSafe --dep boundary_data_v2 \
  -Mroot="$CANDIDATE/test/v2/snapshot_retention.zig" \
  -Mboundary_data_v2="$SELECTED/src/v2/data/root.zig"
```

## Timing and reproduction

The two committed runtime windows and their raw observations live in the
[World report](https://github.com/tkersey/world/blob/main/docs/api-preserving-performance.md#runtime-results).
They measure medians of batch-average full-call times (200 fresh public calls
per batch), not individual-request latency distributions. They establish no p99
behavior. Repeated advance and large constants are reported separately.

The original [cold observations](performance/final-cold-guard.json) retain their
original harness hash and inputs. Five paired fresh-cache samples per workload
measured source-to-image medians of 18.333 → 18.239 seconds, with median paired
ratio 0.997; kernel builds measured 9.662 → 9.652 seconds, median paired ratio
1.000. Ratios of medians and medians of paired ratios are distinct statistics.
Already-built emitter launches were separately about 2.1 ms including startup.
These samples did not demonstrate a cold-build regression; they do not establish
universal non-regression or the historical 0.80-versus-1.8.2 target.

The [repaired harness](performance/cold-guard.mjs) takes explicit paths:

```sh
node docs/performance/cold-guard.mjs \
  --boundary-baseline '/absolute/path/to/B0' \
  --boundary-candidate '/absolute/path/to/B1' \
  --world-baseline '/absolute/path/to/W0' \
  --world-candidate '/absolute/path/to/W1' \
  --output '/absolute/path/to/new results'
node --test docs/performance/cold-guard.test.mjs
```

Relative paths resolve against the invocation directory. Each input must be a
clean repository root with the corresponding `tkersey/boundary` or
`tkersey/world` GitHub origin. Use the repository's Node 26.8.1+ toolchain, with Git and Zig 0.16.0 on PATH. The output must
not exist, its parent must exist, and output/caches must stay outside all four
source trees. Paths with spaces and filesystem aliases are supported.

The workload remains five paired AB/BA cold builds per workload, each with fresh
local and global Zig caches, native ReleaseSafe and World's unchanged guest
ReleaseSmall. The emitter has five warmups and 21 paired launches, separately.
OS caches are not flushed; build-driver, analysis, codegen and link times are
included together. Tool/source/harness/artifact identities accompany the rows.
Failures retain `partial.json` with `status: failed` and a command/cwd diagnostic;
only a complete run writes `cold-guard.json`. Preserve the output directory if a
run fails, and choose a new destination for another attempt.

The [relocated end-to-end run](performance/validation.md#repaired-harness) is a
new observation window. Historical JSON and its hashes have not been rewritten.
[Compiler/data attribution](performance/final-data-phases.json) separately
observed image emission at 121.9 → 106.9 µs for the 64-installation image, with
other observed compiler stages approximately unchanged. These instrumented
phase observations are not uninstrumented overall compiler-speed claims.

## Experiment dispositions and conformance corrections

| Experiment or correction | Disposition and bounded evidence |
|---|---|
| Equal parameter-vector pool | Rejected: fixed-workspace backing unchanged; native retention 135,322 → 135,302 B while allocation calls increased 8 → 9. [Observations](performance/metadata-pool-experiment.json), [archived patch](performance/metadata-pool-prototype.patch.txt), `NEG-000008`. |
| Identity-slot jump coalescing | Rejected: generator 808 → 796 B and borrowed-dependency 9,576 → 9,501 B, other 39 images unchanged; uninstrumented compile/encode/destruction 124,021 → 135,407 ns. [Timing](performance/compiler-coalesce-loop.json), [archived patch](performance/compiler-coalesce-prototype.patch.txt), `NEG-000009`. No smaller BPI2 achievement retained. |
| Earlier admission nesting | Corrected before final timing: the first lifetime change raised the eight-installation decoder peak to 30,476 B versus B0's 24,692 B. Flattening admission reduced it to 16,590 B. Historical observations remain in World's decoder-memory files. |
| Cleanup source oracle | Independently corrected: W0 already produced `[3,7,99]`; the old oracle lost the pending generator finalizer and produced `[3,99]`. [Old oracle](performance/cleanup-original-oracle.json), [W0 result](performance/cleanup-reference-world.json). This is correctness evidence, not a performance gain. |
| Fixture packaging | Cleanup helper moved inside the shipped emitter; all 41 image/source pairs preserved. Strict archive inventory and extracted examples 14/40 pass. The terminal cancellation script retains its one reachable cancel; independent repeated-cancellation tests remain. |

World's rejected exact handoff, continuation-view and collection-cadence
experiments are recorded in its companion report. Losing prototypes remain only
as identified reproduction material, outside production and active tests.
Raw observations, unfavorable runs, counterexamples and original identities are
retained. No format migration, consumer pin change, Agent change or PR #149 work is
part of the performance implementation.
