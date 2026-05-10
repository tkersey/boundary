# ProgramPlan authoring

`ability.program(label, Handlers, Body)` is the public execution entry point for
compiled plans. A body must expose `Body.compiled_plan`, and that value must be
an `ability.ir.ProgramPlan`.

The root package stays small: `ability.effect`, `ability.ir`,
`ability.program`, and `ability.Runtime`.

## Scalar body

A scalar plan uses scalar locals and scalar `ProgramValue` entry arguments. If
the plan has entry parameters, `Body.encodeArgs(handlers)` may return a slice or
array pointer of `ability.ir.ProgramValue`.

## Typed product body

Product plans use `.product` value refs and schema table rows. The body must
declare `Body.value_schema_types` with the exact Zig product type for each
schema index that execution can reach.

`Body.encodeArgs` may return a tuple, for example:

```zig
pub fn encodeArgs(_: Handlers) @TypeOf(.{Payload{ .amount = 42 }}) {
    return .{Payload{ .amount = 42 }};
}
```

The tuple field type must match the entry parameter ref. A product result is
returned as the typed Zig product in `Program.Result.value`.

## Typed sum body

Sum plans use `.sum` value refs and schema-local variant tables. Optional values,
enums, and tagged unions are represented as sum schemas. The body declares the
exact Zig sum type in `Body.value_schema_types`.

`sum_variant_is` compares a sum local against a schema-local variant ordinal and
writes a bool local for ordinary `branch_if` control flow. Unit enum variants
can be matched this way.

`sum_extract_payload` extracts a non-unit variant payload into a destination
local whose value ref exactly matches the variant payload. Extracting a unit
variant or using the wrong destination ref is rejected during plan validation.
Extracting the wrong active variant at runtime fails with
`error.ProgramContractViolation`.

## Outputs

A body with outputs declares:

```zig
pub const Outputs = []i32;
pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *Handlers) !Outputs;
```

The output declarations in `ProgramPlan.outputs` describe the contract metadata.
`collectOutputs` materializes the typed value that appears at
`Program.Result.outputs`.

If outputs own memory, add:

```zig
pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void;
```

Output cleanup runs from `Program.Result.deinit()`. Result cleanup and output
cleanup are independent.

## Result cleanup

Typed results that own memory can expose:

```zig
pub fn deinitResult(allocator: std.mem.Allocator, value: ResultType) void;
```

`deinitResult` runs from `Program.Result.deinit()`. If output collection fails
after a result has been produced, result cleanup still runs. Output cleanup does
not run unless outputs were collected.

Scalar strings and strings inside typed products or sums are borrowed unless the
body documents allocator ownership and implements the matching cleanup hook.

## Nested lexical-with targets

Nested lexical-with execution is explicit. A body opts in with
`Body.nested_with_targets`, using `ability.ir.NestedWithTarget` entries that map
metadata packets to function indexes. `ability.ir.builder.finishWithNestedTargets`
validates the target list while producing the same `ProgramPlan` shape.

The metadata string must exactly match the `call_nested_with` instruction packet.
The function index must name the zero-parameter function that should execute for
that packet. A target with the right metadata but the wrong function index is not
treated as a near miss: it is rejected if the indexed function cannot be entered
as a nested target or if its completion/result shape does not match the call site.

Missing or mismatched targets fail closed. Terminal nested targets may complete
the whole program when their terminal result ref matches the caller's result ref,
including typed product and sum results declared through `Body.value_schema_types`.
There is no global target discovery.

## Program.contract

Every compiled program exposes `Program.contract`, a read-only projection of the
validated body and plan contract. It includes:

- label, result ref, result type, output refs, and output type
- entry parameter refs
- value schema, field, and variant declarations
- requirements, operations, payload refs, resume refs, modes, and after flags
- nested-with target declarations
- unique reachable `return_error` literals
- executable and session capability-ledger metadata
- static session operation yield sites and after-continuation sites

The session ledger includes trace capability flags and the stable fingerprint
version for hosts that want to gate replay/audit behavior from contract
metadata. It also includes `yield_sites` and `after_sites` catalogs derived from
the same entry reachability used by executable/session support. Operation sites
carry stable indexes and fingerprints, function/block/instruction coordinates,
requirement/op metadata, payload/resume/result refs, mode, after capability, and
whether the host may resume or return now. After sites are generated per
reachable after-enabled call site and point back to the source operation site.
Two instructions that call the same op therefore have distinct site indexes and
fingerprints.

`Program.contract` is inspection metadata. It does not expose mutable function,
block, instruction, Artifact, VM, compiler, parser, or capability-map surfaces.

## Program.protocol

`Program.protocol` turns the session site catalog into a typed defunctionalized
protocol surface. It is a static property of the compiled program, derived from
`Program.contract.session.yield_sites` and `after_sites`; it is not an automatic
host driver and does not change `Program.run` or `Program.Session` execution.

Operation descriptors are looked up by static identity:

```zig
const Decide = Program.protocol.operationSite("agent", "decide", 0);
const Tool = Program.protocol.operationSite("tool", "call", 0);
comptime Program.protocol.assertOperationSitesCovered(.{ Decide, Tool });
```

The occurrence index disambiguates repeated static call sites for the same
requirement label and op name. `siteByIndex(index)` is available when the stable
site index is already known. Each operation descriptor exposes `Payload`,
`Resume`, and `Result` type aliases, plus the site index, site fingerprint,
function/block/instruction coordinates, requirement/op identity, op mode,
payload/resume/result refs, `has_after`, `may_resume`, and `may_return_now`.

After descriptors are looked up with `afterSite(requirement_label, op_name,
occurrence_index)` or `afterSiteByIndex(index)`. They expose `Output` and
`Result` type aliases plus the after-site index and fingerprint, source operation
site index and fingerprint, source function/block/instruction coordinates,
original requirement/op identity, and output/result refs. When a handler type
declares `afterDispatch`, the descriptor also exposes `Input`, a static
`input_ref`, and derives input/output types from that handler signature.
Handlerless after descriptors set `has_static_input_ref = false` and
`input_ref = null`; their current input ref is a property of the live after
request's concrete unwind stack.

Dynamic requests can be checked against a descriptor before host code decodes or
responds:

```zig
if (request.matches(Decide)) {
    const typed = try request.as(Decide);
    const payload: Decide.Payload = try typed.payload();
    const trace = try typed.responseTrace(.@"resume", response);
    try session.resumeTyped(typed, response);
    _ = payload;
    _ = trace;
}
```

The check first proves the descriptor belongs to the same program. Operation
requests then compare static site identity and payload/resume/result refs. After
requests compare static site identity and result ref, plus the current input ref
when the descriptor has one. The expected output ref is carried by the live after
request because final and stack-dependent continuations can require a different
output than the descriptor's handler-derived `Output` alias. Handler-owned after
requests use `after.as(AfterSite)` and `typed_after.value()` as
`AfterSite.Input`. Handlerless after requests use `typed_after.value(T)` after
checking the live request's `value_ref`. Both forms use
`after.responseTraceFor(AfterSite, value)` and
`session.resumeAfterTyped(typed_after, value)` with a value matching the live
request output ref.

Coverage helpers are optional comptime witnesses. `assertOperationSitesCovered`,
`assertAfterSitesCovered`, and `assertAllSitesCovered` fail when a reachable
site is omitted, a descriptor is repeated, or a descriptor belongs to another
program. They intentionally stop at enumeration coverage; the library does not
generate a visitor DSL, trait-style host implementation, async dispatcher, or
automatic method dispatch.

## Program.Session

`Program.Session` runs the same validated `Body.compiled_plan` as a caller-owned
request loop. `Session.start` prepares explicit interpreter state without
leaving runtime execution active. `next()` enters runtime execution only long
enough to advance the interpreter, then returns either an operation request, an
after-continuation request, or the final `Program.Result`.

An operation request carries stable requirement/op metadata, payload, resume
ref, result ref, control mode, and after-hook flag. `request.payload(T)` decodes
the typed payload only when `T` matches the plan ref. The host resumes transform
and choice requests with `session.@"resume"(request, value)`, or completes
choice and abort requests through `session.returnNow(request, value)`. The value
type must match the request's resume or terminal result ref.

`request.trace()` returns a read-only operation trace view: program label, plan
label and hash, monotonically increasing session turn index, request kind,
static operation site index and fingerprint, function/block/instruction
coordinates, requirement index and label, op index and name, op mode,
payload/resume/result refs, payload value fingerprint, after flag, fingerprint
version, and stable request fingerprint. `request.fingerprint()` returns the
same request
fingerprint directly, and `request.expectFingerprint(expected)` returns a
precise mismatch error without mutating the session.

When normal completion reaches pending after hooks, session execution yields
after-continuation requests as data rather than calling synchronous
`afterDispatch`. An after request carries the original requirement index and
label, original op index and name, the current value ref and typed value through
`after.value(T)`, the expected transformed output ref, and request identity for
the active session/token. The host resumes that continuation with
`session.resumeAfter(after, transformed_value)`. Multiple pending after hooks
yield in the same reverse unwind order that `Program.run` applies.

`after.trace()` returns the after-request trace view: program label, plan label
and hash, session turn index, request kind, static after-site index and
fingerprint, source operation site index, source function/block/instruction
coordinates, original requirement index and label, original op index and name,
current value ref and fingerprint, expected output ref, result ref, fingerprint
version, and stable request fingerprint.
`after.fingerprint()` and `after.expectFingerprint(expected)` provide the same
direct replay witness helpers as operation requests.

Return-now choice paths and abort terminal paths preserve the terminal behavior:
they bypass pending after continuations when the synchronous semantics bypass
them. Abort operations still cannot declare after hooks under the existing plan
validation rules.

Session execution preserves interpreter frames across helper calls and nested
lexical-with targets. Final result and output materialization use the same
`Body.collectOutputs`, `Body.deinitOutputs`, and `Body.deinitResult` ownership
hooks as `Program.run`.

When `next()` yields an operation or after-continuation request, the session is
parked. The continuation remains explicit session data, runtime active execution
bookkeeping is balanced before control returns to the host, and
`Runtime.deinitChecked()` rejects the owning runtime while the live session still
exists. A parked session can resume later only on the same runtime and owning
thread. Because active execution is not held while parked, host code can run
other programs or other sessions on that runtime between turns.

Operation and after requests expose `responseTrace(kind, value)` helpers. The
response trace records the matching request fingerprint, response kind,
response ref, response value fingerprint, fingerprint version, and a stable
response fingerprint. Response fingerprints distinguish `resume`, `return_now`,
and `resume_after`, and change when the response value changes.

Value fingerprints hash the typed value visible to the host. Scalar support
covers unit, bool, i32, usize, and string contents rather than string pointer
identity. Product and sum support is schema-guided through
`Body.value_schema_types`: product hashing includes the schema identity, field
names, field refs, and field value fingerprints; sum hashing includes schema
identity, variant name/ordinal/ref, and payload fingerprint. Unsupported trace
hashing boundaries fail closed instead of inventing unstable ids.

Trace metadata is a replay-verification substrate. A host can record the next
request fingerprint, rerun a fresh deterministic session, call
`expectFingerprint` on the yielded request, and only then supply a previously
recorded response. The library does not own or serialize trace events.

## Defunctionalized execution and agent loops

`Program.Session` is a defunctionalized execution surface for host-driven loops.
The interpreter reaches an effect operation or after-continuation boundary,
stores its explicit frame state, parks runtime execution, and yields request data
with requirement/op metadata, payload and resume refs, the operation mode, and
typed payload access through `request.payload(T)` or `after.value(T)`.

The same request data exposes deterministic trace and fingerprint metadata for
audit-friendly loops. Request fingerprints include plan identity, request kind,
session turn, static site identity, requirement/op identity, relevant refs, and
payload/current value fingerprints. Response fingerprints include the matching
request fingerprint, response kind, response ref, and typed response value
fingerprint. These fingerprints are stable across fresh deterministic runs with
the same plan, entry args, host responses, and execution path, and are
intentionally separate from in-process request tokens. Static site identity is
not dynamic turn identity: repeated loop yields from the same instruction reuse
the same static site index, while turn indexes distinguish the individual
occurrences.

The host owns external work. It can resume transform and choice requests with a
value matching the resume ref, complete choice and abort requests with a value
matching the current terminal result ref, or resume after continuations with a
typed transformed value matching the after output ref. `ProgramValue` remains
scalar; typed product and sum values use the existing `Body.value_schema_types`
registry that `Program.run` already uses for executable plans. The final value,
outputs, and cleanup hooks follow the same `Program.Result` rules as
synchronous execution.

The session surface does not add an async runtime, parser, compiler, VM,
Artifact API, source-language API, network client, LLM client, public generated
custom effect API, or public root export. Full snapshot/restore for durable
session persistence is intentionally left for a later branch. Trace metadata is
not a snapshot/restore mechanism and is not a serialization format; hosts own
persistence and external orchestration. `ProgramValue` remains scalar, and no
new value codecs are added. Request tokens remain in-process misuse guards, not
durable ids; site, request, response, and value fingerprints are audit and
replay-verification metadata.

## Effect schema row lowering

Built-in effect schemas can lower to ProgramPlan requirement, operation, and
output rows through `ability.ir.schema.LowerBinding`. The caller supplies the
binding type and the table offsets:

```zig
const StateRows = ability.ir.schema.LowerBinding(
    ability.ir.schema.Binding("state", ability.effect.state.Schema(i32, error{}), void),
    .{ .requirement_index = 0, .first_op = 0, .first_output = 0 },
);
```

The returned comptime row bundle contains:

- one `RequirementPlan` row with the binding label, op span, lifecycle tag, and
  output tag derived from the schema
- one `OpPlan` row per family operation with op name, control mode,
  payload/resume codec, payload/resume schema index, and after-hook flag
- zero or one `OutputPlan` row for schema-declared outputs such as state
  final-state or writer accumulator outputs, labeled by the binding label

Offsets remain caller-controlled. The lowerer does not allocate from a hidden
registry, reorder tables, or decide the surrounding ProgramPlan layout. This
keeps it composable with raw rows and with the layout builder.

Scalar payload, resume, and output refs lower without extra metadata. Product
and sum refs require a caller-owned, local schema-index map so the lowerer can
emit the same ordinary ProgramPlan refs a raw row would contain:

```zig
const schema_refs = ability.ir.schema.SchemaRefs(.{
    ability.ir.schema.ref(ProductPayload, 0),
    ability.ir.schema.ref(OptionalPayload, 1),
});

const ExceptionRows = ability.ir.schema.LowerBinding(
    ability.ir.schema.Binding(
        "exception",
        ability.effect.exception.Schema(ProductPayload, error{}, void),
        void,
    ),
    .{ .requirement_index = 0, .first_op = 0, .schema_refs = schema_refs },
);
```

The map is explicit and comptime-only. It rejects scalar entries and duplicate
Zig types, and a missing product/sum payload, resume, or output type fails at
compile time. The indexes are the caller's existing `value_schemas` table
indexes; nested product/sum schema rows still reference whatever caller-owned
schema indexes those rows declare. No hidden registry or global schema discovery
exists.

Writer accumulator schemas distinguish the final handler output from the
ProgramPlan output row. The schema final output is the collected `[]Item`; the
ProgramPlan `OutputPlan` row records the accumulator item ref, because the body
`Outputs` type owns the collection shape and cleanup.

For built-in plan-native helpers, schema lowering is preferred over hand-written
per-built-in row generators. Raw `ability.ir.plan.*` rows remain available for
tests that deliberately exercise table escape hatches or unsupported shapes.

## Custom Protocol Families

Custom protocol families are schema-first authoring data under
`ability.ir.schema.Protocol`. They lower through the same ProgramPlan row path
as built-ins:

```zig
const Approval = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        ability.ir.schema.transform("exists", []const u8, i32),
        ability.ir.schema.choiceAfter("request", []const u8, i32),
        ability.ir.schema.abort("invalid", []const u8),
    },
});

const ApprovalRows = Approval.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
});
```

`ApprovalRows.requirement`, `ApprovalRows.ops`, and `ApprovalRows.outputs` are
ordinary rows. The caller still owns requirement, op, output, and value-schema
indexes. Product and sum payload, resume, and output refs use explicit
`SchemaRefs`; scalar refs need no entries. There is no hidden registry or table
reordering.

After-enabled custom protocol rows publish `has_after` only for
requirement-labeled handler shapes such as `.approval.request.afterDispatch` or
`.approval.authored.afterDispatch`. Top-level op-name and top-level `authored`
fallbacks can still be runtime conveniences when a full plan has globally unique
op names, but row lowering cannot prove that global uniqueness in isolation.

The lowered row bundle also exposes op descriptors for instruction authoring:

```zig
const Request = ApprovalRows.op("request");
try Request.call(root, decision_local, approval_request_local);
```

After compilation with `ability.program`, no custom runtime surface is needed.
`Program.contract` exposes the custom requirement/op rows and session yield
sites, and `Program.protocol` derives typed host-facing descriptors from those
sites. Session hosts can use `matches`, `as`, typed payload/value views,
`resumeTyped`, `returnNowTyped`, `resumeAfterTyped`, response traces, and
coverage helpers exactly as they do for raw ProgramPlans.

`examples/custom_approval_workflow.zig` is the reference custom protocol
example. It defines a `workflow` family with transform, choice, and abort
operations, authors the control flow with ProgramPlan builder helpers, runs
synchronously through `Program.run`, and demonstrates the host-driven
`Program.Session` path through `Program.protocol`.

## Built-in plan helper namespaces

`ability.effect.optional.plan`, `ability.effect.state.plan`,
`ability.effect.reader.plan`, and `ability.effect.writer.plan` are reusable
plan-native helper namespaces. They emit ordinary ProgramPlan rows, value refs,
locals, op refs, and instruction helpers; they do not add a runtime, VM, parser,
compiler, source language, Artifact surface, public root export, value codec, or
custom-effect API.

The state, reader, and writer helpers are transform/output built-ins backed by
the shared schema lowerer:

- `ability.effect.state.plan` exposes state-cell row lowering, scalar and
  explicit-schema state refs/locals, `get` and `set` op refs, `callGet`,
  `callSet`, and the canonical final-state output row shape. The caller owns the
  requirement index, first op index, first output index, and any schema refs.
- `ability.effect.reader.plan` exposes reader-environment row lowering, scalar
  and explicit-schema environment refs/locals, the `ask` op ref, and `callAsk`.
  Reader has no ProgramPlan output row.
- `ability.effect.writer.plan` exposes writer-accumulator row lowering, scalar
  and explicit-schema item refs/locals, the `tell` op ref, `callTell`, and the
  canonical accumulator output row shape. The ProgramPlan output row records the
  accumulator item ref.

These helpers pair with `ability.ir.builder.layout` for ordinary plan authoring:
the helpers produce requirement/op/output metadata and call instructions, while
the layout builder computes function/local/block/instruction table offsets.
Raw ProgramPlan rows remain available when exact table construction is the goal.
Compatibility APIs such as `ability.effect.state.handle`,
`ability.effect.reader.handle`, and `ability.effect.writer.handle` remain
available.

Output ownership stays with the body. `Body.collectOutputs` materializes the
typed output value, and `Body.deinitOutputs` releases any memory owned by that
value. Writer accumulator helpers therefore describe the item ref in the plan
row, while the body still chooses the collected container shape, such as
`[]Item`.

## Examples

Run the typed ProgramPlan example with:

```sh
zig build run-typed-program-plan
```

It demonstrates typed product execution, optional sum matching,
tagged-union payload extraction, output collection and cleanup, and
`Program.contract` inspection through the public API.

`examples/plan_native_optional.zig` demonstrates optional-like control flow as a
plan-native choice operation. The handler either resumes with a typed optional
sum value or returns immediately. The plan branches with `sum_variant_is`,
extracts the `some` payload with `sum_extract_payload`, and leaves the
compatibility `ability.effect.optional.handle` path intact.
`ability.effect.optional.plan` is the reusable plan-native helper namespace for
this shape. It supplies the optional outcome convention, requirement/op rows,
schema rows with caller-owned field/variant offsets, variant rows, and sum-match
instructions; ordinary authored plans still own their layout-builder control
flow.

`examples/plan_native_state_reader.zig` demonstrates state and reader through
`ability.effect.state.plan`, `ability.effect.reader.plan`, and the layout
builder. Its requirement, op, and output metadata come from schema lowering
through those helper namespaces. The state schema contributes `state_cell`
metadata and a binding-labeled final-state output declaration. The reader schema
contributes `reader_environment` metadata and borrows its environment through
the handler, without a handler-owned side channel for the returned value.

`examples/plan_native_writer.zig` demonstrates writer accumulation through
`ability.effect.writer.plan` and the layout builder. The helper lowers the
`writer_accumulator` requirement and accumulator output metadata. The ProgramPlan
output row records the accumulator item codec, while `Body.Outputs` remains the
collected slice materialized as `Program.Result.outputs` and released through
`Body.deinitOutputs`.

`examples/plan_native_exception.zig` demonstrates exception-like abort control
flow as a plan-native `throw` operation. The requirement carries `abort_catch`
metadata, scalar/product/sum payloads are passed to the handler, and the handler
returns the terminal result.

`examples/plan_native_resource.zig` demonstrates resource-like lifecycle rows as
plan-native `acquire` and `release` operations with `resource_bracket` metadata.
The plan explicitly releases typed resources in LIFO order before normal return,
exception-style abort, and optional return-now control transfer.

`examples/agent_loop.zig` demonstrates `Program.Session` as a host-driven
request loop. The plan yields a `decide` operation, the host resumes it with a
typed sum action, a `tool` action causes the plan to yield a tool operation, and
the returned observation is carried by the same ProgramPlan interpreter until a
`final` action returns the answer. The example records request and response
fingerprints during the first run, prints the operation site index for each
yielded request, then starts a fresh session, verifies each recorded request
fingerprint, replays the recorded typed response, and reaches the same final
answer without any network or LLM integration.

## Layout builder

Raw `ability.ir.plan.*` tables remain available as the low-level escape hatch.
Use them when a test needs exact table control, when reproducing a validation
failure, or when deliberately asserting individual `first_*` and `*_count`
values.

For ordinary authored plans, prefer `ability.ir.builder.layout`. The layout
builder accepts nested function specs with local specs, block specs,
instruction lists, and terminators, then computes the flattened table offsets
for the existing `ability.ir.ProgramPlan`:

- function `first_local`, `local_count`, `first_block`, `entry_block`,
  `block_count`, `first_instruction`, and `instruction_count`
- block `first_instruction`, `instruction_count`, and `terminator_index`
- function-local branch and jump targets into global block table indexes

Requirement, operation, output, schema, field, and variant tables are still
ordinary ProgramPlan rows. The layout builder handles table layout for
functions, locals, blocks, instructions, and terminators. The schema lowerer
handles requirement/op/output metadata when an effect binding schema exists.
The first version keeps requirement/op/output spans explicit, while removing
manual local/block/instruction/terminator bookkeeping.

`ability.ir.builder.layout.finish` and `finishWithNestedTargets` validate
through the same ProgramPlan validator and return the same
`ability.ir.ProgramPlan` shape as `ability.ir.builder.finish`. The layout
builder is a comptime authoring layer; use it from `Body.compiled_plan` or
other comptime plan constants.

The layout builder is not a parser, compiler, VM, Artifact surface, source
language, value codec, effect authoring API, or second IR. Nothing survives past
construction except the validated `ProgramPlan`.

`Program.contract` is the public proof surface for generated plans. Tests should
assert contract facts such as labels, result refs, entry parameter refs, value
schemas, fields, variants, requirements, ops, payload/resume refs, after flags,
nested-with targets, and outputs instead of depending on mutable table access.

`ability.ir.schema.LowerBinding` is the preferred row-metadata route for
built-in plan-native helpers. Built-ins should share that schema path instead
of adding bespoke requirement/op/output row generators. Optional-shaped helpers
may still provide control-flow conveniences, but the common metadata should
come from schemas when the schema can describe it.

This is not custom effect authoring yet. It does not expose `effect.Define`,
`effect.ops`, public generated custom effects, a parser, compiler, VM,
Artifact surface, source language, value codec, second IR, or new execution
semantics. It only emits ordinary ProgramPlan row structs that can be inspected
through `Program.contract`.

For common typed examples, `ability.ir.builder.typed` remains available and now
builds through the layout layer while still returning the same
`ability.ir.ProgramPlan`:

- `scalarConstI32`
- `productIdentity`
- `sumVariantI32Branch`
- `sumExtractI32Payload`
- `unitWithOutputs`

These helpers cover scalar demos, product results, optional or enum-like
variant branches, tagged-union `i32` payload extraction, and output declarations.

## Custom effect authoring

Minimal schema-first custom protocol-family authoring is available under
`ability.ir.schema.Protocol`. It is plan-native: custom descriptions lower to
the same ProgramPlan requirement, op, value schema, output, nested-with, and
contract metadata used by built-in prototypes.

See [custom_effect_authoring.md](custom_effect_authoring.md) for the design
boundary and non-goals.
