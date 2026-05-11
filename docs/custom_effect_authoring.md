# Custom effect authoring

Minimal schema-first custom protocol-family authoring is available under
`ability.ir.schema`. It is public-adjacent and additive: the public root remains
small, and the schema path still emits ordinary `ProgramPlan` facts consumed by
`ability.program`.

## Boundary

The public root remains:

- `ability.effect`
- `ability.ir`
- `ability.program`
- `ability.Runtime`

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
const Approval = ability.ir.schema.Protocol(.{
    .label = "approval",
    .lifecycle_tag = .generated_family,
    .ops = .{
        ability.ir.schema.transform("exists", []const u8, i32),
        ability.ir.schema.choiceAfter("request", []const u8, i32),
        ability.ir.schema.abort("invalid", []const u8),
    },
});
```

The operation constructors are:

- `ability.ir.schema.transform(name, Payload, Resume)`
- `ability.ir.schema.transformAfter(name, Payload, Resume)`
- `ability.ir.schema.choice(name, Payload, Resume)`
- `ability.ir.schema.choiceAfter(name, Payload, Resume)`
- `ability.ir.schema.abort(name, Payload)`

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
    .schema_refs = ability.ir.schema.SchemaRefs(.{
        ability.ir.schema.ref(ProductPayload, 0),
        ability.ir.schema.ref(Decision, 1),
    }),
});
```

Missing product/sum refs fail closed. Duplicate schema refs and scalar schema
ref entries continue to fail through the existing `SchemaRefs` map logic.

## Schema Registry

For ordinary plans, derive schema tables and refs together:

```zig
const Schemas = ability.ir.schema.Registry(.{
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

const compiled = ability.ir.builder.semantic.finish(.{
    .label = "approval",
    .ir_hash = 11,
    .entry = "run",
    .schemas = Schemas,
    .requirements = &.{ApprovalRows.requirement},
    .ops = &ApprovalRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = ability.ir.builder.semantic.span(0, 1),
        .params = .{},
        .locals = .{
            ability.ir.builder.semantic.local("request", RequestId),
            ability.ir.builder.semantic.local("decision", ApprovalDecision),
        },
        .result = ApprovalDecision,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                ability.ir.builder.semantic.call(Request, .{
                    .dst = "decision",
                    .payload = "request",
                    .label = "approval.request",
                }),
            },
            .terminator = ability.ir.builder.semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid approval plan: " ++ @errorName(err));
```

The semantic builder computes locals, blocks, instruction spans, terminator
targets, and descriptor-backed op references while still emitting an ordinary
`ability.ir.ProgramPlan`. Authors name blocks and locals instead of computing
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

Raw `ability.ir.plan.*` rows and `ability.ir.builder.layout` remain available
for exact table-shape tests, unsupported instructions, and advanced kernel
authoring. They are no longer the default path for custom effect examples.

## Contract and Protocol

After a schema family is lowered into a `ProgramPlan`, `ability.program` treats
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
- Optional semantic site labels appear on static yield/after sites,
  `Program.protocol` descriptors, dynamic request traces, and after traces when
  the body exposes `site_metadata`.

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

## Preferred Path

1. Define the protocol with `ability.ir.schema.Protocol`.
2. Define value schemas with `ability.ir.schema.Registry`.
3. Lower rows with `Protocol.Rows(Handlers, .{ .schema_refs = Schemas.schema_refs, ... })`.
4. Author control flow with `ability.ir.builder.semantic`.
5. Execute with `ability.program` and `Program.run`.
6. Step host-driven runs with `Program.Session`.
7. Bind dynamic requests with `Program.protocol`.
8. Derive protocol-level op descriptors with `Protocol.operation` when a handler
   needs to emit a target protocol request.
9. Compose typed continuation-aware handlers and protocol-operation handlers with
   `Program.Interpreter`.
10. Inspect effect rows, traces, capsules, and fingerprints.

## Non-Goals

- No `effect.Define`.
- No `effect.ops`.
- No old generated-family public API.
- No direct-style custom effects.
- No generated visitor DSL or trait-style host implementation.
- No automatic host runtime. `Program.Interpreter` is a typed algebra over the
  explicit `Program.Session` machine, not a replacement for it.
- No VM, Artifact, parser, compiler, or source-language API.
- No async runtime, network, or LLM integration.
- No durable session snapshot/restore.
- No serializable request tokens.
- No public root widening.
- No `ProgramValue` widening.
- No new value codecs.
- No cross-thread sessions, persistence backend, or required trace serialization
  format.
