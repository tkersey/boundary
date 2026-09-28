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
