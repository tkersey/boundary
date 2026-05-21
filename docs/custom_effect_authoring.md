# Custom effect authoring

Minimal schema-first custom protocol-family authoring is available under
`boundary.ir.schema`. It is public-adjacent and additive: the public root remains
small, and the schema path still emits ordinary `ProgramPlan` facts consumed by
`boundary.program`.

## Boundary

The public root remains:

- `boundary.effect`
- `boundary.ir`
- `boundary.program`
- `boundary.Runtime`

Custom protocol families do not create a second IR. They do not expose
`effect.Define`, `effect.ops`, old generated-family APIs, direct-style custom
effects, a parser, compiler, VM, Artifact API, source-language API, async
runtime, automatic host driver, network or LLM integration, value codecs, or a
wider public root. Raw `ProgramPlan` construction remains available as an
advanced/kernel escape hatch. Ordinary custom effects should use schema
protocols, schema registries, and semantic program authoring.

## Protocol Families

Define a family as schema data:

```zig
const Approval = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .lifecycle_tag = .generated_family,
    .ops = .{
        boundary.ir.schema.transform("exists", []const u8, i32),
        boundary.ir.schema.choiceAfter("request", []const u8, i32),
        boundary.ir.schema.abort("invalid", []const u8),
    },
});
```

The operation constructors are:

- `boundary.ir.schema.transform(name, Payload, Resume)`
- `boundary.ir.schema.transformAfter(name, Payload, Resume)`
- `boundary.ir.schema.choice(name, Payload, Resume)`
- `boundary.ir.schema.choiceAfter(name, Payload, Resume)`
- `boundary.ir.schema.abort(name, Payload)`

`schema.op.*` exposes the same constructors for call sites that prefer a nested
namespace. Abort ops have no after hook and use the existing terminal
`returnNow` semantics when driven by a session host.

`schema.Protocol` validates non-empty labels, non-empty op names, and duplicate
op names at comptime. The default lifecycle tag is `.generated_family`, and the
default output tag is `.none`. A protocol may declare an output with
`.output_tag` and `.output_type`; output rows are lowered through the same
schema lowerer as built-ins.

## Lowering

Lower a protocol through `Rows`, supplying the handler type and caller-owned
table offsets:

```zig
const ApprovalRows = Approval.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
    .first_output = 0,
});
```

The row bundle contains:

- `requirement`
- `ops`
- `outputs`
- `requirement_index`
- `first_op`
- `first_output`
- `op_count`
- `output_count`

These are ordinary ProgramPlan rows. Offsets stay caller-owned. There is no
hidden schema registry, no row reordering, and no automatic value-schema table.
After-enabled protocol rows infer ProgramPlan `has_after` metadata from the
per-binding handler type's direct `dispatch`/`afterDispatch` pair, or from
requirement-labeled handler shapes that can be resolved before a full plan
exists, such as `.approval.request.afterDispatch` or
`.approval.authored.afterDispatch`.
Top-level op-name and top-level `authored` fallbacks remain runtime conveniences
for globally unique op names, but row lowering cannot prove plan-global
uniqueness and therefore does not publish after metadata from those fallbacks;
their presence also suppresses direct-handler inference for that op.

Scalar payload, resume, and output refs lower without schema refs. Product and
sum refs require explicit caller-owned indexes:

```zig
const Rows = Approval.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = boundary.ir.schema.SchemaRefs(.{
        boundary.ir.schema.ref(ProductPayload, 0),
        boundary.ir.schema.ref(Decision, 1),
    }),
});
```

Missing product/sum refs fail closed. Duplicate schema refs and scalar schema
ref entries continue to fail through the existing `SchemaRefs` map logic.

## Schema Registry

For ordinary plans, derive schema tables and refs together:

```zig
const Schemas = boundary.ir.schema.Registry(.{
    RequestId,
    ApprovalDecision,
    Action,
});
```

The registry exposes `value_schemas`, `value_fields`, `value_variants`,
`schema_refs`, `schema_refs_type`, and `value_schema_types`.
Scalar types are accepted as local/parameter/result types but do not receive
schema indexes. Product and sum schema indexes are deterministic from the tuple
order. Nested product/sum fields and variants must also appear in the tuple so
the registry can use caller-owned indexes. Unsupported types, duplicate
structured entries, and missing nested structured refs fail closed at comptime.
When a semantic spec provides `.schemas = Schemas`, the builder takes the
value-schema tables from that registry; do not repeat them in the spec.

## Semantic Program Authoring

Lowered rows expose operation descriptors for semantic-builder code:

```zig
const Exists = ApprovalRows.op("exists");
const Request = ApprovalRows.op("request");
const Invalid = ApprovalRows.op("invalid");

const compiled = boundary.ir.builder.semantic.finish(.{
    .label = "approval",
    .ir_hash = 11,
    .entry = "run",
    .schemas = Schemas,
    .requirements = &.{ApprovalRows.requirement},
    .ops = &ApprovalRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = boundary.ir.builder.semantic.span(0, 1),
        .params = .{},
        .locals = .{
            boundary.ir.builder.semantic.local("request", RequestId),
            boundary.ir.builder.semantic.local("decision", ApprovalDecision),
        },
        .result = ApprovalDecision,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                boundary.ir.builder.semantic.call(Request, .{
                    .dst = "decision",
                    .payload = "request",
                    .label = "approval.request",
                }),
            },
            .terminator = boundary.ir.builder.semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid approval plan: " ++ @errorName(err));
```

The semantic builder computes locals, blocks, instruction spans, terminator
targets, and descriptor-backed op references while still emitting an ordinary
`boundary.ir.ProgramPlan`. Authors name blocks and locals instead of computing
`first_*` and `*_count` spans. Instruction helpers cover scalar constants,
integer arithmetic, zero comparison, sum matching/extraction, descriptor-backed
protocol calls, branches, jumps, value/unit/error returns, and optional semantic
site labels.

Descriptors expose the op ordinal, op name, mode, `Payload`, `Resume`,
`payload_ref`, `resume_ref`, `opRef(function_ref)`, and
`call(function_ref, dst_local_or_null, payload_local_or_null)` for lower-level
uses. Semantic calls remove the need to duplicate op names, modes, payload refs,
resume refs, and op table indexes while still letting the caller own protocol
families, branch structure, value schemas, outputs, and cleanup hooks.

Raw `boundary.ir.plan.*` rows and `boundary.ir.builder.layout` remain available
for exact table-shape tests, unsupported instructions, and advanced kernel
authoring. They are no longer the default path for custom effect examples.

## Contract and Protocol

After a schema family is lowered into a `ProgramPlan`, `boundary.program` treats
it like any other plan:

- `Program.contract.requirements` exposes the custom requirement row.
- `Program.contract.ops` exposes the custom operation rows.
- `Program.contract.session.yield_sites` exposes reachable operation sites.
- `Program.contract.session.after_sites` exposes reachable after sites.
- `Program.protocol.operationSite` and `afterSite` provide typed host-facing
  static descriptors.
- Dynamic session requests bind to those descriptors with `matches`, `as`,
  typed payload/value views, typed resume/return helpers, and response traces.
- Coverage helpers can prove all reachable custom operation and after sites are
  handled.
- `Program.Handler` binds typed handler functions to those descriptors, and
  `Program.Interpreter` composes them into a continuation-aware driver over
  `Program.Session`.
- `schema.Protocol.operation("op", .{ .schema_refs = ... })` provides a typed
  protocol-level operation descriptor independent of any static Program yield
  site. Handlers declared with `Program.Handler.morphism` can use
  `Program.Handler.reinterpret` to translate a source Program operation into
  another protocol operation while preserving the source continuation as a
  capsule.
- `Program.Handler.protocolOperation(TargetOp, handler)` handles those emitted
  protocol requests. The target response is mapped back through a comptime
  mapper into a valid source-site outcome, so composed interpreters can
  progressively eliminate, transform, expose, or forward residual effects.
- `Interpreter.effectRow(Program)` distinguishes handled Program sites, handled
  protocol operations, reinterpreted source sites, emitted target protocol
  operations, and statically known residual Program sites.
- `Program.ResidualMorphism` and `Program.residualize` compile supported
  declarative protocol morphisms into a new ordinary `ProgramPlan` instead of
  interpreting them dynamically. The first compiled shape supports
  identity/payload passthrough payload mappings and identity resume responses;
  unsupported expression shapes fail closed in residualization metadata or at
  compile time before a residual plan is emitted.
- `Program.Pipeline` plans across residual morphisms and residual-effect goals.
  A pipeline exposes a residual Program, `Pipeline.Interpreter(...)` adapters,
  effect-row metadata, structured blockers, a proof certificate, and
  deterministic source/residual/target trace correspondence.
  `Program.pipelineReport` keeps blockers inspectable when the caller is not
  demanding full success. Residual handlers are passed to
  `Pipeline.Interpreter(...)` explicitly.
- Optional semantic site labels appear on static yield/after sites,
  `Program.protocol` descriptors, dynamic request traces, and after traces when
  the body exposes `site_metadata`.

## Effect Exchange

Schema-first custom protocols can cross host boundaries through
`Program.Exchange` without changing the public root or adding a transport
stack. A manifest image describes the compiled Program exchange surface:
program and plan labels, ProgramPlan hash, exchange/trace/capsule/journal
versions, value schemas with field and variant rows, operation sites, after
sites, semantic labels, modes, refs, and site fingerprints.

When a `Program.Session` parks on a custom operation or after hook,
`Exchange.RequestEnvelope.fromRequest` and `fromAfter` encode the yielded data
as canonical typed bytes. The envelope carries the manifest fingerprint, static
site identity, request fingerprint, trace metadata, payload or current-value
image, expected response refs, result ref, and optional capsule image. Request
tokens remain local misuse guards and are never serialized.

Hosts answer with `Exchange.ResponseEnvelope.resume`, `returnNow`, or
`resumeAfter`. Decode and validation fail closed on malformed bytes,
fingerprint/checksum drift, manifest or ProgramPlan mismatch, wrong request
fingerprint, unsupported response kind, mismatched refs, invalid typed value
images, and unexpected trailing bytes. `Exchange.applyResponse` resumes the
parked session through the existing typed session paths, and
`Exchange.restoreFromRequestEnvelope` can restore a fresh parked session from an
embedded capsule image before applying a compatible response.

The mailbox runner is intentionally synchronous and transport-neutral: hosts
own queues, files, brokers, networks, schedulers, async runtimes, databases,
tools, humans, models, and persistence. Boundary owns the envelope format,
schema/ref validation, fingerprints, capsule compatibility checks, policy
guardrails, and journal-recordable exchange facts. Exchange fingerprints are
semantic witnesses, not security tokens or cryptographic authorization.

### Capability-routed Effect Exchange

For defunctionalized custom effects, handler scope can be represented as data
with `Program.Exchange.ProviderManifest`, `Capability`, `Route`, `Router`, and
`Authorization`. Provider manifests say which protocol labels, sites, protocol
operation fingerprints, response kinds, byte budgets, and capsule policies a
host-side provider claims. Capabilities grant that provider authority over a
subset of request envelopes, and attenuation can only narrow that authority.

Routers match request envelopes against host-owned provider/capability catalogs
and return deterministic route witnesses or structured blockers for no-route,
blocked, or ambiguous cases. Response envelopes can carry an authorization
sidecar that cites the capability path and route that allowed the answer, while
leaving existing response bytes and fingerprints stable. The mailbox runner can
write routed requests and reject inbox responses that do not cite an allowed
capability.

This layer is inspectable validation data, not cryptographic authentication or
a broker. Hosts own identity, signing, encryption, transport, persistence,
scheduling, network/async integration, tools, humans, and models. Request
tokens remain in-process guards and are never serialized.

### Effect Treaties

Direct-style handlers are lexical. When a custom effect is exchanged as a
defunctionalized request envelope, the handler-equivalent has to become
inspectable data. `Program.Exchange.Treaty` is that agreement. Routing finds a
provider. A treaty proves the provider may handle this effect in this way.

`ProviderOffer` describes a handleable effect surface for a provider and
manifest: supported Program sites, protocol operations and labels, accepted and
produced refs, legal response kinds, usage modes, response-use classes, replay
and branch policies, capsule policy, byte limits, tags, and metadata.
`MorphismOffer` describes one-hop protocol adaptation and can cite dynamic
morphism, residual morphism, or pipeline adapter fingerprints.

`TreatyResolver` consumes host-owned catalogs and policy. It can choose direct
handling, dynamic reinterpretation, residualized handling, or pipeline-adapted
handling; filter by provider tags and byte/capsule limits; enforce usage,
replay, branch, response-use, and obligation policy; and attenuate capability
authority when least-authority handling is required. The resolver returns a
treaty or structured blockers and never performs IO, sends messages, starts
tasks, calls providers, or owns cancellation.

The treaty certificate binds request envelope, provider manifest and offer,
capability or attenuated child capability, optional capability instance and
obligation, route, morphism or pipeline fingerprints, usage, response-use,
replay, branch, expected response refs/kinds, and journal policy. A response can
carry a treaty authorization sidecar so validation can reject wrong treaty,
provider, capability, route, response kind, response-use class, replay policy,
branch policy, or obligation transition without changing the response envelope
fingerprint domain.

`MailboxRunner.runTreatyStep` is treaty mode for the existing nonblocking
mailbox pattern: resolve before writing to the provider outbox, pair the request
with the treaty certificate, journal selected/blocked/authorized/accepted/
rejected treaty events, and apply only treaty-valid responses. Treaties are not
legal contracts, cryptographic security, network sessions, async tasks,
distributed consensus, workflow definitions, or provider execution. Hosts still
own identity, signing, encryption, transport, storage, scheduling, network,
persistence, tools, humans, models, and side effects.

### Provider Harnesses

Treaties define the agreement. `Program.Exchange.ProviderHarness` executes the
provider side of that agreement. It lets custom-effect authors define typed
provider handlers and derive the provider manifest, provider offers, offer
fingerprints, treaty resolver catalog metadata, typed request views, typed
outcomes, and coverage assertions from those declarations.

Use handler-first declarations for ordinary providers. This keeps provider
offers and handlers from drifting. `ProviderOffer` remains available as
deterministic data for treaties, journals, catalogs, and certificates, and manual
offers are an advanced escape hatch that can be validated against the derived
handler declaration before use.

`ProviderHarness.handle` is transport-neutral and nonblocking. It receives the
request envelope plus treaty certificate and validates request bytes, manifest,
treaty, provider, offer, capability, attenuated capability, route, usage,
response-use, replay, branch, obligation, capsule policy, byte limits, and
payload or current-value refs before invoking the typed handler. The handler
sees a typed request view with treaty/source/target metadata and typed
payload/current-value accessors. It does not receive request tokens, runtime
pointers, allocator pointers, mutable request envelope internals, or hidden host
context beyond the explicit provider context argument.

Typed outcomes are explicit: resume, return-now, resume-after, replay, reject,
forward, or pending. The harness validates the outcome against the derived offer,
builds the response envelope, attaches treaty-bound authorization, and can record
provider-side journal events. Hosts still own transport, queues, scheduling,
identity, signing, encryption, storage, network, persistence, retries, provider
lifecycle, and cancellation side effects.

Provider Harnesses are not async runtimes, RPC frameworks, network servers,
message brokers, provider registries, security layers, workflow engines, service
discovery systems, source languages, VMs, or Artifact APIs.

#### Program-backed providers

ProviderHarness made provider callbacks typed. Program-backed providers make
provider handlers defunctionalized. Use `ProviderHandler.program` when the
provider-side implementation should itself be an Boundary Program: inspectable
through `Program.contract`, driven through `Program.Session`, capturable through
normal capsules, journaled as a provider sub-computation, and able to yield
nested effects.

The provider declaration maps request data into handler Program entry args.
`payload_to_args` maps the request payload or current after value into the first
handler arg; `unit_args` starts no-arg handlers. The handler Program result maps
back to an outcome with `result_to_resume`, `result_to_return_now`, or
`result_to_resume_after`, subject to the same transform/choice/abort/after
response rules as function-backed outcomes. Mapping validation compares value
refs at comptime where possible and never includes request tokens, runtime or
allocator pointers, thread state, or implicit host context.

Effectful provider handlers park like any other Program. When a handler yields a
nested operation or after request, `startProgramExecution` returns a
provider-program execution with a nested request envelope and handler capsule
image. The host handles that nested request through ordinary Exchange, Treaty,
MailboxRunner, and ProviderHarness code, then calls `continueProgramExecution`
with the nested response. Completion builds the parent response envelope and
attaches treaty authorization. Provider-program execution participates in
Evidence with execution/mapping/nested-request refs and journal events for
started, parked, nested request/response, resumed, completed, rejected, and
failed turns.

Function-backed handlers remain the right tool for small callbacks, external
systems, and fixtures. Program-backed providers do not add async scheduling,
networking, RPC, service discovery, a workflow engine, parser, source language,
VM, Artifact API, persistence backend, signing, encryption, or host-handler
serialization. Hosts still own identity, signing, encryption, transport,
storage, scheduling, network, persistence, provider lifecycle, cancellation,
retries, and side effects.

### Defunctionalization Boundary

Custom effects should keep Boundary-native semantics in Boundary programs or
declarative Boundary data. Opaque Zig functions are still available, but they are
host intrinsics at the world boundary. They are not inspectable effect
semantics.

Use program-backed providers when a provider body should be Boundary-native.
Function-backed `ProviderHandler.intrinsicOperation` and `intrinsicAfter`
declare host-intrinsic provider handlers. The older `operation` and `after`
forms remain source-compatible aliases for function-backed intrinsic handlers.
Dynamic morphism mapper functions are also host intrinsics; residualized and
pipeline-backed morphisms are static Boundary-native transformations.

Use `Program.Evidence.DefunctionalizationReport` and
`Program.Evidence.DefunctionalizationPolicy` to audit custom protocols,
provider harnesses, interpreters, `Program.run` handler sets, morphism offers,
and treaty resolution. Strict policy rejects host intrinsics and unknown bodies.
World-boundary policy can allowlist declared intrinsics by fingerprint, kind, or
label.

### Linear Effect Sessions

Continuations can be copied; the world often cannot. Linear Effect Sessions add
an explicit usage discipline to exchanged custom effects without changing
`Program.Session` stepping. Use `Program.Exchange.Usage` to classify effects as
copyable, replayable, affine, linear, or ephemeral. Use `ResponseUse` to mark
fresh responses, journal replay, deterministic replay, or policy overrides. Use
`BranchPolicy` to describe whether an embedded capsule is unrestricted,
replay-only, single-live-branch, split-required, no-branch, or host-owned.

`EffectSessionSpec` describes the state machine. `Capability` is still a grant;
`CapabilityInstance` is the actual consumable branch-local authority.
`Obligation` connects a request envelope to that instance and records open,
consumed, replayed, canceled, or abandoned status, plus branch id, allowed
response kinds/refs, capsule image fingerprint, and response fingerprints.
Affine and linear effects reject duplicate fresh responses, and linear effects
close by consume or explicit cancellation unless policy records host-owned
abandonment.

Request envelopes can carry optional session, instance, obligation, usage,
branch, replay, ephemeral, and cancelability metadata. Response authorization
can be validated together with an obligation transition, and
`ObligationLedger.validate` catches duplicate consumption and unresolved linear
obligations. This remains deterministic validation metadata; hosts still own
identity, signing, encryption, transport, storage, scheduling, network,
persistence, provider execution, tools, humans, and models.

`examples/custom_approval_workflow.zig` is the reference example. It defines a
custom `workflow` protocol with transform, choice, and abort operations, lowers
it to rows with a registry-derived schema ref map, authors control flow with the
semantic builder, runs through `Program.run`, and also demonstrates a
host-driven `Program.Session` path using `Program.protocol` descriptors and
deterministic trace replay.

`examples/continuation_branching.zig` shows the same schema-first and semantic
authoring stack for protocol-hosted control at a parked choice boundary: the
host captures a reusable continuation capsule, restores it into independent
branches, resumes approval in one branch, and returns denial from another.

`examples/interpreter_branching.zig` shows the higher-level handler algebra over
the same primitive. A typed choice handler captures the current continuation
through `Control.capture`, resumes the main approval path, and later
interpreters restore the reusable capsule into approve and deny branches. The
main path does not hand-write a session loop.

`examples/protocol_reinterpretation.zig` shows handlers as effect morphisms. A
typed approval handler reinterprets `approval.request` into a protocol-level
`policy.check` request, the interpreter preserves the approval continuation as a
capsule, and the mapper converts the policy decision into either approval resume
or approval return-now behavior.

`examples/residualized_approval_policy.zig` shows the static counterpart. A
declarative residual morphism lowers the source `approval.request` site into a
residual `policy.check` Program site. The example runs dynamic reinterpretation
and residual execution for allow and deny cases, prints source/residual
fingerprints, and demonstrates trace correspondence without adding a parser,
source language, public VM, Artifact API, async runtime, persistence backend, or
trace serialization requirement.

`examples/effect_pipeline.zig` composes those pieces. The pipeline residualizes
`approval.request` to `policy.check`, then dynamically reinterprets the residual
policy request to `rules.lookup`. It prints the pipeline certificate summary,
proves source dynamic and residual pipeline results agree, maps residual traces
back to source sites, and shows a partial run where the host resumes a capsule
manually.

## Preferred Path

1. Define the protocol with `boundary.ir.schema.Protocol`.
2. Define value schemas with `boundary.ir.schema.Registry`.
3. Lower rows with `Protocol.Rows(Handlers, .{ .schema_refs = Schemas.schema_refs, ... })`.
4. Author control flow with `boundary.ir.builder.semantic`.
5. Execute with `boundary.program` and `Program.run`.
6. Step host-driven runs with `Program.Session`.
7. Bind dynamic requests with `Program.protocol`.
8. Derive protocol-level op descriptors with `Protocol.operation` when a handler
   needs to emit a target protocol request.
9. Compose typed continuation-aware handlers and protocol-operation handlers with
   `Program.Interpreter`.
10. Use `Program.ResidualMorphism` plus `Program.residualize` when the morphism
    is declarative enough to compile into a residual ProgramPlan.
11. Use `Program.Pipeline` when residualization, goals, blockers, and trace
    correspondence should be planned and certified together.
12. Use `Program.Exchange` when yielded custom protocol requests or after hooks
    must leave the process as typed manifest/request/response envelopes.
13. Inspect effect rows, source maps, trace maps, certificates, capsules,
    envelopes, and fingerprints.
14. Use `Program.Evidence` refs, dependencies, reports, and views when a custom
    protocol surface needs machine-readable validation evidence across
    contracts, protocol descriptors, sessions, exchange envelopes, treaties, or
    provider harnesses.
15. Audit semantic boundaries with `DefunctionalizationReport` and enforce them
    with `DefunctionalizationPolicy` when custom protocols cross host code.

## Non-Goals

- No `effect.Define`.
- No `effect.ops`.
- No old generated-family public API.
- No direct-style custom effects.
- No generated visitor DSL or trait-style host implementation.
- No automatic host runtime. `Program.Interpreter` is a typed algebra over the
  explicit `Program.Session` machine, not a replacement for it.
- No pipeline compiler product. `Program.Pipeline` is an algebraic planner over
  existing Program/residualize/interpreter primitives, not a parser, source
  language, public VM API, Artifact API, async runtime, or persistence backend.
- No VM, Artifact, parser, compiler, or source-language API.
- No async runtime, network, or LLM integration.
- No persistence backend or serializable request tokens; durable support is
  limited to explicit `Program.Session` v1 capsule images and interaction
  journals that hosts persist themselves.
- No serializable request tokens.
- No public root widening.
- No `ProgramValue` widening.
- No new value codecs.
- No cross-thread sessions, persistence backend, or required trace serialization
  format.
- No residualization of arbitrary Zig closures or host functions; those remain
  explicit host intrinsics.

Custom protocols participate in Evidence through the existing
Program.contract, Program.protocol, Program.Session, and Program.Exchange
surfaces. Evidence does not add a parser, VM, new effect semantics, value
codec, security layer, or serialized request tokens; it gives the existing
proof structures one shared reference and reporting vocabulary.
