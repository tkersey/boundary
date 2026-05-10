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
wider public root. Raw `ProgramPlan` construction remains available.

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
uniqueness and therefore does not publish after metadata from those fallbacks.

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

## Plan Authoring

Lowered rows expose operation descriptors for layout-builder code:

```zig
const Exists = ApprovalRows.op("exists");
const Request = ApprovalRows.op("request");
const Invalid = ApprovalRows.op("invalid");

const instructions = [_]ability.ir.plan.Instruction{
    try Exists.call(root, exists_local, request_id_local),
    try Request.call(root, decision_local, approval_request_local),
    try Invalid.call(root, null, invalid_request_local),
};
```

Descriptors expose the op ordinal, op name, mode, `Payload`, `Resume`,
`payload_ref`, `resume_ref`, `opRef(function_ref)`, and
`call(function_ref, dst_local_or_null, payload_local_or_null)`. They remove the
need to duplicate op names, modes, payload refs, resume refs, and op table
indexes while still letting the caller own locals, blocks, instructions,
branches, value schemas, and cleanup hooks.

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

`examples/custom_approval_workflow.zig` is the reference example. It defines a
custom `workflow` protocol with transform, choice, and abort operations, lowers
it to rows, authors the remaining ProgramPlan control flow explicitly, runs
through `Program.run`, and also demonstrates a host-driven `Program.Session`
path using `Program.protocol` descriptors and deterministic trace replay.

## Non-Goals

- No `effect.Define`.
- No `effect.ops`.
- No old generated-family public API.
- No direct-style custom effects.
- No generated visitor DSL or trait-style host implementation.
- No automatic host runtime.
- No VM, Artifact, parser, compiler, or source-language API.
- No async runtime, network, or LLM integration.
- No durable session snapshot/restore.
- No serializable request tokens.
- No public root widening.
- No `ProgramValue` widening.
- No new value codecs.
