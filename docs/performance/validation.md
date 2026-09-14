# Performance delivery validation

This is the shared acceptance summary for Boundary #150 and World #52. The
maintained evidence consists of the existing tests, material measurements and
selected result records. Detailed verification output remains accessible in the
[historical validation directory](https://github.com/tkersey/boundary/tree/e8513f34248e60c933c863abc8b1c95e0f91ef63/docs/performance/validation);
it is not a required inventory of maintained source artifacts. No release was published.

## Checked inputs and reuse

| Alias | Repository / exact commit |
|---|---|
| B0 | Boundary `55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328` |
| B-check | Boundary `2c402b4b2ed69be68b2c5d9be2df77c2b3ce3797` (aggregate, wire, matrix and first cold correction window) |
| B-harness | Boundary `d05df6bd5ec6c322088ef57c36278db93d779b0b` (final executable harness and ten tests) |
| B-package | Boundary `1cf24fbb0ce53da0c46b2f337c91888d0228200a` (fixture/package input) |
| W0 | World `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c` |
| W-code | World `a181646d8ef556b9f1be8187ba7c9f51b9c7fd74` |

The checks ran in detached, clean checkouts. Existing
[execution records](validation/correction-checks.json) and
[additional execution records](validation/correction-extra-checks.json) retain
commands, working directories, source heads, configuration, exit statuses and
times. Their `cold-interface` entry is the earlier eight-test run at B-check;
the final ten-test run is separately bound to B-harness below.

The original runtime windows measured Boundary
`b599e664c57ca455395038bd28b703837f870030` and World
`24867d20afd2076136c0cb14d64fee3a951d0f96`. Their `src/`, `build.zig` and
`build.zig.zon` inputs are unchanged at B-check/W-code. B-harness also changes no
runtime, build, package, source-fixture or existing runtime-benchmark inputs
relative to B-check. The comparisons are recorded in the historical directory.
Those facts preserve the corresponding evidence; they do not substitute runtime
timings for validation of the separately changed harness or packaging.

Tools: Zig **0.16.0**, Node **26.8.2**, macOS arm64 / Apple M2 Pro; native
**ReleaseSafe**, repository-fixed guest **ReleaseSmall**. Cross-engine/package
checks use Wasmtime **48.0.0**, the existing `uv` project and Python **3.14.7**.
Boundary's unchanged Lean aggregate uses **4.33.1**.

Review closeout completed at Boundary
`e8513f34248e60c933c863abc8b1c95e0f91ef63` and World
`0a0b38d03282f7fddbbb9583c7ae81d99a059d6b`. The subsequent archival cleanup
changes no executable inputs, independent expectations or material measurements.
It reuses that acceptance and review evidence, with scope and link checks for the
archival edits; it does not claim execution or fresh reviews of a later HEAD.

## Acceptance lanes

All outcomes below describe the named executions, not new runs for this archival cleanup.

| Lane | Inputs / command | Outcome and retained evidence |
|---|---|---|
| Harness interface | B-harness; `node --test docs/performance/cold-guard.test.mjs` | **Passed**, ten tests: paths, preflight, launch failures/signals, partial results, preserved symlinks, safe imports and PATH shims. [Historical final output](https://github.com/tkersey/boundary/blob/e8513f34248e60c933c863abc8b1c95e0f91ef63/docs/performance/validation/correction-final-interface.log). Stubbed error tests are not performance evidence. |
| Boundary aggregate | B-check; `zig build check-v2 -Doptimize=ReleaseSafe` | **Passed**, 375/375 build steps and 102/102 Zig tests, plus source-oracle, artifact and Lean/trust checks. Commands and outcome in `correction-checks.json`; detailed output in the historical directory. |
| BPI2 wire equality | B0 / B-check; source and economy emission, exact byte comparison | **Passed**, [41 exact comparisons](validation/correction-wire.json); build invocation in `correction-extra-checks.json`. |
| Combined World aggregate | W-code / B-check; `zig build check-v2 -Doptimize=ReleaseSafe` with explicit fixtures, legacy kernel and lifter | **Passed**, 54/54 build steps and 55/55 Zig tests; ownership/failure, capacity, native/JS/Wasmtime transfers, codecs, external consumers and physical package checks. Invocation in `correction-checks.json`. |
| Default-pin World aggregate | W-code / B0; same aggregate without a source override | **Passed; reused**. [Historical output](https://github.com/tkersey/boundary/blob/e8513f34248e60c933c863abc8b1c95e0f91ef63/docs/performance/validation/repaired-world-pinned-check-2.log), bound at the same commit by `world-repair-proof.json` and the pinned package receipt. No pin changed. |
| Four native combinations | `zig build check-v2-native -Doptimize=ReleaseSafe` for W0/B0, W0/B-check, W-code/B0 and W-code/B-check | **Passed**; first three invocations in `correction-checks.json`, fourth included in the combined aggregate. |
| Cross-version source transfers | W0/B0 native producer and W-code/B-check guest; B-check oracle/fixtures | **Passed**, 41 source fixtures, alternating native/JS producers and Wasmtime checkpoints. Build and transfer invocations in `correction-extra-checks.json`. |
| Companion package | B-package / W-code; `node scripts/v2/check_release.mjs` with explicit commits | **Passed**, [package result](validation/correction-companion-package.json): strict inventories, extracted example 14, bundled CLI, runtime-only replay, 563 conformance and 833 external records. Earlier extracted examples 14/40 passed on the same archive; their output remains in the historical directory. |
| Default-pin package | B0 assets / W-code pinned assets; same verifier with explicit commits | **Passed**, [package result](validation/correction-pinned-package.json): 555 conformance and 833 external records, with the same authentication and inventory checks. |
| Cold guard | B0/B-harness and W0/W-code | **Passed**, [final observations](correction-cold-guard-2.json) and [invocation](validation/cold-final-command.json). The [first correction window](correction-cold-guard.json) remains separate. |
| Runtime and memory | Original measured commits above | **Retained**, [World results and raw observations](https://github.com/tkersey/world/blob/perf/api-preserving-data-path/docs/api-preserving-performance.md#runtime-results). Not rerun for archival or reporting edits. |

The aggregate's historical v1.8.2 kernel has SHA-256
`4da38268f12e8a2749a266480748da5460b5030dadfc10804f79ba3a3bb8013e`.
Its use is conformance evidence, not the separate 0.80 cold-compilation comparison.

## Artifact identities

The package result records retain checked commits, kernel identities, comparison
counts and runtime entry hashes. Full emission receipts and source inventories
remain in the historical directory, including the clean B-package/W-code and
B0/W-code bindings. Their existing local execution logs were checked against
recorded hashes before reuse; they are not reconstructed from PR prose.

| Artifact | Identity |
|---|---|
| Companion kernel | 393,588 bytes; `9545076f16482ccb346ab7792ae87f4d9a262c3fe08b4086b3c376ed2b218c06` |
| Default-pin kernel | 392,622 bytes; `0da1f478fa1de495c2354724a8b90d7279fd7219c4dcde7f9f79dff85c1e06b6` |
| Boundary examples archive | `c4bb445cf00682205ae32e20f0cdade0eb5f9cefd4488b2d51fdb4a364fe1d12` |
| Final cold harness | `aed494ba631991fe47c2faedda8240afd0c7a8452405539081f94b763d097711` |

## Repaired harness

The final run used caller-supplied relative checkout paths containing spaces,
with results/caches outside the clean measured trees and the main-module symlink
preserved. No builds or other benchmarks overlapped the window. Each workload
has five paired cold samples with fresh local/global Zig caches; the already-built
emitter has five warmups and 21 paired launches. OS caches are not flushed and
emitter times include process startup. Source, tool, harness and artifact
identities accompany the raw rows.

| Workload | Baseline median | Candidate median | Ratio of medians | Median paired ratio |
|---|---:|---:|---:|---:|
| Cold source-to-image | 16.484069 s | 16.407520 s | 0.995356 | 1.001211 |
| Cold World kernel | 9.549479 s | 9.661370 s | 1.011717 | 1.004112 |
| Already-built emitter launch | 2.428417 ms | 2.408875 ms | 0.991953 | 0.987217 |

All 114-byte emitted images agree; kernels reproduce per side. The slower kernel
median is retained alongside the other results. These samples establish neither
uniform cold speedup nor universal non-regression. The original
[cold window](final-cold-guard.json) and both correction windows retain their
original hashes and observations.

An initial `b54b02d` invocation exited zero without measuring because of macOS's
`/var` alias. Later review found preserved-main aliases and PATH shim dispatch
also needed correction. These were harness failures, not performance samples.
B-harness uses Node's main-module identity and preserves PATH invocation names;
the regression tests retain those distinctions. Intermediate empty logs and
review output are historical detail, not additional maintained test artifacts.

Public APIs, formats, admission, ownership, capacity, independent expectations
and required acceptance checks remain unchanged. No validation gap was created
by removing redundant archival copies. The reports retain the binary-size,
repeated-advance, large-constant and tail-latency limitations.
