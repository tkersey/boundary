# shift

`shift` is a Zig 0.15.2 implementation of one-shot, stackful `shift/reset` with a linear token lifecycle API.

The current runtime is token-driven:

- `shift.reset(Spec, &runtime, body)` runs `body` under `Spec.tag` and returns a `shift.Outcome(Spec)`.
- `shift.shift(Spec, request)` suspends to the nearest active delimiter for `Spec.tag` and yields `request` to the caller.
- `shift.Token(Spec).resumeWith(value)` resumes the owned token exactly once.
- `shift.Token(Spec).discontinue(err)` injects a user-owned `Spec.ErrorSet` error into the suspended `shift(...)` site.
- `shift.Token(Spec).cancel()` issues library-owned terminal cancellation.
- `shift.Token(Spec).deinit()` auto-cancels unresolved tokens.

The current implementation is intentionally narrower than the end-state plan:

- Tokens are one-shot and linear.
- Cancellation is terminal once issued.
- User `discontinue(err)` remains distinct from library cancellation.
- `NoShiftGuard` is an in-place owner handle for regions where suspension is forbidden.
- `Runtime` seals to the first stable owner address that uses it; copied runtime aliases fail with `error.RuntimeAliased`.
- Copied token aliases fail with `error.TokenAliased`.
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

## Examples

```bash
zig build run-generator
zig build run-effect-state
zig build run-effect-handlers
zig build run-job-workflow
```

Expected outputs:

- `run-generator`: yields `1`, `2`, `3`, then reports `done=3`
- `run-effect-state`: prints `cancelled=yes resumed=0`
- `run-effect-handlers`: prints `aborted=yes trace=[enter, before-abort]`

Advanced example:

```bash
zig build run-job-workflow
```

Walkthrough: `docs/job_workflow.md`

Expected output:

```text
scenario=approved
log=queued ingest
log=critical metadata prepared
log=nested audit started
approval=ingest
log=nested audit finished
result=completed

scenario=rejected
log=queued publish
log=critical metadata prepared
approval=publish
log=recovered publish skipped
result=recovered

scenario=cancelled
log=queued cleanup
log=critical metadata prepared
approval=cleanup
result=cancelled
```

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

    var outcome = try shift.reset(demo_spec, &runtime, demo.body);
    while (true) switch (outcome) {
        .complete => |answer| {
            _ = answer;
            break;
        },
        .cancelled => break,
        .token => |*token| {
            outcome = try token.resumeWith(token.request);
        },
    };
}
```

See `docs/semantics.md`, `docs/zero_cost.md`, and `docs/research.md` for the current contract.
