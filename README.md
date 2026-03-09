# shift

`shift` is a Zig 0.15.2 implementation of one-shot, stackful `shift/reset`.

The current runtime is direct-style:

- `shift.reset(Tag, Answer, ErrorSet, &runtime, body)` installs a dynamic delimiter and runs `body` on a fiber-backed stack.
- `shift.shift(Resume, Tag, Answer, ErrorSet, handler)` captures to the nearest active `reset` for `Tag` on the current reset frame.
- `Continuation.resumeWith(value)` resumes the captured continuation exactly once.
- `Continuation.discontinue(err)` discontinues the continuation and propagates `err`.

- `NoShiftGuard` marks regions where suspension is forbidden; `leaveChecked()` returns an error instead of trapping on misuse.
- `Runtime.deinitChecked()` returns an error instead of trapping if the runtime is still active or already destroyed.

The current implementation is intentionally narrower than the end-state plan:

- Handlers must consume the continuation exactly once.
- Public APIs now thread an explicit `ErrorSet` through `reset`, `shift`, and `Continuation`.
- Prompt identity is now collision-free per `Tag` type and is implemented as an internal per-type token rather than a hash of the type name.
- The supplied context-switch stubs cover `x86_64` and `aarch64` hosts.

## Build

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
zig build size-check
zig build bench
zig build bench-first-suspend
```

`zig build bench` runs the direct-style no-capture benchmark in `ReleaseFast`.
`zig build bench-first-suspend` runs the direct-style first-suspend benchmark in `ReleaseFast`.

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

const tag = struct {};
const DemoError = error{};

const demo = struct {
    fn handle(k: *shift.Continuation(i32, tag, i32, DemoError)) shift.ResetError(DemoError)!i32 {
        return try k.resumeWith(41);
    }

    fn body() shift.ResetError(DemoError)!i32 {
        const value = try shift.shift(i32, tag, i32, DemoError, handle);
        return value + 1;
    }
};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    const answer = try shift.reset(tag, i32, DemoError, &runtime, demo.body);
    _ = answer;
}
```

See `docs/semantics.md`, `docs/zero_cost.md`, and `docs/research.md` for the current contract.
