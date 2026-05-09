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
summaries. It is metadata for tests and callers that need to inspect what a
program declares; it does not expose mutable ProgramPlan tables, Artifact or VM
surfaces, or legacy capability maps.

See [docs/program_plan.md](docs/program_plan.md) for typed product/sum bodies,
tuple entry args, outputs, cleanup hooks, nested-with targets, and
`Program.contract`. `ability.ir.builder.typed` provides a small higher-level
builder prototype that still emits `ProgramPlan`. `ability.effect.optional.plan`
provides reusable optional-specific rows and instructions for plan-native
optional authoring while compatibility APIs remain in place.
`examples/typed_program_plan.zig` runs product execution, sum matching,
tagged-union payload extraction, output cleanup, and contract inspection through
the public API.
Plan-native built-in prototypes under `examples/plan_native_*.zig` show the
same public entry point for optional, state/reader, writer, exception-style
abort, and resource-style lifecycle workflows while compatibility effect APIs
remain in place.
See [docs/custom_effect_authoring.md](docs/custom_effect_authoring.md) for the
schema-first custom effect authoring direction. Custom generated effects are not
public yet; custom workflows should still lower to `ProgramPlan` and execute
through `ability.program`.
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

This is the foundation for agentic loops. The library does not bundle an async
runtime, parser, compiler, VM, Artifact API, source language, network client, or
LLM integration, and it does not widen the public root. `ProgramValue` remains
the scalar public carrier; typed product and sum payloads and resumes use the
existing `Body.value_schema_types` schema registry, including after-continuation
values. Result, output, and cleanup rules are the same `Program.Result` rules
used by `Program.run`. Durable session serialization and snapshot/restore are
future directions, not part of this surface.

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
- `examples/plan_native_optional.zig` demonstrates optional-like control flow as
  a plan-native choice op with a typed sum resume value, using
  `ability.effect.optional.plan`.
- `examples/plan_native_state_reader.zig` demonstrates state and reader as
  plan-native transform ops with final state returned through outputs.
- `examples/plan_native_writer.zig` demonstrates writer accumulation through
  typed outputs and explicit output cleanup.
- `examples/agent_loop.zig` demonstrates a host-driven `Program.Session` loop
  where yielded decide/tool operations are data, the session parks between
  turns, and the host supplies a typed sum action plus tool observations without
  handler dispatch.
- `examples/custom_approval_workflow.zig` demonstrates transform, choice, and
  abort operations in one plan without exposing a custom effect API.

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
zig build run-custom-approval-workflow
```
