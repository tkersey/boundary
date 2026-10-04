# Zig 0.17 upgrade: qualification in progress

The maintained successor supports **exact Zig 0.17.0 only**. Frozen 0.16
checkouts, executables, and delivery artifacts are comparison and rollback
inputs, not a supported successor configuration.

The [execution specification](zig-0.17-upgrade-spec.md) remains the completion
contract. The [machine record](performance/zig17-upgrade.json) retains source,
toolchain, census, and observation identities. This report does not claim that
all experiments, acceptance cases, or final reviews have passed.

## Delivery order and executed subjects

| Order | Draft PR | Executed source snapshot | Current evidence |
|---|---|---|---|
| 1 | [Boundary #164](https://github.com/tkersey/boundary/pull/164) | `1ba2234f8781d5ab063cee7fe19b8073a89f8283` | Linux: 317 steps and 857 tests; independent public-package authoring passed; affected macOS checks passed after the predecessor's 317-step aggregate |
| 2 | [World #62](https://github.com/tkersey/world/pull/62) | `50cc310d2027a1392ad1c864506300c3ab55f442` | macOS aggregate: 48 steps, with native/storage suites; Linux delivered runtime independently acquired and smoked |
| 3 | [Agent #42](https://github.com/tkersey/agent/pull/42) | `6c6a0675d833d5f31bcfb1f2b9910e39af66fb68` | Linux: 430 steps and 218 tests, including the permanent incremental lock witness; affected macOS consumer checks passed after the predecessor's 528-step aggregate |

These are tested snapshots, not a final immutable F tuple. Subsequent source
changes require the specification's final rebinding and affected qualification.
No merge or release has been performed.

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
  Material costs await explicit Z17-D05/M09 acceptance; cumulative F remains open.
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
  remains. Final cross-platform qualification is still open.
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
  artifacts remain byte-identical. Final publication/platform gates are open.
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
  optimizer allowances or changed candidate ordering. Cost acceptance and final
  held-out qualification remain open; no policy retuning is promoted.
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

## Remaining work

Complete and decide E01–E10; map every T01–T70 case to executed evidence or an
approved exclusion; qualify all affected held-out and packaged consumers;
review measured regressions; bind the final delivery tuple; and complete the
requested serial reviews. Native bootstrap-build and diagnostic allocator
regressions require explicit cost decisions before promotion.
