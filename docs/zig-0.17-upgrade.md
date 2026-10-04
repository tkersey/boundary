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
| 1 | [Boundary #164](https://github.com/tkersey/boundary/pull/164) | `024fca985a881ffa25529f9b149d1cd5d72afa52` | macOS aggregate: 317 steps; Linux: 317 steps and 857 tests; independent authoring package passed |
| 2 | [World #62](https://github.com/tkersey/world/pull/62) | `50cc310d2027a1392ad1c864506300c3ab55f442` | macOS aggregate: 48 steps, with native/storage suites; Linux delivered runtime independently acquired and smoked |
| 3 | [Agent #42](https://github.com/tkersey/agent/pull/42) | `f7fe530ec170290b40dd52bdfabc0b7266990690` | Linux: 430 steps and 218 tests passed; matching implementation passed 528 macOS steps and 218 Zig tests, including consumer/browser/mobility checks |

These are tested snapshots, not a final immutable F tuple. Subsequent source
changes require the specification's final rebinding and affected qualification.
No merge or release has been performed.

The macOS Agent run started at `3a0676f`; its successor changes only the CI
dependency setup and one documentation command. The Linux rerun qualifies
`f7fe530` directly. The earlier Linux failure was a missing `rg` executable in
the source-registry check, not a passed qualification.

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
- **E10, build protocol:** the isolated finite adapter discovers the real
  configured graph, executes a named step, and verifies reported artifacts.
  Eleven prototype tests cover framing, version rejection, terminal status,
  configuration edits, diagnostic bounds, deadlines, and process-group
  cancellation. Maintenance/cost evaluation and retained-tool disposition
  are outstanding.

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
