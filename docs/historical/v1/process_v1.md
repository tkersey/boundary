# Boundary Process ABI v1

The portable running system is canonical BPI1 bytes plus either initial
arguments or canonical `ABL_PST1` Process State. The `advance` method on a
`boundary.process_v1.CapacityStorage(...)` validates those bytes and evaluates
exactly one finite BPI1 reducer segment.

The Process kernel accepts BPI1 evaluator semantics versions 1, 2, and 3.
Version 2 adds instruction-local authored-failure operands. Version 3 adds the
generic `text_byte_at` and `bytes_byte_at` operations over canonical sequence
payloads while retaining version-2 failure selection. Neither changes the BPI1
container, State format, Process ABI, or any earlier image bytes.

The Process ABI evaluates arbitrary BPI1 programs. It contains no Agent, World,
host, model, prompt, skill, tool, or capability semantics. A frontend may
produce BPI1 and a host may answer residual effects, but neither role changes
the Process state machine or fixed kernel.

Outcomes are progressed State, a self-contained `ABL_ERQ1` Effect Request,
explicitly yielded State, completed Result, authored Failure, or transactional
operational `NeedsCapacity`. Matching resumes use `ABL_ERS1`; wrong-request,
wrong-schema, malformed, or results applied to a distinct successor State do
not mutate the input State. Request identity is content-addressed: a recurrence
with byte-identical State, site, continuation, and payload intentionally has the
same identity. Programs requiring occurrence distinction must author a counter
or nonce in portable State; exactly-once effects are not claimed.

For the native reference API, instantiate `boundary.process_v1.CapacityStorage`
with the physical interpreter's arena capacities and call the storage's
`advance` method. The generated storage derives its own page floor and
occupied-byte watermark, supplies all mutable reducer buffers, and is the sole
owner of `minimum_memory_pages`; semantic reduction records each arena's byte
demand. It rejects a canonical kernel input larger than its declared input
arena before reduction, and every `NeedsCapacity` reserves the 64-byte PKO1
record required to report that outcome. Native `CapacityStorage.advance` also
admits the complete successful PKO1 length against its declared output arena,
so its typed outcome classification matches the fixed kernel without forcing a
serialize/decode round trip.
Allocate at least `minimum_output_bytes` for any generic output arena and at
least `minimum_scratch_bytes` for the scratch arena before retrying the same
input. Every mutable output, scratch, and validation arena must be
disjoint from all source bytes and from every other mutable arena; readonly
source slices may overlap. Invalid mutable aliases reject before writing. Every
State-bearing outcome is returned from the supplied storage product, including
byte-identical pending-request recovery.
An invocation-local capacity tracker records the exact bytes required at each
output producer and reducer scratch allocation before a capacity error.
`NeedsCapacity` therefore preserves the current reduction requirement rather
than reconstructing a global maximum from BPI1 schema bounds or substituting
an unrelated arena's existing capacity.
Physical page projection widens aggregate bytes internally before rounding, so
an exact near-`u64` arena demand retains existing occupied-storage pages.
Internally, one `ReductionAttempt` carries the outcome and that capacity
evidence together through final PKO1 serialization. The generated storage's
`advance` method attaches page evidence and projects only the normative outcome.

`ABL_PST1` stores the program transition digest and a minimally encoded frame
sequence. Each frame contains its continuation-constructor identity and exact
future-live environment bytes. It stores no fuel, host sequence, Machine
profile, scheduler state, pointer, or instance identity.

`boundary.process_v1.state.validateEncoding` checks canonical framing;
`boundary.process_v1.validateState` additionally admits every constructor
environment and path invariant against the supplied BPI1 before execution.
One `advance` invocation performs that full admission once and carries an
internal, non-serializable admitted top-frame projection through the reduction.
State encoders return the canonical `StateView` they already validate. Every
internal State producer must return that refinement and declare the exact
changed frame suffix through the same mutation carrier that serializes it; the
codec-owned `MutationView` carries the first changed frame into one admission
constructor, which admits every frame in that suffix and their internal stack
pairs, plus the pair crossing from the preserved prefix, before publishing
canonical bytes. Initial construction returns bound `AdmittedState` directly
to the first reduction instead of decoding and admitting its environment again.
Public State and Capsule encoders complete semantic admission before their
first caller-output write, so semantic rejection leaves output byte-identical.

The fixed `boundary-process-kernel-v1.wasm` module imports nothing and retains
no authoritative Process State between calls. The non-normative
`scripts/boundary-process-step.mjs` reference byte relay is not a persistent
runtime, capability host, or World implementation. It asks the kernel to
prepare its canonical input header from `u64` sizes obtained from open
regular-file descriptors before reading payload bytes. When preparation admits
the input,
the adapter reads exactly those bytes through the same descriptors, rejects a
changed device, inode, length, modification time, or change time, copies only
BPI1 and instance/result bytes, invokes one kernel operation, writes the
canonical outcome bytes, and exits. The kernel itself is
also admitted as one nonblocking regular-file descriptor before materialization.
The reference relay's 64 MiB kernel ceiling is its own operational limit, not
Process semantics; another conforming embedding may carry a larger compatible
fixed kernel.
If the fixed input arena cannot hold those payloads, preparation returns a
canonical transactional `NeedsCapacity` outcome before any payload copy.
Kernel-input and kernel-outcome framing uses `u64` component lengths. The
wasm32 kernel accepts those lengths as scalar preflight data, so a larger finite
State reports capacity without truncation even though that instance cannot
address the State itself. A component tuple whose aggregate plus framing exceeds
`u64` is unrepresentable and rejects instead of publishing a saturated retry
requirement.
The relay normalizes exported wasm32 pointers to unsigned offsets before
indexing linear memory. Fixed-kernel storage declares input, serialized output,
State, candidate State, value, request, both environments, and scratch as typed
capacity arenas. Page accounting folds over that actual storage product, so a
new arena cannot be omitted from the calculation or its omission witness. Each
growth delta uses the arena's aligned physical size rather than only its logical
payload length.

## Published conformance corpus

The Boundary v1.7.0 evidence backfill is defined by the Process ABI v1
host-conformance assets
`boundary-process-v1-conformance-corpus.json` and
`boundary-process-v1-conformance-corpus.bin`. Boundary owns their canonical
inputs and expected `ABL_PKO1` bytes because it owns both the native Process
reference semantics and the fixed `boundary-process-kernel-v1.wasm`. Each
expected outcome is admitted only after the native result and the exact released
kernel result are byte-identical.

The corpus is an immutable conformance oracle for external hosts such as World.
World consumes and checks the Boundary-owned bytes; it does not author expected
Process outcomes. The corpus is not required for ordinary Boundary compilation
or execution and is not a runtime, host, scheduler, linker, or semantic layer.
See [Process ABI v1 conformance corpus](process_conformance_corpus_v1.md) for the
producer tuple, vector inventory, payload partition, capacity witness, and
release-backfill rules.

Run:

```text
zig build check-boundary-process-v1 --summary all
zig build emit-boundary-process-kernel-v1
zig build check-boundary-process-v1-conformance-corpus -Dprocess-kernel-wasm=/absolute/path/boundary-process-kernel-v1.wasm --summary all
zig build emit-boundary-process-v1-conformance-corpus -Dprocess-kernel-wasm=/absolute/path/boundary-process-kernel-v1.wasm --summary all
```

Release staging adds
`-Dworld-process-host=/absolute/path/world-process-host-v1` so the local receipt
binds successful validation by the pinned World #47 source.
