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
| 1 | [Boundary #164](https://github.com/tkersey/boundary/pull/164) | `f98914c17924926dfed96d719026fd2238097a65` | Linux: 317 steps and 857 tests; independent public-package authoring passed; affected macOS checks passed after the predecessor's 317-step aggregate |
| 2 | [World #62](https://github.com/tkersey/world/pull/62) | `50cc310d2027a1392ad1c864506300c3ab55f442` | macOS aggregate: 48 steps, with native/storage suites; Linux delivered runtime independently acquired and smoked |
| 3 | [Agent #42](https://github.com/tkersey/agent/pull/42) | `c4d1d956d3f9bfb95435f11918dfbd942176b8a3` | Linux: 430 steps and 218 tests; affected macOS consumer checks passed after the predecessor's 528-step aggregate |

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

- **E01, compiler migration:** a preliminary phase probe covers 19 maintained
  workloads, including demanded failure, lazy demand, independent cells,
  retained captures, cleanup, and borrowing. Program bytes and optimizer work
  counts agree. Native requested allocation peaks change; timings from the
  concurrent correctness probe are not performance evidence.
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
- **E05, Linux incremental development: correctness pilot passed.** A persistent
  native debug build of the maintained economy workload handles a private
  optimizer edit, an authoring-helper body edit, an exported-type edit, and a
  build-configuration edit. All four images match fresh builds of the same
  edited tree after every edit and restoration. Compiler processes remain live
  across source edits and restart after configuration changes; recorded retained
  process RSS ranges from about 389 to 426 MB. The first pilot exposed an event
  attribution error in the harness; its failure and incidental watcher cycles
  are retained. This is correctness evidence, not a speedup result. The real
  Agent lock edit then failed to wake authentication, although a fresh invocation
  rejected it and the restored lock passed. Declaring the lock as an explicit
  Run input is being qualified; controlled repeated sampling also remains open.
- **E06, diagnostics:** real grow/shift fault injection and valid failure,
  retirement, and owner-move paths pass in the existing World diagnostic lane.
  An isolated removal of lock calls passes native/Node/Wasmtime transfer and
  capacity checks. Both production kernels occupy 451,779 bytes, but differ
  in code/data bytes; equal size is not proof of equal runtime cost. Native
  allocator costs are being measured separately.
- **E07, alternate WASM backend: blocked.** The official macOS arm64 0.17
  distribution's self-hosted WASM backend
  and linker reject the kernel's `extern var __heap_base` with
  `undefined data: __heap_base`. A three-line reproducer fails the same way,
  while LLVM/LLD and a neighboring self-hosted constant-return control pass.
  Pairing the self-hosted backend with LLD is explicitly unsupported by the
  compiler. Production retains LLVM/LLD. No alternate engine agreement,
  lifecycle cost, or promotion is claimed.
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
an uncontended benchmark machine. Process-list names are excluded from the
public export; all measured values are retained.

## Remaining work

Complete and decide E01–E10; map every T01–T70 case to executed evidence or an
approved exclusion; qualify all affected held-out and packaged consumers;
review measured regressions; bind the final delivery tuple; and complete the
requested serial reviews. E07's compiler limitation remains a blocker to
full-spec qualification unless the specification is explicitly revised.
