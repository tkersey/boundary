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

## Independent basis candidates

The pass now emits both the observation-seeded echelon basis and a canonical
reduced-row-echelon basis when they differ. Each distinct candidate is checked
against the original records independently. Statistics retain actual pre-P01
encoded bytes and separate emitted worker/construction instruction counts.
Selection prefers fewer worker instructions, then construction instructions,
then bytes; it is a deterministic cost heuristic, not a runtime-speed theorem.
The shared pipeline's existing final image and admission-cost guards still apply.
The reservation accounts for both candidate constructions and checks; exhaustion
retains the exact P01 baseline.

The rotating witness has genuinely distinct bases; both pass independent
acceptance and native World expected-output checks. The observation-favoring
candidate emits fewer worker instructions and is selected. The focused harness
passes 44/44, the native suite 10/10, and the ReleaseSafe data aggregate completes
with terminal exit zero: **3/3 steps and 281/281 tests**. Prior timing observations
retain their original candidate labels; final economic qualification is outstanding.

## Source-free placement and platform qualification

The additional placement witness independently encodes inspection and loop objects,
binds the imported worker only at closed link, then destroys source storage and
corrupts both object buffers. Structural linking, semantic linking and checked
affine output preserve the two-word inspection request and resumed XOR result
for three input vectors. The checked linked capture changes from two words to
one. All **11/11 native tests** pass. This strengthens the existing bounded
placement case; it does not establish general multi-worker synthesis.

The preceding integrated ReleaseSafe check completed **319/319 steps and
565/565 tests**, including output ownership after decoded input release. Its
input preceded the new placement test; the native result covers that addition.
The platform corpus completed 78 expected-output/Wasmtime comparisons,
34 malformed-input rejections, 17 same-image restores and 13 wrong-image
rejections against the unchanged authenticated World kernel. Exact input identities
and scope are retained in `performance/m25-platform-qualification.json`.

Delivery now continues on one active branch and draft PR per repository. Earlier
stacked branches are historical checkpoints, not additional milestone work queues.
Full optimization implementation and technical qualification precede code reviews.

## Direct private parameters and bounded accumulator storage

The representation decision now distinguishes an existing capture interface from
an entirely private direct-parameter interface. Requiring a constructor was an
incidental restriction: the admitted direct call already supplies the same ordered
state operands. `affine_target.zig` describes the proposed interface only. Original
admission, complete private-use checks, the independent emitted-record validator,
and final P01 still decide acceptance. Entry points, constructor-backed functions,
handler entries and resource callbacks cannot use the direct-parameter route.
No synthetic constructor, adapter function or wire-format change is introduced.

The direct target keeps a trailing word parameter dynamic when every recursive
call forwards it unchanged and no local operation/edge overwrites it. The checker
still proves the exact ordered input relation at every incoming and recursive
call; this selection is not a certificate. The existing basis portfolio and
source-free final-link schedule consume this target. State and dynamic-input
bounds remain separate, including the 128-state-word case with a dynamic word.

Initial direct candidates validated but failed the unchanged profitability or
admission-growth guards. A local cost probe identified excessive fresh scratch
slots in XOR chains. Emission now reuses one fresh accumulator **within each
expression**. Distinct basis expressions and parallel edge outputs retain separate
slots. The independent checker evaluates actual stable-slot writes in order and
still checks each emitted equation. The default pipeline selects the 8-word parity
case (174 -> 169 image bytes) and the 32-word case (294 -> 265); two- and three-word
cases remain legal no-ops. These are static image measurements, not speed claims.
The regression tests require both actual selected direct calls and exact no-op
retention, alongside well-typed wrong-argument rejection and allocation/work-limit
rollback. Native execution covers original, checked, shared-compiler and closed-link
images with no constructors, both branch choices and three dynamic input values.

The first completed checks passed 286/286 data tests and 12/12 native tests.
The final integrated ReleaseSafe check, including the additional 128-word
boundary and one-scratch assertions, completed **319/319 steps and 570/570 tests**. Existing 8b90033 consumer timing
and its user-accepted costs are historical inputs, not qualification of this change.
General coupled multi-worker synthesis and the remaining L01–L20/runtime economic
obligations remain open; this extends the actual production transformation domain.

The expanded unchanged-kernel platform run completed **21 cases, 94 explicit
expected-output/Wasmtime agreements, 42 malformed-input rejections, 21 same-image
restores and 21 wrong-image rejections**. It includes direct-parameter parity at
8, 32, 64 and 128 words and requires profitable 8/32-word opportunities to be
selected. `performance/m25-direct-platform-qualification.json` binds this evidence
to source 15c5356 and the unchanged authenticated kernel. Real-consumer rebinding
and economics remain separate.

## L01–L20 evidence map

This map names the implemented fragment and its evidence. It does not assert
completion of the full optimization programme or turn a finite model into a
production certificate. General mutually recursive worker co-synthesis is still
outside the implemented recognizer; the concrete placement case required by
§13.9 has real admitted-record, conversion, back-edge and independent-object
witnesses. Unchanged locations retain their identity representation. No claim of
global layout optimality is made.

| Requirement | Concrete evidence and scope |
| --- | --- |
| L01 | `affine_capture_tests`: 24 generated, admitted non-permutation matrices with dynamic inputs/offsets; emission and independent acceptance. |
| L02 | `test/v2/affine_capture`: three-word recurrent capture becomes two; independent expected values at 0, 1, 2, 3, 8 and 31 updates. `original capture admission precedes every affine target decision` preserves rejection even for invalid targets/zero budgets. |
| L03 | `a future reset prevents a one-coordinate parity rewrite`; Annex C independently supplies the shortest future distinguishing suffix. |
| L04 | Native recurrent input/offset witness, missing caller-bias mutation, wrong recursive argument mutation, and `independent acceptance rejects an admissible wrong affine offset`. |
| L05 | Two dynamically selected recursive modes and a separately added third reset mode; the expanded action set forces full state and rejects the stale two-mode candidate. |
| L06 | `affine_parallel_tests`, stable-slot extraction test, native cyclic-edge execution, and one-expression accumulator reuse with independent checking. |
| L07 | `full product inspection of the rotating state preserves all three words`: admitted full tuple observation, rank three, exact P01 no-op. |
| L08 | Full two-word inspection followed by a one-coordinate private loop; native request/resume; independently encoded inspection/loop objects linked without source storage. |
| L09 | Calling a full observer from the parity worker forces the full state; the indexed closure-kernel test separately checks backward propagation over a return edge. |
| L10 | `additional opaque observation expands the actual record state space`: unchanged transitions and containment of every previous basis row in the expanded closure. |
| L11 | Distinct observation/canonical bases independently validate and execute. `affine_state.cost` measures actual construction instructions, all worker update/output/control instructions, and encoded bytes; selection is an explicit deterministic heuristic, not a speed/minimality theorem. |
| L12 | The same-rank wrong basis `{1,2}` is rejected against the actual emitted records; rank alone grants no equivalence. |
| L13 | Rank-zero emission and full-rank no-op tests, plus default-pipeline retention of small unprofitable direct cases. |
| L14 | Exact scalar/reusable/no-owned-or-borrowed-region eligibility; nonlinear OR is a retained boundary; valid opaque computation consumer declines; constructor-backed/public/handler/resource interfaces cannot enter the direct-parameter route. |
| L15 | Independently encoded caller/worker BMO1 objects expose the recurrence only at closed link; ordinary linker/interface admission still precedes the shared semantic stage. Object buffers are destroyed before execution. |
| L16 | Checked 2/3/8/32/64/128-word scaling; direct-parameter 128-word boundary; native/WASM/Wasmtime outputs. The extended cost probe measures initialization, Prepared storage, invocation peak and checkpoints separately. Native/WASM storage and paired latency are measured below; the one native admission increase has explicit user acceptance. |
| L17 | Independently admitted wrong capture order, recursive arguments, parallel transfer, offset, and successor worker are rejected by the record checker. |
| L18 | Annex C prefix reconstruction; 21 actual-image same-image restores and wrong-image rejections through the unchanged kernel. No semantic compiler certificate is used to change World stepping. |
| L19 | Allocation-failure injection for extraction, emission, checked capture/direct transformations and product unpacking; exact deterministic P01 rollback; changed-mode stale candidate rejection and decoded-input lifetime checks. |
| L20 | `performance/m25-annex-c.json` retains the executed finite-model counts and independent-oracle results separately from production tests. |

The final economics probe found a native admission-peak increase for the
128-word direct fixture despite lower Prepared/invocation storage. The user explicitly accepted that bounded increase on 2026-09-28. Full consumer
integration and the paired latency run have now completed; their exact outcomes
are recorded below and in Agent’s conformance evidence.

## Final direct-worker economic observations

The same-contract predecessor probe verifies the exact image identities used by
the timing comparison. For 8/32/128 words, native invocation peaks change
15,476 -> 15,254 / 35,372 -> 33,422 / 108,754 -> 102,992 bytes. Prepared storage
also decreases, and each maximum checkpoint is 11 bytes smaller. The 128-word
admission peak increases 56,430 -> 58,496 bytes; the user explicitly accepted this bounded tradeoff on 2026-09-28. Compiler allocation costs increase and are reported separately.

All 18 paired native/WASM admission, fresh-invocation and quantum-one complete
checkpoint/restore-cycle comparisons finished with no confirmed slowdown above
5%. Fresh-invocation median ratios are 0.851–0.911 native and 0.850–0.873 WASM.
These are bounded fixture observations on an ordinary host, not isolated
checkpoint-phase measurements or a general speedup theorem. Raw windows,
input/executable identities and the sampling protocol are retained in
`performance/m25-direct-timing.json`; memory/control details are in
`performance/m25-direct-memory.json`.

The additional record-boundary suite passed **57/57 tests**, including full tuple
inspection, observer monotonicity, reset, original admission, opaque consumption
and independently admissible offset/successor mutations. Production source is
unchanged from 15c5356; these additions strengthen its qualification.

Production WASM storage measurements used three fresh kernels per arm/case.
For 8/32/128 words, admission, Prepared retention and maximum quantum-one
invocation payload all decrease. At 128 words, WASM admission is
74,254 -> 52,620 bytes, retained payload 60,972 -> 46,290, and cycle peak
111,729 -> 95,200. Linear-memory capacity is unchanged (1,179,648 bytes).
These guest-payload/capacity counts exclude host buffers and RSS and are not
substituted for the separately recorded native counts.

## M2.5 bounded checkpoint disposition

The production source/package input is **15c53569bae3e12131088a0141487b8385173184**
with unchanged authenticated World source f8a1597 and kernel 7d31effb. The
latest additional record-witness suite passed **58/58 tests**. Boundary’s
production-source integrated result remains 319/319 steps and 570/570 tests;
later changes are qualification probes, tests and evidence. Agent’s final
authoring/integration/browser run passed 411/411 steps and 202/202 Zig tests;
its separate economy target passed 208/208 steps and 4/4 tests. Node groups
and both real browser results are retained in Agent’s conformance report.

The native 128-word admission increase is accepted by the explicit user reply;
WASM storage improves and the 18 paired latency comparisons confirm no slowdown
above 5%. Actual residual storage and compiler allocation costs remain visible.
The required bounded M2.5 fragment and §13.9 inspection-to-loop placement case
are qualified. §13.9 does not require identifying every maximal slice or globally
minimizing all simultaneous layouts. General mutually recursive co-synthesis is
an explicit capability limitation, rather than a new prerequisite inferred from
a family name. No broader synthesis/optimality claim is made.

Continue M3’s P06–P10/P21 obligations on the same branch/PR, then the complete
remaining programme. P01–P31, T01–T42, G01–G45 and L01–L20 remain the destination.
Full serial code reviews remain deferred until implementation and required
technical qualification are complete; no merge or release is authorized.
