# shift

`shift` is a Zig 0.15.2 implementation of one-shot, stackful `shift/reset` with an escaping, step-driven suspension API.

The current runtime is explicit rather than callback-driven:

- `shift.reset(Spec, &runtime, body)` runs `body` under `Spec.tag` and returns either `.complete` or `.suspended`.
- `shift.shift(Spec, request)` suspends to the nearest active delimiter for `Spec.tag` and yields `request` to the caller.
- `shift.Suspension(Spec).resumeWith(value)` resumes the captured continuation exactly once.
- `shift.Suspension(Spec).discontinue(err)` injects `err` into the suspended `shift(...)` site.

The current implementation is intentionally narrower than the end-state plan:

- Suspensions are one-shot only.
- Unresolved suspensions keep `Runtime.deinitChecked()` busy until they are resumed or discontinued.
- `NoShiftGuard` is an in-place owner handle for regions where suspension is forbidden.
- `Runtime` seals to the first stable owner address that uses it; copied runtime aliases fail with `error.RuntimeAliased`.
- `Suspension` owner handles reject copied aliases with `error.SuspensionAliased`.
- The runtime is still experimental and does not recover from actual guard-page stack overflow faults.

## Build

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
zig build size-check
zig build docs-sanity
zig build bench
zig build bench-first-suspend
```

`zig build bench` runs the current no-capture reset benchmark in `ReleaseFast`.
`zig build bench-first-suspend` runs the current first-suspend benchmark in `ReleaseFast`.

## Examples

```bash
zig build run-generator
zig build run-effect-state
zig build run-effect-handlers
```

Expected outputs:

- `run-generator`: yields `1`, `2`, `3`, then reports `done=3`
- `run-effect-state`: prints `answer=42 resumed=41`
- `run-effect-handlers`: prints `aborted=yes trace=[enter, before-abort]`

## Minimal Example

```zig
const shift = @import("shift");
const std = @import("std");

const demo_spec = struct {
    /// Prompt tag.
    pub const tag = struct {};
    /// Outbound request type.
    pub const Request = i32;
    /// Resume value type.
    pub const Resume = i32;
    /// Final answer type.
    pub const Answer = i32;
    /// User error surface.
    pub const ErrorSet = error{};
};

const demo = struct {
    fn body() shift.ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
        const value = try shift.shift(demo_spec, 41);
        return value + 1;
    }
};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var step = try shift.reset(demo_spec, &runtime, demo.body);
    while (true) switch (step) {
        .complete => |answer| {
            _ = answer;
            break;
        },
        .suspended => |*suspension| {
            step = try suspension.resumeWith(suspension.request);
        },
    };
}
```

See `docs/semantics.md`, `docs/zero_cost.md`, and `docs/research.md` for the current contract.
