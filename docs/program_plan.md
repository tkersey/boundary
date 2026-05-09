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
- executable capability-ledger metadata

`Program.contract` is inspection metadata. It does not expose mutable function,
block, instruction, Artifact, VM, compiler, parser, or capability-map surfaces.

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

## Custom effect authoring direction

Custom effect authoring is not public yet. The intended direction is
schema-first and plan-native: custom descriptions should lower to the same
ProgramPlan requirement, op, value schema, output, nested-with, and contract
metadata used by built-in prototypes.

See [custom_effect_authoring.md](custom_effect_authoring.md) for the design
boundary and non-goals.
