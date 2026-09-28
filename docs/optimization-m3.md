# M3 — Specialization, joins, and global control

Continue P06–P10 and P21 on Boundary #161 and the existing consumer drafts.
M2.5's bounded checkpoint is qualified; all remaining programme requirements
and final-review scheduling remain unchanged.

## P06 first production slice

`partial_redundancy.zig` performs latest placement of total unsigned word
bitwise expressions and unsigned-word equality at a join's first instruction.
At least one incoming path must already compute the expression. Availability
is currently local to an immediate predecessor; entry-position demand proves
that the original expression must execute on every selected edge into the join.
Pure functions with identical lexical custody are required. This is a bounded
fragment, not general global PRE or speculative code motion.

An available value is passed through a simultaneous edge assignment. A missing
value is computed at the end of an unconditional assignment-free predecessor,
or in a new block reached only by the selected incoming edge. Original parallel
assignments occur before the inserted expression. Other successors, including
early returns, retain their original instructions and edges.

The checker does not trust the reverse invalidation used by discovery. It
reconstructs operand and result versions by a forward scan, applies edge
assignments from the predecessor view, checks definite availability, enumerates
every original incoming edge, and compares all changed/unchanged records.
Original and candidate admission, bounded work rollback and final P01 remain
mandatory. Wrong reused operands, stale mutable operands, omitted paths and an
admissible speculative early-path evaluation are rejected. Allocation failures
release temporary owners.

## Selection and witnesses

The existing static instruction sum cannot value a partial redundancy whose
static expression count stays constant. The shared candidate portfolio now also
uses a bounded entry-path work estimate. Known direct callees are expanded;
applications retain the opaque dispatch weight. Cyclic call/control graphs or
paths deeper than 512 yield unknown rather than a fabricated finite bound.
The metric is a heuristic, not a whole-program runtime
bound. Image/admission guards and independent transformation acceptance remain.

The default semantic pipeline selects a live comparison diamond whose arm result
also controls a branch, preventing prior dead-code removal from erasing the
opportunity. Source-free closed linking selects the same transformation.
Independent record execution counts and native World outputs cover both branch
choices and several input pairs. The critical-edge witness changes expression
evaluations 2→1 on the reuse path, 1→1 on the missing-definition path, and 0→0 on
the early-return path. These are path-specific evaluations, not a claimed speedup.

Focused tests, the data aggregate and native execution have passed for the initial
slice. Final proof counts and remaining qualification are recorded with delivery.
Broader placement, platform/economic
qualification, P09 specialization/inlining, P10 contification and P21 remain open.
No new branch, PR, persistence infrastructure or intermediate review gate is added.

Initial terminal results: **41/41 focused tests**, **3/3 data steps and 306/306
tests** before the last mutation-only addition, and **2/2 native World tests**.
The focused result covers that addition. `performance/m3-pre-initial.json`
records exact scope and raw-log identities. No full M3 or performance acceptance
is claimed.

## P06 ownership, platform and costs

The dedicated region-owner witness is now separately admitted. One predecessor
has no cell owner before the join creates it; PRE leaves the read in place, and
a forged read on that predecessor fails original ownership admission. The
focused suite passes **42/42 tests**. Full ReleaseSafe validation completes
**319/319 steps and 592/592 tests**.

Production Node/WASM and independent Wasmtime pass **72 comparisons** over the
checked critical-edge, shared-pipeline and source-free linked images. Three
same-image restores, three wrong-image rejections and six malformed-input
rejections pass. The checked-pass route is explicitly distinguished from
shared-pipeline selection.

The frozen 15c5356 semantic compiler supplies the cost control; 77892fb supplies
the candidate. All 14 paired admission/fresh/cycle comparisons completed. One
confirmed increase remains: WASM admission +1.54 microseconds (7.4%), pending
explicit user acceptance under §9.5. No fresh invocation or complete
checkpoint/restore-cycle slowdown was confirmed. Native invocation peak grows
98 bytes; WASM cycle peak falls on reuse/early paths and grows 102 bytes on the
missing-definition path. Admission/retention increases remain under 1 KiB;
maximum checkpoints do not grow. These are bounded fixture measurements, not
a general speedup claim. Exact identities and raw windows are retained in
`performance/m3-pre-platform.json`, `m3-pre-timing.json` and `m3-pre-memory.json`.

Remaining P09/P10/P21 work and the full later programme remain mandatory.

## P09 repeated closed-callable workers — in flight

`call_patterns.zig` specializes a private function's reusable callable parameter
when every use is an application and the constructor has no runtime captures.
The constructor body must be a closed leaf; recursive generic functions and
escaping or overwritten parameters are declined. Three caller sites in the
witness share two workers, with four static applications rewritten to direct
calls (two per invocation). Worker arguments preserve their original order.

Keys bind the full program epoch, generic function, parameter, schema and nominal
constructor identity. The independent checker rederives each caller's constructor
origin, checks every clone and call substitution, and preserves custody and
public/handler authority. Variant, block, byte and work bounds roll back to P01.
Final P01's existing reference-closure projection retires an unreferenced generic
implementation; generic fallbacks remain when a caller's constructor is unknown.

The shared semantic compile and source-free closed-link paths select the worker
candidate. Native World checks cover 48 executions across original, checked-pass,
shared-pipeline and linked programs. The integrated ReleaseSafe run completed
319/319 steps and 606/606 tests before the subsequent retirement assertions.
The worker-only platform run passes 72 Node/WASM–Wasmtime comparisons, three
same-image restores, three wrong-image rejections and six malformed inputs.
Paired economics exposed admission and fresh-invocation regressions; those
unaccepted results are retained in `performance/m3-p09-workers-*.json`.

## P09 selective leaf inlining

The measured worker overhead and P09's required product-cancellation witness
select a separate checked substitution inside the shared data-only pipeline.
The owner is `leaf_inlining.zig`; callers retain the existing semantic compile
and final-link APIs. This ordinary construction preserves the current admission,
nominal authority, custody and final-P01 boundaries. It does not alter World.

For a small single-block pure leaf, arguments name the caller's existing values;
each callee instruction writes a fresh caller destination. The checker traces
each operand backwards to its last original callee definition or ordered input,
independently of the emitter's forward map. Returned values replace only the
returned sources of the original simultaneous continuation assignment. Other
caller slots, evaluations and transfers remain unchanged. Mutable callee inputs
therefore cannot overwrite the caller. Handler/resource authority, noncopyable
values, regions, nested custody, effects and non-leaf recursion remain outside
this initial fragment. Site, instruction, byte and work bounds constrain growth.

The shared pipeline now exposes a product/projection pair and removes both via
the existing aggregate and dead-computation passes. Independent wrong-field and
wrong-return mutations reject; allocation failure, parameter overwrites,
simultaneous transfers and recursive refusal have focused coverage. Native World
passes 60 executions across the repeated-callable and two leaf witnesses. The
updated repeated-callable platform run again passes all 72 comparisons and the
restore/rejection checks. Final integrated ReleaseSafe validation completes
319/319 steps and 614/614 tests; focused leaf validation passes 39/39 tests.

Fourteen fresh paired timing cells compare the combined candidate with frozen
c34f7be. Admission peak increases are now 248 bytes native and 216 bytes WASM;
retained storage increases are 162 and 114 bytes. No admission or complete-cycle
slowdown is confirmed. One WASM fresh-complement cell remains +2.44 microseconds
(6.8%) and is not accepted. Raw samples and exact image/emitter/source identities
are in `performance/m3-p09-leaf-*.json`; these do not establish whole-consumer
qualification or a general speedup.

The other required specialization facts remain open, as do the rest of
P09/P10/P21 and the full programme. Final code reviews remain deferred under
the user's scheduling correction.

## P09 known-variant payload workers

The worker owner and independent substitution boundary are retained. The static
key now distinguishes a constructor identity from a variant tag, while preserving
the full program epoch, function, parameter and exact schema. This extends the
private worker ABI to accept the runtime payload directly; payload values never
enter the static key. Existing callers of the shared compiler and final linker
need no new API or sequencing.

Forward definition versions discover a local variant construction whose payload
is still available. The checker independently scans raw instructions backwards
through aliases and rejects an overwritten payload. A copyable/droppable sum
parameter may be used only for matching payload projections and selected-tag
switches, without overwrites, escape or authority-sensitive uses. Matching
projections become moves; selected switches become exact predecessor-view edges.
Different tags, unknown origins, unmatched projections and privileged entries
retain their generic implementation. Original evaluation and admission still
precede the rewrite; fresh candidate admission and final P01 remain mandatory.

Two caller sites with different payload values reuse one worker. A separately
admitted wrong-payload mutation rejects even when its site witness is also forged;
wrong tag, schema and switch-target mutations reject. The original failing-tag
fallback and a payload overwritten after construction retain their behavior.
Native World passes 204 executions over the cumulative P09 fixtures, including
144 variant executions through original, checked, shared and source-free linked
records. Variant platform qualification passes 216 comparisons, nine same-image
restores, nine wrong-image rejections and eighteen malformed inputs. Final
ReleaseSafe validation passes 319/319 steps and 621/621 tests; focused variant
validation passes 38/38 tests.

The total selected variant witness shrinks from 136 to 110 image bytes; the
failure-bearing witness shrinks from 137 to 133. Fourteen paired timing cells
against published ba87362 complete without a confirmed slowdown. Native/WASM
admission peak falls 382/406 bytes and retained storage falls 1190/74 bytes.
Fresh invocation peak falls 1482 bytes native and 347 bytes WASM. Checkpoint
maxima fall from 86 to 82 bytes on the first path and remain 104 on the other two.
These results are specific to this fixture; raw windows and identities are in
`performance/m3-p09-variant-*.json`.

All six repeated-callable images remain byte-identical to the preceding leaf
checkpoint. Its unresolved 6.8% WASM cost is preserved, not reclassified as a win
from the separate variant fixture. Broader constant/schema/evidence specializations,
recursive generalization, cumulative consumer qualification and later programme
requirements remain open. This is not full P09 or M3 closure.

## P09 proved Boolean branch arguments

The same specialization key now carries a proved Boolean value. This first
constant slice removes a read-only Boolean parameter used to choose private
branches, substitutes the exact selected edges in each worker, and preserves
the order of every remaining argument. Unknown inputs retain the generic worker.
Instructions and unrelated branches remain unchanged; parameter overwrites,
escapes and privileged entries remain ineligible. No runtime observation is
promoted into a static constant.

Forward facts discover the constant; the independent backwards origin checker
must prove the same value at every rewritten call. The full program epoch and
exact schema remain part of the key. Wrong selected edges, forged Boolean values
and changed constant bytes reject. Growth/work exhaustion returns the mandatory
P01 baseline, and allocation-failure coverage checks temporary ownership.

The shared pipeline selects the constant-worker candidate and leaves only the
host-selected branch in its witness. Native World covers both Boolean values
and an unknown-argument fallback through original, checked, semantic and
source-free linked programs. The cumulative native suite now passes 300
executions. Other scalar constants, schema/evidence specializations and recursive
generalization remain open; this slice does not narrow the full P09 obligation.

Platform validation adds 72 cross-engine comparisons, three same-image restores,
three wrong-image rejections and six malformed inputs. Final ReleaseSafe
validation passes 319/319 steps and 627/627 tests; focused constant validation
passes 37/37 tests. Ten paired timing cells
against 824a01b complete without a confirmed slowdown. The selected image is
102 bytes versus 129 for the structural fixture. Native/WASM admission peak
falls 388/1032 bytes, retained storage falls 1486/1230 bytes, and fresh invocation
peak falls 1510/1372 bytes. Maximum checkpoints fall from 104 to 82 bytes on
both paths. Raw observations and source/image/tool identities are retained in
`performance/m3-p09-constant-*.json`.

Twenty-four previously qualified callable and variant images remain byte-identical.
Their existing evidence is reused only for those exact inputs and the unchanged
runtime; the earlier unaccepted costs remain unresolved.

## P09 unsigned literals and proof-availability repair

Unsigned u8/u16/u32/u64 parameters can now be removed from a private worker's
interface when their exact value is proved and a matching schema-specific literal
already exists in the original catalog. The worker initializes the old parameter
slot at entry, then preserves the original instructions and failure mappings.
Parameter overwrites and recursive calls remain outside this fragment. A second
existing branch-reduction step consumes the exposed constant comparisons; it
does not rely on stale pre-specialization facts. No new literal pool or evaluator
is introduced. The cheap opportunity filter now requires an actual private call.

A regression test also exposed a concrete proof-availability gap: forward facts
could infer a Boolean through `select`, while the backwards prover could not
certify it. The old standalone pass returned `InvalidCallPattern` for that valid
program. Discovery now checks proof availability before constructing a worker,
retains unsupported calls, and rolls back on proof-budget exhaustion. The final
independent validator still rederives every proof and rejects wrong candidates.
The regression covers both standalone and shared semantic compilation.

Width-specific literals, wrong literal initialization, an out-of-width forged
certificate, unknown arguments and allocation failures have focused coverage.
Native World now passes 420 cumulative executions, including four scalar widths
and a division-by-zero path that must fail before the subsequent comparison.
Original, checked, semantic and source-free linked records agree. Final
ReleaseSafe validation passes 319/319 steps and 635/635 tests; focused word
validation passes 38/38 tests.

The new u64 fixture passes 36 cross-engine comparisons, three same-image restores,
three wrong-image rejections and six malformed inputs. Ten paired timing cells
against 2551b63 complete without a confirmed slowdown. Admission peak changes
by +524 bytes native and -370 bytes WASM; retained storage grows 184/156 bytes;
fresh invocation peak grows 184/111 bytes. These increases remain below 1 KiB.
Maximum checkpoints fall from 104 to 82 bytes on both paths. Raw observations,
the failed/passing proof-gap witness and exact identities are retained in
`performance/m3-p09-word-*.json`.

Thirty earlier callable, variant and Boolean images remain byte-identical. Their
proofs and outstanding cost decisions retain their original inputs. Broader
schema/evidence and recursive-specialization obligations remain explicit; this
does not close P09, M3 or the full programme.

## P10 shared local joins — first nonrecursive slice

`contification.zig` owns the call-to-edge rewrite. A private helper whose raw
callers all belong to one function and share an identical continuation is moved
once into that caller. Ordered arguments enter fresh, disjoint local slots by
simultaneous assignment; internal edges and returns preserve their source views.
Original caller instructions remain unchanged. Independent validation enumerates
the original callers and checks the complete slot, block, custody, instruction
and return correspondence. Final P01 retires the now-unreferenced helper.

This first domain requires non-suspending pure code, one custody scope and
copyable/droppable exportable values. Constructor-addressable helpers, differing
continuations, nested custody and suspension retain their original calls. The
two-predecessor witness keeps one product-building body and exercises both
incoming argument order and a simultaneous internal swap. Wrong argument, swap
and return mappings reject even when independently admissible. Allocation and
work/block/slot/byte bounds preserve deterministic P01 rollback.

Leaf inlining precedes join conversion so the existing local product-cancellation
witness remains available. Of 36 preceding P09 images, 34 remain byte-identical;
the shared and linked Boolean images change and receive fresh qualification.

### Return transitions and measured correction

Initial emission replaced every helper return with a jump to the caller's
continuation. For an empty return-only continuation this added one logical
transition: the shared-join fixture went from five to six quantum-one invocations.
Native/WASM complete checkpoint cycles regressed about 20–31%; the affected
Boolean fixture regressed about 28–30%. The raw rejected observations and exact
inputs remain in `performance/m3-p10-initial-costs.json`.

The retained construction directly returns the value selected by a proved empty
return-only continuation. The checker independently reconstructs whether this is
the helper result or an original caller value. Continuations containing real
work retain their explicit transfers; an attempted bypass is a negative witness.
This removes the added transition without changing World or inventing an opcode.

Both image groups pass 72 cross-engine comparisons each, with six total same-image
restores, six wrong-image rejections and twelve malformed-input rejections. The
shared-join native witness passes 48 executions, and the prior native P09 suite
passes another 420 on the new source. Final ReleaseSafe validation completes
319/319 steps and 644/644 tests; focused join validation passes 40/40 tests.
All 28 paired timing cells against
c5da88e complete without confirmed slowdown after the correction. Shared-join
transitions are again five; checkpoint maxima remain 104 bytes. Native/WASM
admission peak falls 536/64 bytes; retained storage changes -38/+42 bytes and
fresh invocation peak changes -38/+24 bytes. The changed Boolean fixture improves
admission, retention and invocation memory, with unchanged 82-byte checkpoints.
Final evidence is in `performance/m3-p10-{platform,timing,memory}.json`.

The required mutually recursive eligible pair and additional escaping/retained
control witnesses remain open. This slice does not close P10 or M3. P09 residuals,
P21, cumulative consumer qualification and the full later programme remain in scope;
the earlier P06 and repeated-callable cost decisions are not waived by these gains.

## P10 mutually recursive tail groups

The same owner now discovers direct-call strongly connected components with an
iterative, work-bounded graph walk. It replaces the single-helper restriction.
Every member must remain private and in the pure, non-suspending domain; every
internal call must have an empty continuation returning the callee result.
External calls must still share one caller and continuation. Validation rebuilds
the complete use census and certifies a closed tail-call group independently of
the discovery graph. Non-tail work, omitted members, escaping constructor entries
and wrong recursive targets reject.

Equal-schema helper layouts share a caller-local slot bank. Identity tail returns
leave no previous helper values observable, and internal control values are
excluded; parallel argument transfer preserves swaps at the handoff. Caller slots
remain disjoint. Unequal layouts retain separate banks. This is a bounded logical
slot-reuse case, not general physical packing or completion of P22.

The initial separate-bank candidate passed correspondence but failed the existing
admission-growth guard. Sharing equal layouts allowed production selection without
weakening that guard. Initial emission still carried redundant identity transfers
and showed two fresh WASM slowdowns (7.8% and 32.6%); those measurements remain in
`performance/m3-p10-recursive-initial-timing.json`. Removing only identity transfers
preserved real swaps and cleared both measured regressions on the same inputs.

The positive fixture executes A → B → A before returning, through original,
checked, shared and source-free linked records. A separate cyclic near-example
remains progressed after a bounded execution prefix; this is finite-prefix
evidence, with the control mapping supplying the divergence argument. The native
join suite passes 96 completed executions and two nonterminating prefixes.
Focused recursive validation passes 39/39 tests. Final ReleaseSafe validation
passes 319/319 steps and 652/652 tests. Platform checks pass 72
cross-engine comparisons, three same-image restores, three wrong-image rejections
and six malformed inputs.

All 18 final paired timing comparisons against 592a375 complete without confirmed
slowdown. Native/WASM admission peak falls 1486/928 bytes, retained storage falls
874/790 bytes, and invocation peak falls 874/840 bytes. Checkpoint maxima remain
104 bytes. Forty-two earlier images are byte-identical. Exact evidence and the
initial guard rejection are in `performance/m3-p10-recursive-*.json`.

The required mutually recursive positive case is implemented. Additional concrete
escaping/handler-retention witnesses, P09 residuals, P21, full consumer qualification
and the remaining programme stay open; this is not full M3 closure.

## P10 first-class escape witnesses

The concrete negative corpus now includes a helper returned by a factory as a
computation value, then applied, and a captured value retained by a deep handler
while its body yields. Both originals pass independent admission. Contification
declines them and returns the exact mandatory-P01 baseline. Native execution
preserves the returned helper's result and restores/resumes the handler-held
capture on the same image. These strengthen the existing constructor-addressability,
different-continuation, custody and suspension exclusions.

## P21 common tails — initial slice

`common_tails.zig` shares identical complete tails within one function and
custody scope. It redirects every selected edge and function entry, preserving
instructions, operands, assignments, constants and failure payloads. When both
branch edges become identical, the branch becomes one jump; condition-producing
instructions remain until separately validated dead-computation elimination.
Original and fresh candidate admission, a raw correspondence checker and final
P01 remain mandatory. Record-comparison work is charged before traversal.

The initial domain uses copyable/droppable exportable values and functions without
effects, declared regions or call/suspension/control-handler operations. It does
not merge across authority boundaries or reinterpret layout slots. Tests show P01
alone retains the distinct local blocks: this transformation remains outside
P01's local-bijection contract. Different custody and failure payloads, forged
targets and altered instructions reject; allocation and work-limit rollback pass.
A preceding division-by-zero computation still fails before the shared tail.

The shared semantic compiler selects the new candidate, and native World checks
original, checked, semantic and source-free linked outputs. Existing source-level
empty-jump threading is unchanged. Tail duplication, outlining and their remaining
P21 obligations stay open; this is not full P21 or M3 closure.

The new fixture passes 36 cross-engine comparisons, three same-image restores,
three wrong-image rejections and six malformed inputs. Ten paired timing cells
against f436f7e complete without confirmed slowdown. Native/WASM admission peak
falls 444/758 bytes, retained storage falls 232/484 bytes and invocation peak
falls 232/494 bytes. Checkpoint maxima remain 82 bytes. Forty-eight earlier
images remain byte-identical. Raw observations are retained in
`performance/m3-p21-tails-*.json`. Final ReleaseSafe validation passes
319/319 steps and 660/660 tests; the new native tail suite covers 48 executions,
including the preserved preceding failure.

## P21 bounded tail duplication

`tail_duplication.zig` copies a small shared branch tail for an incoming jump only
when the original edge establishes an independently proved Boolean condition.
The tail must keep that condition unchanged and remain in the predecessor's
function and custody. Incoming simultaneous assignments are preserved verbatim.
The checker rederives the condition, checks every original record and exact copy,
and rejects added instructions or extra execution. Original admission and fresh
candidate admission remain mandatory.

Copies immediately feed the existing branch reducer with fresh facts and its
independent origin proof, before common-tail sharing runs. The known branches are
therefore consumed without a duplication/sharing cycle. Copy count, instruction
count, added bytes and work are bounded; exhaustion retains the mandatory P01
baseline. Unknown/overwritten conditions and mismatched custody decline.

The region-cell witness inverts a live cell once on either path. A separately
admitted mutant performing that mutation twice rejects. Native World compares
the original, checked, shared and source-free linked records for both this effectful
witness and the constant-branch witness. Outlining and remaining P21 obligations
stay open; this is not full P21 or M3 closure.

The duplication fixture passes 36 cross-engine comparisons, three same-image
restores, three wrong-image rejections and six malformed inputs. Ten paired
timing comparisons against d23d16a complete without confirmed slowdown. Admission
peak grows 340 bytes native and 184 bytes WASM; retained storage grows 100/76 bytes
and invocation peak grows 100/67 bytes. These increases remain below 1 KiB.
Maximum checkpoints fall from 104 to 82 bytes on both paths. Raw observations
are retained in `performance/m3-p21-dup-*.json`.
Fifty-four earlier images remain byte-identical; their existing runtime evidence
and unresolved cost dispositions retain their original subjects.

Final duplication qualification: 319/319 ReleaseSafe steps and 667/667 tests;
38 focused tests and 48 native executions pass.

## P21 pure-sequence outlining

`outlining.zig` normalizes repeated straight-line return sequences by their actual
input and definition order, then creates one fresh private worker. Each original
site calls that worker with its ordered live inputs and returns the same result.
The independent checker reconstructs the substitution from original definitions,
checks every unchanged record and continuation, and forbids redirects to existing
handler authority. The first fragment is single-assignment, total scalar code with
copyable/exportable values, one custody scope and no effects or regions.

Sequences must exceed the existing eight-instruction leaf-inlining fragment;
outlining runs after shrinking passes. A second semantic compilation is required
to preserve the selected image, guarding against inline/outline oscillation. Exact
mandatory-P01 image sizes reject nonshrinking candidates. Original/fresh admission,
allocation cleanup and work/site bounds remain intact.

The selected witness shares a 25-instruction sequence at two sites. It introduces
two static call sites and one dynamic call per invocation. Native execution passes
24 original/checked/semantic/source-free cases. Platform checks pass 72 cross-engine
comparisons, three same-image restores, three wrong-image rejections and six
malformed inputs. All ten paired timing cells against dd6fec5 complete without a
confirmed slowdown, despite transitions increasing from 27 to 28.

Native/WASM admission peak falls 2808/4670 bytes and retained storage falls
2726/3604 bytes. Invocation peak falls 2673–2754 bytes native and 3523–3830 bytes
WASM, while checkpoint maxima remain 93 bytes. These are fixture-specific measured
tradeoffs, not an inference from image size. Exact evidence is retained in
`performance/m3-p21-outline-*.json`. Full consumer qualification and remaining
programme obligations are still open.

Final outlining qualification: 319/319 ReleaseSafe steps and 673/673 tests;
37 focused tests and 24 native executions pass. Sixty prior images are byte-identical.

## P09 runtime capture arguments

Known reusable callables may now specialize with copyable/droppable runtime
captures, provided they have no owned/borrowed regions and the existing private
leaf/effect restrictions hold. The worker key remains the program epoch,
constructor, schema and parameter—not captured values. Fresh worker inputs carry
capture fields in descriptor order; each direct application passes those fields
before its explicit arguments.

Discovery follows local construction versions and requires each captured operand
to remain available at the call. The independent checker traces the original
construction and later writes, checks the appended layout and every capture/argument
position, and rejects forged capture order even when its site witness is also
changed. Unavailable or overwritten captures retain the original closure.

The earlier runtime-capture test is strengthened from expecting conservative
refusal to requiring one shared static worker with different runtime arguments.
A two-field witness distinguishes capture order in its output; native execution
also verifies the original captured value after a source slot is overwritten.
Original capture admission and nominal/ownership distinctions remain unchanged.

The first capture now reuses the original callable slot, whose only permitted
uses have all become direct calls; later capture fields append slots. This removes
one unnecessary layout entry, but does not close the measured cost gate. The
updated fixture has confirmed native admission +1.40 microseconds (19.1%), native
fresh invocation +0.75–0.92 microseconds (6.9–8.7%), and WASM admission +4.89
microseconds (19.2%). WASM admission/retained/checkpoint-cycle peaks grow
1538/1070/1086 bytes. These costs await explicit §9.5 acceptance or correction.
Checkpoint maxima fall from 158 to 115 bytes on captured paths, and no complete
cycle slowdown is confirmed. Initial and retained measurements are kept separate.

Capture correctness qualification: 319/319 ReleaseSafe steps and 678/678 tests;
48 focused tests, 516 cumulative native executions, 72 cross-engine comparisons,
three same-image restores, three wrong-image rejections and six malformed inputs
pass. All 66 preceding images remain byte-identical. Performance acceptance is pending.

## P22 activation-local logical slot packing

Inspection of the capture fixture found only one completely unreferenced layout
entry. The retained correction therefore packs disjoint live ranges, rather than
launching an unused-slot cleanup. `slot_packing.zig` derives interference from
original admission/liveness, instruction writes and parallel edge transfers.
Inputs remain distinct, ordered and reserved; only instruction temporaries share
their storage. Merged slots require exact schema identity.
The independent checker rederives live-state/write constraints and checks every
instruction, edge, input and schema mapping without trusting the discovery graph.

The first domain is pure, non-suspending, one-custody, copyable/exportable code
without calls, owned regions or internal state. Unreachable edge destinations
still remain distinct. The existing selective source slot-order pass is unchanged;
this pass runs only under the semantic compiler contract and retains P01. It does
not alter World backing storage or reinterpret existing saved images.

Witnesses cover disjoint temporary reuse, an admissible bad interference map,
parallel swaps around 63/64/65/66 slots, suspension/internal-state exclusion,
allocation/work limits and a stable compiler fixed point. Native execution checks
the original, packed, compiled and source-free linked images at every quantum-one
checkpoint, preserving results and transition counts. General retained-activation
and physical-packing cases remain outside this initial fragment.

Initial aggressive coloring reused input slots and retained mapped identity
transfers. Removing identities preserved real swaps, but recursive and outlining
fixtures still showed regressions. Those attempts remain separately recorded.
The retained policy reserves input storage and packs only temporaries; targeted
reruns clear those two families' measured regressions. This follows the supplied
warning that fewer slots alone do not establish a runtime improvement.

The user explicitly accepts the bounded input-preserving candidate costs under
§9.5: cumulative captured-callable admission +1.06 microseconds native (14.5%)
and +3.11 microseconds WASM (12.7%); WASM admission/retained/checkpoint-cycle
memory +1500/+1032/+1043 bytes; and one recursive fresh WASM path +3.34 microseconds
(10.8%) in the final matrix, despite an earlier targeted run not confirming it.
This supersedes the earlier capture-cost question, not other unrelated cost gates.

Final qualification passes 319/319 ReleaseSafe steps and 686/686 tests, 46 focused
packing tests, 84 applicability tests, 756 cross-engine comparisons and 36 native
checkpointed cases, including saves/restores midway through a loop. The final local
cost matrix contains 104 measured cells; byte-identical tails/duplication images
reuse their exact evidence. Initial rejected allocation policies and the retained
policy are separate in `performance/m3-p22-*.json`. Full consumer/package and
remaining programme qualification stay open.

## Consumer work-budget correction (qualification in progress)

The first M3 consumer rebind at `fd2cb6f` preserved behavior but exhausted the
semantic work allowance on all three inquiry applications. Whole-attempt rollback
selected the P01 baseline; ReAct consequently grew from 40,966 to 49,604 bytes
and increased WASM admission peak by 482,052 bytes. These costs are not covered
by the user's earlier synthetic-cost acceptance.

The correction removes nested slot/argument and slot/edge-assignment scans from
P02 propagation, while preserving reads from the simultaneous predecessor state.
A 96-slot rotation is checked against independent backward proofs within 1,500
work units; ordered call transfer is checked within 2,500. Explicit tiny limits
still fail. Dead-computation discovery now enumerates explicit edge sources,
since admitted liveness already contains control operands, instead of scanning
every layout slot against each terminator. Its driver reserves each shrinking
round before execution and charges attempted rounds. Exhaustion discards partial
results and returns the original P01 baseline; zero-round invalid input still
fails original admission.

M3 stage reservations now distinguish whole-record scans from separately bounded
instruction search/proof phases. Call-pattern preflight excludes control forms
that its existing eligibility checker cannot specialize. The rejected experiment
of seeding all discovery from the independent shrinking candidate passed focused
tests but did not resolve the consumer exhaustion; it is not retained.

The initial policy of preserving the old numeric default was an implementation
assumption, not a numeric requirement of §7.4. The prospective semantic default is
400 billion conservative construction-work units for the expanded four-round
schedule, up from 100 billion. P09 defaults to P02's ten-million-unit allowance
for each of its five bounded phases; all five are reserved. Explicit caller
limits still cap their phases, and P01's limits, exact selection and rollback
are unchanged. This is an increased compiler construction allowance, not a World
performance exemption. Full corpus, source/package and runtime qualification
remain required before this correction is accepted or published.

The corrected corpus completes all 18 compilations with no `work_limit` outcome.
Repair and repeated inquiry consume 86.7/88.0 billion reserved units and ReAct
166.1 billion, each converging in two rounds. ReAct emits 41,021 bytes, compared
with 49,604 from the rejected rollback candidate and 40,966 at M2.5. Its native
admission/retained increases versus M2.5 are 3,994/3,384 bytes; WASM increases are
3,192/2,062 bytes. These measured residuals are not accepted by the earlier P22
synthetic-cost decision. Fresh inquiry/ReAct (13 cases) and repeated inquiry
(four epochs, 28 prescribed model responses, four experiments, eight cleanups)
pass native/WASM/Wasmtime comparisons. The other 15 corpus images match the
initial M3 candidate exactly. Integrated validation and remaining economics are
still pending; `performance/m3-work-accounting.json` preserves attempt attribution.

The final integrated ReleaseSafe command completed with exit 0: 319/319 steps
and 689/689 tests. Consumer timing, execution/checkpoint memory and authenticated
package rebinding remain pending. The current source hashes and terminal log
digest are recorded in the work-accounting report.

Replay qualification compares 13 inquiry scenarios (128 semantic boundaries)
and five additional document/consequence/review scenarios (73 boundaries) with
both M2.5 and the pre-cutover controls. Canonical request identities, schemas,
payloads and outcomes agree. Local admission and selected fresh-invocation memory
changes stay within the supplied thresholds; checkpoint maxima do not grow.
Cumulative document/consequence execution peaks above the pre-cutover threshold
are retained explicitly: those increases already appear in the M2.5 control and
are slightly reduced here. Their historical acceptance scope must be reconciled
with the final economic report, not silently inferred from local improvement.
Paired admission and execution/checkpoint timing is running separately after
build and trace generation have stopped.
