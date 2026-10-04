# Zig 0.17 upgrade: execution evidence

The maintained successor supports **exact Zig 0.17.0 only**. Frozen 0.16
checkouts, executables, and delivery artifacts are comparison and rollback
inputs, not a supported successor configuration.

The [execution specification](zig-0.17-upgrade-spec.md) remains the completion
contract. The [machine record](performance/zig17-upgrade.json) retains source,
toolchain, census, and observation identities. The retained records cover all ten opportunities, the acceptance-case witnesses,
and the recorded cross-stack execution subjects. Independent review and live PR
readiness remain provider facts, not claims inferred from benchmark success.

## Delivery order and executed subjects

| Order | Draft PR | Executed source snapshot | Current evidence |
|---|---|---|---|
| 1 | [Boundary #164](https://github.com/tkersey/boundary/pull/164) | `2981507d9d0967babf69c5140674e6536263bfea` | macOS: 317 steps; Linux aggregate and independent public-package authoring pass; 114 frozen artifacts unchanged |
| 2 | [World #62](https://github.com/tkersey/world/pull/62) | `60214850e1be215c57e52a7b36f9ab82cd9cae92` | All 13 public-producer checks pass on macOS and Linux; independently acquired bundles have identical kernels |
| 3 | [Agent #42](https://github.com/tkersey/agent/pull/42) | `539f3fb1444acd7dcf22dda1c8b825de5132cdf8` | macOS: 528 steps / 218 tests including integration, mobility and browsers; Linux: 430 steps / 218 tests; 188 frozen artifacts unchanged |

These are immutable **executed** subjects. Documentation/provenance successors
must retain verified code/package/kernel correspondence and rerun affected
consumer/delivery checks under S05. The dependent PR proof blocks and Agent's
[dependency lock](https://github.com/tkersey/agent/blob/codex/zig-0.17-upgrade/conformance/agent4/dependencies.lock.json)
carry the resulting live binding; that branch link is a locator, not an immutable
measurement identity. No merge or release has been performed.

The original macOS Agent aggregate started at `3a0676f`; `f7fe530` changed only
CI setup and one documentation command. The later cache-environment repair at
`c4d1d95` passed fresh Linux qualification and affected macOS consumer checks.
An earlier Linux run failed because `rg` was missing from the runner.

The additional representation witness passes all nine native tests and compiles
to a big-endian PowerPC64 ELF. It covers logical narrow-integer array/vector and
packed values, initialized extern memory, and the actual fixed-width wire
encoder/decoder. Big-endian execution is not claimed: neither `qemu-ppc64` nor
`qemu-s390x` was found on the host PATH. The argument witness also preserves
empty, spaced, Unicode, repeated, separator, changed, and long argument lists
without changing the installed executable bytes or modification time.

## Experiments and costs

- **E01, compiler migration:** all 22 native complete-cycle workloads preserve
  canonical inputs, outputs and oracle values. Five paired windows show modest
  improvements in several cases and uncertainty spanning parity in others.
  Three bootstrap-cold World benchmark builds show a substantial regression:
  median elapsed time rises from 43.02 to 81.60 seconds, CPU from 42.63 to
  81.43 seconds, peak RSS by a paired median 89,505,792 bytes, logical cache
  storage by 8,523,241 bytes, and executable size by 4,304 bytes. Sources and
  compilers were preacquired, caches were isolated, and network was excluded.
  Both build logs report about 37 seconds for the benchmark compilation itself.
  Kernel bootstrap builds likewise rise from 11.19 to 49.54 seconds, while
  actual kernel compilation stays about five seconds. With an inspected seed
  containing only Maker/compiler-runtime support and generated builtins, three
  project-cold pairs instead improve from 9.27 to 7.78 seconds. The seed omits
  all project/configuration outputs and parsed-source caches.

  Production-WASM measurements cover the same 22 workloads in five paired
  windows. All four producer/runtime combinations, plus the C0 runtime, agree
  at every portable outcome/state boundary. U1/U0 workspace peaks and reserved
  WASM pages agree exactly. Several invocation costs regress about 7–20%:
  scheduler medians rise from 0.966 to 1.126 ms; mixed-64 from 11.676 to
  12.824 ms. The kernel shrinks from 477,875 to 451,779 bytes. Process RSS has
  mixed changes, all retained individually. Separately, C0→U0 retained-loop
  invocation costs rise about 6.8–9.4%; these are source-reconciliation costs.
  The user explicitly accepted the bounded compatibility costs under D05/M09,
  conditional on no further final-integration regression or capacity failure.
  The cumulative and direct integration comparisons are recorded below.
- **E02, configuration caching: retained with an environment repair.** On the
  maintained Agent mobility-authoring check, five paired warm windows measure
  about 23% less elapsed time and 19% less CPU than forcing reconfiguration
  with the same compiler and graph. Authentication executes on all 120 calls.
  Peak-RSS differences are mixed, with no clear regression. A changed-PATH
  probe exposed a real false hit: removing `NODE_TEST_CONTEXT` while configuring
  a Run step serialized the entire old environment. Boundary, World, and Agent
  now remove that variable at process launch. The regression checks successive
  tool selections on a warm graph and rejects 24 source/inventory/permission/
  lock mutations across all four Agent exports. Imported-build and source edits,
  optimization, target, prefix, package root, and authenticated source overrides
  are also exercised; 23 cross-target outputs match their native bytes. These
  measurements do not estimate every cold build or standalone-helper cost.
  The narrow helper cache opt-out for the separate sibling-build-file defect
  remains. The recorded macOS/Linux qualification passes.
- **E03, emitter reuse: selected.** The candidate compiles one economy emitter
  instead of four and retains a fresh process for each configuration. Both
  variants pass 227 authoring tests. All four BPI3 outputs are byte-identical;
  nine interleaved valid/invalid invocations preserve output and rejection.
  The candidate executable occupies 1,080,672 bytes versus 4,324,032 bytes for
  the four predecessor executables. Three cold pairs show a paired median
  complete-build CPU ratio of 0.599, elapsed-time ratio of 0.981, and logical
  cache-byte ratio of 0.833. Five process windows show no confirmed material
  emission-latency regression. Counts 0 and 1 have a 16 KiB paired median
  increase in reported process peak RSS; that fixture-emitter cost is accepted
  for these CPU and storage savings, without changing any memory allowance.
  The updated macOS aggregate passes 317 steps, and all 114 frozen portable
  artifacts remain byte-identical. The final-code package and platform checks pass on the recorded subjects.
- **E04, reflection demand: rejected.** Direct union dispatch passes 227
  authoring tests and preserves all 19 measured images and work counts. Some
  microsecond-scale construction cases improve, and the probe executable is
  about 19 KB smaller. Three cold pairs instead show about 1% higher complete
  authoring/probe build costs; compiler-phase time is broadly unchanged.
  The shipping traversal remains unchanged.
- **E05, Linux incremental development: retain the ordinary default.** A persistent
  native debug build of the maintained economy workload handles a private
  optimizer edit, an authoring-helper body edit, an exported-type edit, and a
  build-configuration edit. All four images match fresh builds of the same
  edited tree after every edit and restoration. Compiler processes remain live
  across source edits and restart after configuration changes; recorded retained
  process RSS ranges from about 389 to 426 MB. The first pilot exposed an event
  attribution error in the harness; its failure and incidental watcher cycles
  are retained. The pilot is not used as speedup evidence. The real
  Agent lock edit then failed to wake authentication, although a fresh invocation
  rejected it and the restored lock passed. Four explicit lock-file Run inputs
  repair that defect. On Linux the watcher rejects the invalid lock within
  122 ms; restored-lock and fresh checks pass. The permanent consumer regression
  passes both tests with zero skips; Agent's updated Linux aggregate passes
  430 steps and 218 tests. The subsequent five controlled Linux windows pass
  all 240 edit pairs and five restorations. Matched-backend source/type edits
  improve checked-artifact latency about 16–18%, but configuration edits have
  a paired median ratio of 14.600 (95% window-bootstrap interval 14.358–16.455),
  adding 18.677 seconds. Summed retained process RSS reaches 463,339,520 bytes.
  Two EPYC CPU models are disclosed and absolute values are stratified; ratios
  compare arms within each host. The benchmark explicitly forces/asserts the
  same backend, so it does not establish a stock-default-backend claim.
  No default incremental switch or speculative production driver is added.
- **E06, diagnostics: retain bounded borrow locks.** Injected growth/shift
  faults are detected, and native/production-WASM N/2N/4N tests at 128, 256
  and 512 continuations preserve checkpoint/outcome bytes and complete cleanup.
  Five paired windows show no confirmed latency regression above 5% at fixed
  mutation work. Requested workspace peaks, checkpoint storage and reserved
  WASM memory match the lock-call ablation exactly. Native process RSS rises
  by a paired median 16 KiB in each case; WASM H128 rises by 917,504 bytes,
  with mixed process RSS differences elsewhere. These measured diagnostic
  costs are accepted for detecting invalid borrows without budget growth.
  Native safe Store layout grows by 72 bytes and Slots(u64) by eight bytes per
  owner, not per resident frame. The ablation retains that container layout.
- **E07, alternate WASM backend: candidate rejected at the build gate.** Both
  official macOS arm64 and Linux x64 compilers reject the actual kernel with
  `undefined data: __heap_base`. Explicitly exported LLVM heap controls
  instantiate and return 65536; neighboring self-hosted controls return 42.
  Self-hosted heap controls fail on both hosts; self-hosted plus LLD is
  explicitly unsupported. This executes the opportunity and rejects an
  unsupported candidate under specification 1.2 and M07. No alternate kernel
  exists for downstream engine/lifecycle measurements. Production retains
  LLVM/LLD; alternate engine agreement is not claimed.
- **E08, optimizer repricing: retain current policies and bounds.** Nineteen
  maintained workloads preserve exact semantic images, work reservations and
  applied/no-op decisions. Five paired windows show native semantic compilation
  ratios of 1.239–1.536 under the new diagnostic allocator. Existing observer
  phases report source checks, lowering, target checks, integrated discovery/
  checking, semantic optimization, encoding and cold admission; they do not
  isolate every internal pass clock. These results do not justify larger
  optimizer allowances or changed candidate ordering. The user accepted the compatibility cost, and the final Agent consumer,
  native/browser and packaged checks pass. No policy retuning is promoted.
- **E09, Agent resident candidate: rejected.** The actual bridge passes nine
  lifecycle cases, thirteen held-out Document cases, and byte equality at every
  replay boundary for 1, 8, 64 and 1024 turns. Five paired windows show useful
  longer-trace savings, but one-turn latency has a paired median increase of
  12.3% (+73,959 ns), with a wide 95% window-bootstrap ratio interval of
  1.015–2.354. Eight/1024-turn ratios are 0.692/0.817; 64-turn uncertainty
  crosses parity. Process peak RSS decreases for longer traces and is mixed
  for one turn. Admission priming adds short-lifecycle cost and mutable cache
  complexity, so the existing fresh bridge remains. The prototype was removed
  from its isolated source tree; only its archived patch and witnesses remain.
  No model/network latency is included or attributed to the runtime.
- **E10, build protocol: evaluated.** Retain the bounded adapter as an archived
  qualification witness and reuse it for E05. Ordinary build/CI entrypoints
  remain unchanged. It discovers 392 configured steps, requests the maintained
  capacity emitter, observes four completed steps, and verifies both generated
  artifacts. Twelve tests cover framing, version rejection, terminal status,
  configuration edits, diagnostic bounds, deadlines, process-group cancellation,
  and finite-process exit. Measurement exposed a one-second delay from losing
  cleanup timers; the repair passes the new regression. Five fresh paired
  windows then show no clear elapsed-time, CPU, or peak-RSS difference from the
  ordinary CLI with equal compiler authentication. The measured additional
  Node heap is about 293 KB. The prebuilt native decoder occupies about 0.55 MB;
  three bootstrap-cold builds take about eight seconds each. That setup cost,
  bounded diagnostic cost, and about 20 KB of adapter/reader/test source are
  accepted for the qualification witness; no
  production runtime cost or general IDE/service is introduced.

On macOS, the pinned 0.16 startup selected libc's allocator for the native safe
profile; 0.17 selects `SafeAllocator`. A safety-enabled `ArrayList(u8)` also
grows from 24 to 32 bytes, and Boundary's `Builder` from 280 to 352 bytes.
Five paired windows put native safe-profile compiler-phase ratios between
1.19 and 1.66 against U0 for these 19 structural workloads. An explicit-libc
attribution probe largely removes those timing increases and reduces many
requested-byte differences, while preserving every program image. This is
an observed diagnostic cost; no allocator-policy change is promoted. Native
layout/allocation differences and production-runtime economics remain separate.

[Raw measurements and candidate patches](performance/zig17-samples.json.gz)
are gzip-compressed JSON. They retain sample order, commands, counters,
artifact hashes, and the independent-window bootstrap method. These are
serialized desktop trials with recorded background activity, not a claim of
an uncontended benchmark machine. Unrelated process-list names are excluded from the
public export; all measured values are retained.

## Cumulative result and explicit cost decision

On October 4, the user selected **“Accept these bounded costs; finish qualification”**
under Z17-D05/M09, provided final integration adds no further regression or
capacity failure. Decision `Z17-D05-M09-2026-10-04` is retained in the machine
record with its exact scope. It grants no merge, release or budget-inflation authority.

Five fresh matched windows compare U0, the measured 0.17 reference, and final
code. Every process uses three warmups and nine samples; whole windows are the
statistical units. All canonical images, outcomes, work reservations and applied/
no-op decisions agree. No additional material primary or whole-stage regression
is confirmed against the 0.17 reference. Requested working peaks and reserved
WASM memory agree exactly; process-RSS differences remain itemized, not treated
as budget growth. These are bounded measurements, not a universal zero-regression theorem.

Against U0, the final production-WASM results retain the already disclosed cost:
scheduler about 16.7% longer, mixed-64 about 9.7%, and install-16 about 20.9%.
Native structural compiler phases range about 15–71% longer in these windows;
the direct 0.17-reference comparison does not identify an added integration cost.
Fresh Agent conversations at 8/64/1024 turns have median ratios 1.012/1.026/1.024;
the one-turn estimate is 1.109 with an interval spanning parity. Setup, compiler
phases, whole conversations, process CPU/RSS and workspace are separate fields
in all **172** per-comparison workload rows.

Three cumulative economy-build pairs retain a useful development tradeoff:

| Metric | U0 | Final code | Paired median change |
|---|---:|---:|---:|
| Bootstrap-cold elapsed | 59.70 s | 94.17 s | +34.47 s |
| Bootstrap-cold CPU | 188.40 s | 117.60 s | −70.75 s (about 37% less) |
| Reported bootstrap peak RSS | 1,899,593,728 B | 2,024,243,200 B | +130,760,704 B |
| Warm no-change command elapsed | 4.87 s | 0.12 s | −4.75 s |
| Warm no-change command CPU | 5.19 s | 0.16 s | −5.02 s |
| Project cache logical bytes | 112,149,137 B | 56,334,410 B | −55,814,727 B |
| Global cache logical bytes | 43,518,332 B | 58,006,529 B | +14,488,197 B |

The warm comparison is **command latency**: U0 reruns the 227 authoring tests;
0.17 reuses their eligible successful result. It is not a claim that those tests
execute forty times faster. Cold runs execute the suite in both arms. Mandatory
external dependency authentication has separate repeated-call witnesses (E02).
RSS is the tool-reported maximum, not a sum of simultaneous build-child memory.
The first-use elapsed cost is within the accepted bootstrap scope; the higher
compiler-process RSS is reported separately from unchanged application budgets.

Both native compilers use LLVM and the same host-native safe intent, but their
resolved native descriptions differ: 0.16 selects `apple_m2` with 74 feature
names; 0.17 selects `apple_a15` with 77. The changed interleave and zero-cycle
move/zeroing tuning flags are retained. Native results therefore include the
compiler's changed native selection; they are not an isolated allocator-only
claim. The production WASM profile remains LLVM/LLD, `lime1`, and the same seven
features, so this native mapping does not explain the WASM regression.

## Acceptance and source-free delivery

The machine record maps all T01–T70 cases to executed witnesses and immutable
records. T23 has no maintained multi-element repetition rewrite: the census
found 48 single-element repeats. T47's alternate backend fails the build gate
on both required hosts, so no alternate artifact is promoted or assigned engine
qualification credit. Independent closure reviews still challenge these dispositions.

Additional final-code witnesses establish:

- 235 old/new native/WASM boundaries across 16 workloads, with the actual
  checkpoint producer rotating among all four peers; wrong images, stale
  replies and malformed envelopes reject, and rejected resident replies preserve state.
- Four unchanged BMO1 objects, eight old/new producer/linker composition cells,
  and 71 malformed inputs rejected by both linkers. Copied linkers run with
  repository reads and process forks denied and no tools on PATH.
- Fifteen isolated mutations of the actual delivered manifest reject. A real
  producer interrupted after staging starts publishes no ready bundle, archive
  or delivery descriptor and leaves no process group.
- The independently acquired Linux bundle passes its installed CLI and fresh-
  process smoke with all repository reads and network access denied and only
  Node on PATH. It has no compiler or sibling-source fallback.

The implementation remains 0.17-only. Frozen C0/U0 sources, compiler distributions,
archives and delivered runtimes are retained as comparison and rollback inputs.
The requested serial reviews and exact provider readbacks determine PR readiness;
this evidence record itself performs neither a merge nor a release.
