# M5: construction and loop optimization

The full corrected specification remains authoritative. P17 is recorded here;
P18 onward, final bindings and installed serial reviews remain open. Separate
M3/P13/P16 economic decisions are not superseded by this construction work.

## P17 construction boundary

The source binding spine already stores IDs and appends records rather than
recopying its preceding computation. Typed `Body.bind` accumulates bindings and
`Body.finish` materializes them once in reverse order. Keep those representations.
The N/2N/4N witnesses count source nodes, array relocation and emitter occurrences;
wall-clock points alone do not establish their growth law.

Two measured metadata operations did repeatedly search existing prefixes:

- `source.Row.unionWith`: an existing-row scan for each right-hand effect ID.
  Generator composition and need-state construction retain this public interface.
  Sorted rows now use a linear merge; unsorted inputs are privately sorted first.
  Left multiplicities, right deduplication, final order and input immutability are
  preserved. In particular, invalid duplicate-left evidence is not silently fixed.
- `Context.fields` and `Body.arguments`: repeated field-name searches. Per-call
  indexes now detect duplicate declarations and resolve supplied arguments.
  Checks still run in declaration order: an earlier missing name/foreign value
  wins over a later duplicate. Temporary indexes use the child allocator and are
  freed on return; owned metadata stays in the builder arena. Scope, source
  occurrence, capture, failure-layout and nominal checks remain in place.

No public API, native emitter invocation, source declaration order or persistent
cache is added. The first indexed version retained scratch in the builder arena;
measurement identified that cost and the retained version uses bounded-lived
scratch with one reservation. Small-arity fixed setup costs remain explicit.

### Deliberate limit

Distinct literal lookup still scans the mutable low-level constant table. At
512/1024/2048 distinct literals, the current implementation visits
130,816/523,776/2,096,128 records. It is not claimed linear. A persistent index
without a mutation boundary would change valid raw-table editing and subsequent
lookup/alias behavior; a new regression test demonstrates that counterexample.
The P17 binding/list representation is retained, not replaced by a redundant
higher-rank encoding or an unsafe cache. No raw construction migration is required.

### Deciding observations

- Long binding spine: 512/1024/2048 occurrences; exact source-node counts,
  array-pointer relocation counts and copied record bytes. Reused and distinct
  configurations are reported separately.
- Typed forward chain: 128/256/512 emitters produce 511/1023/2047 terms and
  513/1025/2049 values. Native emission counts remain N. Authoring is timed
  separately from observed source-copy/check/lowering/target-admission/P01 phases.
- Capture helpers: 32/64/128 authored captures remain exactly 32/64/128 checked
  target capture fields. Publication/capture validation is outside authoring time.
- Effect-row union and named declaration/assembly have separate repeated paired
  measurements against frozen P16 code. Ordered and unsorted row behavior,
  duplicate policy, caller storage and allocation failures have direct tests.
- Native execution compares an explicit binding spine with the forward builder,
  including every external request's nominal identity and payload, authenticated
  replies and the final value. Same-type, differently configured native emitters
  must retain distinct traces and images. Reversed named arguments must still
  materialize in declaration order.

No World execution speedup is claimed for a construction-only change. Consumer
and fixture image equality, integrated checks and final cost reporting remain to
be recorded before delivery.

## P17 retained measurements and qualification

The final five alternating paired windows (three warmups/nine samples per process)
are in `performance/m5-p17.json`. At 2048+2048 sorted row entries, paired median
ratio is 0.01147: control/candidate median times 1,405,667/16,125 ns. At 512 named
fields, declaration ratio is 0.03109 (297,542/9,250 ns), and assembly ratio is
0.02307 (590,250/13,667 ns). These are isolated construction operations, not an
application or execution-speed claim.

One-to-four-field cases pay approximately 42–84 ns of fixed index setup in the
paired observations. Scratch allocation increases are reported. These Boundary
construction tradeoffs fall under the corrected policy; no World cost exception
is inferred. The first arena-retained-index experiment is labelled superseded,
not relabelled as final evidence. Output metadata ownership remains unchanged.

Final ReleaseSafe aggregate: 319 steps / 753 tests, terminal exit zero. Three
native tests pass exact external-request identity/payload order, authenticated
replies, final values, emitter invocation traces and distinct configurations;
a 17-field reversed argument list materializes in declared order. Existing
source capture, nominal, lifecycle and allocation-failure tests remain included.
The new malformed-name tests preserve missing/duplicate/foreign-value priority.

The frozen P16 compiler produces byte-identical images and native emission traces
for both construction representations and both configurations. Raw and typed
representations also agree with each other. All 18 Agent images remain unchanged.
Existing same-image runtime evidence therefore remains applicable to those exact
artifacts; no kernel rebuild, runtime reinterpretation or new public selector is
involved. P17's construction capability and scoped improvements are delivered;
whole-authoring linearity is explicitly not claimed for mutable literal lookup.
P18 onward, pending M3/P13/P16 decisions, final bindings and serial reviews remain.

## P18: guarded scalar loop motion

The data-only pass discovers natural loops with bounded dominator iteration.
Acceptance derives dominance independently by cutting the header from entry
reachability. It re-derives loop membership, single-entry edges and value stability
rather than trusting the discovery matrix or a supplied block list.

Only pure, region-free, single-custody functions with ordinary intra-function
control are admitted to the first rule. Hoisted definitions produce fixed-width
scalars (at most eight bytes), have no authored failure, and use immutable scalar
operands. Identity allocation, mutable reads, resources and handler transitions
are excluded. Invariance is about definitions and edge transfers, not slot-number
equality: loop writes kill availability, and a batch restores fixed status only
in its proven definition order. Earlier reads of a destination prevent moving
its first definition forward.

The initial header is copied on outside entry. Its original guard executes first;
only the body-taking edge enters the hoisted batch. Backedges use the old header
and bypass that batch. No new layout slot is required, no cleanup scope is crossed,
and the zero-trip path performs no hoisted work. Original/fresh admission and the
independent record correspondence precede mandatory P01. Budget exhaustion returns
the exact admitted P01 baseline. Acyclic functions avoid dominator construction.

Shared selection now also compares repeated non-control scalar instructions,
weighted by natural-loop nesting. This is a bounded structural estimate, not a
runtime measurement. Branch-condition producers are excluded from that estimate;
static entry work, exact byte budgets and admission-cost guards remain separate.
An unavailable estimate provides no preference. No guard is weakened for LICM.

Initial native evidence: the simple loop changes XOR evaluations from 2N to N+1
for N>0, and keeps zero at N=0. Guard evaluations remain N+1. Nested placement is
inside the inner guard because the outer induction variable changes; it must not
be lifted once for the whole outer loop. Source-free linking exercises the same
shared compiler. Aliased cell reads, prior-destination reads, edge overwrites,
failing division, public infinite-loop yields, borrowed owners and cleanup scopes
are explicit negative witnesses. A fixture initially listed arithmetic failure
alternatives out of canonical order; original admission rejected it. The corrected
fixture now checks both the unexecuted zero-trip failure and the actual nonzero
failure; no production check was changed for it.

P18 final integrated/consumer/runtime cost qualification is in progress. No P18
cost exception or completion is implied by these initial observations.

### P18 measured correction to entry placement

The first guard-copy candidate passed semantic/native/platform checks but increased
small-program WASM admission memory by up to 2,682 bytes. That candidate's images,
measurements and emitter identity are retained as an initial experiment, not final
qualification. It is not an accepted cost exception.

The retained construction now distinguishes a necessary guard from an unnecessary
one. For total immutable scalar work whose old destination is dead at loop entry,
computing on a zero trip has no declared value/effect/failure observation. Such a
batch reuses an existing single-entry jump predecessor when possible, or adds one
preheader after incoming assignments. A live zero-trip destination still requires
the original guard before hoisting. Acceptance independently checks original
liveness and the complete entry-edge census, in addition to definition stability.

The early synthetic assertion that *every* zero trip must perform zero scalar
calculations was stronger than P18's source contract (no newly executed failing or
observable work). It is replaced by two discriminators: dead pure scalars may be
computed once, while a live zero-trip value of 99 must stay 99 and execute no XOR.
An independently admitted speculative rewrite of that live-value case is rejected.
Failing division, mutable state, public yields, custody and cleanup exclusions are
unchanged. This correction changes placement, not the required observation domain.

### P18 final technical qualification

The retained candidate passes 319 ReleaseSafe aggregate steps / 766 tests and
seven native tests. A subsequent test-only extension runs allocation failure at
every point for all three placements; the final focused run passes 30 tests.
The final native/Node WASM/Wasmtime matrix passes 48 arms and 800 boundaries,
including 48 malformed inputs, 48 same-image restores and 48 wrong-image rejections.
All 18 Agent images remain unchanged.

For ordinary and nested loops the final image size and admission memory match
the frozen P17 semantic control. Guarded live-zero-value loops retain extra entry
code and its measured cost. The 116 final paired timing comparisons retain exact
local semantic controls and structural comparisons separately; 19 comparisons
confirm remaining short-run/admission/checkpoint increases. There is no confirmed
longer fresh-run slowdown. The complete timing and memory decision is in
`optimization-m5-p18-cost-decision.md`; explicit acceptance or correction remains
pending. No initial experiment is relabelled as final evidence.

P19 onward, M3/P13/P16/P18 economic decisions, final package bindings and installed
serial reviews remain open. Native dynamic operation counts establish actual
hoisting; they do not substitute for the measured cost matrix.

## P19: loop unswitching in flight

`loop_unswitch.zig` keeps the original loop guard and first dispatch. It copies
both natural-loop paths and fixes the branch in each copy. Empty specialized
branch blocks are bypassed only when they have no instructions or selected-edge
assignments; mandatory P01 removes the resulting unreachable records. An initial
copy retained those empty jumps; the revised copy avoids their repeated cost.

All internal edges map to the selected copy, with exits retaining their original
targets. Slots use an identity bijection within the same activation: the two paths
are mutually exclusive, preserve their original layout, and cannot cross copies.
Custody remains the same single scope. The independent validator uses header-cut
reachability, rechecks every condition write/edge transfer, and checks the complete
instruction and edge correspondence. No source function, schema, region or nominal
identity is duplicated. The final P01 image must satisfy the exact local added-byte
budget and the existing shared compiler guards.

Pure loops and loops using cells in an already-established region are eligible;
external control effects, cleanup/custody transitions, borrows and nondroppable
state remain excluded. Cell creation, reads and writes stay in their original
per-iteration positions. This is code specialization, not allocation sharing.
The runtime Boolean is never treated as a compile-time constant at entry, and
its original zero-trip guard precedes the first dispatch.

Focused tests currently pass 25 cases including independent admitted wrong-copy
and wrong-selector mutations, condition writes/transfers, custody exclusion,
allocation cleanup and exact P01 fallback for zero work/insufficient code budget.
Four native tests pass both Boolean paths, zero trips, shared compilation and
source-free linking, structural-contract preservation, per-iteration region-local
cell operations, and a failing prefix that remains absent on zero trips.

At 257 iterations the ordinary witness reduces runtime selector tests from 257
to one. Initial guard counts and results remain unchanged. The cell witness
retains N creations, 2N reads and N writes on both paths. The shared selector now
also estimates repeated externally-defined Boolean tests without treating that
estimate as measured speed. It reuses P18's bounded loop analysis.

P19 remains unqualified for delivery: final integrated checks, current consumer
comparison, complete runtime/cost measurements and draft publication remain. The
cell component's original borrow vocabulary must be checked before claiming a
source-free result for that fixture. P20 onward and all outstanding economic and
final review obligations remain in scope.

### P19 technical qualification progress

The retained implementation passes 319 ReleaseSafe aggregate steps / 774 tests,
25 focused tests and four native tests. Full shared compilation and source-free
linking also preserve the cell witness's N creations and N writes; the standalone
unswitch pass preserves both reads per iteration. Other independently validated
passes may eliminate an unused read, which is not attributed to unswitching.

Original component publication succeeds for the cell fixture; no borrow-vocabulary
exception is needed. Linked images equal shared compiler images for both fixtures.
The exact P18 semantic control differs from the structural baseline, so both
comparisons remain separate. All 18 Agent images are unchanged. Cross-engine
qualification and final costs are still in flight; no P19 cost gate is waived.

### P19 economic selection correction

The first full matrix passed 80 arms / 804 cross-engine boundaries and completed
152 paired timing cells, but 92 comparisons confirmed regressions. In particular,
a cell-creation prefix left a specialized jump in place of the old branch: the
condition read disappeared, but logical control work did not. That was insufficient
to justify the code/admission footprint. The initial measurements and exact emitter
identity are retained in `performance/m5-p19-initial.json`; they are not accepted
tradeoffs and will not be relabelled as the revised candidate.

The shared cost estimate now credits removal of an empty repeated dispatch block,
not a condition-read-to-jump substitution after a live prefix. The transformation
checker still supports the complete ordered clone; the canonical compiler selects
the P01 baseline when that candidate lacks the demonstrated control-work benefit.
This is ordinary per-candidate economic selection, not an off switch or a second
product. The original cell-prefix workload stays in the comparison as a fallback
witness rather than being discarded.

A distinct branch-local cell fixture exercises profitable specialization while
retaining N cell creations and writes. It does not replace or rename the original
prefix fixture. Five revised native tests pass: both canonical selected loops and
both fallback paths retain results, guard behavior, failure timing and allocations.
At 257 iterations the pure selected loop executes 1550 logical steps instead of
1806. Final integrated, consumer and cost qualification must be refreshed for this
revised selector before P19 delivery. P20 onward and all pending economic/final
review obligations remain in scope.

### P19 final revised qualification

The revised candidate passes 319 ReleaseSafe aggregate steps / 775 tests and five
native tests. Source-free linking succeeds for all three fixtures. The final
matrix passes 120 arms and 1280 native/Node WASM/Wasmtime execution boundaries, plus
120 each of malformed-input, same-image-restore and wrong-image checks. All 18
Agent images remain unchanged.

The original cell-prefix case now selects its structural P01 baseline. It stays
in the measured corpus; its two structural comparisons are exact-image cases.
The pure and branch-local allocation cases remove the repeated dispatch block.
The complete final report contains 188 timed comparisons and two exact-image
comparisons against distinct local semantic/structural controls.

The revised selection does not eliminate every cost. Seventy-four comparisons
confirm remaining increases, including about 15% WASM fresh-invocation slowdown
at 256 branch-local allocations against the semantic control. Code/admission and
checkpoint-memory increases are also explicit. These are not described as only
empty-input overhead, and fewer dynamic tests are not treated as a speed proof.
The final §9.5 decision is pending in `optimization-m5-p19-cost-decision.md`.
Initial adverse evidence remains in `performance/m5-p19-initial.json`; final data
are in `performance/m5-p19.json`.

P20 onward, separate M3/P13/P16/P18/P19 economic decisions, final package bindings
and installed serial reviews remain open. No cost acceptance is inferred from
technical qualification or draft publication.

## P20 in flight: induction and same-image bounds work

`induction_facts.zig` derives a zero-origin unsigned unit-step loop certificate
from admitted records. It checks every outside initialization, the unique latch,
all writes/transfers of the counter and limit, and acyclicity of one iteration.
A guard `i < limit` makes `i + 1 <= limit <= type_max`; zero or larger strides and
signed counters do not receive this certificate. Loop-constant scalar limits and
actual sequence-length definitions are distinct. A vector capacity can bound
arithmetic but does not replace its runtime length.

The first focused run passes 33 tests including the three new induction cases
and imported loop/admission witnesses. The analysis is still in flight: affine
recurrence and redundant explicit-guard consumers remain to be implemented before
this is a delivered compiler capability. Strength reduction must bound every new
intermediate, including any final recurrence update, and retain fault payload/order.

World work continues in its existing checkout and branch at
`/Users/tk/workspace/tk/world`, `codex/canonical-durable-3183` (base `0ba2120`).
No worktree or branch was created. Its runtime source matches the qualified
`f8a1597` code; intervening commits change tests only.

The current World sequence-get path checked an index and then rechecked the same
single-element range in slicing. The in-flight implementation binds a checked
range to the exact immutable collection view and materializes that range without
a second cardinality check. No unchecked portable opcode or caller-supplied proof
is added. Optional counters report one index check and zero repeated range checks.
Nine focused collection tests pass against World’s exact pinned Boundary data
revision `511fe388587b36ae37307d277e04c22b0bb6f6d9`, including short actual length
inside a larger capacity and maximum-u64 zero-width cardinality. The pinned source
was reconstructed from Git after its package-cache directory was found absent;
that cache miss was not treated as a validation result.

Both repository changes remain uncommitted. This is not World/package/runtime
qualification: same-image differential stepping/restoration, malformed inputs,
allocation/cost measurements, integrated checks and authenticated delivery/rebinding
remain required. No kernel was rebuilt or published in this step. All P20–P31,
remaining T/G/L requirements, pending economic decisions and final reviews remain.

### P20 compiler consumers now implemented

The induction analysis now has production consumers in `induction_reduction.zig`
and `affine_induction.zig`, both wired into shared closed compilation. The former
removes only the exact repeated index/limit relation established by the successful
loop header, when neither version has changed and the comparison result has no
other observer. Portable checked access operations remain checked.

The affine consumer recognizes adjacent unsigned `i*stride+base` operations whose
intermediate product is private. It introduces an ordinary private scalar recurrence,
initializes it after incoming assignments, retains the original result-write point,
and advances it at the latch. Its certificate includes `base + stride*limit_upper`,
including the otherwise-dangerous final transfer after the last useful iteration.
Both original multiplication/addition ranges and every introduced addition fit the
same primitive width. Fault declarations remain on the introduced checked add;
no unchecked arithmetic is introduced. The validator re-derives induction/ranges
and checks actual layout, initialization, replacement and transfer records.

Focused results: 34 guard-reduction tests and 23 affine tests pass, including
allocation failures and independently admitted wrong-edge/seed/increment mutations.
Four native tests pass through the qualified unchanged World runtime. For actual
sequence lengths 0/1/7/50, all multiplications disappear through shared compilation
and outputs match. The 50-iteration case removes 50 multiplications. A u8 case
with 51 iterations is retained: its last useful result fits, but an extra final
recurrence update would overflow. Repeated bounds comparisons drop from `2N+1`
to `N+1` at zero, one, seven and maximum-u8 (255) trip counts. Signed-overflow
behavior and its failure payload remain unchanged.

These are local implementation witnesses, not P20 closeout. Further alias/length
and source-free witnesses, same-image World differential qualification, integrated
checks, cost measurements and authenticated package/runtime delivery remain.
Boundary and World changes are uncommitted, on their existing task branches.

### P20 source-free and alias witnesses

The subsequent native run passes all five tests, including source-free final
linking and same-image checkpoint/restore every 17 steps. Short vectors at actual
lengths 0/1/7/50 retain their results. A capacity-driven loop over a length-three
vector retains its explicit failure payload 99 rather than reaching the different
payload-access failure 73. The updated focused suites pass 35 guard tests and
23 affine tests (including imported witnesses).

World's focused collection suite now passes ten tests against pinned Boundary
data `511fe388587b36ae37307d277e04c22b0bb6f6d9`. The added alias case first accesses
index one of a length-two vector, then writes a length-one vector through the
same cell's alias. Reading the cell again returns absent; the retained immutable
snapshot still returns present. All three accesses perform their own exact-view
index check and no redundant slice check. This is a storage-level alias witness,
not a claim that compiler facts may cross mutable-cell reads.

Integrated Boundary and World native checks, runtime differential qualification,
P20 costs and authenticated runtime delivery remain in progress. These focused
results do not establish P20 completion or a latency improvement.

World `check-storage check-native` subsequently completed successfully against
the current Boundary working tree: 52 storage tests and 87 native/source/session
tests passed in ReleaseSafe. A separate native differential run compared 1,120
identical PKI3 initial/checkpoint requests from the existing P16/P19 corpora.
All PKO3 bytes matched between qualified runtime source `f8a1597` and the current
World P20 tree. Both binaries used the same pinned Boundary data `511fe38` and
the same Agent native host source. This establishes the observed native relation
on those requests; browser/WASM and economic evidence remain separate obligations.

Boundary's ReleaseSafe `zig build check --summary all` also completed with exit
zero on this working tree: 319/319 steps and 789/789 tests passed.

World's full ReleaseSafe `zig build check` with the current Boundary source
override then completed: 39/39 steps, 52/52 storage tests and the nested 87/87
native tests passed. It includes real Chromium 153.0.8010.12 and Firefox 155.0
Worker transfer, 235 native/Node boundaries (23 transfers), and 158
Node/Wasmtime/native boundaries. The locally built candidate kernel SHA-256 is
`eb00cf79b8011a1e42c7ed9e27a72f58a45d5cef7eb212f3d4a8141a117d3478`.
This is local qualification, not an authenticated published artifact or an Agent
runtime rebind. The existing authenticated old kernel remains separately named.

P20's first 36-arm platform run passed on the authenticated old kernel, including
source-free linked records and sampled native/Wasmtime checkpoint correspondence.
The affine length-50 quantum-one cycle peak grew from 8,840 to 9,902 bytes; the
guard and access fixtures improved. Before timing, the selected refinement is to
reuse the removed multiply's private result slot for the recurrence. The existing
whole-function use census must establish no other reads, writes or edge transfers;
the original addition result stays at its old write point. This preserves the
arithmetic and fault proof while removing the assumption that recurrence storage
must enlarge the layout. The discriminator is unchanged-layout validation plus
admitted observer/transfer counterexamples and repeated resource measurement.

The recurrence refinement now preserves the original function layout and reuses
the private multiplication slot. Its independent validator requires exact function
metadata/layout equality. All 24 focused affine tests pass, including the new
admitted product-observer and edge-transfer negatives; all five native P20 tests
also pass with source-free linking and same-image restores. Earlier integrated
Boundary results above precede this refinement and are not relabelled as current.
World runtime code is unchanged by this compiler refinement.

The refined platform matrix passes all 48 cases (three families, four lengths,
P19 semantic control / structural / semantic / source-free linked arms). All 18
Agent images equal the prior P19 corpus. At affine length 50, slot reuse reduces
the candidate quantum-one peak from 9,902 to 9,889 bytes; P19 is 8,841 and structural
is 8,840. The residual growth remains above the §9.5 threshold and needs its cost
disposition together with timings. At the same length, guard/access candidate
peaks are 8,775/10,082 versus P19 9,213/10,677. Checkpoint maxima remain 148/148/155
bytes for affine/guard/access. These are measured working payloads, not RSS or
latency estimates.

The post-refinement Boundary aggregate completed with exit zero: 319/319 steps,
790/790 tests. Compiler timing now compares the retained candidate against both
frozen P19 semantic records and structural records on the authenticated unchanged
runtime, using the existing alternating-window protocol. Those timing runs are
not yet terminal. Partial platform/resource evidence, including the initial
candidate rather than overwriting it, is retained in `performance/m5-p20.json`.

P20 measurement is now terminal: 108 compiler comparisons include 18 confirmed
affine-family increases; guard/access have none. The separate same-image World
comparison completes 54 cells with no confirmed timing or memory regression.
The bounded affine costs await the explicit §9.5 decision documented in
`optimization-m5-p20-cost-decision.md`. No acceptance has been inferred.

## P23 initial production policy slice

P21 tail sharing/duplication/outlining and P22's initial logical packing already
exist from M3; they are not being restarted. P23 now introduces an explicitly
supplied profile of original image identity, version/toolchain, dense original
block counts and a checked total. The semantic owner remains P02 plus P09's
independent checker. Counts affect candidate order only, with deterministic ID
tie-breaking. They never prove reachability, constructor identity or absence of
an alternative. Relocated/source IDs cannot be substituted for original image IDs.

The initial consumer is `call_patterns`: within a fixed variant/block budget it
visits hot original call sites first and leaves nonselected calls generic. The
profile-free limit/rollback behavior is preserved. Whole-program work exhaustion
still rolls back rather than exposing an unfinished proof. The initial focused
run passes 51 tests, including preferred hot constructor selection, retained
zero-count alternatives, exact repeatability, stale identities, wrong toolchains,
wrong count dimensions and overflowing count totals.

Canonical BPF1 encoding/decoding and an explicit local collector are now added;
the collector snapshots counts and checks arithmetic before mutation. The 52-test
focused suite passes, including every truncated prefix of a valid profile and
atomic counter-overflow rejection. Supplied stale profiles reject even under a
zero search budget; the final focused rerun covers this added ordering case.
Shared compiler/final-link integration,
P19/P21 policy consumers, executed held-out/collection-overhead qualification and
P23 completion remain open. This is consumed production code, not P23 closeout.

Seven native call-pattern tests pass, including actual local World execution
collecting only the complement-constructor path, followed by specialization under
a one-variant budget and execution of all four Boolean branch combinations.
The two unobserved identity-constructor paths remain reachable and produce their
expected result. Existing source-free callable/capture/variant/fault witnesses in
that native file also pass. This proves the tested held-out correctness, not
profile collection overhead or a profile-guided speedup.

The environment now permits writes only in Boundary and temporary directories;
World/Agent writes and Git publication are unavailable under the current sandbox.
Existing work is preserved. Boundary implementation continues without changing
permissions, global configuration, branches or worktrees.

### P23 shared compilation and further policy consumers

The shared closed compiler now validates supplied profiles against the original
admitted records, before semantic relocation can change block IDs. Its explicit
profile policy selects call-pattern specialization, loop unswitching or tail
duplication. That target runs once on original records within its variant/copy/
byte bounds, then the normal shrinking/selection pipeline continues without
replenishing that target's budget or reapplying old IDs. Original/fresh admission,
independent transformation checkers, work-limit rollback and final P01 remain.
Structural compilation validates but leaves the profile unused, reported in
statistics. The no-profile route remains unchanged.

The call-policy shared suite passes 107 tests; seven native tests pass with both
profiled direct compilation and source-free BMO linking, including all four
held-out branch combinations after training only one path. Tail duplication now
selects the hotter independently proved incoming edge within one copy (45 focused
tests pass). Unswitching selects the hotter header between two admissible loops
for its one-loop attempt (27 focused tests pass). A combined shared-consumer
suite subsequently completed: 125/125 tests passed, including all three policy
consumers, exact repeatability, stale-profile rejection, unchanged structural
compilation and P01 work-limit fallback. Profile collection overhead, held-out performance, broader
qualification and P23 delivery remain open; these are not speedup claims.

### P23 measured collection and held-out results

The opt-in native collector adds a median 6.17 microseconds (ratio 1.642) to this
12-step short invocation, including identity validation, counter collection and
snapshot creation/destruction. Working peak rises 12,455 to 12,581 bytes; the
returned snapshot retains 88 counter bytes. Both modes execute exactly 12 logical
steps. Five alternating windows retain nine measurements after three warmups;
this is measured collection overhead, not a runtime optimization claim.

The platform measurement completes 36 native/WASM timing cells plus one exact
image-equality comparison. The isolated one-variant pass emits 249 bytes against
its 210-byte no-profile rollback control and has 11 confirmed timing increases,
with native working-memory increases up to 4,250 bytes. These intermediate
results are retained as adverse evidence, not reported as final compiler gains.
The complete shared profiled compiler selects a 193-byte image exactly equal to
ordinary shared compilation. Training and three held-out paths agree; the selected
shared image has no confirmed slowdown versus the structural control in this
matrix. Thus the fixture proves bounded profile-directed selection and preserved
held-out behavior, but no final speedup over ordinary compilation.

`performance/m5-p23.json` retains exact image/profile/binary/source hashes and raw
samples. A further focused negative confirms that a million-count polymorphic
call remains generic without a constructor proof (53 focused tests pass). The
final aggregate and fresh 18-image application comparison remain in progress.

Those checks are now terminal: the ReleaseSafe aggregate passes 319/319 steps and
797/797 tests; the added polymorphic-profile focused run passes 53/53 tests. All
18 freshly emitted Agent images are byte-identical to the P20 corpus. Outputs
and caches stayed in permitted Boundary/temporary paths; no Agent source or
runtime binding was changed. P20 cost acceptance, authenticated runtime delivery,
publication, remaining P22 physical/retention work and P24–P31 plus the remaining
T/G/L requirements and final serial reviews remain open. P23's measured fixture
supports no speedup claim over the ordinary compiler.

## P24 rectangular interchange — first executable slice

`rectangular_loops.zig` recognizes an admitted seven-block rectangular nest with
constant u64 dimensions, zero-origin unit-step counters, immutable scalar inputs,
a total bitwise/move body and a final XOR accumulator update. Block IDs and slot
IDs are discovered from actual control edges and uses. Triangular bounds,
accumulator-dependent body calculations, checked body arithmetic, effects,
custody changes and other unsupported shapes remain unchanged.

The selected ordinary-record construction exchanges only counter initialization,
guards and transfers. Body index meanings and the accumulator expression remain
unchanged. For each original point `(i,j)` in `[0,R) × [0,C)`, the new schedule
visits the same point exactly once in the opposite nesting order. The body's
def-use restriction makes its value depend only on that point and immutable
inputs. Total fixed-width XOR is associative and commutative, so this permutation
preserves the result without preserving incidental iteration order. Both checked
counter updates satisfy `index + 1 <= bound <= max(u64)`, including the final
update; zero-sized domains perform no body computation.

Interchange is selected only when `R > C`, reducing outer-loop bookkeeping and
making the orientation idempotent. An independent validator derives the original
domain again and checks every actual edit and unchanged record; it does not call
the emitter. Original/fresh admission, allocation cleanup, bounded work rollback
and mandatory final P01 remain. The pass is integrated before the earlier loop
passes in semantic closed compilation.

For this fragment the exact logical count is
`9 + 8R + R*C*(body_instruction_count + 3)`. Overflow makes the estimate unknown.
The shared selector can use that count without treating it as runtime timing.
The focused suite passes 22 tests including admitted dependence/triangular/fault
negatives, a forged reduction and allocation/work failures. Native execution
exhausts all 49 dimension pairs from 0 through 6 through direct/shared/source-free
paths, with same-image checkpoint restores every seven steps. The shared 8×2
witness is selected and executes 121 steps versus the original 169, in 151 image
bytes. The existing shared-stage regression suite passes all 126 tests.

This is not P24 closeout. Fixed-size tiling with partial tiles, remaining negative
witnesses, runtime/locality and cumulative-cost measurements, broader platform
qualification and delivery remain required. Existing P20/P23 evidence is not
relabelled as validation of this new compiler stage.

### P24 checked four-by-four tiling

`rectangular_tiling.zig` now constructs ordinary 13-block records for four-by-four
tiles over the same admitted reduction domain. Six fresh scalar slots hold tile
origins, endpoints, a scratch value and the fixed width. Every endpoint is formed
as `begin + min(bound - begin, 4)` after proving `begin < bound`. This avoids an
overflowing speculative `begin + 4`. Row/column increments remain checked and
bounded by those endpoints; each tile advances to its actual endpoint.

For every original point `(i,j)`, the unique tile origins are
`4*floor(i/4)` and `4*floor(j/4)`. The clipped endpoints include that point and
exclude every point outside the rectangle, including both partial final tiles.
The original total body and XOR update are retained exactly. The independent
validator checks layout/constant extension, each guard, range computation,
transfer and unchanged body; it never calls the emitter.

The focused suite passes 27 tests, including admitted wrong-endpoint/advance
mutations, maximum-u64 dimensions, observable per-iteration yield rejection,
nonprogressing-counter rejection and allocation failure cleanup. Native tests
exhaust all 100 rectangles with dimensions 0 through 9. They record actual `(i,j)`
visits to reject duplicates, omissions or out-of-range points, rather than relying
on a final XOR that could hide duplicate pairs. Same-image restores continue every
seven steps; the structural compiler retains the original 169-step contract.
The shared-stage regression suite passes all 126 tests.

The tiling stage is active in semantic compilation after interchange. Its local
cost guard preserves the checked incumbent when the exact logical count cannot
justify the candidate or the byte bound is exceeded. On the nonempty scalar
5×7 witness, the constructed tiled schedule takes 373 logical steps versus 259
in the original schedule, so it is not selected as an improvement. This is a
measured/count-checked construction witness, not a cache-locality or timing gain.
A separate empty-column selection witness also passes: tiling retains the 20×0
candidate and reduces actual logical steps from 169 to 71. All four native tests
complete successfully. Runtime timings, broader platform/cumulative qualification
and delivery remain open.

### P24 platform and measured qualification

Qualification now passes 30 emitted-record cases and 181 sampled native/Wasmtime
comparisons against Node, with every Node quantum-one checkpoint restored. The
restricted session initially blocked Agent's repository-local uv cache; the same
locked embedding then passed with a temporary cache and its existing environment
left unchanged. This infrastructure failure was not counted as a test result.

The P23 compiler control was reconstructed under `/tmp` and its production-module
hashes matched the recorded P23 report exactly. P24's ReleaseSafe aggregate passes
319/319 steps and 807/807 tests. All 18 freshly compiled Agent images remain
byte-identical to P23. World was neither rebuilt nor rebound for these compiler
measurements; the authenticated old kernel is explicitly identified in the report.

The 8×2 fresh-execution median ratios versus P23 are 0.815 native and 0.865 WASM;
checkpoint-cycle ratios are 0.724 and 0.736. Selected schedules have no measured
memory threshold increase and checkpoints do not grow. Construction medians rise
37–41%, with unchanged measured compiler peak; this is reported under the corrected
Boundary construction policy. The deliberately rejected 5×7 tiled candidate
regresses all six timing phases and is kept separate from selected outputs.

Two selected-output comparisons require §9.5 acceptance or correction: 20×0 WASM
admission +3.88 µs (16.5%), and an inherited 1×1 semantic/structural fresh comparison
+2.48 µs (5.7%) whose semantic image is unchanged from P23. The decision is pending
in `optimization-m5-p24-cost-decision.md`; no acceptance is inferred. Exact inputs,
raw samples, limits and the other unconfirmed admission increases remain in
`performance/m5-p24.json`. P24 delivery and the full remaining programme stay open.

### P24 explicit alias and first-failure counterexamples

The negative witnesses now include an admitted rectangular loop inside a region,
with two aliases of one mutable cell and an order-dependent read/update recurrence.
Both P24 recognizers retain it, and original/shared native execution matches an
independent ordered recurrence. The focused suite passes 23 tests.

A second admitted near-example has `i-j` and `j-i` with different failure payloads.
Original/shared execution fails with payload 11; independently forcing the pure
control permutation instead fails with payload 22. Both production recognizers
refuse the checked-arithmetic body. All six native tests pass, including the prior
domain, exact-point, source-free and checkpoint witnesses. This pass changes tests
only; the recorded 807-test aggregate and performance runs are preserved at their
actual input versions, rather than relabelled as reruns of the new tests.

## P27 typed equality search — initial XOR slice

While World writes remain unavailable, the independent Boundary P27 work proceeds.
`equality_saturation.zig` now searches a bounded typed graph for a single-block
total unsigned XOR fragment. Exact schemas and input/definition versions stay on
nodes. Every union records congruence, commutativity, associativity, cancellation
or zero identity. The checker rebuilds the original expression versions, checks
the source epoch, independently replays each registered law from fresh equivalence
classes, and checks the actual extracted records against the proven root class.

Extraction uses a finite cost fixed point and iterative dependency materialization,
with one emitted computation per needed class. Positive operation costs prevent
chosen cyclic dependencies; incomplete extraction is rejected. Final admission,
mandatory P01 and exact materialized image size govern selection, rather than
assuming additive tree cost describes sharing. Checked arithmetic, effects and
noninteger layouts are outside this first fragment.

The `(a XOR b) XOR a` witness saturates in five rounds with 29 nodes, four classes
and 25 unions, then emits a direct return of `b`. Focused tests pass 26 cases,
including cyclic XOR-zero classes, typed-width nonmerge, stale epochs, an admitted
wrong emitted output, original slot redefinitions, `0 * failing_expression`,
bounded exhaustion and every allocation failure. Native checks pass 256
original/direct/shared/source-free executions over u8/u16/u32/u64 with same-image
checkpoint restoration, plus the original and compiled authored-failure case.

The shared compiler invokes this search after expression reuse. Under §7.4, a
local search limit retains the already checked stage input and reports
`search_exhaustions`; it never publishes the incomplete graph. Global construction
limits and P01's original-input rollback remain unchanged. The shared regression
suite passes 127 tests; a strengthened focused test checks that earlier dead-work
removal survives a later equality-search limit.

This is not P27 completion. Aggregate/construction/projection rule coverage,
additional sharing-cost/borrow witnesses, actual search/proof/construction and
runtime measurements, broader qualification and delivery remain open. No dynamic
state equivalence is inferred from one expression graph. All remaining programme
requirements and pending cost decisions remain active.

The strengthened incumbent witness confirms that earlier dead-computation removal
survives exhaustion: 128 original instructions become 127 while the equality
search reports its limit. Original/candidate/proof records are charged before
search or replay allocations; graph node and round limits remain independent.
Search work units are exposed separately from node/class/union counts. The
post-accounting focused suite passes 26 tests; the final interaction and incumbent
checks also pass after the diagnostic counter addition.

### P27 typed products and sharing-preserving extraction

The graph now carries ordered product children and typed field projections. Its
projection rule requires an actual equivalent product constructor, a valid field
index and the exact result schema; proof replay checks those conditions again.
Eligible aggregate types are bounded-depth immutable products of unsigned words.
Internal/region/cell types remain excluded, including when nested in products.
Variadic product comparisons are charged explicitly to the deterministic budget.

The interacting product/projection/XOR witness reduces to its second argument.
A separate witness shares an inner product across two result fields: additive
tree cost is three operations, but actual extraction emits two product operations
and reuses the inner result. An admitted field-order mutation fails the checker.
Regional alias inputs and injected internal-type proof nodes are rejected, and
product extraction/replay pass allocation-failure testing.

The updated focused suite passes 35 tests and the shared regression suite passes
127. Three native tests cover 306 executions across original, direct, shared and
source-free images, including all unsigned widths, nested products, authored
arithmetic failure and same-image checkpoint restoration. These are correctness
and actual-record witnesses; P27 search/proof/construction costs, runtime/platform
measurements, cumulative consumer qualification and delivery remain open.

### P27 retained qualification and measurements

Initial measurements exposed a preflight omission: projection forwarding removed
the field opcode, so the shared driver skipped saturation on remaining products
and moves. The preflight now admits those supported forms. The sharing witness's
shared/source-free images shrink from 74 to 70 bytes and eliminate the remaining
copy; the XOR/projection images are byte-identical to their initial P27 versions.
Their exact runtime evidence is reused, while sharing is freshly qualified and
measured. Initial results are retained separately, not relabelled.

The final ReleaseSafe aggregate passes 319 steps and 822 tests; all 18 Agent
images remain byte-identical to P24. The retained platform matrix contains 45
cases and 162 native/Node/Wasmtime request comparisons, with quantum-one restores.
All 126 retained timing comparisons complete with no confirmed slowdown and no
selected-output memory threshold increase. Versus the recorded P24 control,
representative fresh median ratios are 0.789 native / 0.899 WASM for XOR, 0.812 /
0.836 for projection, and 0.939 / 1.000 for sharing. These are fixture-specific
measurements; no application-wide speedup is claimed.

Selected image sizes are 51/56/70 bytes versus P24's 59/67/74. XOR and projection
complete in one logical step, so their quantum-one cycles need no checkpoint;
sharing's maximum checkpoint remains 109 bytes. Search and proof replay are
measured separately. The source-bound raw samples, proof statistics, exact image
and executable hashes, control reconstruction checks and evidence-reuse scope
are in `performance/m5-p27.json`. No new §9.5 acceptance is needed for this retained
matrix. Earlier pending cost decisions are unaffected. Authenticated package
delivery, publication, final serial reviews and the remaining programme stay open.

## P28 offline extraction/search — solver qualification blocked

`tools/bitvector_extract.zig` reads and admits an actual BPI3 image before exporting
a bounded, versioned SSA bitvector fragment. It retains exact schemas, widths,
input ordinals, definition versions and both image identities. Its first fragment
contains only unsigned inputs/constants and total bitwise operators; checked
arithmetic, effects and other unsupported evaluation requirements reject.

`tools/bitvector_search.py` enumerates bounded candidate DAGs, writes replayable
QF_BV queries and requires the pinned Z3 4.15.3 interface. Source and target
encoders are separate. An independent concrete interpreter checks reduced-width
cases and revalidates/minimizes actual-width counterexamples. Unknown, timeout,
incomplete encoding, malformed/inconsistent solver output, changed executables
and unvalidated models never become proof. Solver answers grant no production
rewrite authority; rule-schema promotion remains a separate required step.

No solver is installed. A task-local `z3-solver==4.15.3` package probe failed DNS
against the dependency host under the current network restriction. This is a
real P28 blocker, not a reason to substitute finite enumeration for SMT proof.
Six parser/model guard tests pass. Actual BPI3 integration emits 16 queries and
returns `not-proved`; the independent interpreter refutes the false return-first-
argument candidate at `(0,1)`. The valid cancellation candidate has no small
counterexample, explicitly **not** a width-parametric or SMT proof. An admitted
`0 * failing_expression` image rejects at extraction and emits no candidates.

`performance/m5-p28.json` preserves the exact extracted input, queries, hashes,
counterexample and blocked outcomes. Real solver execution, automatic valid-rule
rediscovery, production promotion and solver/search cost qualification remain
unfulfilled. No solver dependency was added to the compiler or runtime.

## P29 finite recursive specialization — initial delivery slice

P29 extends P09's existing key, worker builder and independent checker. A selected
configuration parameter must remain unwritten and pass unchanged at every direct
self-call. The worker replaces known constructor applications and known control,
then folds that self-call into itself with the same ordered dynamic arguments and
capture fields. Nonrecursive P09 eligibility remains bounded by its earlier domain;
the new call/effect/control forms are admitted for the recursive slice only.

The binding-time abstraction keeps only one invariant selector in a key. Constructor
IDs/tags/Booleans come from finite original catalogs; numeric keys require an existing
literal and unchanged recursive transfer. Other parameters remain dynamic. When an
entry argument is proved static but changes on recurrence, an independently checked
generalization record identifies that parameter. No sequence of growing numeric
constants or stacks is unfolded. Discovery visits original sites, memoizes exact
epoch/function/parameter/schema/value keys, and clones finitely many original blocks.
Budgets remain a defense; the finite configuration argument does not depend on them.

The simulation relation fixes the original selector (or its known payload/captures)
and equates every remaining live slot with the worker slot. Unchanged instructions
preserve that relation and their authored failure order. Known applications have
the original ordered capture/argument contract. At a recursive call, the selector
is invariant and the same dynamic values enter the same residual worker, establishing
the inductive/coinductive step. Unknown calls, performs and yields are copied in
place with exact nominal identities, operands and corresponding continuation edges.
No host emitter, callback or environmental operation is executed during compilation.

The countdown witness creates one worker, folds one recursive call and generalizes
the known growing counter into a dynamic parameter. Equivalent entry configurations
with distinct counter values reuse that worker. Admitted wrong recursive arguments,
false generalization metadata and changed effect payloads fail the checker. The
focused suite passes 27 tests, including allocation failure cleanup. The 53-test
P09 suite passes after its former blanket recursion-exclusion test was strengthened
to require finite folding without runtime unfolding, as P29 now explicitly requires.

Native direct/shared/source-free tests preserve countdown demand, opaque request
payloads/replies and same-image restores. Shared images reduce from 192 to 166 bytes
for the pure case and 225 to 198 for the effectful case. An undemanded divergent
callback is not evaluated by specialization; when demanded, all tested arms remain
progressed at 128 steps. Its source body is an unconditional self-loop. The final
failure-order test also passes: original, checked and shared execution fail with
payload 11, while an independently admitted reordered worker fails with 22 and is
rejected by the worker certificate. All three native tests complete successfully.
P29 performance, cumulative consumer/platform qualification and delivery remain open;
image reduction alone is not a speed claim.

### P29 qualification and explicit consumer blocker

The ReleaseSafe aggregate passes 319 steps and 828 tests. The standalone recursive
matrix passes 32 cases and 424 native/Node/Wasmtime comparisons, including opaque
request/reply traces and quantum-one restores. All 72 timing comparisons complete
without a confirmed slowdown or measured memory threshold increase. At length 32,
pure fresh median ratios versus P27 are 0.761 native / 0.787 WASM; effectful ratios
are 0.843 / 0.950. These measurements use the unchanged authenticated World kernel.

Sixteen Agent images are byte-identical. Two change: inquiry ReAct 41,021→40,995
bytes and review ReAct 300→248 bytes. Fresh admission measurements for both changed
images have no confirmed slowdown or memory increase. The existing review ReAct
prescribed-response runtime test passes against its exact new image.

Fresh inquiry qualification is blocked. Its required experiment sandbox canary
returns `sandbox_apply: Operation not permitted` under the current session policy.
The gate was not disabled, replaced by an unqualified runner, or counted as passed.
The inquiry image's smaller size and successful admission do not establish execution
or checkpoint performance. Its full execution/cumulative economics remain open.
Consumer fixture manifests also attempted an unavailable pinned dependency fetch;
test emitters were instead compiled from the same existing local modules into `/tmp`,
and their BPI3 bytes matched the corpus exactly. No manifest or World kernel changed.

`performance/m5-p29.json` preserves the matrices, exact source/image identities,
terminal aggregate, passed review test and blocked inquiry evidence. P29 consumer
completion, authenticated bindings, publication, final reviews, earlier economic
decisions and the remaining programme requirements are not closed.

## P30 immutable schema-partition indexing

Measurement identified quadratic pairwise shape comparison inside the shared
linker/P01 schema partition: 1,024 mostly-unique schemas required 1,049,600 exact
comparisons over two rounds. The replacement keeps the original contiguous scan
while there are at most 16 distinct shapes, then uses canonical record keys and
hash indexing. Exact key equality resolves collisions; insertion order preserves
the original first representative and dense class IDs. Nominal maps stay identities.

Each index belongs to one refinement round and is destroyed with that round's
scratch. It is rebuilt after class labels change and never survives into another
compilation. Mutable source-builder schema/literal catalogs remain authoritative;
their public edits and reservation/definition paths are not cached by this change.
Tests compare against an uninstalled pairwise reference, force all hashes to
collide, change completed recursive definitions between invocations, distinguish
nominal region leaves, preserve invalid-reference diagnostics and exercise every
allocation failure. All 12 focused tests pass. Existing recursive authoring
reservation/definition tests are included in the running aggregate.

An initial representative-list scan regressed duplicate-heavy input and was
replaced with the original contiguous path. The retained three-window paired
measurement gives unique-input ratios 0.076/0.039/0.020 at 256/512/1,024 schemas,
with 284/304/334 comparisons. Duplicate-heavy ratios are 0.927/0.926/0.912.
Every class-vector digest matches the reference; measured retained arena capacity
is unchanged. This is a partition construction result, not a World speed claim.
Initial and retained measurements are separate in `performance/m5-p30.json`.
Integrated qualification, application-byte equality and delivery remain pending.

Integrated qualification is now terminal: 319/319 ReleaseSafe steps and 836/836
tests pass, including recursive authoring declaration/definition checks. All 18
Agent images are byte-identical to P29, so no new runtime-image cost is introduced.
The prior inquiry sandbox blocker remains unfulfilled; this construction result
does not waive it. Publication, final serial reviews and the full remaining
programme remain open.

## P31 standalone semantic final linking

The library already performs original component admission, nominal/interface
resolution and independent borrow-summary checking before shared closed compilation.
The standalone `boundary-link` command had not exposed that semantic contract.
Its manifest now accepts `contract: "structural"` (default) or `"semantic"`;
both invoke mandatory P01. BMO1 is unchanged. The Agent wrapper already forwards
its selected contract into `linkWithCompilation`; no Agent source edit was needed.

A new data-only emitter produces provider/client objects in separate processes.
The provider summary is inferred from actual checked bodies using the existing
borrow solver; the client declares the existing BMO1 interface obligations.
Transported linking runs in a directory initially containing only the executable
and two objects. Constructor binding exposes a singleton application and its two
capture operands. Structural output is 110 bytes with one application/construction;
semantic output is 77 bytes with neither application nor captured environment.
Nine direct/linked runtime executions agree on native and Node, restoring every
quantum-one checkpoint. An ordinary factory-return case remains conservatively
unchanged; it is not misreported as a gain.

Both contracts reject a canonical object whose summary is bound to the wrong
function, without emitting an image. Retired `off`/`safe` values reject as invalid
contracts. Existing independently checked false borrow guarantees, nominal sharing
and original-unreachable-contract tests remain in the aggregate. The new result is
recorded in `performance/m5-p31.json`.

The independent-process forwarding-law witness now passes too. Separately emitted
provider/client objects expose a wrapper whose linked body applies its captured
thunk. Inspection finds one forwarding-law witness in the structural image;
semantic linking reduces 127 to 96 bytes, two constructions to one and two capture
operands to one. The constructor fixture independently exposes one dead-capture
witness. All 15 direct/linked native and Node executions agree, including every
quantum-one restore. The harness completed with exit status zero. These are
transformation and correctness observations, not latency measurements.

The report preserves the earlier nine-execution result and identifies the later
fixture sources. The 319-step/836-test aggregate covers the production CLI change;
it predates these test-only additions and is not presented as a fresh aggregate.
Full programme/consumer reconciliation, runtime qualification, pending cost
decisions, publication and final reviews remain open. This is not P31 or goal
completion.

### P31 independent-object private sharing

`sharing-provider` and `sharing-client` now emit independent BMO1 objects, each
containing one private XOR helper. Decoding each transported object confirms its
helper is present. Structural final linking produces a 117-byte image with three
functions and exactly one XOR instruction: the public wrapper and client entry
remain distinct while their private helper bodies share. Three inputs, including
full-width words, return the independently expected `(x XOR y) XOR y = x` result.
Every quantum-one checkpoint agrees between native and the authenticated Node
kernel. The full standalone harness passes 18 executions with exit status zero,
including the earlier constructor/law witnesses and invalid-contract rejections.

`performance/m5-p31.json` retains input-object identities and counts, output
identity/counts and prior qualification evidence. This addition changes only the
fixture and harness, not production compilation. It closes the independent-process
private-sharing witness; it does not establish a new runtime speed improvement.

### P31 standalone policy transport

The existing manifest now forwards the shared objective, semantic work/round
budgets, image-growth/hard-size limits and optional checked profile. Defaults
remain those of the shared compiler. No record format or runtime changes.
Eleven standalone policy checks pass: all three objectives honor the image bound;
zero semantic work/round budgets retain the checked structural baseline; zero
semantic work still shares the two private helpers through P01; impossible hard
limits and stale profiles reject under both contracts without emitting an image.
A valid original-provider profile with all-zero counts is accepted and emits the
same image as the unprofiled route, preserving reachable unobserved behavior.
The existing 18 runtime executions also pass against the changed CLI.

Exact source/executable identities and results are retained under
`policyQualification` in `performance/m5-p31.json`. The fresh Boundary ReleaseSafe
aggregate passes 319/319 steps and 836/836 tests with terminal exit zero. This policy transport
does not resolve the separate World/Agent, solver, economic or publication blockers.

## Remaining execution frontier after P31 qualification

The source-free audit found existing closed-link execution witnesses in
`test/v2/induction.zig`, `loop_unswitch.zig`, `rectangular.zig`,
`recursive_specialization.zig`, `equality_saturation.zig` and `affine_capture.zig`.
These are bounded package witnesses, not proof that the full programme is complete.
The next major implementation obligations retain their original owners:

| Remaining obligation | Current evidence and blocking condition |
| --- | --- |
| P22 physical packing/retained activation proof | Boundary's logical temporary packing is implemented. World `activation_slots.zig` owns persistent physical pages/views; its retained-version obligations are not discharged by the compiler rewrite. World is outside this session's writable roots. |
| P25 superinstructions | World `prepared.zig` owns admitted program leases and derived contracts; `stable_session.zig` owns instruction positions and stepping. The required accelerated sequence/prefix-state implementation and qualification remain outstanding. World writes are unavailable. |
| P26 reuse/retention | Existing `store.zig::aggregateSlice` shares descriptor storage and bounds prefix retention; that existing mechanism is not completion of the specified consumed-node reuse, alias fallback, short-lived allocation and failure witnesses. World writes are unavailable. |
| P28 real solver qualification and rule integration | `performance/m5-p28.json` remains `solver-blocked-not-proved`: pinned Z3 is absent and its package fetch failed DNS. Offline extraction/search guards are not SMT proof. |
| Changed inquiry execution and cumulative costs | The required inquiry sandbox canary returned `unavailable`; the gate remains intact. The smaller P29 image and successful admission do not qualify execution. |
| Economic decisions | M3 consumer residuals and P13/P16/P18/P19/P20/P24 retain their recorded pending dispositions. Accepted P15 costs do not accept these separate reports. |
| Binding/publication/final reviews | Boundary HEAD remains `7c7b5867c3bac6090cabe7980c67ad12c273ac12`; later work is uncommitted. Agent HEAD is `9a358cb42909095de84842ce4ea9364fc3de970d`. Git metadata and World/Agent are read-only in this session, and network access is restricted. No current package rebinding, publication or final review completion is claimed. |

Agent's existing `docs/optimization-m2-adoption.md` contains the owned-consumer
policy audit. Current `src/compiled_tool.zig` forwards the selected contract,
objective, growth/hard-size limits and work/round budgets to final linking; the
earlier M2 snapshot describing missing forwarding is historical. Its audit does
not waive current consumer execution or authenticated binding qualification.

All P01–P31, T01–T42, G01–G45 and L01–L20 requirements remain in force. The current
permission boundary blocks the next World implementation and delivery steps;
it does not authorize moving runtime responsibilities into Boundary, weakening
qualification, resetting the existing drafts or introducing another worktree.

### Access restored; P25 resumed

The user enabled full access on September 29. Exclusive temporary-file write/remove
probes succeeded in all three existing checkouts and their actual Git directories;
GitHub returned HTTP 200. All three named PRs remain open drafts, assigned to
`tkersey`, on the existing branch and previously recorded published heads. The
filesystem/network restriction above is historical, not the current blocker.

P25 implementation has begun in World's existing `stable_session.zig`. The selected
boundary is the current admitted Session: adjacent total unsigned bitwise scalar
operations can share a dispatch while retaining each existing instruction/frame
write. No separate evaluator, serialized plan or new opcode is introduced. Batches
are bounded by eight operations, remaining quantum and the next collection boundary.
`step()` remains the one-operation discriminator; same-image checkpoint bytes at
every prefix are the deciding witness. Physical failure retains the existing
poison/Resident rollback owners. Runtime performance and broader qualification
remain required before this candidate is accepted.

The focused ReleaseSafe P25 test passes all 128 input/quantum/counter combinations,
comparing canonical checkpoint bytes with repeated one-step execution and restoring
each result. It covers quantum 0–7, a four-operation chain, collection boundaries
254/255 and counter wraparound. Two tests pass including the imported clone test.
The first broader native command used the historical data-only Boundary fixture;
it failed to compile because that fixture lacks `src/root.zig`. The corrected
command uses the full current Boundary checkout; no execution failure is inferred
from the fixture-path error.

The corrected World `check-storage check-native` run is terminal with exit zero:
53 storage tests and 87 native tests pass in ReleaseSafe. This is local native
qualification of the P25 candidate; WASM, failure-injection, representative timing
and final package/browser qualification remain open.

The restored network also permits pinned Z3 4.15.3. The real offline P28 search
on the unchanged XOR image completes all 16 candidates: two equivalent targets
are proved at the source width and fourteen candidates are refuted with independently
validated counterexamples. `performance/m5-p28.json::solverAccessQualification`
retains the solver/extractor/source identities, timings and replayable queries,
separately from the earlier unavailable-solver evidence. The discovered identity
is `(a XOR b) XOR a = b`; production rule integration and remaining qualification
are still required. No solver result alone grants production rewrite authority.

### P25 checked failures and first native measurement

Four focused ReleaseSafe tests now pass. Beyond all quantum prefixes and collection
counter wraparound, an overflowing checked operation interrupts the scalar sequence
at its original position. Canonical checkpoint bytes match repeated `step()` at
each cut. The Resident allocation-failure sweep reaches failures after batch work,
proves exact prior-checkpoint preservation and successfully retries every failed
drive. These checks use the unchanged runtime Boundary data input.

The uninstalled `test/current/scalar_batch_bench.zig` is built identically against
the current World candidate and a source snapshot restoring only the two P25
production files to their predecessor. Existing P20 storage changes are present
in both. Both executables admit and execute exactly equal images. Five alternating
process windows, each with three warmups and nine samples, cover 0/2/4/16/256/1024
scalar operations under prepared and fresh execution. None of the twelve cells
confirms a slowdown under the specified 5% / four-of-five-window rule.
Prepared ratios at 16/256/1024 operations are 0.927/0.900/0.902; fresh ratios are
0.989/0.952/0.935. Zero-, two- and four-operation cases are approximately unchanged.

`performance/m5-p25.json` retains exact source/binary identities and raw windows.
This is a native scalar-workload result, not a whole-application gain. WASM,
memory/preparation costs, representative cumulative economics and final integrated
qualification remain open. The candidate is not yet accepted for publication.

### P25 WASM prefix, memory and timing qualification

The baseline and candidate kernels were built from the same runtime data input;
only the P25 runtime files differ. Six images at 0/2/4/16/256/1024 scalar operations
pass 158 paired requests, with native byte comparison at the initial cuts. Every
cut through the short sequences and sampled collection-boundary cuts through the
long sequences preserves outcome/checkpoint bytes. Restoring each progressed
checkpoint and cancelling at those cuts also agrees exactly. Admission peak and
retained bytes, fresh-execution peak, quantum-one cycle peak, checkpoint maximum
and cycle step counts are exactly equal between kernels on all six images.

All 18 WASM timing cells finish five alternating process windows with three
warmups and nine samples. Prepared ratios at 256/1024 operations are 0.877/0.811;
fresh ratios are 0.951/0.912. One four-operation fresh-execution cell confirms
an increase of 1.063 microseconds (7.8%) under the unchanged threshold. Its §9.5
disposition is pending correction or explicit acceptance; none is inferred from
the long-chain benefit. The zero-operation fresh cell has a 7.7% median increase
but does not satisfy the four-of-five confirmation criterion.

Raw platform and timing evidence is appended to `performance/m5-p25.json`, without
relabeling native evidence or authenticating the local candidate kernel as a
delivered artifact. Native physical-memory accounting, WASM failure paths, consumer
economics and final integrated qualification remain open.

### P25 failure/memory completion and restored P29 consumer execution

The additional WASM fixture exercises the authored arithmetic failure at all nine
quantum cuts and restores each unfinished State to the same failure. Sixteen
working/output-capacity cases have identical dispositions across kernels; twelve
fail, preserve the resident's byte-identical prior checkpoint and retry to the
expected result. This is working/output-budget evidence; the full capacity suite,
including fixed linear-memory exhaustion, remains part of final qualification.
Native admission, fresh execution and checkpoint-cycle measurements also finish:
all 18 before/after cells have exactly equal measured peak and retained bytes.
Incidental native timing samples from that memory probe are not a paired latency
qualification. Sources and raw results are appended to `performance/m5-p25.json`.

The restored session permissions also permit Agent's unchanged inquiry sandbox
canary to return `qualified`. The previously blocked P29 consumer command now exits
zero with 13 prescribed-response scenarios, including four inquiry/ReAct fixture
pairs. Original model parsing, approvals, custody, experiment and cleanup assertions
remain active; no paid inference or runner-gate bypass was used. The exact adapter,
fixture and executable identities, authenticated kernel binding and full results
are retained in `performance/m5-p29.json`, alongside the earlier failed attempt.
This removes the sandbox execution blocker. It does not establish P29 consumer
timing/cumulative economic acceptance, or qualify the new P25 kernel by relabeling
the existing authenticated runtime.

## P26 compatible tail-frame reuse and bounded argument scratch

The existing World owner already reuses active control nodes, uses copy-on-write
pages for retained slot views and restarts same-function tail calls. The selected
change extends that restart to different functions only when their exact schema
layouts and custody capacities agree and no custody history is initialized.
`Frames.restart` now takes and checks the target function; its production and
storage-test callers are migrated with no compatibility adapter. Arguments are
gathered from the predecessor view before old locals are cleared or inputs written.
Logical function/position change while compatible physical storage remains owned
by the same view. Aliased pages still copy through the existing Slots owner.

Up to eight direct-call argument descriptors use bounded stack scratch; larger
calls retain the existing arena. This array has the same transition-local lifetime
as its predecessor allocation: callee frame operations copy descriptors, and no
host pointer enters a portable value. This changes allocation behavior, not the
call order or argument contract. The stack bytes must be included separately in
physical resource accounting; reduced heap traffic alone is not a total-memory gain.

Three focused ReleaseSafe tests pass. Eight mutual tail calls reuse their actual
view handles; an explicitly retained prior view keeps its original value and
causes page copying; incompatible layouts take eight allocation fallbacks.
Checkpoints at each reused call restore and complete correctly. Eight stack and
nine heap arguments preserve reversed predecessor order across checkpoint/restore.
Seventeen activation-storage tests pass, including allocation failures at 4/65/256
slots for self and cross-function restarts and rejection of layout/custody mismatch.
The 87-test native suite also passes with the final production changes, including
existing Resident rollback, cleanup and resumption coverage.

`performance/m5-p26.json` binds these observations to their exact inputs. The new
candidate still needs native/WASM allocation, memory and timing measurements,
remaining retention work and final integration. It does not inherit P25 runtime
qualification by relabeling the earlier kernel.

### P26 same-image platform and local economics

The shared data-only frame fixture emits both compatible and incompatible-layout
images. With input counts 0/1/8/128/512, baseline P25 and candidate P26 WASM kernels
agree on all 6,530 quantum-one requests, including intermediate checkpoints and
tested cancellation cuts. Checkpoint sizes and logical step counts are unchanged;
admission peak/retained bytes are identical. Compatible long-call fresh heap peak
falls by 271 WASM bytes and 259 native bytes; fallback long-call heap peak falls
by 90 WASM bytes and 108 native bytes through argument scratch alone.

The bounded stack array contains eight 24-byte native value descriptors (192 bytes),
plus compiler frame/alignment overhead. This bound is reported separately from
heap observations; no total-stack or RSS reduction is inferred. WASM retains its
existing fixed stack reservation. Retained aliases continue to take COW copies.

Forty-four native/WASM timing cells complete five alternating process windows,
three warmups and nine samples each. No cell confirms a slowdown or exceeds the
memory-growth threshold. At 128/512 compatible tail calls, native fresh ratios are
0.831/0.835 and WASM ratios are 0.851/0.829. At 512 incompatible calls, native/WASM
fresh ratios are 0.950/0.945. Short and checkpoint-cycle paths are approximately
unchanged. These are selected-workload local comparisons against P25, not cumulative
application claims or acceptance of P25's separately reported short-case cost.

`performance/m5-p26.json` retains sources, kernel/native executable identities,
raw windows and memory observations. Precise retention beyond frame reuse,
allocation traffic, cumulative consumers and final capacity/browser/package
qualification remain open before full P26/delivery closure.

### P26 release consumed large-blob backing before a resident pauses

The new measurement found a concrete retention gap: after a 1 MiB blob's last
length observation, a progressed Resident still owned 1,051,286 requested bytes.
Only scalar work remained. Periodic/terminal collection eventually released it,
but a paused resident could retain it indefinitely. The initial test fixture had
a descriptor-slice lifetime error before execution; the baseline uses corrected
comptime-owned descriptors, not that invalid attempt.

The selected boundary remains Session/Resident and the existing tracing collector.
When `blob_length` loses its large operand slot under the admitted post-instruction
liveness facts (encoded backing at least 64 KiB), Session records a collection
hint. It does not infer that other aliases are dead or free backing itself.
Hints coalesce until a public drive returns; ordinary periodic/terminal collection
also clears them. `step()` observes the same boundary. The pending flag is part of
transaction rollback and is not serialized into portable State. Collection failure
poisons only the private attempt; Resident restores the original state.

The paused unaliased fixture now owns 2,852 bytes. The direct-aliased fixture keeps
its backing (2,100,037 versus 2,099,891 baseline bytes), and a blob captured in a
future callable also survives and yields its expected length. Requested resident
bytes exclude immutable Prepared and caller-owned input storage; these are not RSS
or whole-process memory claims. The allocation-failure sweep includes failures
after collection and proves byte-identical prior checkpoints and successful retry.

Final native validation passes four focused tests plus the 60-test storage and
87-test native suites; focused tests are a subset, not additional aggregate credit.
`performance/m5-p26.json::retentionCandidate` retains the exact source and log
identities. WASM state/capacity checks and latency/allocation measurements, including
alias-heavy cases, remain required before accepting this retention candidate.

### P26 retention WASM qualification and payload-rehash correction

Fifteen unique/direct-alias/captured-alias cases cross the 64 KiB encoded-backing
threshold and include 1 MiB payloads. Ninety prefix comparisons preserve exact
outcome/checkpoint bytes and restored results. Ten constrained-capacity cases
preserve the prior resident checkpoint and retry successfully. The harness first
attempted two residents in one kernel and correctly received `SessionAlreadyPresent`;
the retained harness closes the first resident before restoring, preserving that
existing contract. The unique 1 MiB WASM resident drops from 1,052,336 to 3,838 live
working bytes. Direct/captured aliases remain live, and linear-memory reservation
is unchanged. Extra working peaks are below the specified memory threshold.

The first timing matrix exposed a 191-microsecond pause cost: garbage collection
rehashed the retiring blob's entire payload to remove its intern-table entry.
Collection now iterates existing entries, journals and removes the current entry
before freeing its payload, then restores ascending free-ID order with constant-
space heap sort. No cached hash field or second interning structure is introduced.
Literal producers intern their blobs; restored State passes `checkCanonical`
before `importOwned`, establishing the table's live-blob coverage. A 128-entry
test verifies partial deletion, retained entries, rollback, complete retirement
and subsequent reuse of the expected free ID. The standard block sorter was
replaced because its 512-element scratch buffer was unnecessary for this purpose.

Final validation passes 61 storage tests and 87 native tests, plus the same 90
WASM prefixes and 24 timing cells. Uninterrupted 1 MiB fresh ratios are 0.658
(unique), 0.797 (direct alias) and 0.657 (captured alias). Six pause-phase cells
still confirm increases of 0.71–1.33 microseconds (10.5–17.3%); §9.5 acceptance or
correction remains pending. No full fresh-execution slowdown is confirmed. Initial,
intermediate and final measurements retain separate kernel identities in
`performance/m5-p26.json::retentionCandidate`; the failed fixture compile and
single-resident harness attempt receive no qualification credit.

Native retention timing/allocation counts, alias-heavy scaling, cumulative consumer
economics and final package/browser qualification remain open. The positive local
results do not close the entire programme or waive any pending measured cost.

### P26 native allocation traffic and alias-heavy correction

An uninstalled common native Resident probe compares current code with the actual
published/authenticated runtime source `f8a1597`, using the fixed runtime Boundary
data input. Preparation and caller buffers are outside its resident allocation
counter; timing uses a separate uninstrumented drive. At 512 compatible tail
calls, runtime allocations fall from 1,030 to 6 and requested allocation traffic
from 263,338 to 3,242 bytes. Each probe checks the result and zero remaining tracked
allocations after close. This is an explicitly named runtime-code baseline, not
a relabeling of the still-required full pre-cutover consumer comparison.

The 64-direct-alias, quantum-one case then exposed a 13.8% slowdown and 1,122 extra
retained scratch bytes from repeated pointless traces. The collection hint now
declines when an initialized, post-instruction-live slot in the same frame holds
the exact same blob ID. Absence of a direct alias is not a uniqueness proof:
indirect/captured aliases still go through the authoritative tracer. Once the
last direct alias disappears, early reclamation remains eligible.

The corrected 1/4/16/64-alias matrix passes identical checkpoint traces and five
paired timing windows with no confirmed slowdown; the 64-alias ratio is 1.002,
and its paused live bytes return to the exact baseline 91,652. The initial probe's
peak field was read after releasing Prepared and is explicitly excluded; the
corrected probe observes memory in a separate untimed operation sequence.
The 61-storage/87-native tests and original 90-prefix WASM matrix pass again.

Final cost reports retain 20 native and 24 WASM cells. Six native pause cells
confirm increases from 0.166 to 10.208 microseconds, with the largest freeing the
1 MiB input; four WASM pause cells increase 1.04–1.35 microseconds. These specific
§9.5 dispositions remain pending. Initial failed scaling, corrected scaling,
native traffic and all cost windows are separate under
`performance/m5-p26.json::retentionCandidate`. Cumulative consumer economics and
final capacity/browser/package qualification remain open.

### P28 offline discovery through the existing production checker

`test/bitvector_integration.mjs` now exercises the complete supported loop on fresh
current-source images. Pinned Z3 4.15.3 checks sixteen bounded candidates and
rediscovers `(a XOR b) XOR a = b` over all 64-bit inputs. The false target `a` is
refuted by the independently replayed/minimized input `(0, 1)`, giving source 1
and target 0. The `0 * failing_expression` fixture remains outside the total
fragment and is rejected before any candidate query is submitted.

The discovered identity is instantiated through the existing typed XOR rule
registry and its independent replay checker; it does not create a second optimizer
or a trusted solver-result import. Exact schema, SSA-version/origin and source-epoch
conditions remain checked. Associativity, commutativity, self-cancellation and zero
identity supply the width-parametric semantic argument; the solver result itself
is claimed only at its actual 64-bit width. Current checked-pass, shared-compiler
and source-free linked outputs are each 51 bytes versus 59 structural bytes and
extract to input ordinal 1. Their bytes match the previously qualified P27 images.

All 59 current production-checker tests and six offline tool-guard tests pass.
The former include independently admitted wrong-output, wrong-width, stale-epoch
and allocation-failure cases. The latter test `unknown`/timeout/incomplete-output
classification; no actual solver timeout is invented. Sixteen searches consume
411.2 ms in total, median 25.76 ms per candidate including process/model work.
Separate current construction/checker medians are 37.71/5.42 microseconds, with
29 nodes, 25 justified unions and five saturation rounds. These are offline and
compiler measurements, not runtime improvements inferred from image size.

`performance/m5-p28.json::productionIntegration` retains exact tool/source/image
identities, replayable queries, concrete counterexamples and qualified-image
equality. P28's bounded local deliverable is qualified; full programme delivery,
consumer economics and final serial reviews remain open.

## Published World runtime qualification

The existing authenticated delivery workflow completed successfully for World
`e89b94ab32118efbad96cca5917f27ddb8510298`, run `36594076098`, artifact
`11046230435` (expires October 29, 2026). The runtime remains built against its
locked Boundary data input `511fe388587b36ae37307d277e04c22b0bb6f6d9`.
Its delivered kernel SHA-256 is
`962d621fd781b19f0ec821e63d31688326467b6bba6f52fa697198c80b00a167`.

All eleven producer checks report passed, including the aggregate, ReleaseFast,
delivered kernel/package/source/capacity/transfer and portable smoke. The aggregate
contains the existing real Chromium/Firefox qualification and exact same-image
transfer assertions. Recorded native/Node agreement covers 237 boundaries and
23 transfers; Node/Wasmtime/native transfer covers 159 boundaries. Counts retain
their own suite scope rather than being added into a fabricated test total.

The downloaded archive and external descriptor were acquired through World's
public hash-bound `runtime acquire`; the installed bundle then passed `runtime
verify --smoke` against its expected manifest hash. A durable local copy of the
verified archive, descriptor and bundle is preserved separately from the earlier
runtime. `performance/m5-runtime-delivery.json` binds the run, artifact, exact
source/kernel hashes, producer checks and local smoke. No local kernel evidence
was relabeled as this delivered artifact.

Agent's dependency lock has not yet changed. Consumer execution/economics on this
exact artifact and authenticated package rebinding remain required. Publication
qualification neither accepts the pending costs nor closes P22/T/G/L reconciliation
or the final serial-review obligation.

### P22 physical packing candidate — retained-page boundary

The initial logical-packing implementation does not alone close P22's explicit
World requirement. The new candidate stays within the existing Slots owner:
ordinary unique pages retain dense addressing; copy-on-write successors may store
only initialized values in a single aligned header-plus-payload allocation.
The logical initialization bitmap determines rank-based physical indices on sparse
pages. Simultaneously initialized slots map injectively; clearing one slot can
reuse its physical cell for another logical slot, while a retained predecessor
keeps its independent page. A sparse page that needs more capacity returns to the
ordinary dense representation. Portable IDs, iteration order, view generations,
schema-bearing values and checkpoint interpretation do not change.

An unconditional compact-allocation attempt failed the existing no-copy growth
witnesses and was rejected. The retained design compacts only at an already
necessary COW boundary and preserves the old tests unchanged. The new test directly
observes physical-cell reuse across distinct logical slots, distinct live values,
predecessor isolation, sparse insertion and promotion back to dense storage.
Native validation passes 62 storage and 87 source/runtime tests. Performance,
same-image cross-engine/capacity evidence and new authenticated delivery remain
open; this is a candidate rather than an accepted faster storage claim.

`performance/m5-p22-physical.json` records the construction, rejected attempt and
proof scope. The running Agent integration still uses the earlier immutable
`e89b94a` export, so its result cannot qualify this newer World source by relabeling.

The focused physical-storage suite now passes 20 tests, including all 256 subsets
of eight noncontiguous logical positions, each with every one-slot insertion and
clear, checked against independent direct-value and iteration expectations.
Original retained views remain unchanged. Additional over-aligned and zero-sized
payload cases exercise the trailing allocation's alignment and ownership.

The same heap-allocation probe is compiled against original `e89b94a` Slots and
the candidate, using the same descriptors and live branches. Across 18 cases
(1/2/4/8/9/16 live values and 1/8/64 branches), allocation counts do not increase.
For 64 branches, sparse pages save 23,040/21,504/18,432/12,288 retained heap bytes
at 1/2/4/8 values; 9/16-value dense pages use exactly the old heap bytes. The
stack-resident Slots owner and call stack are outside these counters and remain
separate resource obligations. Timing was deliberately not measured while the
Agent aggregate was active. This is memory evidence, not a speed claim.

P22's WASM storage target now passes explicit sparse/dense page thresholds,
logical iteration and retained-predecessor checks in an import-free, unshared
wasm32 module. The candidate kernel also agrees with a freshly built native
`e89b94a` runner using the exact locked Boundary `511fe38` source on all 237
canonical boundaries and 23 transfers in the existing kernel suite. Its additional
Node/Wasmtime/native State-transfer suite passes 159 boundaries, including retained
scopes, reentrant captures, custody, resources and independently linked components.
These runs are terminal with exit zero; exact binaries and logs are bound in the
P22 physical report. Candidate timing, total-resource cost and final authenticated
delivery remain open. The old delivered kernel is not relabeled as this candidate.

The existing capacity suite also passes against the physical-packing candidate:
input, working, output and fixed linear-memory failures preserve unchanged retry
input. Native owner accounting identifies 24 extra bytes in `Slots(graph.Value)`
(104→128) for physical-page statistics; this is separate from the measured page
savings. At two values across 64 retained branches, heap payload is 29,168→7,664
bytes with 66 allocations in both builds. No whole-runtime/RSS reduction follows
solely from that probe. Identical native timing probes are built against both
implementations but remain unmeasured while Agent integration is active.

### Verified candidate dependency binding and inquiry consumers

A candidate Agent lock now binds the independently downloaded Boundary `36023aa`
and World `e89b94a` source archives to their GitHub commit trees, complete source
inventories and actual Zig package inventory. The World artifact ZIP digest,
delivery archive hash, manifest and runtime inventory also verify. Agent's existing
`snapshotDependencies`/`verifyRuntime` accept the complete candidate tuple. The
candidate lock and transports are preserved with the acquired bundle; the installed
repository lock is unchanged pending full qualification and cost disposition.

The verified Boundary package rebuilds Agent's economy emitter and reproduces all
18 previously measured P30 images byte-for-byte. The new delivered World kernel
passes all 13 prescribed-response inquiry cases, including four inquiry/ReAct
fixture pairs, with the qualified experiment sandbox, native control and locked
Wasmtime checks unchanged. The temporary test adapter changes only the explicit
candidate-lock argument to the existing runtime verifier. No runner or admission
gate is bypassed and no paid inference is used.

`performance/m5-runtime-delivery.json` retains the candidate lock digest, complete
verification observations, exact emitter/image identities and inquiry result. This
qualifies these checks on the new artifact; broad consumer timing/cumulative costs,
installed binding, remaining P/T/G/L closure and final reviews remain open.

### Delivered-runtime Agent admission and replay capture

Five alternating process windows compare admission of all 18 identical corpus
images through the previous and new authenticated runtime locks. Each process
uses three warmups and nine samples. No image confirms a slowdown; measured
admission peak and retained bytes are exactly equal in every paired observation.
This isolates runtime changes and is not the separate pre-cutover cumulative
compiler/image comparison. `performance/m5-runtime-delivery.json::sameImageAdmission`
retains all windows and the verifier-bound kernel/image identities.

The unchanged prescribed-response inquiry harness captured 128 PKI3/PKO3 pairs
across 13 scenarios. Every reply remained checked against native and locked
Wasmtime execution. A local copy of those fixtures is preserved with the acquired
runtime; its adapter only records bytes at the existing invocation boundary.
`test/consumer_runtime_replay.mjs` verifies fixture digests and both dependency
locks, then measures the same commands in alternating processes with immutable
reply oracles. This measures fresh runtime invocation/admission/restore work,
excluding external experiments, inference and host latency. The full replay
timing run is in progress; it is not counted as passed or economically accepted.

### Accepted P25/P26 measured tradeoffs

On September 29 the user explicitly accepted the consolidated P25/P26 costs:
P25's four-operation WASM fresh invocation increase of 1.06 microseconds (7.8%),
P26's measured native reclamation pauses of 0.166–10.208 microseconds, and four
WASM pause increases of 1.04–1.35 microseconds. The reported 64-alias regression
was corrected before this decision. The acceptance is recorded in the P25/P26
performance reports and supersedes their earlier pending disposition for these
exact measurements only. Earlier M3/P13/P16/P18/P19/P20/P24 decisions and the
still-running consumer comparisons are not included. Correctness, binding and
remaining programme qualification obligations are unchanged.

The delivered-runtime replay is now terminal with exit zero. All 13 scenarios
complete five alternating windows, each with three warmups and nine measured
replays of their recorded invocation sequence. Every one of the 128 recorded
command/reply bindings remains byte-exact on both authenticated kernels. No
scenario confirms a timing slowdown or exceeds the peak-memory growth threshold.
The full windows are retained under `sameImageReplay` in the runtime delivery
report. These results isolate runtime changes on current images; they do not
replace pre-cutover image/compiler comparisons or measure external host latency.

### Reconstructed pre-cutover comparison

The retained cutover report identifies the original Agent `dd336f0` and Boundary
`6313768` commits. Their recorded images were no longer present in the inspected
artifact directories, so immutable temporary Git exports rebuilt the original
economy emitter without modifying its source or creating another worktree.
All 18 original corpus images are regenerated. Inquiry and ReAct hashes exactly
match the pre-cutover hashes in the earlier cumulative report, establishing the
comparison's continuity rather than replacing its baseline with a newer image.

The existing prescribed-response cases regenerate 128 baseline invocation/reply
bindings and pass native/Wasmtime checks. Comparing them with the current-image
traces on the new delivered kernel proves equal nominal semantic effect identities,
request/resume schemas, canonical payloads and completed values at all 128 boundaries
across 13 scenarios. Image-bound envelopes and private State identities are
deliberately separate; no cross-image state transplant is performed.
`performance/m5-runtime-delivery.json` retains the reconstruction identities and
per-boundary results. Cumulative admission timing is running against this original
corpus; it is not yet reported as passed or economically accepted.

Cumulative WASM admission now completes all 18 images and five paired windows.
Review-model confirms a 62.666-microsecond (13.55%) increase; the other seventeen
images do not confirm timing slowdowns. Six images exceed the memory-growth
threshold: clarify-first, document-consequence, document, review-clarify_first,
review-mid_review and review-model. Their exact peak/retained observations and
all windows are retained in `cumulativeAdmission` in the delivery report.
The earlier cutover decision explicitly accepted six *native* admission-memory
increases and the earlier WASM review-model timing cell. Its scope is preserved;
current WASM memory costs are not silently accepted by that native decision.

The pre-cutover corpus and all 128 baseline command/reply pairs are now preserved
alongside the candidate runtime for later replay. The cumulative execution
controller checks semantic correspondence before timing and gives each runtime
its own immutable manifest and checkpoints. Its timing run remains active; no
cumulative execution cost or pass is claimed from admission results.

On September 29 the user explicitly accepted the current cumulative WASM admission
costs: the six measured peak increases of 5,880–14,614 bytes, retained increases of
4,054–12,104 bytes, and review-model timing increase of 62.7 microseconds (13.6%).
This resolves the current admission disposition recorded above for the exact
measured tuple. It does not accept cumulative execution costs or the earlier
separate package-cost decisions. The full raw measurements remain unchanged.

The cumulative inquiry runtime replay now completes with exit zero across all
13 scenarios, five paired windows each. No scenario confirms a timing slowdown
or peak-memory growth beyond the threshold. Both tuples reproduce every command's
own expected reply, after semantic correspondence was checked across all 128
boundaries. This is runtime invocation/admission/restore cost over prescribed
traces, not total host/tool latency. Full raw windows and exact manifests are in
`performance/m5-runtime-delivery.json::cumulativeReplay`. Other consumer families,
earlier cost decisions and final programme/rebinding/review closure remain open.

### Additional cumulative document/consequence consumers

The existing four consequence economy cases and all thirteen document cases now
pass on both the reconstructed original images/runtime and current images/delivered
runtime. Across their 363 captured invocation boundaries (86 consequence and 277
document), semantic effect identities, request/resume schemas, canonical payloads
and completed values agree. Existing approval, stale-evidence, uncertain-delivery,
cleanup and raw-versus-bridge assertions remain active. These captures did not
enable the optional native comparison and make no new native-equality claim.

The first candidate-document adapter omitted the explicit candidate lock on later
bridge/postflight calls and correctly failed the unchanged dependency verifier.
The corrected adapter supplies that same verified lock at every existing call;
all assertions remain unchanged. Candidate and baseline traces retain independent
image/state identities. Sources, adapters and log digests are recorded under
`additionalConsumers` in the runtime-delivery report. The 17-case cumulative
replay timing run is active; early rows are not a completed economics verdict.

The additional replay is now terminal: all 17 scenarios complete five paired
windows with no confirmed timing slowdown. Fifteen scenarios exceed cumulative
peak-memory thresholds: two consequence cases by 5,518 bytes, document cases by
6,338–7,010 bytes, and one document case by 9,332 bytes. These remain separate
from accepted admission costs. The historical M3 decision includes cumulative
document/consequence execution-memory bounds; its consolidated acceptance request
is pending and no acceptance is inferred while awaiting the reply.

All six existing review-consumer tests also pass on each tuple. The original
tests retain their authored order, malformed-reply, unknown-answer, multiple-call
and normalized model-failure assertions. Only absolute adapter paths and the
explicit candidate dependency lock differ. The installed Agent lock remains
unchanged. Exact adapters, logs and cumulative timing/memory windows are retained
in the runtime-delivery report; final package integration and P/T/G/L closure
remain open.

### Full candidate Agent package integration

The normal Agent setup succeeds in a temporary export of Agent `9a358cb` with
only its prospective lock and `build.zig.zon` Boundary pin changed. Original
setup/build/check/verifier sources match the active checkout. The installed
checkout/lock remain unchanged while this candidate is qualified.

The first aggregate correctly rejects a package-profile mismatch: the archive
extract retains mode 0644 for `tools/bitvector_search.py`, while Zig's managed
package gives it mode 0777. All 483 paths, file bytes and sizes otherwise agree.
The existing distinct `archive-extracted` and `zig-managed` inventory fields now
bind their separately observed modes; no verifier comparison is weakened. Full
source/package/runtime verification then succeeds with the managed profile.
The historical first candidate lock and observations remain separate evidence.

The corrected `check-agent4 check-agent4-integration` ReleaseSafe aggregate is
running through the ordinary package/runtime paths, including the existing
consumer tests. `performance/m5-runtime-delivery.json::fullAgentIntegration`
records its input scope and failed first attempt. No terminal aggregate pass,
installed adoption, or final programme completion is claimed yet.

That candidate aggregate is now terminal with exit 1: 401/409 build steps succeed
and all 202/202 Zig tests pass, but packaging fails with `cannot inspect Git source
identity: rev-parse HEAD`. The temporary source export does not provide the real
Git identity required by the unchanged package producer. This invalidates use of
that export as the final package-qualification route, not the package identity
requirement. No fake Git identity or weakened package check is substituted.
Package integration must continue from an actual committed candidate binding on
the existing Agent branch; the incomplete aggregate is preserved as failed.

The binding is now committed as Agent `de37343` on the existing branch. The
unchanged package producer succeeds from that real checkout using the completed
build's fixtures; its manifest reports `packagedSourceMatchesHead: true`. The
275,156-byte archive has SHA-256
`c87ddd976031c05d058d7e4c95fe0802a4aff4db0f646758df429981f8f17203`.
The unchanged integration runner is active against this committed binding.
The separate compiled-tool browser/file/browser transfer passes in Chromium
153.0.8010.12 and Firefox 155.0 with the delivered `962d621f` kernel, including
destroyed workers, file-server transfer and exactly one cleanup. These completed
checks do not relabel the earlier failed aggregate or qualify the newer P22 kernel.

P22 inspection found that `retainedBytes()` still multiplied live pages by the
now-header-only `Page` size. It now uses the existing allocated-page byte count.
An independent allocator-counting test covers dense and packed pages, a directory,
clear and both releases; all five focused activation-slot tests pass. This changes
the pending candidate's accounting and requires fresh final artifact qualification;
earlier P22 kernel evidence remains bound to its original bytes.

The corrected P22 source then passes the integrated 66-test storage suite,
87-test native suite and WASM storage check (12/12 outer steps). Its rebuilt kernel
has exactly the prior SHA-256 `c5361898...393a72`, so the same-byte canonical,
cross-engine transfer and capacity results remain applicable. This does not claim
authenticated publication of the pending source or completed timing qualification.

### Committed Agent qualification continuation and P22 costs

Agent `c931e25` is published on the existing draft #39. Its parser-package tests
now use the integration runner's existing `AGENT4_ARCHIVE` selection. The earlier
committed-checkout integration failed 5/95 tests: a GitHub fetch connection closed
in the isolated installation, and four parser callers opened an older local
archive whose lock correctly rejected the candidate runtime. A fresh Zig fetch
returns the exact expected package hash; the unchanged isolated installation then
passes. All five corrected parser CLI tests pass with the actual candidate package,
including parked resumption, EOF choices and the shared call allowance. All five
runtime commands prevented by the first failing runner also pass. The historical
aggregate remains failed; final frozen-head aggregate qualification remains open.

P22's direct native storage timing exposed repeatable overhead, including dense
controls. The revised candidate skips an impossible dense-capacity check, computes
sparse copy destinations with an ascending live-bit cursor, and uses fixed-size
allocation/deallocation for dense pages. Its dense storage overhead drops from
roughly 20–31% to 9–14% in the repeated probe; compact sparse pages retain their
measured memory benefit and explicit timing tradeoffs. These are storage-probe
observations, not whole-application speed claims.

The revised source passes 66 storage tests, 87 native tests and import-free WASM
storage checks. Kernel `e3b9aec1...da2e7ba` matches the frozen native predecessor on
237 canonical boundaries/23 transfers and passes 159 Node/Wasmtime/native transfer
boundaries plus unchanged retry-input capacity checks. Across 24 WASM blob
fresh/pause timing cells, no slowdown is confirmed. Twenty native resident cells
retain two confirmed pause increases of 41–42 ns; the shortest samples approach
the native clock's resolution and remain recorded, without inferred acceptance.
Native fresh/prepared scalar timing, full cost disposition and authenticated
changed-source delivery are still required.

The final P22 candidate is World `cb52f4f`, published on existing draft #59. Empty
prefix rank now returns zero directly; all twelve native fresh/prepared scalar
cells stay within the timing gate, correcting the earlier long prepared slowdown.
The final 24-cell WASM fresh/pause comparison confirms neither timing slowdown nor
peak-memory growth. Four direct native storage cells retain 10–83 ns increases
(6.1–8.0%); two resident pause cells retain approximately 41 ns increases (10.9%).
An explicit decision for those six cells is pending. This neither accepts nor
supersedes separate historical package cost decisions.

The final 18-case storage probe independently checks values and allocator balance,
and reports retained bytes, peak page bytes and actual predecessor copies. At 64
branches, 1/2/4/8 live-value cases save 23,040/21,504/18,432/12,288 page bytes;
9/16-value dense controls use the original bytes. Every 64-branch case avoids 64
copies of descriptors that are immediately overwritten. The 24-byte native Slots
owner increase remains a separate observation from heap savings.

Boundary's new retained-view test initially assumed that physical isolation must
increase descriptor copies. With an overwrite-only packed successor, all prior,
current and checkpoint values pass while that traffic proxy fails. The test now
checks exactly one additional live backing page and preserves every independent
value and checkpoint assertion. All three packing tests pass against both the
final World source and preserved `e89b94a` baseline; failed and corrected results
remain distinct in the physical report. This is an integration repair for P22,
not additional authoring scope.

Final kernel `9356b126...df1338d` passes the integrated 66 storage/87 native tests,
WASM storage, 237 canonical boundaries/23 transfers, 159 cross-engine transfer
boundaries and unchanged-input capacity retries. Authenticated producer run
`36629384504` is active on exactly `cb52f4f`; no delivered-artifact result is claimed
before its terminal result and verified acquisition.

### Requirement reconciliation: G43 and G45

All three Python reference blocks extracted from the accepted attachment execute
with their stated counts. Annex A checks 4,330 exhaustive graphs and 500 seeded
graphs; Annex B checks 69,904 XOR inputs, 19,683 action associativity cases and
7,736 toy quantum cases; Annex C reproduces 78,804 independent transitions and
its other recorded counts. Exact source hashes and complete results are retained
in `performance/m5-runtime-delivery.json::referenceModels`. These results prove
only their finite-model claims and receive no production-performance credit.

G43 inspection found that semantic error translation already removed stale source
indices but did not explicitly mark the unavailable origin set as ambiguous.
The local correction sets that existing marker. An admitted source undergoes real
semantic changes, then fails its hard image limit; the test requires no fabricated
function/variable identity and explicit ambiguity, and checks that a subsequent
success clears the diagnostic. The exact ambiguity assertion fails before the
correction and passes afterward. The 226-test authoring aggregate also passes.
Coalescing's existing many-origin/projection tests remain the independent evidence
for its own original-input maps. This diagnostic correction adds no authoring
uniformity prerequisite and does not change successful program bytes.

The active environment now allows writes only in Boundary and temporary folders;
Git metadata, Agent and World are read-only. The diagnostic successor is local and
unpublished. Agent `52059f6` remains committed with Boundary `5619ee8` and delivered
World `cb52f4f`; its original aggregate has no terminal summary available and its
tool process handle is missing. No restart, terminal pass, successor package
binding or review completion is inferred. Requirement reconciliation and the
remaining historical cost decisions stay open.

### Requirement reconciliation: G34, G41 and the concrete prefix defect

G34 now varies eight deterministically generated hash seeds inside the private
schema-partition test implementation, alongside forced all-hash collision and
the independent pairwise reference. All 12 focused tests pass. The public entry
still fixes seed zero; no runtime option or alternate optimization policy exists.

G41 now has one combined executable-record witness. Two capture-dependent branches
are removed, two applications become direct calls, three formerly captured worker
arguments become removable, and final P01 shares the newly equal workers. Omitting
branch pruning, application specialization or argument removal prevents its named
contribution; P01's admitted baseline has three functions and its selected result
has two. The first fixture's unequal layouts correctly prevented structural
sharing; the retained fixture gives the workers compatible layouts without
weakening P01. Six native variants preserve three independently expected results.
Original/staged/shared images are 197/113/106 bytes. Nine Node/WASM cases preserve
their results across 72 quantum-one boundaries, restoring each checkpoint in a
fresh instance. The retained emitter and harness are
`test/v2/optimization_interaction_emit.zig` and `test/optimization_interaction.mjs`.

The continuing Agent aggregate's partial log identifies a concrete integration
failure: `parser_source_free.mjs` reads its archive, link-only executable and object
fixtures from `source/zig-out`, although this run uses a different install prefix.
The old archive's lock correctly rejects the selected runtime. The necessary
repair passes the build-selected prefix to this script, reads those three artifact
inputs there, and extends its source-denial checks to that canonical prefix.
The exact patch is prepared and syntax-checked at
`/tmp/agent-prefix-repair/repair.patch`; it is not applied because Agent is read-only.
This closes a named qualification dependency, not another authoring migration.
No aggregate success or executed repair qualification is claimed.

The current local data aggregate is terminal and passes **536/536 tests, 3/3
steps** after the private seed variation. The G43 authoring aggregate passes
226/226; G41's retained native and WASM harnesses pass. These are the available
local successor checks, not proof of a published final tuple. Further execution
is blocked at the prepared Agent prefix repair and publication/rebinding: the
current profile makes the owning repository and Git metadata read-only and
disables approval escalation. Preserve the existing branches, local changes,
qualified bundles and prepared patch when restoring access. The full programme,
unanswered historical cost dispositions and installed final reviews remain open.

Access was subsequently restored by the user. The original Agent aggregate is
now terminal: 406/411 steps succeeded, 202/202 Zig tests and 95/95 Node tests
passed, with one failed install-prefix step. The prepared repair is applied to
the existing Agent branch and its focused source-denial check is running. No
aggregate pass is inferred from the successful test subsets.

### Final authenticated tuple and terminal consumer qualification

Agent `cbf1d47` binds Boundary `9912ffb` and authenticated World `cb52f4f`
(kernel `9356b126`). The applied prefix repair passes its source-denial proof.
The final ReleaseSafe `check-agent4 check-agent4-integration
check-compiled-tool-browser` aggregate terminates successfully: **411/411 steps,
202/202 Zig tests and 95/95 final Node tests, no skips**. This is a new passing
aggregate; the previous prefix-failing aggregate remains failed.

All six final consumer timing runs also terminate successfully. The 18 local
admission and 30 local replay comparisons have no confirmed slowdown or memory
increase. Cumulative replay has no confirmed fresh-invocation slowdown in the
30 scenarios. The six cumulative admission-memory increases exactly match the
previously accepted before/after values; review-model admission now measures
+63.374 µs (13.83%), compared with the earlier accepted approximately +62.7 µs
(13.6%). The local comparison confirms no additional runtime slowdown.

Fifteen cumulative document/consequence execution-memory threshold increases,
up to 9,332 bytes, remain within the pending historical M3 cost decision. Neither
permissions restoration nor acceptance of P22's separate six cells accepts them.
The complete six-run samples, identity bindings, commands and dispositions are
retained in `performance/m5-runtime-delivery.json` under `resumedFinalTuple.timing`.
Historical M3/P13/P16/P18/P19/P20/P24 cost dispositions and final installed serial
reviews remain open. No merge, release or final programme completion is claimed.
