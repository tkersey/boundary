# Whole-program coalescing — implementation evidence

Status: in progress. An opt-in `safe` path now performs checked coalescing in
direct compilation and final linking. The default remains `off` pending the full
acceptance and promotion gates. This is not a completed qualification report.

The [acceptance inventory](coalescing-acceptance.md) maps every T01–T42 row and
promotion gate to current bounded evidence and explicit outstanding work.

The accepted source is the September 25, 2026 version 2.0 specification supplied
with this task (attachment `76f1c36f-9372-40cc-9466-f61061359f29/pasted-text-1.txt`).
All T01–T42 and promotion gates remain required. A finite graph test does not
prove the raw-record transformation, admission precision, or World execution.

## Starting tuple

Remote `main` identities were checked before implementation:

| Repository | Commit |
| --- | --- |
| Boundary | `f512dbbfb14ab61ed5e1d875518c2b683ff5d215` |
| Agent | `7b3215cecabd93e7b8d4c547f6c3948a838cf3f5` |
| World | `c20695e00056186a4b74564da6e4ca1c368cb33b` |

Agent's current lock selects those exact Boundary and World commits. Its expected
WASM SHA-256 is `7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f`.
This is a lock observation, not a new artifact authentication result.
Toolchain: Zig 0.16.0, Darwin arm64. Source moved from `src/v2` into `src`
after the specification's inspected revision. The current authored-handler
API additionally exposes the existing cleanup-obligation bound.

Unchanged Boundary `zig build check -Doptimize=ReleaseSafe` passed in the
isolated worktree before implementation. This includes current authoring,
pure-data, components, independent source-oracle, and codec checks; it does
not stand in for the new optimizer's runtime matrix.

The exact Python appendix, executed with `uv run python3` and assertions enabled,
reproduced 4,330 exhaustive graphs, 500 seeded graphs, and 11 adversarial assertions.
Unchanged Agent `zig build check-agent4 -Doptimize=ReleaseSafe` also passed.

## Identity audit in progress

| Identity | Current owning use | Required treatment / outstanding proof |
| --- | --- | --- |
| Effect | `program.Effect`, effect handling and ordered use-site evidence | Fixed nominal anchor; only already-resolved component bindings identify declarations. |
| Region | schemas, protection, runtime region descriptor and dynamic installation | Injective static relocation; preserve distinct dynamic region nodes. |
| Resource | `resource_admission.zig` authority membership, representation schemas | Injective relocation; every live introducer/eliminator function is singleton. |
| Entry function | roots and invocation interface | Singleton. |
| Function | call target, layout and custody; borrow queries indexed by entry block | Whole-body correspondence, fresh admission; prove caller/provenance precision. |
| Function equality | World `stable_session.zig:executeControl` self-tail restart | Sharing can expose the existing self-tail fast path. Check logical boundaries, state correspondence and capacity behavior; do not infer cost equivalence. |
| Block | function ownership, CFG, live-slot facts, saved controls | Total local correspondence; fresh facts; no within-function tail merging. |
| Slot / custody | activation layout, simultaneous assignments, custody parent tree | Function-local bijections, never catalogue relocation. |
| Constructor | closure descriptor and `borrow_flow.Step.environment` selector | Ordered capture contract and code correspondence; caller/provenance witness required. |
| Handler | installed description, `borrow_flow.Step.handler_state` selector | Full mode/strategy/contract comparison; distinct installations stay distinct. |
| Capture | immutable layout; source diagnostics and original capture observers | Share descriptions only; retain original occurrence evidence and accurate aliases. |
| Schema | exact type contracts, state admission, callable dispatch filtering | Reuse linker partition semantics; nominal anchors and ordered variants preserved. |
| Literal | schema plus immutable bytes | Exact schema class and payload equality. |
| Runtime node | World store, frames, cells, environments, resumptions, custody | No optimizer map; preserve allocations and original alias/separation relations. |
| Value comparison | `admission.zig` restricts `equal`/`less` to integer scalars (and boolean equality); World `instruction.zig` uses scalar decoding | These opcodes do not compare closure constructor identities. This does not discharge other identity uses. |
| Image / checkpoint | BPI3 identity, PST3 and authenticated request envelope | New image identity; no checkpoint or reply transplantation. |

`borrow_flow.zig` filters constructor projections by exact constructor identity
and handler-state projections by exact handler identity. Merely proving equal
runtime bodies does not discharge the valid-input preservation requirement.
Original component borrow contracts are checked in `linker.checkBorrows` before
the existing reachable projection; that ordering must remain intact.

The audit is not yet exhaustive. No new identity exclusions or equivalence claims
are authorized merely by the table. Remaining work includes the complete opcode
argument, full checker mutation matrix, live-image opportunity census,
Agent integration, the remaining execution witnesses, and the measurement protocol.

## Discovery foundation

`coalescing_graph.zig` performs split-only refinement over exact typed keys.
Keys include length-delimited labels/anchors, edge roles and target kinds,
previous classes, and singleton pins. Exact lexicographic sorting is used;
there are no fingerprints whose collisions can authorize equivalence.
Equal keys choose the lowest original node index. Profile singleton restrictions
participate from the initial partition and propagate through predecessor edges.

Every changed refinement after local grouping splits a finite class. There are
at most as many such splits as nodes. No host recursion unfolds graph cycles.
Per-round keys are temporary; only the caller-owned representative array escapes.
The work counter charges node/edge visits, key bytes and conservative exact-sort
comparison byte bounds. Exhaustion returns `WorkLimit`, never a partial map.
The final optimizer must use that error to restore its original baseline across
all extraction rounds; this engine alone does not implement that transaction.

The independent Zig pair-deletion oracle covers the same exhaustive unary graph
domain as the appendix and 500 additional deterministic typed graphs. Its random
sequence is Zig's PRNG, not a claim to duplicate Python's random corpus.
Tests also cover quotient idempotence, recursive sharing, restricted profiles,
allocation failures, malformed references and work exhaustion.

## Raw-record validator foundation

`coalescing_witness.zig` checks map domains and candidate provenance, idempotent
representatives, injective nominal mappings, live resource/entry pins, profile
restrictions, and local slot/custody/block bijections. It retains the
representative's physical slot/custody layout. These checks alone are expressly
not record equivalence.

`coalescing_validation.zig` independently reads the original and actual candidate
records. It neither imports discovery nor calls the relocation rewriter. It
checks roots, all catalogues, schemas, function interfaces, slot schemas, custody
ancestry, instructions, failure tables and every control payload under the maps.
Explicit field inventories and exhaustive opcode/union switches fail compilation
when a record gains an unclassified field or operation. Ordered vectors preserve
order and multiplicity; only declared sets are sorted/deduplicated under mapping.
The validator borrows inputs only during the call and releases its scratch.

The initial negative test independently admits both a return-41 program and its
return-42 mutant, then requires correspondence rejection. Further tests cover
forged maps, changed continuation edges, authority merges, profile restrictions,
and allocation failures. No claim of complete T35/T36 coverage is made yet.
Every candidate built by opt-in compilation/linking now passes this checker both
before and after typed reachable projection, followed by fresh closed admission.

The existing linker's schema partition was moved unchanged into
`schema_partition.zig`; both paths reuse this implementation. The linker
still performs its original interface/borrow checks and closed projection.

## Foundation verification

The current foundation passed:

- `zig build check -Doptimize=ReleaseSafe` (before final formatting only).
- `zig build check-data -Doptimize=Debug`.
- `zig build check-data -Doptimize=ReleaseSafe`.
- `zig build check-data -Doptimize=ReleaseFast`.
- `zig build check-components -Doptimize=ReleaseSafe`.
- `zig fmt --check` for changed Zig files and `git diff --check`.

The data checks were rerun after final formatting. The component witness retains
object lengths 160/375/612/195 bytes and linked lengths 811/842 bytes. The path
registry contains every new Zig file, and both test files are in the data aggregate.
No existing tests or assertions were removed or weakened.

These original results establish the foundation. The following progress adds an
opt-in implementation; outstanding work remains listed explicitly below.

## Opt-in compilation and selection

Select the same options through these paths:

```zig
// Existing calls remain off by default.
const options: boundary.data.coalescing.Options = .{ .mode = .safe };
// Typed authoring retains its own mandatory capture observer/publication check.
var compiled = try context.compileWithOptions(allocator, entry, failure, options);
// Raw staged source:
var lowered = try boundary.source.lowerObserved(allocator, module,
    .{ .coalescing = options });
// Source-free linking:
var linked = try boundary.data.linker.linkWithOptions(allocator, instances,
    bindings, entry_point, options);
```

The standalone linker manifest accepts `"coalescing": "safe"` or `"off"`.
Open component emission defers the pass. Existing `link` and typed `compile`
remain source-compatible wrappers. No codec implicitly optimizes its input.

Comparison-only views number input slots in interface order, visit the CFG in
ordered breadth-first traversal, and number other slots at their first occurrence.
They complete unused slots by schema class and multiplicity. Custody ancestors
are named before children; unused subtrees are ordered by exact bottom-up tree
shape ranks. No program-depth host recursion is used. The original representative
layout is retained and separately checked by the raw-record validator.

One graph contains functions, constructors and handlers. Fixed schema/literal/
capture classes feed labels; ordered typed outgoing references feed refinement.
The two profiles use the same implementation, with singleton function seeds for
`descriptions`. Materialization uses the existing typed relocation methods.
Every actual rewrite is checked, projected, checked again, freshly admitted, and
sized with `program_image.encodedLength` before selection.

Selection uses exact BPI3 bytes, then total live catalogue count, then `full` on
an exact tie. A selected round must shrink the catalogue count and cannot grow
bytes. Rounds continue to a fixed point. Allocation failures and invalid witnesses
propagate as errors. A deterministic work-limit failure releases intermediate
selections and returns the original ordinarily validated live baseline.
Caller-owned optional round storage reports both candidates and the selected
profile; `round_count` versus `rounds_recorded` makes truncation explicit.

## Captured-closure evidence

The maintained public typed-authoring fixture independently emits N helper
functions, constructors and capture sites. Its entry parameters supply captures
`3, 7, ...`; each helper applies checked u64 addition to its own capture and `10`.
Typed literal expressions are instead embedded in helper bodies by existing
lowering. The literal-based variant is retained as a negative fixture and does
not incorrectly merge those different constant-using bodies.

| N | Off BPI3 bytes | Safe BPI3 bytes | Safe helper bodies / constructors / captures |
| --- | --- | --- | --- |
| 1 | 143 | 143 | 1 / 1 / 1 |
| 2 | 211 | 174 | 1 / 1 / 1 |
| 16 | 1,129 | 574 | 1 / 1 / 1 |
| 64 | 4,770 | 2,313 | 1 / 1 / 1 |
| 256 | 20,333 | 9,871 | 1 / 1 / 1 |

All N retain N dynamic construction instructions. Native and Node/WASM produce
the independently expected values (13, 17, ...). The N=2 case additionally checks
u64 overflow failure, matching quantum-one logical boundaries, restore on a fresh
runtime for every step, and rejection of an off-image checkpoint by the safe image.
The same authenticated runtime is used for both arms; no checkpoint is rewritten.
These observations do not establish effects, cleanup, mutable-cell or multi-shot
coverage, real Agent value, or performance non-regression.

[Machine-readable closure results](coalescing-closure-evidence.json) include sizes,
record counts, discovery work and both candidates for each extraction round.
They contain no timing or memory improvement claim.

The selected baseline runtime was acquired with Agent's current authenticated
setup, which verified source/archive/package/runtime inventories and rebuilt the
locked kernel with digest
`7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f`.
A separate native fixture executable was built from the same authenticated World
`c20695e` and Boundary `f512dbb` input directories.

Reproduce the closure checks after acquiring the locked runtime and native peer:

```sh
zig build build-coalescing-fixtures -Doptimize=ReleaseSafe
node test/coalescing_execution.mjs zig-out/bin/coalescing-fixture \
  "$WORLD_RUNTIME" \
  7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f \
  "$WORLD_NATIVE"
```

## Outstanding delivery work

### Initial compiler measurements

The maintained `coalescing-bench` measures source construction, lowering, encoding
and cold Boundary image admission separately, with allocator calls, cumulative
requested bytes and peak requested bytes per phase. These counters exclude
allocator metadata/RSS and World runtime live memory. Source construction includes
any checks performed by the public typed-module builder. The compiler phase
observer reports the coalescing interval; individual discovery/validation/sizing
times are not yet separately instrumented.

[Before](coalescing-compiler-before.json) and [after](coalescing-compiler-after.json)
reports retain all samples from independently launched alternating off/safe
windows: three warmups and nine samples per process, three initial windows plus
two confirmations when an initial cold-admission ratio exceeds 1.05. Ten small
synthetic effect/closure/hyperfunction fixtures are measured. The host was not
isolated from other work, so timings are observations with raw variation retained.
This is neither the B0 control nor complete Agent/runtime/linking qualification.

The initial profile exposed redundant no-change work: both portfolios were
materialized, validated and admitted even after full discovery found only singleton
classes. The pass now retains the current validated baseline directly in that
case. The restricted description profile can only split full classes, so it
cannot produce a merge when the full relation has none. Nontrivial transformations
still cross both raw-record checks and fresh admission. Round observations mark
`materialized: false` rather than pretending candidate work ran.

In these windows, enabled compilation medians dropped 21–48% versus the initial
implementation, with lower or unchanged peak requested allocation. The updated
safe/off compiler ratios remain approximately 1.6–4.4×. All before/after image
digests match, including disabled controls. No synthetic cold-admission cell met
the specified confirmed >5% slowdown rule in these measurements; this does not
close the real-consumer or World runtime non-regression gates.

```sh
zig build build-coalescing-bench -Doptimize=ReleaseSafe
node test/coalescing_measure.mjs zig-out/bin/coalescing-bench measurements.json
```

The no-change/idempotence tests require zero candidate validator/admission calls
after reaching the fixed point. The complete data/authoring suite also retains
work-limit rollback and deterministic allocation-failure tests. Remaining compiler
measurement obligations include scaling/mostly-unique graphs, source-free linking,
all internal phases, and the unchanged real consumer corpus.

### Enabled/disabled semantic fixtures

The [browser report](coalescing-browser-evidence.json) runs ten fixtures under
both modes in real Chromium and Firefox Workers. Every quantum-one output is
compared byte-for-byte with the native peer for that exact image. Workers are
destroyed after each step, so each successor restores on a fresh host instance.
The server exposes only runtime embedding modules, the authenticated kernel,
and a small transport worker; it exposes no compiler or application source.
Semantic traces/results are compared between modes, replies are bound to each
actual request, wrong-program restores reject, and a wrong kernel digest rejects.

```sh
node test/coalescing_browser.mjs zig-out/bin/authoring-cases "$WORLD_RUNTIME" \
  7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f \
  "$WORLD_NATIVE" "$WORLD_BROWSER_TOOLS" > docs/coalescing-browser-evidence.json
```

`WORLD_BROWSER_TOOLS` selects the existing locked World Playwright installation.
This recorded subset covers cell/memo separation, fresh hyper helpers, State/Choice
and cleanup. It is not a claim that every remaining fixture/platform gate passed.

The native authoring aggregate now starts four independent compiler threads
with separate debug allocators. Each repeatedly alternates safe compilation,
disabled compilation and deterministic work-limit fallback. Image identities
must match serial controls after the source builders have been destroyed;
observations must remain caller-local and each allocator must report no leak.
This is bounded concurrent execution evidence, not a general race-freedom proof.

The data aggregate also admits and round-trips an unoptimized image containing
duplicate scalar schemas. Explicit coalescing merges those schemas while retaining
both ordered alternatives of `sum(A, A)`. Both injection encodings remain valid,
the third ordinal remains invalid, and codec-only round trips retain original
bytes and the duplicate-containing catalogue.

The [recursive execution report](coalescing-recursive-evidence.json) compares two
independently emitted mutually recursive groups with distinct role base values.
The equivalent groups coalesce role-for-role (five functions including entry
become three). Changing one group's odd-role base value preserves all five
functions. Inputs 0, 1, 2, 7 and 16 return independently calculated values with
matching quantum-one boundaries in native World, Node/WASM and Wasmtime.

A nonterminating variant emits alternating role requests. Both modes preserve
the first 128 stepping operations, request payloads and contracts, using replies
bound to each image's own requests and fresh-host checkpoint restoration. This
establishes the recorded finite prefix only; no timeout or finite prefix is
presented as a proof of equivalent divergence. Reproduce with `recursive` as the
final argument to the maintained coalescing execution harness.

The [bounded production-record corpus](coalescing-generated-evidence.json)
enumerates all 36 combinations of three-slot renaming and simultaneous assignment
permutations. Seeds 0–35 contain independently numbered equivalent functions and
must share code. Seeds 64–99 swap one returned operand-list field and must remain
distinct. All 72 valid programs execute in both modes on native World, Node/WASM
and Wasmtime, with an independent permutation/value oracle and matched boundaries.
Seeds 128–163 use an out-of-range destination; all 72 off/safe compilation attempts
reject with `InvalidReference` and publish no bytes.

Use the fixture emitter's `generated-SEED` selector for an individual case, or
pass `generated` as the runtime harness's final argument for the complete corpus.
The generator covers a bounded stable-slot subset; it is not a general program
equivalence proof. Recursive generation and remaining semantic families still
need their separately required coverage.

The [simultaneous-assignment report](coalescing-edge-evidence.json) checks two
alpha-renamed function bodies containing a swap or three-way slot cycle. Both
fold to one body while retaining the representative's original input layout.
For inputs `11, 22, 33`, each invocation returns `22, 11, 33` for the swap and
`22, 33, 11` for the cycle. Native, Node/WASM and Wasmtime agree at quantum-one
boundaries. These raw admitted-record fixtures intentionally exercise stable-slot
assignment patterns that the higher-level source API does not expose directly.
Run `test/coalescing_execution.mjs` with the existing runtime arguments and
`edges` as its final argument to reproduce them.

Authority tests now cross the public pass after original admission and live
projection. The former discovery-only test was corrected to root its resource
through a live layout. Privileged/unprivileged and distinct privileged identities
stay separate. Unauthorized unused resource introduction and elimination reject
in both modes. Their authorized counterparts may be discarded by ordinary
reachability; that discarded authority does not pin otherwise live helpers, and
a second safe pass preserves exact image identity.

The maintained [semantic report](coalescing-semantic-evidence.json) records 72
executions across 31 authored fixtures. Both modes agree with native
World, Node/WASM, Wasmtime 48.0.0 (Python 3.14.7), and the independent higher-order
source oracle. Coverage includes deep/shallow and answer-transforming handlers,
cleanup and disposal, lazy/demanded behavior, failure ordering, arithmetic,
regions, and typed capture/handler interfaces.

The stateful closure additions independently emit equivalent bodies that capture
distinct cells or a deliberately shared cell. Code and constructors coalesce,
while the original allocation sites remain: two versus one ordinary cells, and
three versus two cells for the memo examples (including their evaluation counter).
Independent counters return `1, 1, 2`; shared counters return `1, 2, 3`.
Independent memo cells evaluate twice and return `1, 1, 2`; a shared memo cell
evaluates once and returns `1, 1, 1`. These observations survive quantum-one
checkpoint/restore in each runtime. Existing multi-shot State/Choice examples
also retain branch-local `[1, 1]` versus deliberately shared `[1, 2]` results.
This does not yet close the full recursive multi-shot or hyperfunction matrix.

The ordinary `hyper.ana`, `Query.ask`, `invoke`, `force` and `deferValue` paths
are also exercised through separately emitted definitions. The duplicate case
shrinks from 19 functions/15 constructors to 12 functions/nine constructors
(887 to 531 bytes) while retaining captures 3 and 7 and returning 13 and 17.
A second Step configuration adds one and returns 13 and 18; its distinct code
remains (18 functions/14 constructors). The lazy case emits a real query but
never forces its divergent peer, returning 3 and 7 in both modes. Normal and
checked-overflow cases agree with the source oracle and all three runtimes at
matched stepping boundaries. No emitter cache is used to manufacture sharing.

Each execution uses quantum one and restores its own checkpoint on a fresh host
instance at each boundary. The differential comparison includes semantic request
identity bytes, effect IDs, payload/resume schemas, payload bytes, boundary kinds,
cleanup failures and cancellation fields. Only image-bound request/checkpoint
identities are excluded. Replies are bound independently to each actual request.
The report binds the emitter, native peer, runtime kernel, harness and source
fixtures by digest. These cases do not establish the entire acceptance matrix.

The [depth-eight helper-chain report](coalescing-tree-evidence.json) exercises
reference-induced sharing through alternating direct calls and constructed
computations. Equivalent chains reduce 19 functions to 10 and eight constructors
to four (780 to 424 bytes). A changed leaf propagates through the relation and
retains all 19 functions/eight constructors; its small description saving is
reported separately. Normal and checked-overflow executions preserve matched
boundaries. The source-level structural assertions are in `check-authoring`.

Reproduce with the authenticated World paths described above. Keep the Wasmtime
environment outside the immutable source input:

```sh
zig build build-authoring-cases build-coalescing-fixtures -Doptimize=ReleaseSafe
export WORLD_KERNEL_SHA256=7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f
export WORLD_WASMTIME_PEER="$WORLD_SOURCE/test/current/peer.mjs"
export UV_PROJECT_ENVIRONMENT="$WORLD_WORK/cache/coalescing-wasmtime"
export PYTHONDONTWRITEBYTECODE=1
node test/run_authoring_cases.mjs "$WORLD_RUNTIME" "$WORLD_NATIVE" \
  zig-out/bin/authoring-cases coalescing docs/coalescing-semantic-evidence.json
node test/coalescing_execution.mjs zig-out/bin/coalescing-fixture "$WORLD_RUNTIME" \
  "$WORLD_KERNEL_SHA256" "$WORLD_NATIVE" trees > docs/coalescing-tree-evidence.json
```

### Diagnostic provenance update

The source translator no longer chooses the first constructor using a capture
description when admission already names a different failing function. When the
source is ambiguous, it reports a representative and related original function
IDs and leaves the lexical variable unset. Presentation retains up to eight IDs
with an explicit truncation flag; the full temporary correspondence remains
available while the checks run.

Optional coalescing diagnostics identify the original/baseline/transformation/
candidate/mapping/cost stage. All catalogue maps and local slot/custody maps are
composed from the original input across accepted rounds; dead originals retain
the missing sentinel. Nominal regions use the existing sparse projection rather
than a dense allocation proportional to their largest identifier. Map updates
check every domain before mutation. Scratch is released before returning an
owned program, and no source AST, provenance record, or diagnostic enters a wire
image or saved state.

Transformation locations refer to the current round's original records;
candidate-admission locations refer to the candidate. Both are translated to
original aliases. Constructor diagnostics additionally match capture and callable
schema references so different typed constructors sharing code are not conflated.
Successful calls and new phases clear stale observations. Statistics expose a
failed check as an error rather than a successful optimization outcome.

Tests cover renamed slots and custody trees across successive mappings, a dead
lower-ID declaration, sparse live regions, stale-map rejection without partial
updates, allocation failures, and identical output with diagnostics enabled.
Separately admitted constructor-contract and shared-body mutants distinguish a
unique constructor origin from a shared implementation's multiple origins.

The dedicated [cross-object witness](coalescing-component-evidence.json) now
passes object-only linking and native/WASM execution. Two independent processes
emit library objects with private captured helpers; a third emits the importing
client. No application source or emitter is present in the linking directory.
The closed image shrinks from 253 to 177 bytes, functions from five to three,
constructors from two to one, and capture descriptions from two to one. Both
images return 13 and 17 with the same quantum-one progression and fresh-host
restore trace. Object bytes are identical under off/safe component emission.
The fixture explicitly binds its closure before application: the existing local
direct-application optimization otherwise eliminates its constructor before
global coalescing, which would not exercise the required constructor witness.

`check-components` runs this structural witness automatically. Runtime checking
uses the same arguments as the closure harness:

```sh
node test/coalescing_components.mjs zig-out/bin/coalescing-fixture \\
  zig-out/bin/boundary-link zig-out/bin/coalescing-inspect \\
  "$WORLD_RUNTIME" \\
  7d31effb1d4e32523d0fcbd5b4d5f5a8a2289fbd4c731173a33b1c174524282f \\
  "$WORLD_NATIVE"
```

The actual candidate pipeline now also checks role-preserving merging of two
mutually recursive groups and propagation of a changed constant around the
recursive relation. That is structural/admission evidence, not yet a runtime
divergence-prefix qualification. Existing same-named private-effect separation,
false imported borrow promises, and constructor/handler borrow-substitution
tests run unchanged assertions under both off and safe.

At this implementation step, the ReleaseSafe data, authoring and component
aggregates pass, as does the maintained native/WASM closure command above.
The complete ReleaseSafe `check` aggregate passed before the final added
component/capture tests and formatting; those affected aggregates were rerun
afterward. Data tests additionally passed in Debug and ReleaseFast before final
formatting. The added tests preserve all predecessor cases and assertions.
The source-free component harness now exercises `safe` with only transported
objects and the linker: its first linked image is 804 bytes versus 811 bytes off.
The dedicated witness above attributes its reductions to actual code and
constructor coalescing.

The goal remains active. In particular:

- Complete the identity/opcode and admission-precision audit and the remaining
  end-to-end diagnostic mutation cases.
- Exercise the actual candidate pipeline on deep parent trees, mutually recursive
  groups, all semantic differences, simultaneous assignments, schema sums,
  nominal identities, resource authority, handler modes and borrow provenance.
- Complete corruption/generative/allocation/concurrency tests and the full T01–T42
  matrix; existing green aggregates are not a replacement for these cases.
- Extend source-free cross-object coverage to the required nominal region/resource,
  explicit-effect-binding and recursive constructor/handler cases.
- Propagate options through Agent's final compiled-tool link and update/authenticate
  the candidate dependency selection without changing the locked World evaluator.
- Run the unchanged real consumer opportunity census and B0/B1/B2 qualification,
  including the complete timing, memory, checkpoint and platform protocols.
- Complete phase/resource/work accounting, investigate measured scaling, and
  remove redundant checks only where their exact obligations remain covered.
- Run the required serial review/closeout workflow on final commits and publish
  authorized draft changes. Promote the default only after all required gates pass.
