# ability

`ability` is a Zig library for explicit local effect programs.

The public package root is intentionally small:

- `ability.effect`
- `ability.ir`
- `ability.program`
- `ability.Runtime`

`effect` defines the effect families. `ir` exposes the public ProgramPlan
builder. `program` gives a reusable execution surface for one named compiled
body. `Runtime` is the caller-owned local runtime used to run programs
repeatedly.

## Program

`ability.program` executes a `Body.compiled_plan`. The plan is built at comptime
with `ability.ir.builder`, validated before it escapes, and interpreted by
`Program.run`.

`ability.ir.ProgramPlan` executes scalar values directly and can execute
structured `product` and `sum` values when the body declares an exact
`Body.value_schema_types` tuple matching the plan schema tables. `ProgramValue`
stays the scalar public carrier; typed bodies may instead return a tuple from
`Body.encodeArgs`. Sum plans can branch with `sum_variant_is` and extract
non-unit payloads with `sum_extract_payload`; both operations are validated
against schema-local variant tables and exact destination refs.

Helper calls run through an interpreter-owned frame stack. Recursive helper
plans are bounded by the interpreter step budget rather than by host stack depth.
Nested lexical-with rows stay fail-closed unless `Body.nested_with_targets`
maps the exact metadata packet to a concrete zero-argument plan function using
`ability.ir.NestedWithTarget`. Unsupported plans report a capped capability
ledger in compile errors; the ledger records stable blocker tags, function and
instruction coordinates, and whether the 64-record cap truncated diagnostics.

```zig
const std = @import("std");
const ability = @import("ability");

const Handlers = struct {
    authored: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 41;
        }

        pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
            return value + 1;
        }
    },
};

fn plan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "authored", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{ .requirement_index = 0, .op_name = "authored", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32, .has_after = true }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = "demo",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = plan();
};

pub fn main() !void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const Program = ability.program("demo", Handlers, Body);
    var result = try Program.run(&runtime, .{ .authored = .{} });
    defer result.deinit();

    // result.value == 42
}
```

The label must be non-empty. `Program.Result` exposes `value`, `outputs`, and
`deinit()`. `Program.Session` exposes the same plan as a host-driven loop:
`Session.start` prepares explicit interpreter state, `next()` yields typed
operation requests or after-continuation requests with requirement/op metadata
and typed value access, and `@"resume"`, `returnNow`, or `resumeAfter` feed typed
values back into the interpreter before a final `Result` is collected. Yielded
requests park the session: runtime active execution is not held while control is
back with the host, but the owning `Runtime` must outlive every live session.
Yielded requests also expose read-only trace metadata through `trace()` and a
stable request fingerprint through `fingerprint()`. Hosts can compute matching
response metadata with `responseTrace(...)` before resuming the session, and can
use `expectFingerprint(...)` to fail cleanly when replay reaches a different
request boundary.
String results in `Program.Result.value` should be
treated as borrowed unless the body documents and implements ownership cleanup
through `Body.deinitResult(allocator, value)`. The value cleanup hook is
independent of output cleanup, so it can run even when output collection fails.
Bodies that declare `Outputs` must implement
`Body.collectOutputs(allocator, handlers)` and can release those values with
`Body.deinitOutputs`.

Plans with entry parameters can add `Body.encodeArgs(handlers)` and return
either `[]const ability.ir.ProgramValue` for scalar arguments or a tuple whose
field types match the entry locals. Product and sum schemas require
`Body.value_schema_types`; nested lexical-with execution requires
`Body.nested_with_targets`.

Each compiled program also exposes `Program.contract`, a read-only inspection
view derived from the validated ProgramPlan. The contract reports the public
program label, result codec and schema reference, typed result and output Zig
types, entry parameter refs, value schema/field/variant declarations, output
declarations, requirement and operation metadata, op payload and resume
references, op modes, after-hook flags, nested-with target declarations, unique
`return_error` literals, and the executable and session capability-ledger
summaries. The session ledger advertises whether trace metadata and value
fingerprints are supported, exposes the current fingerprint version, and
contains static `yield_sites` and `after_sites` catalogs for entry-reachable
session yield points. Operation sites include stable site indexes and
fingerprints, function/block/instruction coordinates, requirement/op metadata,
payload/resume/result refs, mode, and host resume/return-now capabilities.
After sites are tied to the source operation call site, not merely to the op
row. Optional semantic site labels authored through the semantic builder are
projected to these sites for display/debugging without changing fingerprints.
It is metadata for tests and callers that need to inspect what a program
declares; it does not expose mutable ProgramPlan tables, Artifact or VM
surfaces, or legacy capability maps.

For host code that wants typed defunctionalized dispatch, each compiled program
also exposes `Program.protocol`. This is derived from
`Program.contract.session.yield_sites` and `after_sites`; it is not a second
runtime. `Program.protocol.operationSite(requirement_label, op_name,
occurrence_index)` and `siteByIndex(index)` return static operation site
descriptors with `Payload`, `Resume`, and `Result` Zig type aliases plus the
site index, fingerprint, source coordinates, requirement/op identity, mode,
refs, after flag, resume/return-now capabilities, and optional site labels.
`afterSite(...)` and `afterSiteByIndex(index)` return after descriptors with
`Output` and `Result` aliases plus the source operation site identity and refs.
Handler-owned after descriptors also expose `Input` and a static `input_ref`;
handlerless after descriptors set `has_static_input_ref = false` because their
current value ref is defined by the concrete after stack. A host can check a
dynamic request with `request.as(Site)` or `after.as(AfterSite)`, decode through
the descriptor-owned payload or static/dynamic current-value type, compute
site-aware response traces, and use `session.resumeTyped`,
`session.returnNowTyped`, or
`session.resumeAfterTyped`. After response traces and typed after resume validate
the live request's expected output ref, which can differ from the descriptor
output ref for stack-dependent final continuations.
Coverage helpers such as `assertOperationSitesCovered`, `assertAfterSitesCovered`,
and `assertAllSitesCovered` fail at comptime for omitted reachable sites,
duplicate descriptors, or descriptors from another program.

`Program.Handler` and `Program.Interpreter` add a typed algebra over
`Program.Session`; they do not replace the primitive session machine. A handler
binds to one `Program.protocol` operation or after descriptor and returns a
site-specific outcome: resume, return-now, resume-after, suspend, forward,
reinterpret, or fail. Transform handlers can resume, suspend, forward,
reinterpret, or fail; choice handlers can also return now; abort handlers can
return now, suspend, forward, reinterpret, or fail; after handlers resume-after,
suspend, forward, or fail. A handler receives a `Control` value exposing the
current trace, fingerprint, site metadata through the typed request, and
`capture(allocator)` for a reusable continuation capsule without advancing the
current session. Store the captured capsule, not the `Control` value;
`Control.capture` is only valid during the handler call for the currently parked
request or after-continuation.

Handlers can also act as effect morphisms. `schema.Protocol.operation("op",
.{ .schema_refs = ... })` derives a typed protocol-level operation descriptor
	that is independent of any compiled `Program` yield site. A handler declared with
	`Program.Handler.morphism(Morphism, handler)` can return
	`Handler.reinterpret(Morphism, payload)`: the
interpreter captures the source continuation as a `Program.Session.Capsule`,
emits an inspectable `Program.ProtocolRequest(SourceSite, TargetOp)`, and later
maps the target protocol response back into a source-site outcome through the
comptime mapper. Protocol-operation handlers are added with
`Program.Handler.protocolOperation(TargetOp, handler)`, so a composed
`Program.Interpreter(.{ source_morphism, target_handler, ... })` can eliminate a
high-level effect by translating it into a lower-level protocol and resuming the
original capsule.

`Program.Interpreter(.{ ... })` drives a `Program.Session` with those handlers
until it returns `done`, `suspended`, `unhandled`, or `reinterpreted`. Suspended
and unhandled results own a capsule plus parked-kind, trace, request
fingerprint, capsule fingerprint, and reason metadata. A reinterpreted result
owns the source capsule plus source request/capsule fingerprints, target protocol
label/op/mode/ref metadata, target payload value and fingerprint, morphism
witness fingerprint, and a separate reinterpretation fingerprint. Partial interpreters
are valid: missing handlers or explicit `forward` return an owned unhandled
capsule, and an unhandled target protocol request returns `reinterpreted` to the
host. Complete interpreters can call `assertCoversAll()` or `assertEliminates()`;
`effectRow(Program)` reports handled program sites, handled protocol ops,
reinterpreted source sites, emitted target protocol ops, forwarded/residual
program sites when statically knowable, and assertion helpers cover
reinterpretation and protocol-op handling. Manual session loops remain available
for hosts that need lower-level control.

Declarative morphisms can also be residualized. `Program.ResidualMorphism`
describes a source `Program.protocol` operation site, a target
`schema.Protocol.operation` descriptor, restricted `ability.ir.expr` payload
mapping metadata, response mapping metadata, and a disposition. The first
residualizer compiles supported identity/payload mappings with identity resume
responses into an ordinary `ProgramPlan` by replacing the source operation row
with the target protocol operation row. The returned residual program exposes
`compiled_plan`, `contract`, `protocol`, `Session`, `Handler`, `Interpreter`,
`effect_row`, `source_map`, `residualForSourceSite`, `sourceForResidualSite`,
and `mapResidualTrace`. This is an algebraic ProgramPlan transformation inside
the defunctionalized kernel: it is not a parser, source language, public VM,
Artifact API, async runtime, persistence layer, or trace serialization format.
Arbitrary Zig handlers and closures remain interpreter-only.

`Program.Pipeline` composes the same pieces into a proof-carrying residual
effect pipeline. A pipeline catalog lists declarative residual morphisms and a
static residual-effect goal. `Program.pipelineReport` is inspectable without
compiling a residual plan; it reports route witnesses, effect-row metadata, and
structured blockers such as missing handlers, unsupported residualization
shapes, schema mismatches, and unsatisfied goals. A successful
`Program.Pipeline` exposes `Residual`, `Interpreter(...)`, `certificate`,
`effect_row`, `pipeline_fingerprint_version == 1`, and source/residual/target
trace mapping helpers. It does not change `Program.run` or `Program.Session`;
callers pass residual handlers to `Pipeline.Interpreter(...)` explicitly, and
manual interpreters, capsules, morphisms, and residualization remain available.

See [docs/program_plan.md](docs/program_plan.md) for semantic program
authoring, typed product/sum bodies, tuple entry args, outputs, cleanup hooks,
nested-with targets, and `Program.contract`.
`ability.ir.builder.semantic` is the preferred construction layer for ordinary
custom protocol programs: it accepts typed params/locals/results, named blocks,
protocol op descriptors, and optional site labels, then emits an ordinary
`ProgramPlan`. `ability.effect.optional.plan` provides reusable
optional-specific rows and instructions for plan-native optional authoring while
compatibility APIs remain in place.
`examples/typed_program_plan.zig` runs product execution, sum matching,
tagged-union payload extraction, output cleanup, and contract inspection through
the public API.
Plan-native built-in prototypes under `examples/plan_native_*.zig` show the
same public entry point for optional, state/reader, writer, exception-style
abort, and resource-style lifecycle workflows while compatibility effect APIs
remain in place.
See [docs/custom_effect_authoring.md](docs/custom_effect_authoring.md) for the
preferred custom effect path: define `schema.Protocol`, derive schemas with
`schema.Registry`, author control flow with `builder.semantic`, execute through
`ability.program`, bind requests with `Program.protocol`, and audit/replay with
traces and fingerprints. Raw `ProgramPlan` tables remain available for advanced
kernel work; old `effect.Define`, `effect.ops`, and generated direct-style
custom effects remain outside the public surface.
See [docs/release_hardening.md](docs/release_hardening.md) for package/lint
coverage, file classification, and the built-in effects roadmap.

## Defunctionalized execution and agent loops

`Program.run` is the synchronous handler-dispatch path. It keeps executing the
validated `Body.compiled_plan` until the result and outputs are ready.

`Program.Session` is the defunctionalized, host-driven path. `next()` enters
runtime execution only long enough to advance the interpreter, then yields the
next effect operation as request data instead of dispatching to a Zig handler.
When normal completion reaches pending after hooks, `next()` yields
after-continuation request data in reverse unwind order. Each yielded op or after
request parks the session: the continuation is explicit interpreter frame state
stored in the session, not a captured Zig closure, and
`Runtime.deinitChecked()` rejects the runtime while that live session exists.
The host can inspect state or run other programs on the same runtime while a
session is parked, then resume later on the owning runtime/thread. The host
resumes an operation with a typed value, returns now from a choice/abort request,
or resumes an after continuation with the typed transformed value. Return-now and
abort terminal paths bypass after continuations, matching `Program.run`.

Each yielded request has a deterministic trace view. Operation traces include
the program label, plan hash, session turn index, static operation site index
and fingerprint, function/block/instruction coordinates, requirement and op
identity, op mode, payload/resume/result refs, payload value fingerprint, after
flag, and request fingerprint. After traces include the same program and turn
context, static after-site index and fingerprint, the source operation site
index, source function/block/instruction coordinates, the original
requirement/op identity, current value ref and fingerprint, expected output
ref, result ref, and request fingerprint. Static site identity and dynamic turn
identity are separate: a loop that yields from the same instruction reuses the
same static site while each occurrence receives a different turn index.
Fingerprints are stable across fresh deterministic runs when the plan, entry
args, host responses, and execution path are the same; they change when the
static site, yielded op, visible value, response kind/value, turn index, or plan
identity changes. Value
fingerprints hash supported typed values by contents and schema: unit, bool,
i32, usize, strings by bytes, and product/sum values through
`Body.value_schema_types`.

`Program.protocol` lets hosts avoid string-dispatching those records. The host
can bind `const Decide = Program.protocol.operationSite("agent", "decide", 0);`,
check `request.matches(Decide)` or `try request.as(Decide)`, decode
`Decide.Payload`, and resume with `Decide.Resume`. Handler-owned after requests
decode `AfterSite.Input`; handlerless after requests decode with
`typed_after.value(T)` after inspecting the live request value ref. Their
response value is checked against the live request output ref. The dynamic check
first proves the descriptor belongs to the same program, then compares static
site identity plus the relevant request refs before any site-aware response
trace or typed resume helper is used.

Trace fingerprints are audit/replay witnesses, not request tokens. Request
tokens remain in-process misuse guards for the active session and should not be
serialized as durable ids. Trace metadata is also not a session snapshot or a
prescribed serialization format. Hosts own persistence, external orchestration,
and any replay transcript encoding.

### Continuation capsules

For in-process branching, `Session.current()` returns the parked operation or
after-continuation request without advancing the interpreter. `Session.capture`
copies the parked continuation into a reusable `Session.Capsule`; restoring it
creates a fresh live parked session for the same `Program` and plan, with new
request tokens while preserving the same trace-visible request identity and
copied typed values. Hosts must `deinit` capsules; string, string-list, product,
and sum values are copied into capsule-owned storage. Capsules are owner values:
pass them by pointer, do not copy the struct itself, and restore them only before
`deinit`.

Capsule metadata includes the parked kind, static site indexes, result ref,
frame/after-stack shape, and a deterministic continuation fingerprint. Capsule
fingerprints and request fingerprints are audit/replay metadata. Request tokens
remain in-process misuse guards, not durable ids. Request and after request
payload views are ordinary session request views; inspect them while the parked
session that produced them is still live.

Capsules are owned Zig values for the same process; they are not `ProgramPlan`
artifacts, VM bytecode, source-language values, or a stable cross-version
serialization format. Hosts own any persistence if they serialize capsule
metadata themselves.

This is the foundation for agentic loops. The library does not bundle an async
runtime, parser, compiler, VM, Artifact API, source language, network client, or
LLM integration, and it does not widen the public root. `ProgramValue` remains
the scalar public carrier; typed product and sum payloads and resumes use the
existing `Body.value_schema_types` schema registry, including after-continuation
values. Result, output, and cleanup rules are the same `Program.Result` rules
used by `Program.run`. Durable session serialization remains a future direction;
in-process capsules are the public branching surface.

## Effects

Effect families remain under `ability.effect`. Built-in and custom bound
programs that expose `has_compiled_plan` execute through the same ProgramPlan
interpreter used by `ability.program`.

The shipped examples build reusable programs from semantic ProgramPlan
authoring and public plan-native helpers:

- `examples/state_basic.zig` demonstrates two named operations over handler-owned
  state.
- `examples/typed_program_plan.zig` demonstrates typed product/sum execution,
  outputs, cleanup, and `Program.contract` using semantic authoring for ordinary
  control flow.
- `examples/plan_native_optional.zig` demonstrates optional-like control flow as
  a plan-native choice op with a typed sum resume value, using
  `ability.effect.optional.plan`.
- `examples/plan_native_state_reader.zig` demonstrates state and reader as
  plan-native transform ops with final state returned through outputs.
- `examples/plan_native_writer.zig` demonstrates writer accumulation through
  typed outputs and explicit output cleanup.
- `examples/agent_loop.zig` demonstrates a host-driven `Program.Session` loop
  where yielded decide/tool operations are data, the session parks between
  turns, semantic site labels plus request/response fingerprints are printed,
  and a second run verifies the recorded request fingerprints before replaying
  the same typed responses.
- `examples/continuation_branching.zig` demonstrates `Session.current`,
  reusable continuation capsules, fresh restored request tokens, copied payload
  ownership, and multiple typed outcomes from one parked operation request.
- `examples/interpreter_branching.zig` demonstrates the higher-level typed
  handler/interpreter algebra: a handler captures the current continuation with
  `Control.capture`, the current interpreter resumes the main approval path, and
  two restored interpreters branch the reusable capsule into approve and deny
  outcomes.
- `examples/protocol_reinterpretation.zig` demonstrates typed protocol
  morphisms: an `approval.request` choice site is reinterpreted into a
  protocol-level `policy.check` transform request, the source continuation is
  preserved as a capsule, and the policy answer maps back to either resume or
  return-now behavior for the original approval site.
- `examples/residualized_approval_policy.zig` demonstrates the same approval to
  policy morphism compiled statically: dynamic reinterpretation and the
  residualized program agree for allow and deny cases, the residual program
  exposes a `policy.check` site, and the source/residual fingerprints map back
  to the eliminated approval site.
- `examples/effect_pipeline.zig` demonstrates a proof-carrying pipeline:
  `approval.request` is residualized to `policy.check`, the residual policy site
  is dynamically reinterpreted to `rules.lookup`, the certificate prints
  residualized/emitted/residual effect metadata, and a partial run returns an
  inspectable target request plus capsule.
- `examples/custom_approval_workflow.zig` demonstrates transform, choice, and
  abort operations declared through a schema-first custom protocol family,
  schema registry, semantic builder, and both synchronous and host-driven
  session execution.

## Build

The maintained verification contract is:

```sh
zig build
zig build test --summary none
zig build lint -- --max-warnings 0
```

Useful example runs:

```sh
zig build run-state-basic
zig build run-typed-program-plan
zig build run-plan-native-optional
zig build run-plan-native-state-reader
zig build run-plan-native-writer
zig build run-agent-loop
zig build run-continuation-branching
zig build run-interpreter-branching
zig build run-protocol-reinterpretation
zig build run-residualized-approval-policy
zig build run-effect-pipeline
zig build run-custom-approval-workflow
```
