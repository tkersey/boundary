# Performance delivery validation

This is the shared validation record for Boundary #150 and World #52. Logs below
are checked in as ordinary PR artifacts. They contain actual verifier output;
release receipts identify actual locally built packages. No release was published.
The absence of GitHub-attached checks at the reviewed heads was a visibility gap,
not evidence that local checks had not run.

## Checked inputs and reuse

| Alias | Repository / exact commit |
|---|---|
| B0 | Boundary `55e8feedcae0b9ee1492da11f9fbd4a1ac7ff328` |
| B-code | Boundary `2c402b4b2ed69be68b2c5d9be2df77c2b3ce3797` (repaired executable harness and tests) |
| B-package | Boundary `1cf24fbb0ce53da0c46b2f337c91888d0228200a` (reviewed fixture/package input) |
| W0 | World `87698f92ca7be4d5442e97ba27a2468aa3ff6a7c` |
| W-code | World `a181646d8ef556b9f1be8187ba7c9f51b9c7fd74` |

The correction checks use detached, clean checkouts at these immutable commits.
[Command records](validation/correction-checks.json) and
[additional command records](validation/correction-extra-checks.json) give exact
executables, arguments, working directories, source heads, environment overrides,
exit statuses and times. Their individual logs include the same command headers.
Subsequent commits on these PRs add only reports, observations and supporting
logs under `docs/`; they are not claimed to have been executed as code.

The original runtime windows measured Boundary
`b599e664c57ca455395038bd28b703837f870030` and World
`24867d20afd2076136c0cb14d64fee3a951d0f96`. The
[input comparison](validation/measured-input-comparison.txt) establishes empty
diffs for `src/`, `build.zig` and `build.zig.zon` from those inputs to B-code/W-code
and lists all intervening changes. This preserves those timing observations'
production relevance. It does not validate changed fixture packaging or the new
harness; those have separate execution evidence below. No unrelated runtime
window was repeated because a documentation commit changed HEAD.

Tool configuration: Zig **0.16.0**, Node **26.8.2**, macOS arm64 / Apple M2 Pro;
native **ReleaseSafe**, guest **ReleaseSmall** as fixed by the repository.
Cross-engine/package checks use Wasmtime **48.0.0** through the existing `uv`
project (Python **3.14.7**). Boundary's existing Lean aggregate uses its unchanged
`semantics/v2/lean-toolchain` (Lean 4.33.1); trust output is retained in the aggregate log.
The [package receipts](validation/repaired-world-receipt.json) record tools,
source file identities, kernel memory settings and artifacts. Reservations,
capacity, public lifecycle and workload expectations were not weakened.

## Acceptance lanes

| Lane | Inputs and command/configuration | Outcome and accessible output |
|---|---|---|
| Repaired harness interface | B-code; `node --test docs/performance/cold-guard.test.mjs` | **Passed** — [log](validation/correction-cold-interface.log); eight tests including arbitrary/relative/spaced paths, missing paths/tools, dirty trees, existing output, subprocess errors/signals, partial results and symlink CLI entry. Stubbed failure bookkeeping is not performance evidence. |
| Boundary aggregate | B-code, World not involved; `zig build check-v2 -Doptimize=ReleaseSafe` with isolated output/cache | **Passed** — [log](validation/correction-boundary-aggregate.log). 375/375 build steps and 102/102 Zig tests; data/authoring/economy, source oracle, lifetime/alias/cycle/failure sweeps, artifact tests and existing Lean/trust checks. |
| BPI2 wire equality | B0 and B-code; baseline source/economy emission and exact file-byte comparison | **Passed** — [build log](validation/correction-baseline-wire-build.log), [41 exact comparisons](validation/correction-wire.json). The older [dirty exploratory comparison](boundary-wire-equality.json) remains historical. |
| Combined World aggregate | W-code + B-code and its emitted fixtures; `zig build check-v2 -Doptimize=ReleaseSafe` with explicit source, fixture, v1 kernel and lifter paths | **Passed** — [log](validation/correction-world-companion-aggregate.log). 54/54 build steps and 55/55 Zig tests; ownership/failure and capacity checks, source/target transfers across native/JS/Wasmtime, codecs, external consumers and physical package checks. |
| Default-pin World aggregate | W-code + B0; no Boundary source override; explicit B0 fixtures, v1 kernel and lifter | **Passed; reused** — [actual log](validation/repaired-world-pinned-check-2.log), [stored execution receipt](validation/world-repair-proof.json). Pinned-source kernel `0da1f478…`; no pin changed. |
| Four native source combinations | `zig build check-v2-native -Doptimize=ReleaseSafe` for W0/B0, W0/B-code, W-code/B0; W-code/B-code included in aggregate | **Passed** — [W0/B0](validation/correction-native-w0-b0.log), [W0/B-code](validation/correction-native-w0-b1.log), [W-code/B0](validation/correction-native-w1-b0.log). |
| Cross-version source transfers | W0 native embedding built with B0, W-code/B-code guest; current source-transfer runner and B-code oracle/fixtures | **Passed** — [native build](validation/correction-cross-native-build.log), [41-fixture transfer log](validation/correction-cross-source.log). Actual native and JS producers alternate; Wasmtime also checks source checkpoints. |
| Companion package and extracted examples | B-package + W-code assets; W-code `node scripts/v2/check_release.mjs … B-package W-code` | **Passed** — [fresh log](validation/correction-companion-package.log), [package result](validation/correction-companion-package.json). Strict source/archive inventory, extracted example 14, bundled CLI, runtime-only replay and 833 external records. [Example 40 and 14 log](validation/closed-emitter-package-check.log) is retained from the earlier checked archive. |
| Default-pin package | B0 published Boundary assets + W-code pinned assets; same verifier with explicit commits | **Passed** — [fresh log](validation/correction-pinned-package.log), [package result](validation/correction-pinned-package.json). Same inventory/authentication and fresh consumer checks. |
| Cold performance guard | B0/B-code and W0/W-code, repaired B-code harness | **Passed** — [new observations](correction-cold-guard.json), [command](validation/cold-command.json), [log](validation/cold.log), [exit](validation/cold-exit.json). Details below. |
| Existing runtime/memory windows | Original measured commits above, unchanged production inputs | **Retained** — [World's raw observations and statistical scope](https://github.com/tkersey/world/blob/perf/api-preserving-data-path/docs/api-preserving-performance.md#runtime-results). Not rerun for report changes. |

The explicit historical kernel supplied to aggregate checks is the v1.8.2 asset,
SHA-256 `4da38268f12e8a2749a266480748da5460b5030dadfc10804f79ba3a3bb8013e`.
Its presence is a conformance prerequisite, not the separate 0.80 cold-compilation
comparison. The exact command paths and lifter selection are in the new logs.

## Package evidence

Before reuse, every available old log was compared byte-for-byte by SHA-256 with
its stored [Boundary](validation/boundary-repair-proof.json) or
[World](validation/world-repair-proof.json) execution receipt. All matched. The
receipts' historical `/tmp` paths identify the original files; copies with those
same basenames are linked here and remain byte-identical. A receipt alone is not
substituted for the accessible verifier output.

| Asset set | Source binding and supporting records |
|---|---|
| Boundary candidate | [Receipt](validation/repaired-boundary-receipt.json), [SHA256SUMS](validation/repaired-boundary-SHA256SUMS.txt), [emission log](validation/repaired-boundary-release-2.log): B-package, clean; 41 programs, 126 source scripts. |
| World companion | [Receipt](validation/repaired-world-receipt.json), [SHA256SUMS](validation/repaired-world-SHA256SUMS.txt), [emission log](validation/repaired-world-release-2.log): W-code + B-package, clean; 563 exact native/JS/Wasmtime record checks. |
| World default pin | [Receipt](validation/repaired-world-pinned-receipt.json), [SHA256SUMS](validation/repaired-world-pinned-SHA256SUMS.txt), [emission log](validation/repaired-world-pinned-release.log): W-code + B0, clean; 555 exact record checks. |

Companion kernel: **393,588 bytes**,
`9545076f16482ccb346ab7792ae87f4d9a262c3fe08b4086b3c376ed2b218c06`.
Default-pin kernel: **392,622 bytes**,
`0da1f478fa1de495c2354724a8b90d7279fd7219c4dcde7f9f79dff85c1e06b6`.
Boundary examples archive:
`c4bb445cf00682205ae32e20f0cdade0eb5f9cefd4488b2d51fdb4a364fe1d12`.
All source, archive, fixture bundle and conformance artifact identities are in
the receipts. The current cold build reproduces the companion kernel hash.

## Repaired harness

The end-to-end run used caller-supplied relative paths under a fresh temporary
directory named `boundary performance correction …`, with `B0 checkout`,
`B1 checkout`, `W0 checkout`, `W1 checkout` and sibling `cold results` directories.
These locations contain spaces and are outside the former hardcoded roots.
Preflight and final readback confirm clean source identities. No builds or other
benchmarks ran alongside this measurement window.

| Workload | Baseline median | Candidate median | Ratio of medians | Median paired ratio |
|---|---:|---:|---:|---:|
| Cold source-to-image | 16.118078 s | 16.162010 s | 1.002726 | 1.001650 |
| Cold World kernel | 9.183982 s | 9.177047 s | 0.999245 | 0.999245 |
| Already-built emitter launch | 2.122375 ms | 2.127625 ms | 1.002474 | 0.998436 |

There are five paired cold samples per workload, fresh local/global object caches
for every sample, and five emitter warmups followed by 21 paired launches.
OS caches are not flushed. Timings include the original subprocess boundaries;
the emitter includes process startup. The 114-byte emitted image is identical
across all cold and emitter samples, and kernels are reproducible per side.
These near-parity observations do not establish a uniform cold speedup or a
universal non-regression theorem.

Harness SHA-256:
`05584c4b4366395c5384230f7ca76db87a5c02f895cdff6c17d64404b3e1cc88`.
The old [cold window](final-cold-guard.json) retains its original hash and data.
One initial execution of revision `b54b02d` exited zero without running because
its CLI entry comparison did not canonicalize macOS's `/var` alias. The
[original command](validation/initial-performance-correction-cold-command.json),
[empty log](validation/initial-performance-correction-cold.log) and
[exit status](validation/initial-performance-correction-cold-exit.json) are retained.
This attempt is a **failed harness validation with no performance samples**.
B-code fixes the comparison and adds a real subprocess regression. The completed
run above is a distinct observation, not a replacement of failed timing data.

## Remaining limits

No required environment gap is currently hidden by a report or digest. Final
check outcomes above must be read at their named commits. This finite suite is
not a universal proof of every runtime path, individual-request tail latency,
or memory non-regression. The storage representation, repeated-advance and
large-constant limitations remain in the reports. Draft status, public pins,
formats and release state are unchanged.
