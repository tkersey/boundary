# ProgramPlan authoring

`boundary.program(label, Handlers, Body)` is the public execution entry point for
compiled plans. A body must expose `Body.compiled_plan`, and that value must be
an `boundary.ir.ProgramPlan`.

The root package stays small: `boundary.effect`, `boundary.ir`,
`boundary.program`, and `boundary.Runtime`.

Boundary Closure Elaboration emits the same kind of body: an ordinary
`Body.compiled_plan` plus optional value schema, nested target, site metadata,
source-map, effect-row, trace-map, normal-form, and certificate constants. The
elaborated program is consumed through normal `Program.contract`,
`Program.protocol`, `Program.Session`, and `Program.run`; no TreatyResolver or
ProviderHarness is needed for internal routes that were elaborated.
`BoundaryClosure.Elaboration.Target` adds the target-neutral `WorldSurface`
metadata and normalization trace/certificate evidence an adjacent World
interpreter can use to dispatch residual world ports by dense id without
re-running treaty or provider search.

`Target.Module.ProgramPlanImage` is the canonical image summary of the validated
residual plan used inside a Certified Boundary Module. It records the plan label,
plan hash, IR hash, entry function, and validated row-table counts needed for
module validation and diagnostics. It does not expose mutable instruction
construction or arbitrary runtime code mutation APIs. Value schema image data
uses schema-local refs and diagnostic labels only; it does not widen
`ProgramValue` or authorize native Zig type identity.

Executable modules now carry a separate `Target.Module.ExecutablePlanImage`
section. This section is the portable execution byte witness for later loaded
sessions: it owns canonical row tables for functions, requirements, operations,
outputs, schemas, locals, call arguments, blocks, terminators, instructions,
string literals, stable error identities, nested-call refs, entry function, and
the execution feature bitmap. It uses format/fingerprint version 1 and is
validated independently of the summary image. Unsupported executable semantics
must reject before session creation rather than after partial execution.

`Target.Module.LoadedExecutionProfile` and the loaded value image types are the
portable substrate consumed by that future session. Profile v1 fixes checked
arithmetic, architecture-independent word values encoded as `u64`, supported
instruction/terminator/value-codec feature sets, and explicit execution and
allocation limits. `LoadedValue.Image` is schema-driven canonical data rather
than a Zig value: it binds schema identity and bytes, rejects trailing data,
validates product and sum refs through schema tables, and decodes into
Boundary-owned arena storage.

`LoadedModule.Session` also has a portable session-image shell and an explicit
`startExecutable` constructor that decodes the executable-plan rows into owned
session state. Start binds the module, executable-plan, profile, and
entry-function identities; `next()` can execute bounded no-argument scalar local
plans over decoded rows, including `return_unit`, `return_value`, scalar
constants, checked i32/u64 arithmetic, zero comparisons, jumps, branches, and
deterministic fuel exhaustion. Completing `call_helper` frames are also executed
through explicit function and call-argument rows. It also supports the first
residual request shape (`const_string`, `call_op`, `return_value` with string
payload and scalar response/result refs). The yielded request carries canonical
payload image bytes and site/world-port/value identity, and `resume` accepts
canonical response image bytes, encodes the final result through the module
result ref, and rejects wrong or duplicate responses without mutating the parked
request. Helper calls that would park on residual
requests and other unsupported instruction shapes return stable
`unsupported_feature` failures until the interpreter and continuation image
broaden; `freeze` and `thaw` roundtrip canonical loaded-session bytes, including
parked request identity and payload evidence, and reject substituted module,
plan, profile, session, or malformed image fingerprints before mutable state is
reconstructed.

`LoadedModule` projects the ProgramPlan-facing consumption data without turning
the image into a VM: ProgramPlan hash, normal-form kind, main export result ref,
argument refs, import projections, validation diagnostics, compatibility, and
dependency reports. World decides whether and how to bind and run the residual
plan.

## Scalar body

A scalar plan uses scalar locals and scalar `ProgramValue` entry arguments. If
the plan has entry parameters, `Body.encodeArgs(handlers)` may return a slice or
array pointer of `boundary.ir.ProgramValue`.

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
`Body.nested_with_targets`, using `boundary.ir.NestedWithTarget` entries that map
metadata packets to function indexes. `boundary.ir.builder.finishWithNestedTargets`
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

`boundary.ir.builder.semantic` is the preferred authoring layer for ordinary
custom protocol programs. It is a construction helper, not a source language:
`finish(spec)` lowers typed functions, parameters, locals, named blocks,
terminators, and protocol calls into the existing `boundary.ir.ProgramPlan`.
After construction, execution, validation, contracts, sessions, protocol
descriptors, traces, and fingerprints all observe the same ordinary plan kernel.

The semantic builder sits above raw `boundary.ir.plan.*` rows,
`boundary.ir.builder.layout`, and schema protocol row descriptors. Authors can
declare locals by Zig type and call protocol descriptors directly:

```zig
const Schemas = boundary.ir.schema.Registry(.{ Request, Decision });
const Rows = Workflow.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = Schemas.schema_refs,
});
const RequestOp = Rows.op("request");

const compiled = boundary.ir.builder.semantic.finish(.{
    .label = "approval",
    .ir_hash = 11,
    .entry = "run",
    .schemas = Schemas,
    .requirements = &.{Rows.requirement},
    .ops = &Rows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = boundary.ir.builder.semantic.span(0, 1),
        .params = .{},
        .locals = .{
            boundary.ir.builder.semantic.local("payload", Request),
            boundary.ir.builder.semantic.local("decision", Decision),
        },
        .result = Decision,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                boundary.ir.builder.semantic.call(RequestOp, .{
                    .dst = "decision",
                    .payload = "payload",
                    .label = "approval.request",
                }),
            },
            .terminator = boundary.ir.builder.semantic.returnValue("decision"),
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
`boundary.ir.builder.layout` is still useful when the caller wants nested
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
`boundary.ir.schema.Protocol`, without a `ProgramPlan` call site:

```zig
const Policy = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{boundary.ir.schema.transform("check", []const u8, bool)},
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
operation-site descriptor, a target `boundary.ir.schema.Protocol.operation`
descriptor, a restricted payload mapping expression from `boundary.ir.expr`, a
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
    .payload = boundary.ir.expr.identity(),
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

### Capability-routed Effect Exchange

The exchange layer also exposes a typed capability calculus under
`Program.Exchange`. `ProviderManifest` is a deterministic provider claim: label
and provider fingerprint, supported program manifests, protocol labels,
operation and after sites, protocol-op fingerprints, response kinds, request and
response size limits, capsule acceptance/restore policy, semantic tags, and
metadata bytes. It is a capability target, not identity, authentication, or a
network address.

`Capability` grants one provider authority to answer a narrowed set of request
envelopes: request kind, program labels or plan hashes, operation/after sites,
protocol-op fingerprints, requirement/op labels when site indexes are not
available, response kinds and refs, capsule policy, byte limits, optional
journal/branch policy fingerprint, optional logical expiry generation, parent
capability fingerprint, and attenuation path fingerprint. Attenuation is
monotone: child sets must be subsets, byte limits must shrink or stay equal,
and capsule permissions cannot be enabled by a child when disabled by a parent.

`Route` witnesses the deterministic result of matching request envelope,
provider manifest, capability, and optional policy. `Router` returns a single
route, no route, blocked routes with structured blocker tags, or ambiguous
routes; ambiguity fails closed by default. Response envelopes may cite an
`Authorization` sidecar containing provider, capability, capability-path, route,
request, response, and authorization fingerprints. The sidecar preserves the v1
response envelope fingerprint domain and is validation metadata only.

`MailboxRunner` can route yielded request envelopes to routed outboxes and can
require capability authorization before applying responses. `Session.Journal`
has exchange event entries for provider manifests, granted or attenuated
capabilities, selected or blocked routes, and authorized or rejected responses.
Hosts still own identity, signing, encryption, transport, storage, scheduling,
networking, persistence, brokers, tools, humans, and models. Request tokens are
still not serialized; capability fingerprints are deterministic audit metadata,
not cryptographic authorization.

### Effect Treaties

In direct-style algebraic effects, a handler is installed lexically. In Effect
Exchange, the handler-equivalent is negotiated data: an `Exchange.Treaty`.
Routing finds a provider. A treaty proves the provider may handle this effect in
this way.

Provider offers describe what can be handled: sites, protocol operation
fingerprints, protocol labels, payload/current-value refs, response refs and
kinds, supported usage modes, response-use classes, replay and branch policies,
capsule policy, byte limits, tags, and metadata. Morphism offers describe one
hop of protocol adaptation and cite dynamic morphism, residual morphism, or
pipeline fingerprints when those adapters are available.

`TreatyResolver` is pure and catalog-driven. Given a request envelope, manifest,
provider manifests, offers, capabilities, optional capability instances,
morphism offers, optional obligations, and treaty policy, it selects direct
handling or adapted handling, attenuates capability authority when policy
requires least authority, validates usage/replay/branch/response-use/capsule
constraints, and returns a treaty, no treaty, ambiguity, or structured blockers.
It performs no IO, transport, scheduling, provider calls, or cancellation.

The treaty and treaty certificate bind the request envelope fingerprint and
request envelope format, provider, offer, capability, attenuated capability path,
route, optional morphism or pipeline, usage mode, response-use policy, replay
policy, branch policy, expected response refs and kinds, obligation metadata,
and journal policy. Treaty-bound response authorization validates the returned
response against that certificate while keeping existing response envelope bytes
and fingerprints stable.

`MailboxRunner` treaty mode resolves before outbox write, sends the request
envelope with the selected certificate, journals treaty request/selection,
certificate, authorization, accepted, and rejected response events, and rejects
responses that cite the wrong treaty, provider, capability, route, usage,
response-use, replay, branch, response kind, or obligation transition. Effect
Treaties are deterministic protocol negotiation metadata, not cryptographic
security, legal-contract semantics, a network runtime, async runtime,
distributed consensus, workflow engine, or provider execution layer. Hosts own
identity, signing, encryption, transport, storage, scheduling, network,
persistence, and side effects.

### Provider Harnesses

Treaties define the agreement. `Program.Exchange.ProviderHarness` executes the
provider side of that agreement. It is a typed validation-and-response adapter
over Effect Exchange, not a transport or execution runtime.

The preferred construction is handler-first: a typed provider declaration derives
the provider manifest entry, provider offer, offer fingerprint, treaty resolver
catalog metadata, typed provider request view, typed outcome type, validation
metadata, and coverage metadata. `ProviderOffer` remains ordinary deterministic
data for treaties, certificates, journals, and catalogs. Manual offers are an
advanced escape hatch and must exactly match the derived handler declaration.

`ProviderHarness.handle` receives a request envelope plus treaty certificate and
validates the envelope, manifest, treaty, provider, offer, capability,
attenuated capability, route, usage, response-use, replay, branch, obligation,
capsule, byte-limit, and payload/current-value metadata before handler
invocation. The handler gets a typed request view with the provider, offer,
treaty, certificate, route, capability, obligation, branch, source, target, and
value fingerprints plus typed payload/current-value accessors. The view does not
expose request tokens, runtime pointers, allocator pointers, mutable request
envelope internals, or implicit host context.

Handlers return explicit typed outcomes: resume, return-now, resume-after,
replay, reject, forward, or pending. The harness checks that the outcome is
legal for the derived offer, builds the `ResponseEnvelope` through existing
exchange machinery, attaches treaty-bound `Treaty.Authorization`, and can record
provider-side journal events for manifest/offer derivation, receipt, validation,
rejection, handler invocation, response build, authorization, forwarding, and
pending results. Hosts still own queues, files, network, identity, signing,
encryption, storage, scheduling, persistence, retries, and provider lifecycle.

ProviderHarness is not an async runtime, RPC framework, network server, message
broker, provider registry, service discovery system, security layer, workflow
engine, source language, VM, or Artifact API.

#### Program-backed providers

ProviderHarness made provider callbacks typed. Program-backed providers make
provider handlers defunctionalized. A declaration can use
`Program.Exchange.ProviderHandler.program(.{ ... })` to bind an offer to an
ordinary Boundary Program instead of a Zig callback. The declaration still
derives the provider manifest entry, provider offer, offer fingerprint, catalog
metadata, value refs, response metadata, and Evidence refs. A manual
`ProviderOffer` remains an escape hatch, but it must exactly match the
program-backed declaration, including the provider-program mapping fingerprint.

The first request mapping forms are deterministic: `payload_to_args` maps the
request payload or after current value into the handler Program's first entry
arg, and `unit_args` starts no-arg handlers for no-payload operations.
`payload_and_metadata_to_args` and custom comptime mapping are reserved for
typed deterministic metadata mapping. Request tokens, runtime pointers,
allocator pointers, and implicit host context are not mapped. Handler results
map through `result_to_resume`, `result_to_return_now`, or
`result_to_resume_after`; invalid mappings fail closed against the operation
mode and expected response refs.

`ProviderHarness.startProgramExecution` validates the parent request, treaty
certificate, provider offer, route, capability, usage, response-use, branch,
obligation, byte limits, and value refs before starting the handler Program
under `Program.Session`. If the handler completes synchronously, the result is
converted into a normal provider response packet with treaty-bound
authorization. If it yields a nested request or after request, the harness
returns a parked provider-program execution containing the nested request
envelope, handler capsule image fingerprint, parent request/treaty/provider
fingerprints, handler Program label and plan hash, and Evidence refs. The host
routes the nested request through ordinary Exchange/Treaty/MailboxRunner/
ProviderHarness machinery and resumes the provider handler with
`continueProgramExecution`.

Provider-program journal events record started, parked, nested request, nested
response, resumed, completed, rejected, and failed turns. Evidence domains cover
provider-program execution, request/result mapping, and nested request linkage.
Function-backed handlers remain supported for simple host callbacks, external
provider calls, and tests. Program-backed providers are not an async runtime,
provider scheduler, network server, RPC system, workflow engine, VM, source
language, parser, Artifact API, persistence backend, service discovery, signing,
encryption, or distributed system. Hosts own identity, signing, encryption,
transport, storage, scheduling, network, persistence, provider lifecycle,
cancellation, retries, and side effects.

### Defunctionalization Boundary

Boundary-native semantics should be Boundary programs or declarative Boundary data.
Opaque host functions are supported only as explicit host intrinsics at the world
boundary. Boundary does not pretend opaque host callbacks are algebraic-effect
semantics.

`Program.Evidence.SemanticBody` classifies execution bodies as
`boundary_program`, `declarative`, `residualized_program`, `pipeline`,
`kernel_primitive`, `host_intrinsic`, or `unknown`. Program-backed
ProviderHarness declarations report `boundary_program`; function-backed
ProviderHarness declarations, `Program.Interpreter` handlers, `Program.run`
handler sets, and dynamic morphism mappers report `host_intrinsic`.
Residualized and pipeline-backed morphisms report static Boundary-native bodies.

`Program.Evidence.DefunctionalizationReport` summarizes those classifications
for providers, offers, treaties, resolver results, interpreters, run handler
sets, morphism offers, pipelines, journals, and catalogs.
`Program.Evidence.DefunctionalizationPolicy` can reject intrinsics or unknown
bodies, allowlist intrinsics, require program-backed providers, require
static/declarative morphisms, and make TreatyResolver prefer less opaque routes.

### Boundary Closure Certificates

`Program.BoundaryClosure` turns the individual defunctionalization facts into a
whole-system closure proof. Given root effect shapes, provider offers,
morphism offers, capabilities, treaty policy, defunctionalization policy, and
world-port declarations, it builds static treaty plans, a deterministic closure
graph, a closure report, and a closure certificate.

Closure is a dry-run evidence pass. It does not execute provider handlers, start
a scheduler, send messages, or persist state. It proves what is handled by
Boundary-native programs, declarative bodies, residualized programs, pipelines,
or kernel primitives, and what remains as explicit world ports that an adjacent
`world` interpreter must implement.

See [boundary_closure.md](boundary_closure.md).

### Linear Effect Sessions

Continuations can be copied; the world often cannot. Linear Effect Sessions are
Boundary's deterministic usage calculus for capability-routed external effects.
The public surface stays under `Program.Exchange`: `Usage` distinguishes
copyable, replayable, affine, linear, and ephemeral effects; `ResponseUse`
records fresh, replayed, deterministic-replay, or override responses; and
`BranchPolicy` describes unrestricted, replay-only, single-live-branch,
split-required, no-branch, and host-owned capsule branching.

`EffectSessionSpec` declares the state machine for an external effect. A
capability grant remains general authority, while `CapabilityInstance` is the
branch-scoped consumable authority object. When a request is yielded, an
`Obligation` can bind the request envelope and site fingerprints to the
capability instance, usage mode, branch id, allowed response kinds/refs,
optional capsule image fingerprint, and lifecycle status. Obligations transition
through open, consumed, replayed, canceled, or abandoned. Affine and linear
obligations reject duplicate fresh consumption; linear obligations must be
consumed or explicitly canceled unless a host-owned abandonment policy says
Boundary should only record metadata.

Request envelopes have optional session/instance/obligation metadata, usage
mode, branch policy, replay policy, ephemeral flag, and cancelability flag.
Request tokens remain in-process guards and are never encoded. Response
authorization can produce an `AuthorizationResult` that cites the obligation
transition fingerprint, previous/next obligation status, previous/next session
state, response use class, instance-consumption flag, and branch-open flag.
Journal exchange events include effect-session, capability-instance,
obligation, transition, branch, and blocker metadata; `ObligationLedger`
validates duplicate consumption and unresolved linear obligations.

This is deterministic validation metadata, not cryptographic security, an async
runtime, a workflow engine, or a persistence backend. Hosts own identity,
signing, encryption, transport, storage, scheduling, networking, provider
execution, tools, humans, models, and persistence.

## Effect schema row lowering

Built-in effect schemas can lower to ProgramPlan requirement, operation, and
output rows through `boundary.ir.schema.LowerBinding`. The caller supplies the
binding type and the table offsets:

```zig
const StateRows = boundary.ir.schema.LowerBinding(
    boundary.ir.schema.Binding("state", boundary.effect.state.Schema(i32, error{}), void),
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
const schema_refs = boundary.ir.schema.SchemaRefs(.{
    boundary.ir.schema.ref(ProductPayload, 0),
    boundary.ir.schema.ref(OptionalPayload, 1),
});

const ExceptionRows = boundary.ir.schema.LowerBinding(
    boundary.ir.schema.Binding(
        "exception",
        boundary.effect.exception.Schema(ProductPayload, error{}, void),
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
For new authored programs, `boundary.ir.schema.Registry(.{ ... })` is the usual
way to derive those schema tables and `schema_refs` together.

Writer accumulator schemas distinguish the final handler output from the
ProgramPlan output row. The schema final output is the collected `[]Item`; the
ProgramPlan `OutputPlan` row records the accumulator item ref, because the body
`Outputs` type owns the collection shape and cleanup.

For built-in plan-native helpers, schema lowering is preferred over hand-written
per-built-in row generators. Raw `boundary.ir.plan.*` rows remain available for
tests that deliberately exercise table escape hatches or unsupported shapes.

## Custom Protocol Families

Custom protocol families are schema-first authoring data under
`boundary.ir.schema.Protocol`. They lower through the same ProgramPlan row path
as built-ins:

```zig
const Approval = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        boundary.ir.schema.transform("exists", []const u8, i32),
        boundary.ir.schema.choiceAfter("request", []const u8, i32),
        boundary.ir.schema.abort("invalid", []const u8),
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
boundary.ir.builder.semantic.call(Request, .{
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

After compilation with `boundary.program`, no custom runtime surface is needed.
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

`boundary.effect.optional.plan`, `boundary.effect.state.plan`,
`boundary.effect.reader.plan`, and `boundary.effect.writer.plan` are reusable
plan-native helper namespaces. They emit ordinary ProgramPlan rows, value refs,
locals, op refs, and instruction helpers; they do not add a runtime, VM, parser,
compiler, source language, Artifact surface, public root export, value codec, or
custom-effect API.

The state, reader, and writer helpers are transform/output built-ins backed by
the shared schema lowerer:

- `boundary.effect.state.plan` exposes state-cell row lowering, scalar and
  explicit-schema state refs/locals, `get` and `set` op refs, `callGet`,
  `callSet`, and the canonical final-state output row shape. The caller owns the
  requirement index, first op index, first output index, and any schema refs.
- `boundary.effect.reader.plan` exposes reader-environment row lowering, scalar
  and explicit-schema environment refs/locals, the `ask` op ref, and `callAsk`.
  Reader has no ProgramPlan output row.
- `boundary.effect.writer.plan` exposes writer-accumulator row lowering, scalar
  and explicit-schema item refs/locals, the `tell` op ref, `callTell`, and the
  canonical accumulator output row shape. The ProgramPlan output row records the
  accumulator item ref.

These helpers pair with `boundary.ir.builder.layout` for ordinary plan authoring:
the helpers produce requirement/op/output metadata and call instructions, while
the layout builder computes function/local/block/instruction table offsets.
Raw ProgramPlan rows remain available when exact table construction is the goal.
Compatibility APIs such as `boundary.effect.state.handle`,
`boundary.effect.reader.handle`, and `boundary.effect.writer.handle` remain
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
compatibility `boundary.effect.optional.handle` path intact.
`boundary.effect.optional.plan` is the reusable plan-native helper namespace for
this shape. It supplies the optional outcome convention, requirement/op rows,
schema rows with caller-owned field/variant offsets, variant rows, and sum-match
instructions; ordinary authored plans still own their layout-builder control
flow.

`examples/plan_native_state_reader.zig` demonstrates state and reader through
`boundary.effect.state.plan`, `boundary.effect.reader.plan`, and the layout
builder. Its requirement, op, and output metadata come from schema lowering
through those helper namespaces. The state schema contributes `state_cell`
metadata and a binding-labeled final-state output declaration. The reader schema
contributes `reader_environment` metadata and borrows its environment through
the handler, without a handler-owned side channel for the returned value.

`examples/plan_native_writer.zig` demonstrates writer accumulation through
`boundary.effect.writer.plan` and the layout builder. The helper lowers the
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

Raw `boundary.ir.plan.*` tables remain available as the low-level escape hatch.
Use them when a test needs exact table control, when reproducing a validation
failure, or when deliberately asserting individual `first_*` and `*_count`
values.

`boundary.ir.builder.layout` is the lower construction layer under semantic
authoring. It accepts nested function specs with local specs, block specs,
instruction lists, and terminators, then computes the flattened table offsets
for the existing `boundary.ir.ProgramPlan`:

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

`boundary.ir.builder.layout.finish` and `finishWithNestedTargets` validate
through the same ProgramPlan validator and return the same
`boundary.ir.ProgramPlan` shape as `boundary.ir.builder.finish`. The layout
builder is a comptime authoring layer; use it from `Body.compiled_plan` or
other comptime plan constants.

The layout builder is not a parser, compiler, VM, Artifact surface, source
language, value codec, or second IR. Nothing survives past construction except
the validated `ProgramPlan`. Use it directly when you need raw instruction rows
or exact lower-level shape control; use `boundary.ir.builder.semantic` for
ordinary custom protocol programs.

`Program.contract` is the public proof surface for generated plans. Tests should
assert contract facts such as labels, result refs, entry parameter refs, value
schemas, fields, variants, requirements, ops, payload/resume refs, after flags,
nested-with targets, and outputs instead of depending on mutable table access.

`boundary.ir.schema.LowerBinding` is the preferred row-metadata route for
built-in plan-native helpers. Built-ins should share that schema path instead
of adding bespoke requirement/op/output row generators. Optional-shaped helpers
may still provide control-flow conveniences, but the common metadata should
come from schemas when the schema can describe it.

None of these builders exposes `effect.Define`, `effect.ops`, public generated
custom effects, a parser, compiler, VM, Artifact surface, source language,
value codec, second IR, or new execution semantics. They only emit ordinary
ProgramPlan row structs that can be inspected through `Program.contract`.

For common typed examples, `boundary.ir.builder.typed` remains available and now
builds through the layout layer while still returning the same
`boundary.ir.ProgramPlan`:

- `scalarConstI32`
- `productIdentity`
- `sumVariantI32Branch`
- `sumExtractI32Payload`
- `unitWithOutputs`

These helpers cover scalar demos, product results, optional or enum-like
variant branches, tagged-union `i32` payload extraction, and output declarations.

## Custom effect authoring

Minimal schema-first custom protocol-family authoring is available under
`boundary.ir.schema.Protocol`. It is plan-native: custom descriptions lower to
the same ProgramPlan requirement, op, value schema, output, nested-with, and
contract metadata used by built-in prototypes.

See [custom_effect_authoring.md](custom_effect_authoring.md) for the design
boundary and non-goals.

## Evidence And Validation

Each concrete `Program` exposes `Program.Evidence`, the shared substrate for
Boundary's proof machinery. Evidence domains centralize the format and
fingerprint versions used by ProgramPlan hashes, session trace/request/response
fingerprints, capsule images, journals, exchange envelopes, provider identities,
provider manifests, provider offers, capabilities, routes, authorizations, linear obligations,
treaties, ProviderHarness metadata, morphisms, residualization, pipelines,
semantic body classifications, host intrinsics, and defunctionalization reports.

Format versions govern encoded bytes. Fingerprint versions govern canonical
digest semantics. Journal versions govern event encoding. Certificates and
authorizations are snapshots of validated dependency graphs. Request tokens are
local in-process misuse guards and are not serialized or included in semantic
fingerprints.

`Evidence.Ref` gives blockers, reports, certificates, authorizations, and
journal projections a shared reference language without replacing typed
subsystem objects. `Evidence.DependencyGraph` records role-labeled refs and
computes deterministic dependency fingerprints. `Evidence.Blocker` and
`Evidence.Report` provide common validation views while existing subsystem
blocker/report APIs remain source-compatible. `Evidence.CertificateView`,
`Evidence.AuthorizationView`, `Evidence.JournalProjection`, and
`Evidence.PolicySummary` make validated proof snapshots and journal metadata
consistent across ProviderHarness, Treaties, Linear Effect Sessions,
Capabilities, Exchange, Journal, Residualization, Pipeline, Defunctionalization
Boundary, and Boundary Closure Certificate surfaces.

Evidence fingerprints are deterministic semantic witnesses. They are not
cryptographic signatures, authentication tokens, or transport security. Hosts
own identity, signing, encryption, transport, storage, scheduling, provider
execution, provider lifecycle, and cancellation effects.

See [evidence_kernel.md](evidence_kernel.md) for the domain inventory, version
bump policy, and maintainer workflow for adding evidence objects, blockers,
reports, certificate views, and journal events.
