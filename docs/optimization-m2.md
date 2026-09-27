# M2 — executable-record optimization (in progress)

Base: the accepted Boundary cutover `ef25b3d`. Agent's recorded cutover costs
are accepted tradeoffs; they remain in cumulative comparisons. No frontend
uniformity migration is part of this work.

## Implemented first consumer

`data.value_facts` admits the original records, binds facts to their BPI3 identity,
and records a distinct definition for each stable-slot write. It currently derives
constants, constructor origins, unsigned masks and sequence length facts. A
worklist transfers predecessor values simultaneously and joins incoming facts;
cycles lose unsupported constant precision. Constructor sets widen to explicit
unknown above four possibilities. Host, constructor, handler and resource-authority
entries remain open-world unknown roots. Private direct-call workers receive
ordered caller argument facts through the same monotone worklist, including
recursive components. Return values remain conservatively unknown. An incoming
vector’s maximum is not its actual length.

Variant facts now track up to four possible tags produced by `variant`, preserving
their stable-slot versions through moves, joins and ordered transfers. A fifth
possibility or unknown incoming value widens to explicit unknown. Known tags
restrict feasible `switch_variant` edges and make `variant_tag` constants
available to branch reduction. The independent backwards checker reconstructs
the tag from raw definitions and predecessor edges; it does not trust the forward
set and does not equate tag knowledge with payload knowledge. Returned payloads
remain unknown unless separately proved.

The source-free semantic-link witness changes **88 → 62 bytes**, eliminates the
proved branch and its dead tag/construction work, invokes final P01, and preserves
results for runtime payloads including maximum u64. External variants keep their
branch and both runtime alternatives. Conflicting joins, changed tags, forged
branch choices, payload/tag confusion and allocation failures have focused checks.
Validation: **57 focused tests, 253 data-aggregate tests and ten native link/runtime
tests passed**. All 18 retained-corpus probes finish default budgets and reproduce
the previous candidate's exact image hashes; no new real-corpus speedup is claimed.

Selected product-field facts use the existing checked aggregate recognizer and
stable operand versions. Forwarding a field into an ordinary move lets fresh P02
analysis consume its scalar fact on the next pipeline round; no second product
representation is needed. A source-free interaction witness selects either of
two same-typed Boolean fields, prunes the corresponding branch, specializes the
closed callable, and removes the dead construction. It preserves the distinct
runtime results and changes **184 → 112** / **185 → 118 bytes**. All eleven native
application/link tests pass. This establishes the selected local-field case;
general product propagation across control flow remains a precision limitation.

`data.application_specialization.run` consumes those facts. It replaces a locally
constructed computation and its single application with the existing function's
direct call, passing captures before explicit arguments in their original order.
It requires one definition/consumption, available capture versions, portable
captures and no captured/required regions. An independent raw-record checker
checks correspondence without consuming the finder's facts, followed by fresh
admission and mandatory P01. This is an external-semantics transformation;
it does not promise the same internal microsteps across different images.

`data.branch_reduction` uses feasible-edge facts and an independent backwards
constant-origin proof. It preserves evaluation of the condition and original
admission, then runs P01. The proof conservatively declines ambiguous joins and
cycles, and a depth limit is reported rather than risking native stack exhaustion.
A proven branch removes an alternative constructor path, enabling a closed
constructor application to become a direct call across blocks. That witness
shrinks from 163 to 121 bytes. An unknown external condition retains both targets.

The independent origin proof now reconstructs unsigned constants, bitwise AND
(including a proved zero mask), and unsigned equality/ordering comparisons from
raw definitions. These facts were already available to forward analysis but
previously could not authorize a branch rewrite. Boolean equality is also checked.
Operand evaluation and the primitive remain in the branch candidate; subsequent
dead-computation removal still requires its separate totality/demand proof.
The source-free masked-integer witness shrinks **86 → 58 bytes** through the shared
semantic final linker and final P01. Native World preserves results for zero, one,
the high unsigned bit and the maximum u64. A preceding division-by-zero remains a
failure after branch and dead-computation reduction. Unknown inputs, reversed
comparison operands and a forged branch choice cannot certify the wrong edge.
Focused validation: **51 application/data tests and nine native application/link
tests passed**. These are synthetic size/correctness observations; Agent remains
bound to the authenticated `8321156` input, whose integrated qualification is
still running, until the next coherent rebind.

`data.dead_computation` now consumes that specialized candidate. Backwards demand
removes unused total instructions only when their results and operands permit both
copy and drop. It excludes calls, mutable operations, faulting instructions and
resource/cleanup operations. Zero-capture constructions additionally require no
owned or borrowed regions. The independent checker compares the retained raw
subsequence and candidate liveness, with original and fresh candidate admission.
A deterministic instruction-work limit rolls back to the original before final
P01. This removes the remaining unused constructor and condition in the branch
witness, reducing 121 to 106 bytes (163 bytes before the combined transformations).
Native World preserves its output; unused division by zero still produces failure.
This is the dead-computation subset of P05, not dead-argument/store completion.

The first witness removes one `computation` instruction and one `apply`, retains
one direct call, and reduces BPI3 from 108 to 97 bytes. Unchanged native World
returns the same ordered pair for three distinct runtime capture/argument pairs.
This is synthetic capability evidence, not a real-Agent speed claim.

The known-argument witness now calls a private worker with a constant boolean;
that argument proves one worker branch infeasible and enables P03, reducing the
witness from 194 to 152 bytes. A separate
worker receiving a singleton closed callable specializes its incoming `apply`.
The backwards checker reconstructs all raw direct callers and accepts only
agreement, without reusing the forward analysis. Two incoming constructors,
unknown host arguments, constructor-visible workers and opaque captured
environments retain conservative behavior. A recursive worker that changes its
argument joins both values instead of freezing its initial caller's constant.

`data.dead_arguments` removes unused copy/drop parameters from private direct-call
workers and the corresponding ordered argument at every call. It retains argument
evaluation. The independent checker verifies the complete call set, input liveness,
usage permissions and exact ABI subsequences; original and candidate admission
precede final P01. This lets dead-computation elimination remove the construction
formerly passed to the specialized callable worker: one parameter, one argument
and one constructor disappear, reducing that witness from 131 to 119 bytes.
Host, constructor, handler and resource-authority interfaces retain their inputs.

`data.aggregate_reduction` forwards local immutable product projections from
available original operand versions, including moved product aliases. Its checker
traces raw definitions backwards, verifies the ordered field and rejects a source
overwritten after construction. Copy/drop permissions and original/fresh admission
remain required. Subsequent checked DCE removes unobserved product construction;
an externally returned aggregate remains materialized. The witness shrinks from
81 to 69 bytes. This is logical product scalar replacement; physical allocation
placement remains a separate obligation.

Data-only native tests now cover source-free BMO decoding and closed linking.
One links the product object before reduction. Another binds an independently
encoded caller's imported worker to a second object's exported worker; only after
linking does its known argument prune the branch and enable P03/P05. That witness
shrinks from 194 to 131 bytes, preserves World output, and runs final P01. The
optimizer reads linked records after the object byte buffers have been overwritten.
These tests exercise the transformation sequence explicitly; automatic semantic
compiler/final-link integration remains unfinished.

`data.expression_reuse` implements the early P04 total-expression subset. A
definition catalogue records opcode, output schema, immediate and ordered operand
slots; must-availability invalidates a definition on any source/operand write or
relevant parallel edge assignment. Intersections require availability on every
incoming path. Reuse is checked separately by backwards raw-record traversal to
the dominating successful producer. Mutable reads, faulting expressions, closures,
packages/resources and non-copy/drop values are excluded. No commutative or
copy-alias canonicalization is assumed. Cyclic proofs conservatively decline.

The diamond witness computes the same XOR before and after a control-flow region;
reuse reduces its dynamic XOR evaluations from two to one on both paths. A local
repetition also reuses its earlier value. The linked-record native witness shrinks
82 to 81 bytes and preserves outputs for both paths and multiple operands. This
does not establish a timing improvement. The pass bounds discovery and independent
correspondence work deterministically, defaults to one million work units, and
rolls back the complete candidate before final P01 when that budget is exhausted.
Original/fresh admission and P01 retain their own obligations and budgets.

`data.cell_reduction` implements the minimum private-cell case for a worker with
one returning block. A portable copy/drop payload replaces the cell's private slot;
allocation/read/store operations become value assignments and unit results at the
same ordered points. The independent checker matches the entire original record
sequence against those scalar state transitions and checks all uses, interfaces
and permissions. Original/fresh admission precedes final P01. Subsequent checked
DCE removes overwritten scalar assignments. Aliases, payload capture, suspension,
calls and intervening fault observations remain outside this local case.

The one-store witness shrinks 135 to 119 bytes. A source-free linked witness with
two stores before a read shrinks 136 to 119 bytes: one cell allocation, one read
and two cell stores disappear, and World preserves the final value for three
input pairs. Store unit results remain explicit until independently proved dead.
This establishes logical elimination, not physical stack placement or a measured
World latency/memory gain.

The cell-use inspection also exposed missing body-slot reads in P03's existing
scope-control census. Handler/region bodies and cleanup computations now count as
uses; a reusable computation applied and then used as a handler body retains its
construction. This repairs the existing specialization guard without expanding
authoring scope.

`data.capture_reduction` removes dead copy/drop capture fields from a private
constructor and rewrites its ordered worker inputs, every construction operand
list and every direct worker call together. Explicit application arguments stay
unchanged. The original capture descriptor is retained for other constructors;
the reduced constructor receives a fresh descriptor before P01 removes or shares
unused structural records. All ownership/use flags and nominal region references
remain unchanged. The checker verifies original demand and complete raw-record
field/input/argument correspondence with fresh candidate admission.

The initial privacy domain requires one constructor per worker, no host/handler/
resource entry role, and each constructed closure slot used only by local applies,
without aliases. Repeated applications are supported. Opaque uses decline the
transformation. The existing exact slot-use scanner is now shared by P03 and P07,
including its scope-body/cleanup reads. Evaluations that produced removed captures
remain, including arithmetic failures. A known-branch witness keeps its capture
before pruning and removes it afterwards; the simple reused-closure image shrinks
115 to 109 bytes.

The source-free retained-state witness captures a 4096-byte array, pauses after
construction and resumes both versions with their own image identities. Dead
capture removal changes the closure environment from one value to zero, reachable
serialized blob payload from 4096 to zero bytes, and checkpoint size from 4207 to
105 bytes. These are measured logical retention/checkpoint costs, not allocator
high-water or latency measurements. A second native witness returns both results
from repeated closure calls with distinct arguments across three input triples.

`data.capture_summary` implements the non-projection XOR family: two immutable
`u64` captures observed only through their ordered bitwise XOR become one captured
XOR. Every original operand evaluation remains before the inserted combination.
All constructors and direct worker callers receive that combination; every worker
observer becomes a move from the summary input. Original slot layouts remain a
prefix, and inserted computations use fresh caller slots. Individual field reads,
field writes, non-`u64` captures, captured regions and opaque closure uses decline.

The representation decision is a native checked record rewrite owned by Boundary.
The law is `s = x XOR y`: because the two fields are immutable and every observer
computes precisely that total 64-bit operation, replacing each observer by `s`
preserves every subsequent result/effect. New construction work is one finite
total instruction, so it introduces no divergent unmatched execution. Original
admission, an independent complete observer/caller correspondence check, fresh
admission and final P01 remain owners of their existing obligations. A correctly
typed OR substitution and an independent field observer are deciding falsifiers.
The operator is bytewise in `data.scalar`; tests exhaust byte pairs and exercise
all 64 bit positions, alongside runtime repeated-call witnesses.

The source-free native witness preserves both repeated-call outputs and resumes
each checkpoint with its own image. Actual captured scalar payload is 16 to 8
bytes and checkpoint size is 125 to 115 bytes; BPI3 size stays 135 bytes. No size
change is used as a speed proxy.

### XOR-summary cost observation

Tune reused World's `test/v2/replay_bench.zig` on paired immutable PKI3 inputs.
Apple M2 Pro, macOS 27.2, Zig 0.16.0 ReleaseSafe; seven alternating paired process
batches, three warmups and nine fresh invocations per process. Every outcome is
checked against an independently encoded digest. Fresh-invocation time includes
admission, execution and output encoding; it is not phase-separated admission or
steady-state timing. [Raw observations](performance/m2-capture-summary.json)
include exact input/source digests and construction samples.

| Reused calls | Median paired candidate/baseline time | Paired range | Peak working payload, bytes |
| --- | --- | --- | --- |
| 2 | 1.005 | 0.938–1.032 | 10,661 → 10,442 |
| 32 | 0.948 | 0.907–0.988 | 28,849 → 28,849 |

The two-call timing is inconclusive; the 32-call synthetic case improves about
5.2% by paired medians. Allocation counts remain 56 and 180, respectively. These
measurements establish neither an Agent improvement nor browser/WASM performance.
The original C0 corpus remains the cumulative qualification baseline.

Boundary construction (P01 alone versus summary plus final P01) costs 38.0 → 64.5
µs for two calls and 69.6 → 136.3 µs for 32 calls; allocation counts increase
44 → 100 and 52 → 118. This isolated construction overhead includes the new
analysis and independent validation and is retained under the corrected Boundary
construction-cost policy. It is not silently charged to World, nor does it waive
later phase-separated World or whole-consumer cost gates.

`data.capture_projection` implements P07's immutable product-field case. A private
constructor observing exactly one field captures that field, and its worker reads
the projected value directly. Constructors and direct callers project only after
the original product evaluation. A fresh private computation schema carries the
new bound; shared schemas/descriptors and public inputs are preserved. The checker
verifies the full original observation census, exact selected field, fresh caller
slots, worker slot types, constructor types and every unchanged record. Original
and candidate admission and final P01 remain mandatory. Effectful/opaque capture
contexts and potentially failing extraction are outside this domain.

The source-free witness changes reachable blob payload from 4104 to zero bytes and
checkpoint size from 4215 to 115 bytes, preserving both repeated-call results and
same-image resumption. An independent parent use of the original product remains
correct. A failing variant extraction still fails only after construction. The
small scalar-pair image grows 131 to 134 bytes under this semantic transformation;
P01's own no-growth decision is unchanged.

Tune's existing replay benchmark measured seven alternating paired batches with
three warmups/nine samples per process on the same M2 Pro/ReleaseSafe configuration.
The two-call timing is inconclusive (paired median ratio 1.000, range 0.780–1.059);
the 32-call ratio is 0.977 (range 0.970–0.987). Peak working payload is
20,380 → 20,403 bytes and 33,220 → 33,205 bytes, respectively. Allocation calls
change 61 → 60 and 216 → 185. The 23-byte increase is recorded and below the
supplied memory threshold. [Raw observations](performance/m2-capture-projection.json)
bind exact inputs/sources. These fresh-invocation timings do not discharge separate
admission, checkpoint timing, or real-consumer qualification.

Focused checks cover swapped equal-type operands, capture reassignment, stale
facts after constructor mutation, range/known-bit and length/bound distinctions,
and every allocation-failure point in the small transformation witness.
The dead-computation slice adds live-overwrite and fault-deletion mutations,
work-limit rollback, and allocation-failure coverage. Its focused suite has 36
passing tests, and the native record suite has four. The initial division fixture
was rejected because its fault table used the wrong wire order; correcting the
fixture to the admitted overflow/zero order left production admission unchanged.
The caller/argument slice expands this to 46 focused tests and six native World
tests, including a faulting computation whose now-unused argument is removed while
its evaluation still fails. A temporary parameter-removal statistics bug was
corrected: count before transferring the list storage, whose length then resets.
The product suite adds seven cases (26 tests including imported module tests),
covering wrong-field mutations, overwritten inputs, aliases, escaped outputs,
invalid original annotations and allocation failures. Native coverage now has
seven application/link tests and one product/link test. The initial cross-object
fixture violated imported declaration structure; it was repaired to use a missing
entry and only the imported ABI slots, preserving production component admission.
P04 adds twelve focused cases (30 tests including module tests): local/join reuse,
operand writes and parallel swaps, non-dominance, self-overwritten producers,
early/late budget rollback, differing fault payloads, distinct closure captures,
mutable cell reads and allocation failures. Three native tests cover linked
diamond execution, path-specific mutation and a real cell read after mutation.
The cell suite has seven focused cases (25 with module tests), including a wrong
stored-value mutation, aliases, suspension, fault observation and allocation
failures. The scope-census regression expands the specialization suite to 48 tests.
One additional native linked-cell test covers three input pairs before/after.
The dead-capture suite adds eight cases (27 with module tests), including direct
callers, shared descriptors, opaque aliases, forged correspondence, original
failure evaluation and allocation failures. Two native tests cover retained-state
measurement/resumption and repeated-call outputs.
The XOR-summary suite adds nine focused cases (27 with module tests), including
forged OR, individual observation, mutation, direct callers, opaque aliases,
preserved faulting evaluation, allocation failures and primitive-law checks.
Native/source-free checkpoint and repeated-call tests pass, and the replay
benchmark verifies all paired outcomes.
The projection suite adds seven cases (25 with module tests), including a
well-typed wrong-field mutation, multiple observers, direct callers, shared types,
delayed failure and allocation failures. Three native tests cover source-free
retention/resumption, parent observation and delayed failure timing.

## Shared closed-compilation path

`data.closed_compilation` now owns the structural/semantic contract for source
lowering and final linking. Both contracts run P01. Structural remains the
compatibility default; semantic preserves the specified external contract while
allowing different private layouts and logical work across newly compiled images.
`source.lowerObserved` selects it through `CompileOptions.contract`;
`authoring.Context.compileWithCompilation` preserves the mandatory original named
capture observer; `data.linker.linkWithCompilation` applies the same driver after
all imports, interfaces and borrow summaries have been checked. Existing structural
entry points forward to this implementation. Component emission defers both
whole-program P01 and semantic work until a closed link, even if its caller selects
semantic compilation. Ordinary codecs and World execution are unchanged.

The driver holds an admitted P01 baseline and independently owned successors.
It refreshes analyses through the existing checked passes and runs final P01 on
the selected candidate. False witnesses, allocation failures and checked arithmetic
overflow remain errors. Work/round exhaustion discards the semantic attempt and
returns the exact structural baseline; hard image limits still apply on rollback.
Original-invalid input rejects before a zero optimization budget can defer work.
Semantic error indices are not misreported as original source-variable locations.

The defaults are four rounds and 100,000,000,000 conservative scan-reservation
units. Reservations now follow each pass's actual scan domain: block pairs for
branch correspondence, applications for specialization, per-block instruction
pairs for aggregate forwarding, and relevant cell/constructor/input counts for
the corresponding rewrites. Counted analyses/proofs reserve their existing caps;
literal bytes remain linear. The former square of all unrelated metadata was
rejected by the real corpus. These are reservations, not claims of executed
comparisons. Logical records are counted directly because wire compression is
not a work bound. Value propagation additionally counts work
up to 10,000,000 units; backwards proofs count up to 1,000,000 units and retain the
256-level stack guard. GVN retains its counted bound. No unfinished facts escape.
P01 keeps its separate exact accounting and rollback rule.

Final image growth uses the supplied exact integer defaults: size zero,
balanced `max(1024, ceil(baseline/20))`, speed `max(4096, ceil(baseline/4))`.
Explicit zero growth and stronger absolute image limits work as specified.
Candidate selection also considers explicitly heuristic static operation and
capture-payload estimates; those estimates are not runtime measurements. A real
no-op retains the baseline bytes. Observer callbacks do not select output.

Tune found unnecessary full passes in this initial driver. Applicability checks
now read the admitted records/liveness: absent branches/applies/cells, no repeated
eligible opcode, no dead destination/input, or absent eligible capture shapes skip
the corresponding stage. They do not authorize a rewrite; selected stages retain
all independent validators. Five alternating paired batches, each with three
warmups and nine samples, preserved every selected image digest. Median paired
construction ratios (after/before) are 0.123 arithmetic, 0.130 reusable_body,
0.496 cells_independent and 0.131 deep. [Lossless raw observations](performance/m2-closed-compilation.json)
retain all sample values. These measure removal of avoidable construction work,
not a World speedup or elimination of the remaining compiler overhead.

Checks: 237 data tests and 218 authoring tests pass; native typed compilation
executes both contracts after all source owners are released, and the two-object
native witness now also executes the actual semantic final-link path. Tests cover
original capture violations, open deferral, zero and late limits, hard byte limits,
compressed-wire accounting, observer determinism and allocation-failure cleanup.

### Owned-consumer audit in progress

Agent source inspected at `c181ef58623cd0260a0bee7ad44dafdf099fdc20`:

| Owner | Current evidence | Required continuation |
| --- | --- | --- |
| `src/authoring.zig:89` | Registry admission runs before either Boundary compilation path; direct compilation forwards `boundary_options`. | Select the audited contract at owned product emission, preserving registry verification. |
| `src/compiled_tool.zig:171` | Final linking currently forwards only coalescing options. | Forward the full compilation policy to the shared final linker after rebinding the Boundary dependency. Keep original tool-role/interface checks. |
| `runtime/parser_cli.mjs:100` | `--max-quanta` counts drives of 100 World work units; model/check allowances are separate host counters before environmental calls. | Preserve limits and ingress handling; qualify semantic images and boundary cancellation/allowance behavior. |
| `docs/parser-synthesis.md:38` | Quanta are explicitly image work units; exhaustion parks the actual checkpoint and exact pending ingress, without retrying an external call. | Document the new-image semantic contract without weakening same-image work accounting or external-call budgets. |
| World runtime | No execution or State codec changes in this integration. | Keep exact same-image stepping/interruption and authenticated runtime bindings during consumer qualification. |

This is not a completed consumer migration. Agent's emitter policy, compiled-tool
forwarding, source/package/runtime rebinding and corresponding tests remain open.

### Real-corpus follow-up

Agent draft #40 now binds the authenticated `517cfb1` source/package and forwards
the complete policy through compiled tools. Its first 18-workload emission has ten
work-limit outcomes; that pin is not qualified for semantic adoption. These are
required-fixture failures, not optimizer successes or a reason to waive budgets.

The follow-up scopes GVN definition sets to their owning function and pre-indexes
actual predecessor edges, avoiding scans of unrelated definitions/blocks. Reuse
also requires original availability and declines capture/control boundaries that
would widen retention obligations. Candidate admission exposed those obligations
on real review/document records; it was not bypassed. Separately, DCE now preserves
every explicit control-edge source read until a checked edge rewrite removes the
assignment, even when the destination is semantically dead.

The corrected code passes 239 data tests, including new edge-demand and retention
boundary regressions. A probe of the original failing images now completes the
three review cases with optimizations and sharing-64 as a real no-op. Six larger
cases still hit work limits. Agent's recorded ten failures remain the evidence for
its unchanged pin; the newer probe does not relabel that evidence. Remaining work
is to finish budget/scan corrections, authenticate the successor pin and rerun the
whole consumer qualification.

The subsequent correction keeps all shipping limits unchanged. GVN now indexes
only repeated exact expressions (hashes select buckets, raw records decide),
partitions availability by transparent control-flow regions, schedules changed
successors with a worklist, and indexes the independent validator's targets and
raw predecessor edges. Capture boundaries still prohibit reuse. On inquiry/ReAct,
the complete GVN check performs 441,678 counted units and checks 381 replacements;
the previous validator needed over three million units in a diagnostic run.
No witness, admission or mutation check was removed.

The driver also remembers a stage's proved no-op only while actual program records
remain unchanged; record equality invalidates that fact after any transformation.
This avoids reserving and repeating the same completed no-op within one search.
All 18 existing corpus images now finish under the default limits. The three
inquiry images reduce 35,591 → 35,257, 35,973 → 35,637 and 49,604 → 41,021 bytes.
[Input-bound probe evidence](performance/m2-corpus-budget.json) records exact input
digests, outcomes and work. This is an admitted-record probe, not fresh Agent
emission or runtime qualification. Repinning and re-emission remain required.

## Candidate selection and admission-set costs

The 18-image Agent qualification exposed two new native admission-memory costs
at `8321156`: expression reuse enlarged the immutable analysis-set pool, crossing
geometric allocation capacities. Reordering DCE before reuse did not fix them;
declining literal reuse fixed only one. Neither experiment was retained.

At `95277a2`, the shared driver added a third, independently validated candidate: dead
computation removal from the ordinary baseline. The full pipeline still runs.
That initial selection considered an admission-set score alongside the
existing image, operation and capture estimates: 24 times node capacity plus
12 times interning-table capacity. It rejected score growth above
`max(1024, floor(baseline_score / 100))`, without using addresses, allocator-resize
outcomes or clock measurements. This is an economic heuristic, **not** a bound
on World memory; actual runtime qualification remains required. Public contracts,
exact image-growth limits, work limits, independent validators and P01 are intact.

The shrinking candidate consumes the existing work budget and reports its
selection explicitly. A proved no-op is reused only for unchanged records.
All candidate owners are released on failure; incomplete full search keeps the
existing exact-baseline rollback contract.

The source-bound record probe in `docs/performance/m2-candidate-selection.json`
completes all 18 retained cutover images under defaults. No image increases native
Prepared peak or retained memory versus cutover. Review-model chooses shrinking:
2,356 → 2,331 image bytes and 136 fewer peak/retained bytes; clarify-first chooses
shrinking: 9,453 → 9,428 image bytes and 182 fewer peak/retained bytes. ReAct keeps
the full candidate, reducing peak admission by 159,702 bytes and retained storage
by 129,662 bytes. C0 comparisons remain alongside local ones.

The data/authoring aggregate passes (245 + 218 tests). The final focused run
passes 69 tests, including the added shrinking-candidate allocation-failure and
budget-rollback case. Three native GVN tests pass, including a source-free
semantic-link selection that still executes one
XOR on each diamond path. This probe uses existing images; Agent source emission,
new package binding and final economic qualification are still required. Agent's
ongoing aggregate remains bound to `8321156` and is not relabeled by this result.

Production WASM admission then exposed a flaw in that initial heuristic: its
native capacity concealed a 536 → 553 node growth crossing WASM's 542 → 816
allocation threshold. The two review-mode images grew by about 13.6 KiB peak
and 6.7 KiB retained memory under the unchanged authenticated kernel.

The corrected score derives geometric capacities from **node count**, using
explicit growth starts 2, 4, 5 and 8 (Zig 0.16, 64/128-byte cache lines and
16/24-byte nodes). Each profile must satisfy the same score-growth guard. No
compiler-host capacity or allocator behavior chooses the output. These fixed
profiles remain an economic heuristic; a toolchain or node-layout change requires
fresh qualification, and no runtime-memory bound is claimed.

`docs/performance/m2-candidate-profiles.json` records the corrected 18-image
native/production-WASM probe. Both review modes select shrinking and have only
38/44-byte WASM peak/retention increases, below the supplied memory threshold;
their native costs decrease. No other workload introduces an admission-memory
increase. ReAct retains peak reductions of 159,702 bytes native and 481,834 bytes
WASM, with 129,662/360,632 fewer retained bytes respectively. All work budgets
complete. Seventy focused tests pass, including the exact hidden-capacity-cliff
counterexample. Fresh source emission/rebinding and execution/checkpoint/timing
qualification remain required.

## Frozen implementation qualification

At `5f5c11e`, `zig build check -Doptimize=ReleaseSafe -j2 --summary all` finishes
successfully: **319/319 steps and 526/526 tests** across the repository's current
authoring, data, component and source-semantics aggregate.

`docs/performance/m2-platform-witnesses.json` binds fourteen existing record cases
to source-free linking and the unchanged production World kernel. Node/WASM
completes **56 independent expected-value comparisons**; the existing locked
Wasmtime embedding agrees on all 56 canonical outcomes. Node also rejects 28
malformed initial inputs, restores fourteen same-image portable States and rejects
twelve wrong-image restores (the unknown variant/callable arms have identical
images). Cases include product-field/branch/direct-call interactions, captured
calls, private cells, dead captures, XOR summaries, field projection, and known/
unknown variants. A separate checked P04 diamond case qualifies actual reuse even
when the full pipeline prefers a cheaper DCE candidate. This is semantic/custody
evidence, not runtime timing.

Agent's final tuple is bound to this immutable input. Its browser
transfer assertions complete in Chromium 153.0.8010.12 and Firefox 155.0, with two
worker destructions, a real file read and cleanup in each. The enclosing Agent
aggregate completes with exit zero: **418/418 steps and 205/205 Zig tests** across
authoring/native/integration/economy/browser targets, plus **95/95** in its serial
Node batch. The World kernel has not been rebuilt.

The real inquiry/ReAct comparison records thirteen scenarios and 128 semantic
boundaries per arm. C0, the uninstalled C1 control and C2 agree on every canonical
request payload/schema, nominal effect identity, result, approval, write and
cleanup. Native and production-WASM fresh-invocation peak memory decrease against
both controls, and checkpoint maxima do not grow. The exact local/cumulative
observations are in Agent's `conformance/agent4/m2-runtime-comparison.json`.
Paired timing measurements and review closure remain pending; memory savings do
not establish latency improvements.

## Remaining M2 obligations

This is not complete M2 or canonical pipeline adoption. The specification's
M2 is the smallest useful checked semantic slice; M3 explicitly owns broader
specialization, worker/wrapper/inlining and global control. Section 4.6 permits
coarse finite facts and requires extensions to have actual consumers. The earlier
remaining-work list mixed later precision improvements into M2's gate.

M2 closeout still requires the owned-consumer policy audit and qualification of
the final source/package/runtime tuple, required serial/browser checks, paired
economics against C0, and applicable G/T obligations. Shared demand, effect,
custody and escape obligations use the original admission/trait/liveness owners
and the conservative scope/use census; no second ownership checker is introduced.

The broader program still owes richer return/call contexts, context cloning when
callers disagree, product facts across control flow, broader cell/P07 contexts,
and remaining P04 alias/cyclic cases where required by their named packages.
These limitations are retained, not marked complete or removed from scope.
M2.5's production affine synthesis follows the M2 checkpoint, then M3 and the
remaining dependency-ordered program. No whole-family precision campaign is an
additional prerequisite for that transition.

Reproduction of the native record witness uses only Boundary data and World:

```sh
zig test -O ReleaseSafe --dep boundary_data --dep world \
  -Mroot=test/v2/application_specialization.zig \
  -Mboundary_data=src/data/root.zig --dep boundary_data \
  -Mworld=/absolute/world/src/root.zig
```
