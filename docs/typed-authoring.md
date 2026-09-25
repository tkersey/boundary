# Typed, structured authoring

Import `boundary.authoring`. It stages ordinary Boundary source; the existing
source checker, lowering, target admission and unchanged World interpreter remain
authoritative. The low-level `boundary.computation` API remains available.

## Start here

[`examples/structured_branch.zig`](../examples/structured_branch.zig) is a complete
public example. [`examples/authoring_client.zig`](../examples/authoring_client.zig)
adds a reusable callable, two ordered calls, named records, a derived responder,
residual lookup and checked overflow. Both emit ordinary BPI3:

```sh
zig build emit-structured-branch -Doptimize=ReleaseSafe > branch.bpi3
zig build emit-authoring-client -Doptimize=ReleaseSafe > client.bpi3
```

The canonical route is:

1. Initialize a source `Builder`, then `authoring.Context.init(&builder)`.
2. Declare schemas, external/local operations, and named function interfaces with
   explicit allowed effects. Retain declarations to reuse their code.
3. Open a function body with `body`, or a capturing nested body with `closureBody`.
   Calls, applications, effects, projections and checked arithmetic bind their
   results in forward order. `parameter` and `field` use declared names.
4. Finish with `ret`, then `Context.define`. `Context.compile` checks and lowers
   while retaining source-oriented diagnostics. Alternatively return `module`
   from `Application.emit` and call `boundary.program.lower`.
5. Encode the returned owning `Compiled` with `encode`; deinitialize it afterward.
6. Use the separately verified World package to prepare/start or invoke the image.
   Supply only environmental replies and transfer actual State; host code does
   not reconstruct authored branches, handlers or continuations.

The client takes one Boolean byte followed by a record containing little-endian
u64 `input` and `offset`. False returns their checked sum without a request. True
interprets two local questions as two external `client/lookup` requests carrying
`input`, then returns `first_reply + offset + second_reply` with checked addition.
Its overflow is an authored unit failure. Replies must bind to the current actual
request, including after restoration.

## Staging and lifetimes

| Zig emitter operation | Generated computation |
|---|---|
| Zig `if` selects code to construct | `conditional` selects runtime work |
| Zig `try` propagates construction/allocation failure | `checkedAdd` emits an authored failure edge |
| Zig `defer` releases native resources | `protect` installs portable cleanup |
| Calling a staging function constructs source | `apply` executes an authored callable in World |
| `lambda` constructs and binds a callable value | `apply` forces a zero-argument delay when demanded |

No native callback enters the Program. Inspecting schemas or diagnostics does not
force delayed work. Recursive function declarations can be used before definition;
all declarations must be defined before `module` or `compile` publishes a snapshot.
Calls and lambda constructions made before a body is opened are rechecked against
that function's eventual lexical parent at publication. Valid uses in that parent
and forward uses of global functions remain supported; discarded branches do not
contribute pending scope obligations.
Publication also compares the declared named failure layout with executable
arithmetic faults and protected cleanup contracts, including late helper
definitions. Abandoned staging branches do not contribute executable uses.
The recursive adapter retains the existing finite `hyper.ana` construction.

Keep the source builder at a stable address. Contexts, handles, copied names and
source snapshots borrow its arena until `Builder.deinit`. `Context` and `Body` are opaque arena-owned handles; pointer aliases share lifecycle
state. Clients cannot copy, reopen, or retarget staging storage. `Compiled` owns its output independently.
`module` copies the source arrays, so later builder growth cannot stale its slices.

`ret` and `abandon` close a body and its descendants to further authoring. Abandoning
an unused branch is harmless; abandoning a declared function leaves it undefined
and prevents publication. A closure legitimately captures ancestor values while
being authored. The runtime lifetime of those captures is checked independently.
Sibling values and branch-local values cannot escape directly: use `conditional`,
`block` or `match` to produce a parent-scope result.

Construction errors, including allocation and named-argument validation failures,
may poison the context. After an error, retain its diagnostic, discard the context
and tear down its source builder; general transactional recovery is not promised. No successful checked
module is returned from a failed operation. Diagnostic handles remain valid until
that builder is destroyed; `renderAlloc` returns caller-owned text.

## Declarations and guarantees

`Schema`, `Operation`, `Function`, `Value`, `FailureLiteral`, `Computation`, `Handler` and `Region`
are distinct opaque handle categories. Zig rejects category substitution. Runtime
checks reject foreign contexts, out-of-scope values, incompatible named layouts,
arguments, branch results and capability instances. Final source/target admission
still owns effect allowances, affine/linear use, capture safety and borrowed-region
escape. In particular, one-shot use in mutually exclusive arms is allowed; two
sequential uses are rejected. Lambda and aggregate construction bind once rather than silently
creating a fresh one-shot value at each use.

`checked` supports add, subtract, multiply, divide and remainder with opaque
`FailureLiteral` handles constructed once with `c.literalFailure(T, item)`. Ordinary
`Value` handles cannot substitute for this category. The constructor establishes
literal status; arithmetic checks origin and publication checks the failure schema. Overflow is explicit; division and remainder additionally require
an explicit zero-divisor failure. `checkedAdd` is the short addition spelling.
The operand schemas determine the result; no expression is evaluated in the host.

`scalar(T)` supports the existing portable scalar subset (void, bool and supported
fixed-width integers). `record` and `alternatives` accept dynamically selected
named fields. `sequence` describes homogeneous sequences. `product`, `field`,
`variant`, `caseOf` and `match` preserve these names and schemas. `Schema.fields`
and `describe` inspect the metadata. This is not a serializer for arbitrary Zig
pointers or recursive native structures; unsupported `scalar` types fail clearly.

Compatibility compares builder origin, raw schema identity and the complete named
metadata graph, including callable and resumption capture bounds. Memoized schema
pairs handle sharing and recursion without
repeated unfolding; allocation identity is only a fast path. Names are compared
within declarations; equal raw product shapes do not make
incompatible named layouts interchangeable. Operation identity is nominal: two
`local` calls with identical display names create distinct capabilities.
`external` explicitly permits environmental performance; `local` requires the
matching capability. `scoped` additionally declares named authored body operands.

`callable` fixes named parameters, result, allowed effects, use, capture allowance
and regions. `functionFor` derives a declaration from that interface. `lambda`
checks the function's complete declared interface. Actual lexical captures and
values retained across effects are compared with named capture bounds using the
existing compiler's capture and liveness observations. Ownership, borrowing and
multiplicity remain checked by the unchanged admission rules. A value used only
before suspension does not become a continuation capture. Reusing a returned function emits calls without rebuilding its
body. Staging configurations are values, not a cache keyed only by Zig type.

## Interpretation, ownership and diagnostics

`handler` derives the operation payload, capability, clause signature and
resumption input. Intentional choices remain explicit: deep/shallow mode, body
input and interpretation answer, resumption use, body use (`body_use`), residual effects, continuation
captures, body captures, handler state and owned/borrowed regions.

Use `returnFunction`, `clauseFunction` and `handledSchema` to author its pieces.
Return functions expose `result`; clauses expose `payload`, named state and scoped
bodies, and `resumption`. `resumeValue` continues and returns for postprocessing.
`resumeWith` installs a successor for a shallow resumption. Deep resumptions return
the interpretation answer; shallow resumptions return the handled body's input
schema. For shallow work, explicitly allow effects that its resumed body can use;
`escaping` names effects that can select outside attachments (such as residual
external lookups). The authoritative checker validates this allowance.

`responder` derives the ordinary resume clause from an authored function. Its
residual effects remain explicit. Body capture and continuation capture bounds are
separate: allowing a capability in a continuation does not silently grant a body
permission to capture an outside instance. Nothing widens an effect/capture/use
allowance to make admission pass. Capture applicability follows the existing
admission rule: every declared handler sharing an effect instance contributes its
continuation capture bound, including unused handler declarations. A successful
raw check after names have been erased does not make incompatible named bounds
interchangeable.

`protect` keeps local cleanup inside the Program across suspension. `dispose`
expresses local owned-resumption disposal; it does not cancel the enclosing
session. `regionBodySchema` derives the implicit region-token parameter and
contract; `withRegion` supplies that token and takes only the remaining named
arguments. `region` and these contracts retain nominal region boundaries. Existing low-level resource/loan constructions remain supported.

`Context.lastDiagnostic()` contains a stable error category, entity, failed relationship,
and expected/actual schema handles when available. `render` and `renderAlloc`
render that same information. `Context.compile` also retains the authoritative
source/target diagnostic for failed effects, captures, borrows, uses and answers.
Diagnostic function labels are not emitted and do not change executable bytes.
Errors explain the relationship rather than recommend widening permissions.

`authoring.interop` is the deliberate advanced boundary for existing source
libraries. Its caller promises that raw IDs come from the supplied source builder;
it checks available bounds, categories and schema relationships. Erased numeric
provenance cannot be reconstructed. Imported positional schemas use positional
names unless the adapter supplies checked names. Scoped operation imports retain
their body schemas and expose those operands under positional names. `cleanupInfo`
retains the supplied typed failure layout in both the primary-failure alternative
and the cleanup-failures sequence; it does not erase known names through import. Ordinary covered clients need
neither these adapters nor mutable source catalogs. Finish low-level recursive
schema definitions before adoption, and keep adopted declarations stable afterward;
appending independent declarations is supported. Raw catalog mutation is outside
the checked handle contract.

## Migrated constructions

All four source consumers retain their existing behavior and public entry points:
`one_effect`, `combinators.twice`, choice family/first/all/allScoped, and
`hyper_demand`. The hyper bridge handles recursive interface setup and existing
library calls; the example retains its own demands, runtime branch, checked
additions, delayed descriptors and reciprocal startup. Two Need instances remain
nominally distinct despite identical display strings.

Before, `twice` allocated destination variables, built references, and nested two
binds backward. Its implementation now expresses:

```zig
const first = try forward.apply(callable_value, &.{});
const second = try forward.apply(callable_value, &.{});
const result = try forward.product(pair, &.{
    .{ .name = "first", .value = first },
    .{ .name = "second", .value = second },
});
try self.define(function_handle, try forward.ret(result));
```

Choice formerly repeated payload, result, answer, capability and clause ordinal
relationships in schema/function/handler records. It now declares the operation
and explicit handler policy once, obtains named clause inputs, resumes each branch
and concatenates the results. Multi-shot use, answer transformation, captures and
region allowances remain intentional decisions.

## Acceptance and reproduction

The accepted task is the typed structured-authoring contract: category/scope-safe
handles, dynamic named schemas, forward control, derived effect interpretation,
focused diagnostics, the four migrations, and a fresh package client. No runtime,
wire format, ownership checker, Agent API or formal research migration is included.
Finite cases establish their exercised observations, not universal soundness.

| Requirement | Deciding evidence |
|---|---|
| A01 | Colliding live contexts reject foreign schema/effect handles; local control succeeds |
| A02 | Sibling/escaped locals and finalized ancestry reject; joins and nested capture succeed |
| A03 | External package's deliberate Operation-to-Schema substitution fails Zig typing |
| A04 | Runtime Boolean selects requests versus pure result; emitter performs neither |
| A05 | `twice` returns ordered pairs from replies (7,11) and (23,5) |
| A06 | Deep/shallow results 100/43; both answer-transforming versions agree; bypass returns 18 |
| A07 | Non-tail resumption postprocessing and cleanup request after restored suspension |
| A08 | Sequential one-shot use and exclusive reusable capture reject; exclusive branches and clone-safe choice succeed |
| A09 | Wrong nominal capability and missing residual allowance reject; declared controls succeed |
| A10 | Checked overflow before an effect yields no request; after it retains the request |
| A11 | Same configuration type emits 7/11; explicit function reuse adds no bodies |
| A12 | Unused failing delay returns 42; demanding it produces the authored failure |
| A13 | Reciprocal demands request 19 and retain both callers; replies 19/29/max-u64 give 42/52/failure |
| A14 | Runtime-selected records work; wrong fields and same-shape differently named joins reject |
| A15 | Exhaustive allocator fail-index sweeps cover core constructors, handlers, snapshots and diagnostic text |
| A16 | Archived public package builds in an unrelated directory; consumer uses only public modules |
| A17 | Structured/rendered relationships, authoritative capture/effect errors, label byte-invariance |
| A18 | Existing low-level aggregate, component APIs, source oracle and separate data-only package import |

```sh
zig build check -Doptimize=Debug
zig build check -Doptimize=ReleaseSafe
zig build build-authoring-cases -Doptimize=ReleaseSafe
node test/run_authoring_cases.mjs RUNTIME_DIR NATIVE_RUNNER zig-out/bin/authoring-cases
node test/package_authoring.mjs RUNTIME_DIR NATIVE_RUNNER /absolute/client.bpi3
node test/authoring_execution.mjs RUNTIME_DIR NATIVE_RUNNER hyper BASELINE.bpi3 CANDIDATE.bpi3
```

Set `WORLD_WASMTIME_PEER` to the existing qualified World's `peer.mjs` to include
Wasmtime and alternate the actual producer of transferred State. Use a private
copy of its locked test dependencies when World is read-only. The external driver
pins the selected kernel digest and uses the existing 2 MiB / 8 MiB / 2 MiB limits.
All requests receive replies bound to the restored destination's actual request.

The package check archives committed HEAD, fetches the normal Zig package,
constructs an outside consumer, checks its foreign-effect sibling and static
category error, and executes the client. It also imports `boundary_data` through
a separate `data-only` dependency. It never modifies the extracted library.

## Source and runtime binding

Baseline: `ab0c52636023b7db7690f647f0fedc10bbba93ef`, tree
`43f598f4ed6b58d267e293f7c4186849bdb63194`. Zig 0.16.0, Node 26.9.0;
native target `aarch64-macos.27.2...27.2-none`.

Fixed World source: `669a37a563363541f2a92ba3cee644dba7b86a70`, tree
`f803635405f997c8e072112da42cefc8491f9cb4`. Build-time Boundary-data:
`1b00c8c159f0cb490a1223fac8d3d208cef41cb1`.

- archive: `99c3eb8a2cb24e5002824050b24aab9f816436215c0b70f39f353057a31a3f70`
- manifest: `47af5517108c550ab7ecef9a188ba3e545e916bb1e196b065ef6a342a2dfa69d`
- kernel: `df7fe1ae0ed0de7b2976c98b1534d1d55f4c341b7148837ce32f42ed8d011084`
- native companion: `c77e77fd568d52284c3c973080852fa1aa515f6e3c47ac14213d2cc051fc061e`

The native delivery record separately identifies the same World source commit and
Boundary-data dependency for the digest above. Its bytes were verified locally;
World was not rebuilt.

The selected archive was externally digest-checked, safely extracted into private
stable storage, then its supported verifier checked 35 inventory files and ran
execution/restore smoke. ABI 3; wasm32 ReleaseSmall; 65,536-byte stack; 256 MiB
maximum memory. Smoke defaults are 65,536 / 1,048,576 / 65,536 bytes. This verifies
the selected dependency under no concurrent package writer; it does not claim
hostile same-user mutation isolation or repair World's verifier.

The draft PR records current exact-head validation and serial-review status.
Completion is not implied by this acceptance inventory: blocked or unexecuted
checks must remain explicit in that account. World and Agent remain unchanged.

## Measured construction cost

The baseline is the frozen revision above. Complete BPI3 counts for representative
migrations (before → after) are:

| Construction | Bytes | Functions | Blocks | Instructions | Constructors/captures |
|---|---:|---:|---:|---:|---:|
| one-effect | 85 → 85 | 1 → 1 | 2 → 2 | 0 → 0 | 0 → 0 |
| ordered twice | 169 → 186 | 3 → 3 | 7 → 9 | 3 → 3 | 1 → 1 |
| all-choice | 269 → 286 | 4 → 4 | 9 → 11 | 8 → 8 | 1 → 1 |
| first-choice | 247 → 256 | 4 → 4 | 8 → 9 | 6 → 6 | 1 → 1 |
| reciprocal demand | 1,234 → 1,290 | 23 → 22 | 57 → 65 | 25 → 24 | 16 → 15 |

The additional bind/jump blocks retain the once-created symbolic values used by
the forward API. They are ordinary source lowering, with no extra World protocol
or external operation. The original bounded reciprocal harness still succeeds:
reply 19 gives 42 with 95 fresh transfers, versus 83 baseline. Transfers count
quantum-1 boundaries and are not a runtime throughput claim. The small fixed image
increase is recommended for acceptance; no capacity was raised or test weakened.

One-effect authoring was measured in five alternating baseline/candidate pairs,
with 20 warmed in-process emission observations per pair. Median microseconds:

| Stage | Baseline | Candidate |
|---|---:|---:|
| Native authoring | 0.250 | 0.834 |
| Lower/check | 4.834 | 5.792 |
| Encode | 2.042 | 2.125 |
| Existing World replay, 20 paired observations | 126.875 | 123.834 |

Warmed incremental native-emitter build medians were 176.0 and 173.3 ms. These are
local bounded measurements, not cold-build or speedup claims. The added native
cost comes from owned labels/handles, explicit bindings and the source snapshot;
it adds about 1.6 microseconds to this small emission. Replay variation does not
establish a speedup. Reproduce author/lower/encode with
`test/build_authoring_economy.zig` and `test/authoring_economy.zig` against the exact
baseline and candidate source roots; `tools/authoring_stats.zig` reads image counts.
The test-only low-level twice reference preserves the baseline construction.

For capture-bearing programs, `module()` performs a publication-time admission
pass before returning its independently owned snapshot. `compile()` combines this
named validation with its normal lowering and avoids a duplicate pass. Observation
scratch uses the parent allocator and is reclaimed; ordinary low-level compilation
does not allocate the optional source-variable map. Twenty alternating warmed
whole-process reciprocal-demand emissions measured medians of 4.342 ms baseline
and 4.929 ms candidate, including process startup, authoring, admission and encoding.
The roughly 0.59 ms increase includes the extra snapshot admission and named
metadata work; this measurement does not isolate their individual costs. Retaining
that bounded cost is recommended to check named captures before raw-source
publication. Reproduce with `-Dworkload=examples/hyper_demand.zig` and the economy
build's `emitter` step, timing the executable; the baseline's private `Application`
prevents using the in-process `measure` step for that workload.


Local validation for this draft uses the private sibling `../boundary-runtime-61b776`:
`bundle/runtime` is the verified loader/kernel directory, `world-fixtures` is the
fixed native companion, and `peers/current/peer.mjs` selects the unchanged locked
Wasmtime test peer. These are dependency/test artifacts, not alternate source or
implementation branches. The archive remains alongside the bundle for durable
reproduction; no historical launcher or task binding is needed.


The first serial-review wave identified three metadata-boundary defects. Regression
cases now cover imported scoped-operation execution, named failure inspection,
imported/constructed sequence composition, nested-name rejection, borrowed and
recursive interfaces, shared graphs, and allocation failure during compatibility
checking. Their original subjects and CAS provenance are retained in the three
Review Fold records for this execution. Review status remains owned by the draft PR.


A later review wave exposed failure-layout publication and capture-bound metadata
gaps, plus missing rejection diagnostics. Their regressions cover failure producers,
cleanup consumers, late definitions, abandoned branches, callable/resumption bounds,
stale diagnostic replacement and allocation failure. Allocation injection additionally
exposed a pre-existing stale target-diagnostic location after projection; target
admission now clears prior-pass locations before reporting a new failure.


Capture regressions additionally cover declaration-to-lambda retyping, actual
lexical captures of generic declarations, live continuation records, values used
only before suspension, abandoned lambda construction, both publication entry
points, and allocation failure. Named observations consume existing admission
facts; they do not introduce a second ownership analysis or alter capture bounds.

## Consolidated public consumer

`examples/authoring_client.zig` accepts `use_effect` and a `numbers` record with
`input` and `offset`. It constructs one void failure literal and one reusable
local question callable. The pure branch returns checked `input + offset`.
The effectful branch asks once, checks `first + offset`, asks again, then checks
`partial + second`. An overflow after the first reply therefore prevents the
second request. `test/authoring_execution.mjs` checks all six specification vectors
against actual requests, transferring portable State between fresh runtime peers.

`interop.literalFailure` admits an existing raw literal with an explicit named
schema, preserving the advanced named-layout regression surface. Like other raw
adapters, it cannot recover erased numeric provenance. `interop.builder` exposes
the retained low-level builder without exposing authoring lifecycle records.
Diagnostics returned by `lastDiagnostic()` are read-only snapshots of the record;
the schema handles and labels still borrow the builder arena.
