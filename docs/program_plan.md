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

Missing or mismatched targets fail closed. There is no global target discovery.

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

## Examples

Run the typed ProgramPlan example with:

```sh
zig build run-typed-program-plan
```

It demonstrates typed product execution, optional sum matching,
tagged-union payload extraction, output collection and cleanup, and
`Program.contract` inspection through the public API.
