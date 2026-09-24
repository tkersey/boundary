# Typed, structured authoring

`boundary.authoring` builds the existing Boundary source language. It gives
schemas, effects, functions, values, callables, and bodies distinct Zig types,
checks ordinary builder and lexical scope mistakes while staging, and folds
forward statements into source binds. `boundary.authoring.lower` still runs the
normal source checker, lowering, and target admission. World runs the resulting
BPI3 image; authoring does not execute effects.

## Start with one effect

This is the complete construction in `examples/one_effect.zig`:

```zig
const boundary = @import("boundary");

pub const Application = struct {
    pub fn emit(a: *boundary.authoring.Builder) !boundary.authoring.Module {
        const integer = try a.scalar(u32);
        const lookup = try a.external("example.lookup.v2", integer, integer);
        const entry = try a.declare("main", &.{
            .{ .name = "input", .schema = integer },
        }, integer, &.{lookup});
        var body = try a.body(entry);
        const reply = try body.perform(lookup, try body.parameter("input"));
        try a.define(entry, try body.finish(reply));
        return a.module(entry, try a.scalar(void));
    }
};
```

Call `boundary.authoring.lower(allocator, Application)`, defer
`compiled.deinit()`, and encode with `compiled.encode`. The repository example
does this and can be emitted with:

```sh
zig build emit-one-effect -Doptimize=ReleaseSafe > one-effect.bpi3
```

The application must obtain World from its own trusted delivery. Verify that
bundle with `world.mjs runtime verify --root BUNDLE --manifest-sha256
EXPECTED_MANIFEST_SHA --smoke`. Then use World's public `Kernel`, `encodeInput`,
`decodeOutcome`, `decodeRequest`, and `encodeResult` API. The environment supplies
typed external replies; the program owns the continuation. The
[public-package client](../test/public_authoring_client/main.zig) and its
[World driver](../test/public_authoring_client/world.mjs) show the complete
encode, request/reply, restore, and result path without private imports.

## Two stages, two kinds of control

| Native Zig staging | Generated computation |
| --- | --- |
| Zig `if` chooses source to construct | `Body.select` chooses a branch when World runs |
| Zig `try` propagates allocation or construction errors | `Body.checkedAdd` and `Body.fail` emit runtime failures |
| Zig `defer` releases an emitter owner | `Body.protect`, `Body.dispose`, and region scopes govern portable cleanup |
| Calling a staging callback creates source | `Body.apply` runs a symbolic callable under World |
| Creating `Body.lambda` records code and its environment | Applying the callable forces that code when demanded |

`Body.checkedAdd` takes a `FailureLiteral` from `Builder.literalFailure`; its
overflow payload is encoded in the image. `Body.fail` takes an ordinary runtime
`Value` and can fail with a computed payload.

Build each runtime branch as a child body and finish it. `Body.select` joins
equal result schemas. Values from the parent can be read in children; a sibling
local cannot be read in another branch or after the join. The join's returned
value belongs to the parent. A nested function body created by `bodyWithin`
can capture its parent; Boundary checks its explicit capture bound and use.
Copies of the same `Body` share one scope-owned statement sequence; finishing
any copy closes that scope after all of its staged statements have been folded.

`Body.lambda` creates a symbolic callable expression. Repeating that expression
may construct distinct runtime closures. Use `Body.bindValue` when subsequent
operations must refer to **one** runtime value. The checker then rejects
sequential double consumption of a one-shot value and permits uses in mutually
exclusive branches where its control-flow proof allows them.

`Body.finish` closes that body for authoring. Its local handles cannot be used
through another body. Closing a nested native body does not shorten the lifetime
of a runtime closure it authored; Boundary's ownership checker governs that.
`Body.abandon` closes an unfinished body and its descendants for authoring
without producing a block. A function whose body was abandoned cannot become
a checked Module until a valid definition is supplied.
The raw source builder and its arena must outlive all authoring handles. The
convenience `authoring.lower` owns and releases both after compilation. If an
allocation fails while building manually, discard the builder and tear it down;
no successful checked Module is returned by the failed call.

## Data, effects, and handlers

`Builder.record` and `Body.product`/`field` use field names, while
`Builder.variant` and `Body.inject`/`variantCase`/`matchVariant` cover tagged
alternatives. The descriptor slices can be selected at authoring time; their
schema IDs do not need to be `comptime`. `productSchema`, `sumSchema`, and
`sequenceSchema` also accept checked schema handles. Portable records and
variants are explicit; this API does not serialize arbitrary Zig pointers or
recursive host objects.
Names are authoring metadata. Two records or variants may have the same
positional source schema ID while assigning different names to those positions.
The high-level handles retain the named layout across declarations, calls,
applications, handlers, and joins, and reject a mismatched named access. The
product, sum, and sequence schema constructors retain child descriptions too,
as do the exposed cell and cleanup-exit descriptions. Nested named layouts
therefore remain checked across calls and effect payloads. The
metadata does not change BPI3 or make data identity nominal at runtime.
Copy returned handles as needed; construct a new declaration to change its
signature. Editing an issued value, effect, function, interpretation, or
finished block's type or origin metadata is rejected.
`Builder.module` checks named failure values and protected cleanup exit
descriptions in defined bodies against its declared failure schema.
If a raw fail value or cleanup lambda lacks authoring provenance, a module with
a named failure schema rejects it; the low-level source API remains available.
`Builder.module` returns an issued authoring Module that retains that failure
description. `Builder.compile` checks it again against the captured source view
before lowering, including definitions of already staged helpers added after
module construction. Source terms added after publication are outside that view.

`Builder.external` declares a host-facing operation. `Builder.local` declares
one interpreted through a nominal capability. Two local effects with identical
names remain different instances. `Body.performLocal` checks the capability's
instance; a handler does not accept a same-shaped foreign capability.

`Builder.scopedLocal` names the operation's callable body parameters and its
explicit use-site effect allowance. `Body.performScoped` checks the supplied
body schemas and nominal use-site capabilities. The handler clause receives
each scoped body by its declared name. `examples/authoring_scoped.zig` demands
one such body through a derived clause; constructing it in Zig does not run it.

`Builder.interpret` derives one operation's clause parameters, resumption input,
handler answer, and state schema from its declarations. The return and clause
functions expose named `value`, `payload`, and `resume` parameters plus named
state fields. Define their bodies with normal forward construction. Deep versus
shallow mode, resumption use, capture bound, residual effects, escaping effects,
and region allowances remain explicit. `Body.resumeValue`, `resumeWith`, and
`resumeComputation` expose the relevant continuation forms. The handled body
result (`input`) and outer handler result (`answer`) may differ. A clause can
return an answer without resuming when its declared use permits that.
For a deep handler, a resumption returns the outer answer; for a shallow
handler, it returns the handled input. A shallow continuation may be attached
to a compatible deep or shallow successor. A resumed computation receives the
operation's declared use-site capability parameters, when any, and may only
exercise their explicit effect allowance.

For a common question/responder pattern, `Builder.responding` takes an authored
responder function, the handled body's result schema, an explicit residual row,
capture bound, mode, and use. It derives the identity return clause and the
resumption call. The responder's declared effects must fit the residual row;
interpreting the local question does not make its external lookup pure. See
`examples/authoring_responder.zig` and the outside-tree client. Shallow state
reattachment and a deep answer-changing bypass are shown in
`examples/authoring_shallow.zig` and `examples/authoring_bypass.zig`.

For protected owned resources, `Builder.resource`, `borrowedSchema`,
`resourceAuthority`, and `Body.packResource`/`unpackResource` expose the current
nominal resource contract. `Builder.region` and `declareScoped` keep the region
allowance explicit; `Body.protect` installs local cleanup and transfers the
owned value to it. The cleanup callable needs an authored exit-info first
parameter and a unit result; module publication checks the exit-info failure
description against its failure schema. `examples/authoring_borrow.zig`
exercises a valid borrow and
protected release. Ownership admission remains Boundary's checker, including
borrow escape and nonduplicable capture restrictions.

## Errors and compatibility

Zig rejects category swaps such as passing an `Effect` where a `Schema` or
`Function` is required. Authoring operations reject foreign-builder handles,
out-of-scope values, incompatible fields, arguments, branch joins,
capabilities, and disallowed responder effects. Inspect `Builder.diagnostic`
for a stable category, the authored entity, expected/actual schemas, and
introduction/use names when known; `Diagnostic.render` prints the same record.
`Builder.compile` also retains the source/target checker detail for capture,
borrow, use, and admission errors. Diagnostics borrowed from a manually owned
builder remain valid until its raw source arena is destroyed. Labels are
metadata: changing them does not change executable BPI3 bytes or force delayed
work.

For an error that must be inspected after teardown, use a manually owned
`Builder` and call `OwnedDiagnostic.copy(allocator, builder.diagnostic.?)`
immediately after the reported error. The caller owns that snapshot and calls
`deinit`. Allocating it can return `OutOfMemory`. A later authoring operation
clears the borrowed diagnostic before reporting its own result; no stale
diagnostic is inferred from an arbitrary application callback's final error.

The low-level `boundary.computation.Builder` API remains public. `adoptSchema`,
`adoptEffect`, `adoptRegion`, and `authoring.Interop` form an explicit bridge for
existing source libraries. A raw numeric ID cannot recover the builder it came
from; the bridge caller must supply an ID from the same source builder, and
Boundary's source checker remains authoritative. The reciprocal example keeps
`hyper.ana` and demand interpretation in the existing library while the small
`hyper_authoring` adapter contains raw interoperation. Ordinary application
code and the package client need no catalog access or raw AST records.
IDs exported from a typed value or block retain their authoring schema in the
bridge, so re-adoption under a same-shaped but differently named layout rejects.
Their lexical origin is retained too, so re-adoption cannot move a branch-local
value or finished branch block into its parent.
An unrelated raw ID has no recoverable named-layout provenance and cannot be
adopted as a named handle; advanced callers keep using the low-level source API
for that path.
Metadata-free adopted callables and resumptions can satisfy unnamed schemas,
but a matching numeric ID alone cannot satisfy an authored named argument or
result. `Interop.lambdaAs` retains the authored function signature when a raw
lambda must enter the typed API.

## What the migrations remove

In `combinators.twice`, the old source manually allocated two destination
variables, made two raw `apply` terms, then nested two binds backward before
forming a product. The migrated body calls `apply` twice in order and constructs
a named `first`/`second` record. The same reusable callable contract, effects,
regions, specialization evidence, and two runtime calls remain.

In `choice`, the old construction separately repeated effect IDs, resumption
input/answer/effect lists, return and clause parameter ordinals, and handler
clauses. `Builder.interpret` now derives those mechanical relationships from
the selected operation and named parameters. The choice between all results or
the first result, multi-shot permission, deep mode, capture bound, residual row,
and owned/borrowed regions remain explicit. The existing public `all`, `first`,
and `allScoped` signatures are preserved.

## Verification account

`zig build check-public-authoring` copies the normal package into an external
temporary directory and builds/tests the retained client through public imports.
It forwards the parent Zig global-cache choice to that nested build, including
an explicit `--global-cache-dir` override.
Runtime scripts in `test/v2` and the client directory accept an independently
verified World bundle and fixed native companion as arguments. No World source,
kernel, capacity, or wire format is changed by this API.

### Required discriminators

The focused Zig tests are in `src/v2/authoring_tests.zig`; the named World
scripts below accept the verified bundle, image, kernel digest, and fixed native
runner as arguments. These are bounded observations. Boundary's source and
target admission retain general authority.

| ID | Witness |
| --- | --- |
| A01 | Equal-index foreign schema and value handles reject; local handles lower. |
| A02 | Sibling and unrelated-function values reject; explicit joins and nested capture lower. |
| A03 | Zig category types remain distinct. |
| A04 | `authoring_branch_world.mjs` executes only the selected effectful branch. |
| A05 | `authoring_twice_world.mjs` observes two ordered requests and independent replies. |
| A06 | Choice all/first, shallow successor state, and deep answer/bypass World drivers distinguish results and traces. |
| A07 | `authoring_bypass_world.mjs` resumes non-tail work; `authoring_protect_world.mjs` retains local cleanup across fresh-instance restoration. |
| A08 | A bound linear callable works in exclusive branches; sequential reuse and reusable capture reject; copy-safe capture and a protected borrow succeed. |
| A09 | The public client rejects a foreign nominal capability; responder construction rejects a missing residual allowance. |
| A10 | Client and bypass World drivers check which requests precede success and authored failure. |
| A11 | `authoring_config_world.mjs` obtains 11/12/11 from same-type configurations and one reused declaration. |
| A12 | `authoring_lazy_world.mjs` leaves an unused failing delayed body undemanded and fails when demanded. |
| A13 | `hyper_demand_world.mjs` restores reciprocal State in fresh Node processes; `authoring_wasmtime.mjs` compares Node/Wasmtime/native transfer. |
| A14 | Runtime-selected named record and variant schemas lower; wrong fields, callable arguments, and nested product/sum/sequence layouts reject. |
| A15 | Allocation-failure iteration covers constructors, finalization, encoding, and owned diagnostics; an exhausted builder cannot publish a Module. |
| A16 | `zig build check-public-authoring` builds/tests an outside-tree public-package client, whose World driver checks execution. |
| A17 | Structured category, entity, schema, scope, and source detail tests cover authoring and ownership failures; label-only edits emit equal bytes. |
| A18 | Existing source, component, data, and semantic regressions remain in both aggregates; the data-only entry and its 104 tests pass. |

### Baseline comparison and cost

The immutable source baseline is `ab0c52636023b7db7690f647f0fedc10bbba93ef`.
The four migrated constructions were emitted from it and from this branch with
Zig 0.16.0 in ReleaseSafe. Structural counts are schema/constant/effect/function/
block/instruction/handler counts from admitted BPI3 data:

| Construction | Baseline bytes and counts | Candidate bytes and counts |
| --- | --- | --- |
| `one_effect` | 85; 2/0/1/1/2/0/0 | 85; 2/0/1/1/2/0/0 |
| linked `twice` component | 803; 22/4/3/12/29/22/2 | 803; 22/4/3/12/29/22/2; byte-identical |
| choice all | 269; 7/3/1/4/9/8/1 | 269; 7/3/1/4/9/8/1; byte-identical |
| choice first | 247; 7/2/1/4/8/6/1 | 247; 7/2/1/4/8/6/1 |
| reciprocal demand | 1,234; 16/6/3/23/57/25/2 | 1,246; 16/6/3/23/58/25/2 |

The recursive image's 12-byte, one-block increase comes from a final forward
bind around an existing hyperfunction term. It does not duplicate a body per
runtime input; fresh-State request/reply/failure traces match the baseline.
One paired representative workflow used three isolated-cache ReleaseSafe native
emitter builds, nine already-built process emissions, and 40 warm-kernel World
start/reply replays per version. Medians were baseline→candidate: build
12.603→13.065 s, emission 2.521→2.555 ms, and replay 0.585→0.627 ms. These
local paired observations show a modest build/emission cost; the warm replay
difference is negligible at this scale. They are not a throughput guarantee or
a reason to change World's selected package.
