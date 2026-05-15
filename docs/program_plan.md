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

## Semantic Program Authoring

`ability.ir.builder.semantic` is the preferred authoring layer for ordinary
custom protocol programs. It is a construction helper, not a source language:
`finish(spec)` lowers typed functions, parameters, locals, named blocks,
terminators, and protocol calls into the existing `ability.ir.ProgramPlan`.
After construction, execution, validation, contracts, sessions, protocol
descriptors, traces, and fingerprints all observe the same ordinary plan kernel.

The semantic builder sits above raw `ability.ir.plan.*` rows,
`ability.ir.builder.layout`, and schema protocol row descriptors. Authors can
declare locals by Zig type and call protocol descriptors directly:

```zig
const Schemas = ability.ir.schema.Registry(.{ Request, Decision });
const Rows = Workflow.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = Schemas.schema_refs,
});
const RequestOp = Rows.op("request");

const compiled = ability.ir.builder.semantic.finish(.{
    .label = "approval",
    .ir_hash = 11,
    .entry = "run",
    .schemas = Schemas,
    .requirements = &.{Rows.requirement},
    .ops = &Rows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = ability.ir.builder.semantic.span(0, 1),
        .params = .{},
        .locals = .{
            ability.ir.builder.semantic.local("payload", Request),
            ability.ir.builder.semantic.local("decision", Decision),
        },
        .result = Decision,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                ability.ir.builder.semantic.call(RequestOp, .{
                    .dst = "decision",
                    .payload = "payload",
                    .label = "approval.request",
                }),
            },
            .terminator = ability.ir.builder.semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid semantic plan: " ++ @errorName(err));
```

`schema.Registry(.{ ... })` derives `value_schemas`, `value_fields`,
`value_variants`, `schema_refs`, and `value_schema_types` from Zig types. Scalar
types need no schema row. Product and sum indexes are deterministic from the
registry tuple order, and nested product/sum refs must be present in the same
caller-owned registry. Unsupported types and duplicate structured entries fail
closed at comptime. When a semantic spec provides `.schemas = Schemas`, the
builder takes the value-schema tables from that registry; callers should not
repeat those tables separately.

Semantic instructions cover the current public plan-native control-flow shapes:
string, i32, and usize constants; `add_i32`; `sub_one`; zero comparison;
sum-variant matching; sum payload extraction; protocol calls through
`Protocol.Rows(...).op(name)` descriptors; jumps; branches; value/unit/error
returns. Named blocks are resolved to table indexes by the builder, so ordinary
authors do not compute `first_local`, `local_count`, `first_block`,
`block_count`, `first_instruction`, `instruction_count`, or terminator target
indexes.

Protocol calls can carry optional semantic labels such as
`approval.request` or `agent.tool`. Labels are debug/display metadata. When a
body exposes `Body.site_metadata = compiled.site_metadata`, those labels appear
on static session yield/after sites, `Program.protocol` descriptors, dynamic
request traces, and after-request traces. They are not durable ids, are not
source-code locations, and do not participate in plan, site, request, response,
or value fingerprints; the trace fingerprint version remains the existing
version unless the hashed contents change.

Raw ProgramPlan construction remains available for kernel tests, unsupported
instructions, exact table-shape assertions, and advanced escape-hatch work.
`ability.ir.builder.layout` is still useful when the caller wants nested
function/block specs but already owns raw instruction rows. New custom effect
programs should start with `schema.Protocol`, `schema.Registry`, and the
semantic builder.

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
When `Body.site_metadata` is present, operation and after sites also expose an
optional semantic label for display and debugging.

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
payload/resume/result refs, `has_after`, `may_resume`, `may_return_now`, and
optional `semantic_label` metadata.

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

## Program.Handler and Program.Interpreter

`Program.Handler` and `Program.Interpreter` are the typed handler algebra above
`Program.Session`; they are not a new runtime and do not hide the primitive
session machine. Handler declarations bind one function to one
`Program.protocol` operation or after descriptor:

```zig
const Decide = Program.protocol.operationSite("approval", "request", 0);
const Interpreter = Program.Interpreter(.{
    Program.Handler.operation(Decide, decide),
});
```

The handler receives a typed request and a `Control` value. `Control` exposes
the currently parked kind, request or after trace, request fingerprint, and
`capture(allocator)`, which copies the current continuation into a reusable
`Program.Session.Capsule` without mutating or advancing the live session.
`Control` is a live handler-boundary capability: store the capsule returned by
`capture`, not the `Control` value itself.
Request tokens remain in-process guards and are not exported as durable ids.

Handlers return site-specific outcomes:

- transform operation: `resume`, `suspend`, `forward`, `reinterpret`, or `fail`
- choice operation: `resume`, `returnNow`, `suspend`, `forward`, `reinterpret`,
  or `fail`
- abort operation: `returnNow`, `suspend`, `forward`, `reinterpret`, or `fail`
- after continuation: `resumeAfter`, `suspend`, `forward`, or `fail`

Invalid helper use fails at comptime where the static descriptor mode proves the
outcome is impossible. Runtime outcome application still validates the live
request, response ref, and typed value before resuming the session.

Protocol-level operation descriptors are available directly from
`ability.ir.schema.Protocol`, without a `ProgramPlan` call site:

```zig
const Policy = ability.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{ability.ir.schema.transform("check", []const u8, bool)},
});
const Check = Policy.operation("check", .{});
```

The descriptor exposes protocol label, op name, mode, `Payload`, `Resume`,
`Result`, payload/resume/result refs, and a deterministic protocol-operation
fingerprint. Product and sum payload/resume/result refs require the caller to
pass a `schema.Registry` through `.schema_refs`; scalar refs use the existing
scalar schema refs. Descriptor fingerprints include both the declared value refs
and the concrete payload/resume/result type identities, so equal schema indexes
from different registries do not alias distinct protocol operations.

Handlers can use these descriptors as target effect constructors. A
`Program.Morphism(.{ .source = SourceSite, .target = TargetOp, .Mapper = Mapper
})` proves the source Program operation site and target protocol operation
match the typed mapper. A handler declared with `Program.Handler.morphism` may
return `Program.Handler.reinterpret(Morphism, payload)`, which captures the
source continuation as a
`Program.Session.Capsule`, builds an inspectable
`Program.ProtocolRequest(SourceSite, TargetOp)`, and attaches mapper functions
that convert target `resume` or `return_now` responses back into a valid
`Program.Handler.SourceOutcome(SourceSite)`. The mapper is a comptime type with
plain functions, not a hidden closure; invalid source outcomes and wrong target
payload types fail at comptime where Zig can prove them.

Protocol-operation handlers bind to protocol-level descriptors:

```zig
const Interpreter = Program.Interpreter(.{
    Program.Handler.morphism(ApprovalViaPolicy, approvalHandler),
    Program.Handler.protocolOperation(Check, policyHandler),
});
```

Normal Program requests are offered to Program-site handlers. Reinterpreted
protocol requests are offered to protocol-operation handlers in the same
interpreter entry list. If no later handler accepts the target request, execution
returns `reinterpreted` to the host with the owned source capsule and target
request metadata. If a protocol handler answers, the interpreter applies the
mapper to the source outcome, restores the source capsule, resumes or returns
from the original site, and continues running the same primitive
`Program.Session`.

`Program.Interpreter(.{ ... })` drives a `Program.Session` until one of four
results is reached:

- `done`: owns the ordinary `Program.Result`
- `suspended`: owns a capsule for an explicit handler suspension
- `unhandled`: owns a capsule for a missing handler or forwarded-unhandled site
- `reinterpreted`: owns the source capsule plus target protocol request data for
  a missing or explicitly forwarded target protocol operation

Suspended and unhandled results also include the parked kind, request or after
trace, request fingerprint, capsule fingerprint, and reason
(`explicit_suspend`, `unhandled`, or `forwarded_unhandled`). The host owns these
capsules and must deinit them. Reinterpreted results include the stop reason,
source request fingerprint, source site fingerprint, source capsule fingerprint, target
protocol label/op/mode, target payload/ref metadata, target payload fingerprint,
target protocol-op fingerprint, morphism witness fingerprint, optional semantic
label, and a separate reinterpretation fingerprint.

Interpreters can be partial. A missing handler or `forward` outcome declines the
current site and returns an unhandled capsule. The host can manually restore the
capsule through `Program.Session`, or restore it and continue with another
`Program.Interpreter`. Complete interpreters can assert coverage with
`Interpreter.assertCoversAll()`, `Interpreter.assertEliminates(Program)`, or
`Program.protocol.assertAllSitesCoveredBy(Interpreter)`, which reject omitted
operation sites, omitted after sites, duplicate handlers, and foreign sites at
comptime. `Interpreter.effectRow(Program)` exposes handled Program operation
sites, handled after sites, handled protocol operations, reinterpreted source
sites, emitted target protocol operations, and statically known residual Program
sites. `assertReinterprets(SourceSite, TargetOp)`,
`assertHandlesProtocolOps(.{ ... })`, and `assertResidualSites(.{ ... })`
provide focused effect-row witnesses for partial and composed interpreters.

Interpreter options may include `.trace_recorder`; the driver records request
and response traces before applying typed resume, return-now, or resume-after
outcomes. The fingerprints are the existing session fingerprints. The trace
fingerprint version remains 2; request, response, site, value, and continuation
fingerprint contents remain unchanged. Reinterpretation uses a separate
`Program.reinterpret_fingerprint_version == 2` for the reinterpreted request
witness.

## Residualization

Dynamic reinterpretation and static residualization are two views of the same
effect algebra. Dynamic reinterpretation parks a source continuation and handles
the target protocol request at interpreter time. Residualization compiles a
declarative subset of those protocol morphisms into a new ordinary
`ProgramPlan`, so a host can run or step the residual program directly.

`Program.ResidualMorphism(.{ ... })` accepts a source `Program.protocol`
operation-site descriptor, a target `ability.ir.schema.Protocol.operation`
descriptor, a restricted payload mapping expression from `ability.ir.expr`, a
response mapping descriptor, a disposition, and an optional mapping label. The
first compiled shape is intentionally narrow: identity or payload passthrough
payload mappings and identity resume response mappings are compiled by replacing
the source operation row with the target transform operation row. Constant,
field, variant, product, sum, and branch descriptors are represented for
fail-closed reporting, but unsupported plan rewrites block before a residual
`ProgramPlan` is produced.

```zig
const ApprovalViaPolicy = ApprovalProgram.ResidualMorphism(.{
    .source = ApprovalRequest,
    .target = CheckPolicy,
    .payload = ability.ir.expr.identity(),
    .response = ApprovalProgram.ResidualResponse.resumeIdentity(),
    .label = "approval.request-as-policy.check",
});

const ResidualProgram = ApprovalProgram.residualize(.{
    .label = "approval-as-policy",
    .morphisms = .{ApprovalViaPolicy},
});
```

The result is a normal program-shaped type. It exposes `compiled_plan`,
`contract`, `protocol`, `run`, `Session`, `Handler`, and `Interpreter`, plus
residual metadata: `effect_row`, `source_map`, `residual_row`, `unsupported`,
`residualization_fingerprint`, `residualForSourceSite`,
`sourceForResidualSite`, and `mapResidualTrace`. The residual effect row reports
eliminated source sites, reinterpreted source sites, emitted target protocol
ops, residual operation sites, and unsupported morphisms. Source/residual trace
correspondence is separate from request fingerprints: the trace fingerprint
version remains 2, reinterpretation fingerprint version remains 2, and
residualization introduces `Program.residual_fingerprint_version == 1`.

`Program.Pipeline(.{ ... })` synthesizes residualization into one
proof-carrying effect pipeline. The catalog can name residualizable morphisms
and a residual-effect goal. `Program.pipeline.Goal` currently exposes
`allowResiduals`, `eliminateAll`, and `rejectAllResiduals`;
`Program.pipelineReport` can be used when the caller wants blockers instead of a
compile error. Residual handlers are supplied explicitly to
`Pipeline.Interpreter(...)`; report-time catalog entries are not used as hidden
runtime handlers.

```zig
const Pipeline = ApprovalProgram.Pipeline(.{
    .label = "approval-policy-pipeline",
    .residualize = .{ApprovalViaPolicyResidual},
    .goal = ApprovalProgram.pipeline.Goal.allowResiduals(),
});

const ResidualPolicy = Pipeline.Residual.protocol.operationSite("policy", "check", 0);
const Interpreter = Pipeline.Interpreter(.{
    Pipeline.Residual.Handler.operation(ResidualPolicy, handlePolicy),
});
```

The pipeline certificate records the source and residual plan hashes, pipeline
fingerprint (`Program.pipeline_fingerprint_version == 1`), residualization
fingerprints, source and residual effect rows, residualized route witnesses,
emitted protocol operations, blockers, source/residual site maps, and the trace
mapping policy. `Pipeline.assertValid()` and
`Pipeline.certificate.check()` verify that the claimed rows and maps satisfy the
goal. Trace helpers map residual request traces and target protocol requests
back to source sites without changing existing request/site/response/value
fingerprints.

Residualization emits ordinary `ProgramPlan` rows: requirements, ops, value
schemas, locals, blocks, terminators, instructions, and site metadata remain the
same runtime data that `Program.run` and `Program.Session` already execute.
There is no parser, broad source language, public VM API, Artifact API, async
runtime, network integration, persistence backend, serializable request token,
cross-thread session, or required trace serialization format. Arbitrary Zig
handlers and closures remain interpreter-only; only declarative plan-level
morphisms can be residualized.

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
payload/resume/result refs, payload value fingerprint, after flag, optional
semantic site label, fingerprint version, and stable request fingerprint.
`request.fingerprint()` returns the same request
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
current value ref and fingerprint, expected output ref, result ref, optional
semantic site label, fingerprint version, and stable request fingerprint.
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

## Continuation capsules

`Session.current()` inspects the parked operation or after request without
advancing the interpreter. `Session.capture(allocator)` copies that parked
continuation into a reusable `Session.Capsule`; `Session.restore(runtime,
handlers, &capsule)` creates a fresh live parked session for the same `Program`
and plan with fresh in-process request tokens. Capsule metadata records the
parked kind, site indexes, result ref, frame/after-stack shape, and deterministic
continuation fingerprint, while trace request fingerprints remain stable for the
same captured continuation. Hosts must `deinit` capsules. Capsules are owner
values: pass them by pointer, do not copy the struct itself, and restore them
only before `deinit`.

Capsules own copied scalar and schema-guided typed values, including strings,
string lists, products, and sums, so restored branches do not borrow the original
session's value storage. Reusable capsules can fork computation at an effect
boundary: each restore gets fresh request tokens, while capsule/request
fingerprints remain audit and replay witnesses. Request and after request payload
views remain ordinary session request views; inspect them while the parked
session that produced them is still live.

Capsules are first-class continuation snapshots. `Session.Capsule.Image` adds a
narrow v1 durable byte image for the same `Program` and plan; decode rebuilds an
owned capsule candidate and `Session.restore` remains the validation and
fresh-token authority. Capsule images are not `ProgramPlan` artifacts, VM
bytecode, or source-language values, and compatibility is scoped to the explicit
v1 format and fingerprint policy.

`Session.Journal` is the matching host transcript surface. It records
request/response/capsule/done entries, encodes deterministic bytes, and exposes
a replay cursor that checks the fresh yielded request fingerprint before the
host applies the corresponding decoded typed response. The journal recorder can
be provided as `.journal_recorder` alongside an existing `.trace_recorder`.

The session surface does not add an async runtime, parser, compiler, VM,
Artifact API, source-language API, network client, LLM client, public generated
custom effect API, or public root export. Hosts still own persistence and
external orchestration. `ProgramValue` remains scalar, and no new value codecs
are added. Request tokens remain in-process misuse guards, not durable ids;
site, request, response, value, continuation, capsule-image, and journal
fingerprints are audit and replay-verification metadata.

## Effect Exchange

`Program.Exchange` adds a transport-neutral ABI over the existing session
surface. A manifest image is a deterministic contract for a compiled `Program`:
it names the program/plan labels, ProgramPlan hash, exchange/trace/capsule and
journal versions, value schema rows, operation sites, after sites, semantic
labels, refs, modes, and site fingerprints. It does not contain mutable plan
tables, runtime state, request tokens, handlers, host context, source-language
data, allocator state, VM bytecode, or Artifact package data.

Request envelopes are created from yielded operation and after requests with
`Exchange.RequestEnvelope.fromRequest` and `fromAfter`. They carry the request
kind, manifest fingerprint, request and site fingerprints, trace metadata,
typed payload or current-value image, expected response refs, result ref, turn
index, optional capsule image bytes, optional journal branch id, and an envelope
fingerprint. Response envelopes are built with
`Exchange.ResponseEnvelope.resume`, `returnNow`, and `resumeAfter`; they carry
the matching request envelope fingerprint, request fingerprint, response kind,
response ref, typed response value image, response trace fingerprint, and
response envelope fingerprint.

Decode and validation fail closed on wrong magic, unsupported version,
truncation, malformed lengths, checksum/fingerprint mismatch, invalid value
image, schema-ref mismatch, unexpected trailing bytes, unsupported response kind,
manifest mismatch, request mismatch, and program/plan hash mismatch.
`Exchange.applyResponse` resumes a parked session only when the current yielded
request fingerprint and response ref/kind/value are compatible with the
envelope. Request tokens remain local misuse guards and are never serialized.

Capsule embedding is optional. If a request envelope contains a capsule image,
`Exchange.restoreFromRequestEnvelope` decodes it, restores a fresh parked
session, and verifies that the restored current request fingerprint matches the
envelope before a response is applied. `Exchange.MailboxRunner` is deliberately
small and nonblocking: it writes request envelopes to a host-owned outbox, reads
response envelopes from a host-owned inbox, and returns parked/running/done
without adding async, network, scheduler, broker, database, RPC, or tool/LLM
integration. `Exchange.Policy` is a local guardrail for allowed sites, response
kinds, capsule embedding, response value images, and byte limits; it is not a
cryptographic security layer.

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
For new authored programs, `ability.ir.schema.Registry(.{ ... })` is the usual
way to derive those schema tables and `schema_refs` together.

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
`SchemaRefs`; scalar refs need no entries. `schema.Registry(.{ ... })` can
derive the matching value-schema tables and schema refs in one deterministic
place. There is no hidden registry or table reordering.

After-enabled custom protocol rows publish `has_after` for the per-binding
handler type's direct `dispatch`/`afterDispatch` pair, or for requirement-labeled
handler shapes such as `.approval.request.afterDispatch` or
`.approval.authored.afterDispatch`.
Top-level op-name and top-level `authored` fallbacks can still be runtime
conveniences when a full plan has globally unique op names, but row lowering
cannot prove that global uniqueness in isolation; their presence also suppresses
direct-handler inference for that op.

The lowered row bundle also exposes op descriptors for semantic instruction
authoring:

```zig
const Request = ApprovalRows.op("request");
ability.ir.builder.semantic.call(Request, .{
    .dst = "decision",
    .payload = "approval_request",
    .label = "approval.request",
});
```

The protocol family also exposes protocol-level descriptors that are not tied to
any static Program site:

```zig
const Check = Policy.operation("check", .{ .schema_refs = Schemas.schema_refs });
```

These are typed defunctionalized effect constructors for reinterpretation and
external protocol-operation handlers. They expose the protocol label, op name,
mode, payload/resume/result types, schema refs, and stable protocol-op
fingerprint without adding a ProgramPlan call site.

After compilation with `ability.program`, no custom runtime surface is needed.
`Program.contract` exposes the custom requirement/op rows and session yield
sites, and `Program.protocol` derives typed host-facing descriptors from those
sites. Session hosts can use `matches`, `as`, typed payload/value views,
`resumeTyped`, `returnNowTyped`, `resumeAfterTyped`, response traces, and
coverage helpers exactly as they do for raw ProgramPlans.

`examples/custom_approval_workflow.zig` is the reference custom protocol
example. It defines a `workflow` family with transform, choice, and abort
operations, derives schema tables with `schema.Registry`, authors control flow
with `builder.semantic`, runs synchronously through `Program.run`, and
demonstrates the host-driven `Program.Session` path through `Program.protocol`
with deterministic trace replay.

`examples/protocol_reinterpretation.zig` demonstrates protocol morphisms over
the same kernel: an `approval.request` choice operation is handled by emitting a
protocol-level `policy.check` transform request, preserving the approval
continuation as a capsule, and mapping the policy answer back into either
approval resume or approval return-now behavior.

`examples/effect_pipeline.zig` demonstrates the pipeline form: an approval site
is residualized into `policy.check`, the residual policy site is dynamically
reinterpreted into `rules.lookup`, full execution agrees with source dynamic
interpretation, and a partial interpreter returns an inspectable protocol
request plus reusable capsule.

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

`ability.ir.builder.layout` is the lower construction layer under semantic
authoring. It accepts nested function specs with local specs, block specs,
instruction lists, and terminators, then computes the flattened table offsets
for the existing `ability.ir.ProgramPlan`:

- function `first_local`, `local_count`, `first_block`, `entry_block`,
  `block_count`, `first_instruction`, and `instruction_count`
- block `first_instruction`, `instruction_count`, and `terminator_index`
- function-local branch and jump targets into global block table indexes

Requirement, operation, output, schema, field, and variant tables are still
ordinary ProgramPlan rows. The layout builder handles table layout for
functions, locals, blocks, instructions, and terminators. The semantic builder
adds typed local/result declarations, descriptor-backed protocol calls, named
block targets, and optional site labels above this layer. The schema lowerer
handles requirement/op/output metadata when an effect binding schema exists.

`ability.ir.builder.layout.finish` and `finishWithNestedTargets` validate
through the same ProgramPlan validator and return the same
`ability.ir.ProgramPlan` shape as `ability.ir.builder.finish`. The layout
builder is a comptime authoring layer; use it from `Body.compiled_plan` or
other comptime plan constants.

The layout builder is not a parser, compiler, VM, Artifact surface, source
language, value codec, or second IR. Nothing survives past construction except
the validated `ProgramPlan`. Use it directly when you need raw instruction rows
or exact lower-level shape control; use `ability.ir.builder.semantic` for
ordinary custom protocol programs.

`Program.contract` is the public proof surface for generated plans. Tests should
assert contract facts such as labels, result refs, entry parameter refs, value
schemas, fields, variants, requirements, ops, payload/resume refs, after flags,
nested-with targets, and outputs instead of depending on mutable table access.

`ability.ir.schema.LowerBinding` is the preferred row-metadata route for
built-in plan-native helpers. Built-ins should share that schema path instead
of adding bespoke requirement/op/output row generators. Optional-shaped helpers
may still provide control-flow conveniences, but the common metadata should
come from schemas when the schema can describe it.

None of these builders exposes `effect.Define`, `effect.ops`, public generated
custom effects, a parser, compiler, VM, Artifact surface, source language,
value codec, second IR, or new execution semantics. They only emit ordinary
ProgramPlan row structs that can be inspected through `Program.contract`.

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
