# shift

`shift` is a Zig 0.15.2 implementation of one-shot, stackful `shift/reset` with a linear token lifecycle API.

The current runtime is pending-owner-driven:

- `shift.reset(Spec, &runtime, body)` runs `body` under `Spec.tag` and returns a `shift.Outcome(Spec)`.
- `shift.shift(Spec, request)` suspends to the nearest active delimiter for `Spec.tag` and yields `request` to the caller.
- `shift.Pending(Spec).request()` reads the request carried by `Outcome.pending`.
- `shift.Pending(Spec).resumeWith(value)` resolves the current pending owner exactly once.
- `shift.Pending(Spec).discontinue(err)` injects a user-owned `Spec.ErrorSet` error into the suspended `shift(...)` site.
- `shift.Pending(Spec).cancel()` issues library-owned terminal cancellation.
- `shift.Pending(Spec).escape()` promotes the current pending owner into an explicit `shift.EscapedToken(Spec)` for delayed resolution.
- `shift.EscapedToken(Spec).deinit()` auto-cancels unresolved escaped owners.

For workflow-style consumers, the library also exposes a namespaced helper layer:

- `shift.driver.run(Spec, &runtime, body, context, handle)` drives the `shift.Outcome(Spec)` loop for you.
- `shift.driver.Decision(Spec)` encodes `.resume_value`, `.cancel`, and `.discontinue` when `Spec.ErrorSet` is non-empty.
- The pending-owner loop remains the canonical low-level surface; the driver helper is additive rather than a replacement.

The current implementation is intentionally narrower than the end-state plan:

- Pending owners are one-shot and linear.
- Cancellation is terminal once issued.
- User `discontinue(err)` remains distinct from library cancellation.
- `NoShiftGuard` is an in-place owner handle for regions where suspension is forbidden.
- `Runtime` seals to the first stable owner address that uses it; copied runtime aliases fail with `error.RuntimeAliased`.
- Copied escaped-owner aliases fail with `error.TokenAliased`.
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

Benchmark contract:

- `zig build bench` and `zig build bench-first-suspend` now report warmed five-sample medians from a single invocation instead of one cold-start-sensitive timing.
- Steady-state baseline artifacts live in `bench/baselines/direct_style_v2.json`.
- The public-driver regression proof against `HEAD` lives in `bench/baselines/public_driver_perf_proof_v1.json`.
- The pending-owner API follow-up investigation lives in `bench/baselines/pending_owner_api_perf_proof_v2.json`.
- Regenerate `bench/baselines/pending_owner_api_perf_proof_v2.json` with `bench/capture_pending_owner_perf_proof.sh` so the decision uses repeated warmed invocations rather than a single run.

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
        .pending => |*pending| {
            outcome = try pending.resumeWith(pending.request());
        },
    };
}
```

See `docs/semantics.md`, `docs/zero_cost.md`, and `docs/research.md` for the current contract.
The research track now branches into `docs/research_laws.md`, `docs/research_machine.md`, and `docs/research_decision.md`.

## Workflow Helper Example

```zig
const shift = @import("shift");

const workflow_spec = struct {
    pub const tag = struct {};
    pub const Request = []const u8;
    pub const Resume = void;
    pub const Answer = void;
    pub const ErrorSet = error{};
};

const workflow = struct {
    fn body() shift.ResetError(workflow_spec.ErrorSet)!workflow_spec.Answer {
        _ = try shift.shift(workflow_spec, "step");
    }
};

const handler = struct {
    fn handle(_: *@This(), _: workflow_spec.Request) anyerror!shift.driver.Decision(workflow_spec) {
        return .{ .resume_value = {} };
    }
};
```

Use the helper when you want a supported request/response driver loop without taking direct pending-owner resolution yourself. The `effect_handlers` and `job_workflow` examples use this layer; the smaller `generator` and `effect_state` examples stay pending-owner-first.
