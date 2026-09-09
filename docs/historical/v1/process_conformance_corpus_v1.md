# Boundary Process ABI v1 conformance corpus

Boundary's v1.7.0 evidence backfill defines an immutable Process ABI v1
conformance oracle for external hosts. Once the asset pair is attached, a host
given canonical BPI1 plus InitialArgs or `ABL_PST1` Process State, and an
optional `ABL_ERS1` EffectResult, can invoke the fixed Boundary Process kernel
and compare its canonical `ABL_PKO1` bytes with the Boundary-owned expected
bytes.

This corpus is release evidence. It is not required for ordinary Boundary use
and does not add another runtime, host, test framework, linker, wire format, or
semantic layer.

## Producer and assets

The semantic producer tuple is fixed:

```text
repository:                 tkersey/boundary
release tag:                v1.7.0
release URL:                https://github.com/tkersey/boundary/releases/tag/v1.7.0
commit:                     4fd4cd959ea283a6b5af12a228f0d80a102683e3
Boundary version:           1.7.0
Process Kernel ABI:         1
kernel byte length:         647473
kernel SHA-256:             178f9c2fb79402a85ab5a7905586879347ad5c99f988127eec001c9ecfd813f0
kernel imports:             0
```

The release backfill attaches exactly two corpus assets to Boundary v1.7.0:

```text
boundary-process-v1-conformance-corpus.json
boundary-process-v1-conformance-corpus.bin
```

The JSON is the closed manifest and partition map. The BIN is a headerless
concatenation of all referenced artifacts. There is no archive wrapper or
checksum sidecar. The manifest binds the complete BIN and every artifact slice;
GitHub release metadata binds both assets.

## Ownership and parity law

Boundary owns the expected outcomes because it owns both implementations whose
agreement establishes them:

```text
process_advance_v1 native outcome
    == exact released boundary-process-kernel-v1.wasm outcome
    == published expected ABL_PKO1 artifact
```

The native emitter calls the Process reference implementation and canonical
outcome encoders; it does not reimplement reduction. Corpus construction
compiles the immutable WebAssembly module once, creates a fresh instance for
each vector, invokes one Process operation, and rejects before asset construction
on the first byte difference.

World #47 is a consumer of this evidence. It validates the manifest and payload,
runs the fixed Boundary kernel as a host, and compares the result with the
Boundary-owned expected bytes:

```text
World-hosted fixed Boundary kernel outcome
    == published expected ABL_PKO1 artifact
```

World does not invent, normalize, or replace expected Process outcomes.

## Vectors and scenarios

The manifest contains exactly these 20 vectors in this order:

| Index | Vector ID | Input | EffectResult | Expected kind | Scenarios |
| ---: | --- | --- | --- | --- | --- |
| 0 | `typed-effect-initial` | `initialArgs` | none | `Requested` | `typed-residual-effect`, `non-agent` |
| 1 | `pending-request-reconstruction` | `state` | none | `Requested` | `pending-request-reconstruction` |
| 2 | `typed-resume` | `state` | present | `Completed` | `typed-resume`, `completion` |
| 3 | `initial-progress` | `initialArgs` | none | `Progressed` | `initial-progress` |
| 4 | `explicit-yield` | `initialArgs` | none | `ExplicitlyYielded` | `explicit-yield` |
| 5 | `authored-failure-v1` | `initialArgs` | none | `AuthoredFailure` | `authored-failure-v1` |
| 6 | `authored-failure-v2-bad-math-progress` | `initialArgs` | none | `Progressed` | `authored-failure-v2` |
| 7 | `authored-failure-v2-bad-math` | `state` | none | `AuthoredFailure` | `authored-failure-v2` |
| 8 | `authored-failure-v2-bad-position-progress` | `initialArgs` | none | `Progressed` | `authored-failure-v2` |
| 9 | `authored-failure-v2-bad-position` | `state` | none | `AuthoredFailure` | `authored-failure-v2` |
| 10 | `authored-failure-v2-success` | `initialArgs` | none | `Completed` | `authored-failure-v2`, `completion` |
| 11 | `effect-morphism` | `initialArgs` | none | `Requested` | `effect-morphism`, `typed-residual-effect` |
| 12 | `recursion-call` | `initialArgs` | none | `Progressed` | `recursive-call-return`, `initial-progress` |
| 13 | `recursion-branch` | `state` | none | `Progressed` | `recursive-call-return`, `ordinary-progress` |
| 14 | `recursion-recur` | `state` | none | `Progressed` | `recursive-call-return`, `ordinary-progress` |
| 15 | `recursion-base-branch` | `state` | none | `Progressed` | `recursive-call-return`, `ordinary-progress` |
| 16 | `recursion-return-inner` | `state` | none | `Progressed` | `recursive-call-return`, `ordinary-progress` |
| 17 | `recursion-return-root` | `state` | none | `Progressed` | `recursive-call-return`, `ordinary-progress` |
| 18 | `recursion-complete` | `state` | none | `Completed` | `recursive-call-return`, `completion` |
| 19 | `needs-capacity` | `initialArgs` | none | `NeedsCapacity` | `needs-capacity` |

Their nonempty scenario arrays cover exactly these 13 admitted scenario names:

```text
initial-progress
ordinary-progress
typed-residual-effect
effect-morphism
recursive-call-return
explicit-yield
completion
authored-failure-v1
authored-failure-v2
pending-request-reconstruction
typed-resume
needs-capacity
non-agent
```

The sequence proves an initial typed residual request, exact pending-request
reconstruction, typed resume, one-step progress, explicit yield, evaluator
semantics v1 and v2 authored failures, effect reification, recursive call and
return through terminal completion, and default-kernel operational capacity.
The typed effect fixture is deliberately a generic non-Agent program.

## Payload partition

Every vector contributes distinct image, instance, and expected-outcome
artifacts. Only `typed-resume` also contributes an EffectResult artifact:

```text
20 image artifacts
20 instance artifacts
1 EffectResult artifact
20 expected-outcome artifacts
61 artifacts total
```

Vectors appear in the order above. Within each vector the BIN appends image,
instance, optional EffectResult, then expected outcome. Artifacts are not
deduplicated even when their bytes repeat. Each manifest record binds its ID,
contiguous offset, byte length, and lowercase SHA-256. The 61 records cover the
BIN from offset zero to its exact end with no gap, overlap, unreferenced slice,
or unreferenced artifact.

For every vector, `nativeOutcomeSha256`, `kernelOutcomeSha256`, and the digest
of the referenced expected-outcome artifact are equal. The manifest also binds
the complete payload digest and length.

## Default-kernel `NeedsCapacity`

The `needs-capacity` vector targets the released default kernel, not a
constrained test kernel. Its valid small non-Agent BPI1 image and deterministic
zero-filled InitialArgs artifact make the encoded `ABL_PKI1` input exactly one
byte larger than the default 32 MiB input arena:

```text
required ABL_PKI1 bytes:       33554433
minimum_input_bytes:           33554433
minimum_output_bytes:          64
minimum_scratch_bytes:         0
minimum_memory_pages:          2457
```

The encoded input has a 40-byte header, so its instance length is
`33554433 - 40 - image byte length`. The builder passes the exact image and
instance lengths to `boundary_process_kernel_prepare_input`. Preparation
returns zero and publishes the canonical 64-byte `NeedsCapacity` outcome before
any image or instance payload byte is copied into guest memory. The native
reference independently derives the same four requirement fields from the
released kernel's live-page, occupied-memory, and input-capacity probe values.

This vector proves transactional default-host preflight behavior. It does not
claim that an oversized instance is semantically valid after capacity is added,
and it does not repurpose the constrained-output-capacity fixture.

## Build and validate

With a preverified local copy of the exact released kernel, run network-free:

```text
zig build check-boundary-process-v1-conformance-corpus -Dprocess-kernel-wasm=/absolute/path/boundary-process-kernel-v1.wasm --summary all
zig build emit-boundary-process-v1-conformance-corpus -Dprocess-kernel-wasm=/absolute/path/boundary-process-kernel-v1.wasm --summary all
zig build emit-boundary-process-v1-conformance-corpus -Dprocess-kernel-wasm=/absolute/path/boundary-process-kernel-v1.wasm -Dworld-process-host=/absolute/path/world-process-host-v1 --summary all
```

The check rebuilds the local Process kernel, requires byte identity with the
released kernel, emits the native vectors, proves 20/20 native/kernel parity,
validates the closed manifest and complete partition, runs focused negative
gates, and performs two independent byte-identical rebuilds.

The emit step installs only:

```text
zig-out/boundary-process-v1-conformance/
  boundary-process-v1-conformance-corpus.json
  boundary-process-v1-conformance-corpus.bin
  boundary-process-v1-conformance-generation-receipt.json
```

The generation receipt is local evidence and is not a release asset or a BIN
artifact. When `-Dprocess-kernel-wasm` is omitted, the builder acquires the
exact `v1.7.0` release asset and verifies its tag target, release metadata,
filename, byte length, digest, import set, ABI version, and required exports.
An override changes only acquisition: it must pass the same byte and module
identity checks, and its local path never enters manifest bytes.

The third command is the release-staging form. It passes the generated pair to
the pinned World #47 manifest and payload validators and finalizes
`worldContractValidated: true` only after they accept the exact bytes. This does
not replace Boundary's stricter exact-inventory validation or the
native/fixed-kernel execution proof.

## Release backfill

The corpus is added to the existing Boundary v1.7.0 release because it supplies
evidence for unchanged v1.7.0 semantics. The tag remains at
`4fd4cd959ea283a6b5af12a228f0d80a102683e3`; it is not moved or recreated, no
v1.7.1 is minted, and no existing asset is replaced.

Before upload, regenerate from the clean merged tooling commit, require two
independent identical builds, validate with Boundary and World, peel the release
tag again, and inspect both required asset names. If a name already exists,
download it and compare its metadata, full bytes, and conformance:

- retain it when it is byte-identical;
- upload only a missing peer after any existing peer is proved identical;
- stop on any difference, upload refusal, tag drift, or unstable digest evidence;
- never delete and silently replace a public corpus asset.

After upload, read the release API back, anonymously redownload both assets,
revalidate the public pair, and require World #47 public acquisition to lock the
same `v1.7.0` producer tuple and 20-vector manifest. Once World locks the assets,
they are immutable. A discovered defect requires a new successor Process tuple,
not replacement of this evidence.

## Non-claims

The corpus does not change BPI1, Process ABI v1, `ABL_PST1`, `ABL_ERQ1`,
`ABL_ERS1`, `ABL_PKO1`, the Process kernel ABI or bytes, native Process
semantics, Machine ABI v2, or any public Boundary API. It does not provide World
host code, an Agent transcript, capability adapters, persistent Process storage,
scheduling, linking, multi-shot resumptions, or application-specific WebAssembly.

Boundary publication proves generic Process semantic truth only. The separate
Agent transcript remains a high-complexity downstream witness, and World must
prove that it hosts both. Publishing this corpus alone does not complete World
conformance.
