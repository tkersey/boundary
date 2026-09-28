# M2.5 — affine capture-state synthesis (in progress)

Development base: Boundary `7d48c08364dd6d021c46ea64fad584937e9e930f`
(PR #162), qualified with Agent `b40b6d0` (#40) and unchanged World runtime.
I.9 now defers full code reviews until the complete optimization programme and
technical qualification are finished. Earlier review receipts remain historical;
they do not gate this successor and do not certify changed code.

## Current implementation

`src/data/affine_space.zig` provides bounded exact GF(2) row insertion,
predecessor pullback, future-observation closure and independent equation
checking, for up to 128 whole-word coordinates. Deterministic work exhaustion
returns an error without publishing a partial closure. The equation checker
reconstructs supplied coefficients; it does not invoke the discovery algorithm.

`src/data/affine_extract.zig` consumes that kernel from actual record dataflow.
It models unsigned moves, constants and XOR, tracks writes to stable slots, and
reads every parallel transfer from the predecessor view. It keeps state rows,
ordered dynamic-input rows and constant offsets distinct. Unsupported operations
produce unknown, never a fabricated zero. The consumer must seed their required
original coordinates or decline the slice. The current test independently admits
its original records before extraction and derives the rotating transition from
the records rather than a fixture name.

Executed ReleaseSafe checks: standalone algebra 3/3; extractor harness 12/12
(including imported primitive tests). These are not twelve independent optimizer
witnesses. Solver cases include three-to-two rotating observations, reset exposing
an additional coordinate, exact-equation mutation rejection, budget rollback and
permutation parity at 2, 3, 8, 32, 64 and 128 coordinates.

## Remaining delivery

This is an early draft, not the M2.5 transformation delivery. The actual use census,
private capture/worker rewrite, location-indexed predecessor worklist, complete
IR/model/emitted-IR correspondence validation, shared pipeline/final-link adoption,
L01–L20 production witnesses and runtime economics remain required. The mathematical
kernel and extraction test do not prove emitted-program equivalence or memory gain.
The next slice must rewrite the three-live-word capture/worker cycle into two words
and validate the actual ordered interfaces and affine input/offset terms.

## Capture/worker census

`affine_capture.analyze` now admits the original Program and enumerates the
private worker's scalar observations and recursive call transitions. Its first
domain keeps a fixed capture layout and declines unsupported cross-block dataflow,
owned/borrowed captures and unresolved control. Actual recursive argument order
supplies the transition rows, input terms and offsets consumed by closure.
An admitted three-word recursive capture fixture derives rank two; exposing one
original coordinate under the same rotation requires rank three. All new partial
owners release under allocation failure, and exhausted work returns no plan.
The focused ReleaseSafe harness passes 15/15 tests including imported primitives.
This establishes the census/analysis slice only. No capture or worker ABI has yet
been rewritten, and no runtime memory saving is claimed.

## First checked emitted candidate

The current local implementation emits a two-word capture descriptor, a reduced
worker input prefix and matching recursive call arguments. Initialization computes
the selected basis from original operands after their existing evaluation.
`affine_validate.zig` independently symbolically interprets original and emitted
records; it does not invoke extraction, closure or emission. It checks unchanged
metadata/control, ordered boundary observations, initialization and recursive
state/input/constant equations. Unsupported cross-block transfers are rejected.
Fresh original/candidate admission remains separate from this correspondence.

`affine_state.run` accepts only that checked candidate and then runs final P01.
Work exhaustion returns the exact P01 baseline. The 29-test focused ReleaseSafe
harness passes, including allocation-failure sweeps and well-typed capture-order,
recursive-input and basis mutations. The native World test executes original and
checked images against independent expected outputs for both branch choices and
three input vectors (12 executions). It passes. This fixture currently exercises
one recursive transition, not the complete repeated-input/multimode obligation.

These changes are not yet integrated into the shared compiler/final-link schedule.
Location-sensitive layouts, broader recurrence, full input/offset coverage,
source-free integration, platform/economic qualification and remaining L01–L20
cases remain required. Two captured words do not establish lower total memory.

The data aggregate completes with **3/3 steps and 265/265 tests**. The native World
suite now passes two tests: the original twelve branch executions plus thirty-six
original/reduced recurrent executions at 0, 1, 2, 3, 8 and 31 updates. The latter
uses dynamic XOR input, nonzero update offset and direct-input/output-offset terms.
The first run exposed an in-place array-update error in the Zig host oracle on the
original image (input 1,2,4,8; two updates). The oracle now snapshots predecessor
scalars before assignment, implementing the specified simultaneous update. Both
original and reduced programs match it; no optimizer or runtime change was needed.
These are correctness witnesses, not runtime cost measurements.

## Shared pipeline and expanded witnesses

Semantic closed compilation now schedules affine state synthesis before direct
application specialization, using the existing deterministic reservation, rollback,
image and admission-cost guards. Structural compilation remains unchanged. The
same stage is reached through final source-free component linking. The native
closed-link test destroys its original component bytes before executing output.

Production parity fixtures at 2, 3, 8, 32, 64 and 128 words all emit one-word
captures after independent validation. Their permutations are generated rather
than matched by a name. The 128-word test exposed a verifier scratch-symbol limit;
entry/opaque-result symbols now have a separate 512-symbol bounded representation,
while capture coordinates retain their 128-word limit. Exhaustion still rolls back;
this is not a claim of unbounded analysis. Multiple recursive modes, a new reset
that requires full state, stale-candidate rejection, rank-zero emission and
full-rank no-op are tested.

The closure kernel now uses an indexed predecessor worklist. Its location test
retains two coordinates at full inspection and one in the parity loop; adding a
return edge propagates full requirements back into the loop. Actual record tests
preserve full external inspection before a reduced private loop and reject state
loss when that loop can call a full observer. The native World request/resume test
checks the original pair payload and the resumed parity result for each image.

Current results: 41/41 focused tests; 5/5 native World tests; the preceding data
aggregate passed 269/269 before the final location additions. A fresh full
ReleaseSafe aggregate is running. No latency, total-memory or checkpoint reduction
is inferred from captured word counts.

General multi-worker location synthesis is still incomplete: the current record
recognizer gives each selected recursive worker one fixed layout and treats
unresolved worker calls as full argument observations. The predecessor kernel can
represent varying locations, but this does not by itself establish the full
production location-sensitive transformation. That remaining extractor/emitter
integration, full L01–L20 mapping, source-free multi-component coverage, platform
and economic qualification remain required.

## Parallel capture transfers

The pre-edge integrated slice completed ReleaseSafe with **319/319 steps and
554/554 tests**. Its result is not relabeled as qualification of later edge changes.
The newly added admitted CFG-loop witness initially returned a legal no-op,
identifying a missing M2.5 capability. It now emits a two-coordinate loop state.

Extraction reads every edge source from the predecessor view. Emission computes
reduced state assignments and preserves non-state transfers, and the independent
checker verifies the emitted edge equations separately from the extractor.
Branch/jump applicability reaches the shared semantic compiler; recursive calls
remain supported. A wrong parallel transfer still passes ordinary admission but
fails transformation acceptance. The focused harness passes **44/44 tests**, and
all **6 native World tests** pass, including the shared-pipeline CFG back-edge
witness. A fresh data aggregate is running for the edge changes.

The post-edge ReleaseSafe data aggregate now completes with terminal exit zero:
**3/3 steps and 275/275 tests**. The integrated compiler/linker, scale, mode and
parallel-edge slice is ready for the existing draft. This does not close M2.5's
remaining representation, platform, consumer and economic obligations.

## Independent-object and initial economic evidence

The native suite passes 7/7 tests after adding independently encoded caller and
worker objects. The caller's constructor refers to an imported worker; only closed
linking supplies the recursive implementation. Shared semantic linking and the
standalone checked affine pass both preserve the independently expected result
after both original object buffers are destroyed.

Annex C was extracted unchanged and run with `uv run`; its recorded finite-model
counts reproduce, including 78,804 independent transition checks and 13 rejected
corrupt/stale certificates. `performance/m25-annex-c.json` keeps that model-only
scope explicit and does not add its counts to production tests.

`performance/m25-synthetic-memory.json` records a first native requested-byte
probe, separate from timing. The standalone affine output has a new admission
and invocation-memory cost, while the full semantic pipeline reduces that fixture's
image 204 → 201 bytes, invocation peak 16,326 → 16,248 bytes and maximum checkpoint
137 → 126 bytes. Admission peak is 8,736 → 8,784 (+48 bytes). The standalone increase
is retained in the report. Same-contract C1 attribution, paired timings, platform
and real-consumer costs are not yet qualified.

## Measured private-input normalization

An uninstalled same-contract C1 control omits only the affine schedule entry.
Five alternating native timing windows exposed a synthetic regression in the
initial candidate: median admission +6.9%, fresh invocation +19.2%. The exact
source delta, raw samples and memory results remain in
`performance/m25-same-contract-costs.json`; those timing costs were not accepted.

The candidate now normalizes recurring affine input offsets once at every known
incoming direct call/application. Recursive calls forward the encoded input.
Capture state remains the derived `H x`; original argument evaluations remain in
order, and opaque/escaping constructor uses still decline. Input reassignment
through CFG edges disables this normalization for that input. The independent
checker interprets the input relation and checks every incoming/recursive argument,
without trusting discovery. A well-typed missing caller conversion is rejected.

All eight native World tests pass. Five paired windows against the same C1 give
median admission ratio 1.04957 and fresh-invocation ratio 0.95385; the slower first
candidate window is retained. Synthetic invocation peak is 15,718 → 14,920 bytes,
admission peak 8,622 → 8,672 (+50), checkpoint maximum 137 → 126, and logical
transitions 288 → 258. Image size is 188 → 195 bytes. Construction costs and the
standalone-pass arm remain visible. `performance/m25-input-normalization.json`
records these observations and limitations. They are not real-Agent, WASM or
final economic qualification. The post-normalization data aggregate is running.

The post-normalization data aggregate completes with terminal exit zero:
**3/3 steps, 275/275 tests passed**. This closes that local validation, not the
remaining M2.5 cross-platform, real-consumer, representation and economic gates.

## Private product captures

`capture_unpack.zig` independently checks scalarization of a homogeneous unsigned
product captured by a private recursive worker. It preserves original product
construction/evaluation, introduces ordered total field projections at construction
and direct-call sites, and gives only that constructor a fresh capture descriptor
and callable schema. It rejects whole-product/opaque capture uses and shared worker
interfaces. The validator checks exact field order and all unchanged records;
a wrong same-typed projection remains admissible but is rejected as a transformation.

The shared semantic schedule consumes this stage, then existing aggregate forwarding
and dead-computation removal expose the scalar affine cycle. The focused composition
passes 32/32 tests including allocation failures. The native suite passes 9/9 tests,
including the product-backed cycle through the complete pipeline. The product's
three live words become two affine words. The updated data aggregate is running;
previous timing measurements remain bound to the pre-product schedule and are not
relabeled as this candidate's final economics.

The product-stage data aggregate passed 278/278 tests. A further whole-product
observation case confirms that legitimate full-tuple observation keeps the exact
P01 baseline rather than forcing scalarization (33-test focused harness passed).
A generated production test also passes 24 admitted non-permutation affine
matrices with dynamic input and offsets through discovery, emission, independent
acceptance and final P01. This is one generated test with 24 cases, not 24 new
independent test functions. The updated aggregate including these cases is running.

The updated product/generated-case ReleaseSafe data aggregate completes with
terminal exit zero: **3/3 steps and 280/280 tests**. The product-capture slice is
qualified at this local level; final platform, consumer and economic validation
remains outstanding.
