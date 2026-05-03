# ability

`ability` is a Zig library for explicit local effect programs.

The public package root is intentionally small:

- `ability.effect`
- `ability.program`
- `ability.Runtime`

`effect` defines the effect families. `program` gives a reusable execution
surface for one named body. `Runtime` is the caller-owned local runtime used to
run programs repeatedly.

## Program

```zig
const std = @import("std");
const ability = @import("ability");

const Handlers = struct { base: i32 };

const Body = struct {
    pub fn program(_: *ability.Runtime, handlers: Handlers) !struct {
        value: i32,
        outputs: struct { total: i32 },
    } {
        return .{
            .value = handlers.base + 1,
            .outputs = .{ .total = handlers.base + 2 },
        };
    }
};

pub fn main() !void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const Program = ability.program("demo", Handlers, Body);
    var result = try Program.run(&runtime, .{ .base = 40 });
    defer result.deinit();

    // result.value == 41
    // result.outputs.total == 42
}
```

The label must be non-empty. The handler type passed to `ability.program` is the
exact type accepted by `Body.program(runtime, handlers)`. `Program.Result`
always exposes `value`, `outputs`, and `deinit()`.

## Effects

Effect families remain under `ability.effect`. Programs can call the public
family handlers directly from `Body.program`. For example, `examples/state_basic.zig`
runs a state effect and returns both the body value and final state output.

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
