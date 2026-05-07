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

`ability.ir.ProgramPlan` can describe richer value schemas than
`ability.program` executes today. The current executable subset is scalar-only:
entry results, entry parameters, operation payloads, operation resumes, and
instruction-reachable locals must use `unit`, `bool`, `i32`, `usize`, or
`string` codecs. `product`, `sum`, and `string_list` remain visible in the IR as
schema and metadata shapes, but they are not executable through
`ability.program` yet.

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
`Body.deinitResult`. `outputs` is currently `void`; observable outputs should
remain explicit ProgramPlan values or handler-owned state until output
materialization is promoted onto the public plan-backed path.

Plans with entry parameters can add `Body.encodeArgs(handlers)` and return a
`[]const ability.ir.ProgramValue`. That public value union is the argument
carrier consumed by the ProgramPlan interpreter.

## Effects

Effect families remain under `ability.effect`. Built-in and custom bound
programs that expose `has_compiled_plan` execute through the same ProgramPlan
interpreter used by `ability.program`.

The shipped examples build reusable programs directly from public ProgramPlan
IR:

- `examples/state_basic.zig` demonstrates two named operations over handler-owned
  state.
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
zig build run-custom-approval-workflow
```
