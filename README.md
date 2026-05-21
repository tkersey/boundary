# boundary

`boundary` is a Zig library for explicit local effect programs.

The public package root is intentionally small:

- `boundary.effect`
- `boundary.ir`
- `boundary.program`
- `boundary.Runtime`

`effect` defines the effect families. `ir` exposes the public ProgramPlan
builder. `program` gives a reusable execution surface for one named compiled
body. `Runtime` is the caller-owned local runtime used to run programs
repeatedly.

Each concrete `Program` also exposes `Program.Evidence`, the canonical internal
evidence kernel for versioned fingerprint domains, evidence refs, dependency
lists, validation blockers/reports, certificate and authorization views, journal
projections, and policy summaries. Evidence fingerprints are deterministic
semantic witnesses, not cryptographic security claims or serialized request
tokens. See [docs/evidence_kernel.md](docs/evidence_kernel.md).

## Program

`boundary.program` executes a `Body.compiled_plan`. The plan is built at comptime
with `boundary.ir.builder`, validated before it escapes, and interpreted by
`Program.run`.

`boundary.ir.ProgramPlan` executes scalar values directly and can execute
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
`boundary.ir.NestedWithTarget`. Unsupported plans report a capped capability
ledger in compile errors; the ledger records stable blocker tags, function and
instruction coordinates, and whether the 64-record cap truncated diagnostics.

```zig
const std = @import("std");
const boundary = @import("boundary");

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

fn plan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const value = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        boundary.ir.builder.callOp(root, value, boundary.ir.builder.op(root, 0), null) catch unreachable,
        boundary.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]boundary.ir.plan.Function{.{
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
    const requirements = [_]boundary.ir.plan.Requirement{.{ .label = "authored", .first_op = 0, .op_count = 1 }};
    const ops = [_]boundary.ir.plan.Op{.{ .requirement_index = 0, .op_name = "authored", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32, .has_after = true }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_value }};

    return boundary.ir.builder.finish(.{
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
    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const Program = boundary.program("demo", Handlers, Body);
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
either `[]const boundary.ir.ProgramValue` for scalar arguments or a tuple whose
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
`schema.Protocol.operation` descriptor, restricted `boundary.ir.expr` payload
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
`boundary.ir.builder.semantic` is the preferred construction layer for ordinary
custom protocol programs: it accepts typed params/locals/results, named blocks,
protocol op descriptors, and optional site labels, then emits an ordinary
`ProgramPlan`. `boundary.effect.optional.plan` provides reusable
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
`boundary.program`, bind requests with `Program.protocol`, and audit/replay with
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
serialized as durable ids. Trace metadata is also not a session snapshot.
Hosts that need restart-like handoff can use the explicit v1 capsule image and
journal codecs under `Program.Session`; hosts still own persistence backends and
external orchestration.

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

Capsules are owned Zig values for the same process. `capsule.encode(allocator)`
or `Session.Capsule.Image.fromCapsule` produces deterministic v1 bytes, and
`Session.Capsule.decode(allocator, bytes)` reconstructs an owned reusable
capsule for the same `Program` and plan before `Session.restore` mints fresh
request tokens. Capsule images are not `ProgramPlan` artifacts, VM bytecode, or
source-language values, and compatibility is limited to the explicit v1 format
and fingerprint policy.

`Session.Journal` records deterministic request/response/capsule/done entries.
Its recorder can run alongside existing interpreter trace recorders through
`.journal_recorder`, and its replayer validates that a fresh session yields the
recorded request fingerprint before exposing the decoded typed response value.
Journals replay by fingerprints and typed response images, never by request
tokens.

### Effect Exchange

`Program.Exchange` is the transport-neutral ABI for moving yielded effects
across host boundaries as canonical typed data. `Exchange.Manifest.encode`
describes the compiled program's exchange surface: program and plan labels,
ProgramPlan hash, trace/capsule/journal/exchange versions, operation sites,
after sites, semantic labels, value schemas, refs, modes, and site
fingerprints. It is a protocol contract, not a VM artifact or package format.

`Exchange.RequestEnvelope.fromRequest` and `fromAfter` encode the currently
yielded operation or after-continuation request with trace metadata, static site
identity, typed payload/current-value image, expected response refs, optional
capsule image, and envelope fingerprint. Request tokens, runtime pointers,
allocator state, thread IDs, handlers, and host context are never serialized.

`Exchange.ResponseEnvelope.resume`, `returnNow`, and `resumeAfter` encode a
host answer for a specific request envelope. Decode and validation fail closed
on bad magic/version, truncation, malformed lengths, trailing bytes,
fingerprint mismatch, manifest/request mismatch, unsupported response kind,
wrong response ref, or invalid typed value image. `Exchange.applyResponse`
applies a validated response to the currently parked `Program.Session` through
the existing typed resume/return/resume-after paths. If a request envelope
contains a capsule image, `Exchange.restoreFromRequestEnvelope` restores a fresh
parked session and verifies the current request fingerprint before resuming.

`Exchange.Policy` provides local guardrails for allowed sites, response kinds,
capsule embedding, response value images, and envelope/payload sizes. The policy
is not cryptographic security. `Exchange.MailboxRunner` is a small nonblocking
pattern over host-owned outbox/inbox storage; Boundary owns canonical bytes and
validation, while hosts own transport, persistence, scheduling, network, async,
RPC, message brokers, databases, tools, humans, and models.

### Capability-routed Effect Exchange

`Exchange.ProviderManifest` records what a host/provider claims it can handle:
provider label/fingerprint, supported program manifests, protocol labels, sites
or protocol-op fingerprints, response kinds, byte limits, capsule policy, tags,
and metadata. `Exchange.Capability` grants one provider permission to answer a
subset of request shapes. Capabilities can be attenuated deterministically:
child grants may remove sites, response kinds, refs, capsule permissions, or
byte budget, but attempts to add authority fail closed.

`Exchange.Router` matches a request envelope against host-owned provider and
capability catalogs and returns a route witness or a no-route, blocked, or
ambiguous result. Response envelopes can carry an `Exchange.Authorization`
sidecar citing provider, capability, capability-path, route, request, and
response fingerprints. This sidecar deliberately preserves existing response
envelope byte/fingerprint semantics; it adds validation metadata rather than
changing the transport ABI.

`Exchange.MailboxRunner` can use a router to append routed requests to
host-owned outboxes and can require capability authorization before applying an
inbox response. `Session.Journal` can record provider/capability/route and
authorization events for route selection, blocked routes, authorized responses,
and rejected responses. These capabilities are deterministic validation data,
not secret bearer tokens, identity, signing, encryption, transport security, or
network authentication. Hosts that need those properties wrap Boundary’s data in
their own security and transport systems.

### Effect Treaties

Direct-style algebraic handlers are installed lexically. Exchanged
defunctionalized effects need the same idea represented as data: an
`Exchange.Treaty`. Routing finds a provider. A treaty proves the provider may
handle this effect in this way.

`Exchange.ProviderOffer` describes a deterministic handleable surface linked to
a provider and manifest: supported sites or protocol operations, accepted and
produced refs, response kinds, usage modes, response-use classes, replay and
branch policies, capsule policy, byte limits, tags, and metadata.
`Exchange.MorphismOffer` describes one-hop protocol adaptation metadata over
existing dynamic morphism, residual morphism, and pipeline fingerprints.

`Exchange.TreatyResolver` is a pure resolver over host-owned catalogs. It
validates the request envelope against the manifest, finds direct or adapted
offers, checks capabilities, optionally attenuates to least authority, enforces
usage/replay/branch/response-use/capsule policy, selects a route, and returns a
treaty, no-treaty, ambiguity, or structured blockers. It never sends messages,
calls providers, performs IO, or owns scheduling.

`Exchange.Treaty.Certificate` binds the request, manifest, provider, offer,
capability or attenuated child, optional capability instance or obligation,
route, morphism or pipeline fingerprints, usage mode, response-use policy,
replay policy, branch policy, expected response refs/kinds, and journal policy.
Response envelopes can carry a treaty authorization sidecar that cites the
treaty, certificate, offer, route, usage, replay, branch, and response-use
metadata while preserving the existing response envelope fingerprint domain.

`Exchange.MailboxRunner.runTreatyStep` runs treaty mode: resolve before writing
to the outbox, attach the treaty certificate for providers, journal treaty
request/selection/certificate/authorization/accepted/rejected events, and reject
responses that do not match the selected treaty. Effect Treaties are typed,
deterministic protocol-negotiation metadata. They are not legal contracts,
cryptographic security, network sessions, async tasks, workflows, brokers,
distributed consensus, or provider execution. Hosts still own identity,
signing, encryption, transport, storage, scheduling, network, persistence, and
cancellation side effects.

### Provider Harnesses

Treaties define the agreement. `Exchange.ProviderHarness` executes the provider
side of that agreement. A harness is declared from typed provider handlers, and
the handler declarations derive the provider manifest, provider offers, offer
fingerprints, treaty resolver catalog entries, typed request views, outcome
types, and coverage metadata. `ProviderOffer` remains deterministic data for
treaties, journals, catalogs, and certificates, but the preferred path is
handler-first so provider offers and provider handlers cannot drift.

`ProviderHarness.handle` is transport-neutral and nonblocking. It receives a
request envelope and treaty certificate, validates envelope, manifest, treaty,
provider, offer, capability, attenuated capability, route, usage, response-use,
replay, branch, obligation, capsule, byte-limit, and payload/current-value
metadata before invoking the typed handler. The handler receives a typed request
view with treaty/source/target fingerprints and typed payload or current-value
accessors, not request tokens, runtime state, mutable envelope internals, or host
context outside the explicit provider context argument.

Handlers return explicit outcomes: resume, return-now, resume-after, replay,
reject, forward, or pending. The harness checks the outcome against the derived
offer policy, builds the response envelope with existing exchange machinery,
attaches a treaty-bound `Treaty.Authorization`, and can record provider-side
journal events for received, validated, rejected, invoked, built, authorized,
forwarded, and pending turns. Hosts still own inboxes, outboxes, transport,
scheduling, identity, signing, encryption, storage, network, persistence,
provider lifecycle, and retries.

Provider Harnesses are typed validation-and-response adapters. They are not an
async runtime, RPC framework, network server, message broker, provider registry,
security layer, workflow engine, service discovery system, source language, VM,
or Artifact API. Manual `ProviderOffer` construction remains available as an
advanced escape hatch, and harness validation can reject manual offers that do
not exactly match the derived handler declaration.

#### Program-backed providers

ProviderHarness made provider callbacks typed. Program-backed providers make
provider handlers defunctionalized. `ProviderHandler.program` binds a provider
offer to an ordinary Boundary `Program`: the request payload or current value is
mapped into handler entry args, the handler runs through `Program.Session`, and
the handler result maps back to a provider outcome such as resume, return-now,
or resume-after.

Because the handler is a Program, it can yield nested effects. The harness
returns a parked provider-program execution with the nested request envelope and
a capsule image for the handler continuation. Hosts route that nested request
through the same Exchange, Treaty, MailboxRunner, and ProviderHarness machinery,
then call `continueProgramExecution` with the nested response. On completion,
the original provider response is built with the existing `ResponseEnvelope` and
treaty authorization path. Provider-program execution has deterministic
fingerprints, Evidence refs, and provider-program journal events for started,
parked, nested request/response, resumed, completed, rejected, and failed turns.

Function-backed handlers remain supported for simple callbacks, external
integrations, and fixtures. Program-backed providers are not an async runtime,
provider scheduler, network server, RPC layer, workflow engine, VM, source
language, parser, Artifact API, persistence backend, or security system. Hosts
still own identity, signing, encryption, transport, storage, scheduling,
network, persistence, provider lifecycle, cancellation, and retries; request
tokens, runtime allocators, thread state, and arbitrary host handlers are not
serialized.

#### Defunctionalization boundary audit

Boundary-native semantics are represented as Boundary programs or declarative
Boundary data. Opaque host functions remain supported, but they are marked as
host intrinsics, not treated as inspectable effect semantics.

`Program.Evidence.SemanticBody` classifies semantic bodies as
`boundary_program`, `declarative`, `residualized_program`, `pipeline`,
`kernel_primitive`, `host_intrinsic`, or `unknown`.
`Program.Evidence.HostIntrinsic` gives opaque host behavior a deterministic
descriptor and Evidence ref. `Program.Evidence.DefunctionalizationReport` counts
the boundary kinds for provider harnesses, provider offers, treaties, resolver
results, interpreters, `Program.run` handler sets, morphism offers, pipelines,
journals, and catalogs. `Program.Evidence.DefunctionalizationPolicy` can reject
intrinsics, reject unknown bodies, allowlist intrinsics, reject dynamic mappers,
require program-backed providers, require static/declarative morphisms, and
prefer less opaque treaty routes.

Program-backed provider declarations report `boundary_program`; function-backed
ProviderHarness declarations report `host_intrinsic`. `Program.Interpreter` and
`Program.run` handler functions are host intrinsics. Dynamic morphism mapper
functions are host intrinsics; residualized and pipeline-backed morphisms report
static Boundary-native bodies. TreatyResolver can reject or prefer routes using
those classifications, and rechecks defunctionalization policy during
treaty-response validation.

See [docs/defunctionalization_boundary.md](docs/defunctionalization_boundary.md).

#### Boundary closure certificates

`Program.BoundaryClosure` analyzes a configured root program/catalog/policy
surface as evidence, not as runtime execution. It builds static effect shapes
from reachable operation and after sites, dry-runs treaty planning by shape,
records a deterministic closure graph, lowers blockers through
`Program.Evidence.Blocker`, and emits a closure report and certificate. The
certificate proves every configured Boundary effect shape is handled inside
Boundary, or that the only open boundaries are explicit allowlisted world ports.

Closure prepares a contract for an adjacent `world` interpreter. World can
consume root refs, provider refs, static treaty plans, world-port declarations,
policy summaries, evidence refs, and blockers without rediscovering Boundary's
graph. Boundary still does not implement World: scheduling, storage, network,
transport, provider lifecycle, host intrinsic execution, retries, identity,
signing, encryption, and cancellation remain host-owned.

See [docs/boundary_closure.md](docs/boundary_closure.md).

### Linear Effect Sessions

Continuations can be copied; the world often cannot. Linear Effect Sessions are
the bridge. `Program.Exchange.Usage` classifies exchanged effects as
`copyable`, `replayable`, `affine`, `linear`, or `ephemeral`; `ResponseUse`
distinguishes fresh provider answers from journal/deterministic replay and
policy overrides; `BranchPolicy` records whether reusable capsules are
unrestricted, replay-only, single-live-branch, split-required, no-branch, or
host-owned.

`EffectSessionSpec` is a small deterministic state-machine descriptor.
`Capability` remains general authority, while `CapabilityInstance` is the
consumable authority object for one effect session branch. A yielded request can
open an `Obligation` that records the request envelope fingerprint, request and
site fingerprints, usage mode, branch id, allowed response kinds/refs, optional
capsule image fingerprint, and lifecycle status. Obligations can be consumed,
replayed, canceled, or abandoned when policy permits; affine and linear
obligations reject duplicate fresh consumption, and linear obligations are
cleanly closed by consume or explicit cancel.

Request envelopes can carry optional session/instance/obligation usage
metadata without serializing request tokens. Response authorization can be
combined with an obligation transition so hosts can validate provider,
capability, route, request, response, current obligation status, and session
state in one deterministic result. `ObligationLedger.validate` catches duplicate
consumption and unresolved linear obligations, and journal exchange events can
record session, instance, obligation, transition, branch, and blocker metadata.

This is deterministic validation metadata, not cryptographic security. Hosts
still own identity, signing, encryption, transport, storage, scheduling,
networking, persistence, provider execution, tools, humans, and models.

This is the foundation for agentic loops. The library does not bundle an async
runtime, parser, compiler, VM, Artifact API, source language, network client, or
LLM integration, and it does not widen the public root. `ProgramValue` remains
the scalar public carrier; typed product and sum payloads and resumes use the
existing `Body.value_schema_types` schema registry, including after-continuation
values. Result, output, and cleanup rules are the same `Program.Result` rules
used by `Program.run`.

## Effects

Effect families remain under `boundary.effect`. Built-in and custom bound
programs that expose `has_compiled_plan` execute through the same ProgramPlan
interpreter used by `boundary.program`.

The shipped examples build reusable programs from semantic ProgramPlan
authoring and public plan-native helpers:

- `examples/state_basic.zig` demonstrates two named operations over handler-owned
  state.
- `examples/typed_program_plan.zig` demonstrates typed product/sum execution,
  outputs, cleanup, and `Program.contract` using semantic authoring for ordinary
  control flow.
- `examples/plan_native_optional.zig` demonstrates optional-like control flow as
  a plan-native choice op with a typed sum resume value, using
  `boundary.effect.optional.plan`.
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
- `examples/provider_harness_direct.zig` demonstrates request-side treaty
  mailbox execution, handler-first provider offer derivation, provider harness
  validation, treaty-authorized response construction, and requester-side resume.
- `examples/provider_harness_morphism.zig` demonstrates the provider harness
  example entrypoint used for morphism treaty proof wiring.
- `examples/provider_harness_replayable.zig` demonstrates the provider harness
  example entrypoint used for replayable treaty proof wiring.
- `examples/defunctionalization_boundary.zig` demonstrates program-backed and
  function-backed providers answering the same request, then prints semantic
  body classifications, intrinsic fingerprint, treaty preference, and strict
  intrinsic rejection.
- `examples/host_intrinsic_allowlist.zig` demonstrates a function-backed
  provider as an explicit host intrinsic: strict policy rejects it, a
  world-boundary allowlist admits it, and the treaty-authorized response
  completes.
- `examples/boundary_closure_strict.zig` demonstrates a strict closure
  certificate where a root approval effect is handled by a program-backed
  provider with no world ports or host intrinsics.
- `examples/boundary_closure_nested.zig` demonstrates closure planning for a
  root approval effect whose program-backed provider yields a nested
  `policy.check` effect handled by another Boundary-native provider.
- `examples/boundary_closure_world_port.zig` demonstrates strict rejection of a
  host intrinsic and world-boundary acceptance when the same intrinsic is
  surfaced as an explicit world port.
- `examples/durable_capsule_replay.zig` demonstrates v1 capsule image
  encode/decode, restored fresh request tokens, and reusable approve/deny
  branches.
- `examples/journal_replay.zig` demonstrates deterministic journal
  encode/decode and replay-cursor validation before applying a typed response.
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
zig build run-provider-harness-direct
zig build run-provider-harness-morphism
zig build run-provider-harness-replayable
zig build run-boundary-closure-strict
zig build run-boundary-closure-nested
zig build run-boundary-closure-world-port
zig build run-program-provider-direct
zig build run-program-provider-nested
zig build run-program-provider-resume
zig build run-custom-approval-workflow
```
