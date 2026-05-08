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
`deinit()`. String results in `Program.Result.value` should be treated as
borrowed unless the body documents and implements ownership cleanup through
`Body.deinitResult(allocator, value)`. The value cleanup hook is independent of
output cleanup, so it can run even when output collection fails. Bodies that
declare `Outputs` must implement
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
`return_error` literals, and the executable capability-ledger summary. It is
metadata for tests and callers that need to inspect what a program declares; it
does not expose mutable ProgramPlan tables, Artifact or VM surfaces, or legacy
capability maps.

See [docs/program_plan.md](docs/program_plan.md) for typed product/sum bodies,
tuple entry args, outputs, cleanup hooks, nested-with targets, and
`Program.contract`. `ability.ir.builder.typed` provides a small higher-level
builder prototype that still emits `ProgramPlan`. `examples/typed_program_plan.zig`
runs product execution, sum matching, tagged-union payload extraction, output
cleanup, and contract inspection through the public API.

## Effects

Effect families remain under `ability.effect`. Built-in and custom bound
programs that expose `has_compiled_plan` execute through the same ProgramPlan
interpreter used by `ability.program`.

The shipped examples build reusable programs directly from public ProgramPlan
IR:

- `examples/state_basic.zig` demonstrates two named operations over handler-owned
  state.
- `examples/typed_program_plan.zig` demonstrates typed product/sum execution,
  outputs, cleanup, and `Program.contract`.
- `examples/custom_approval_workflow.zig` demonstrates transform, choice, and
  abort operations in one plan.

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
zig build run-custom-approval-workflow
```
