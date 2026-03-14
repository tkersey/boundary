# shift

## Purpose

`shift` exists to be a semantics-first Zig implementation of direct-style typed
`shift/reset`.

In the repo's current state, that means two things:

- the public surface is prompt-value-based, ATM-bearing, and protocol-driven
- the public API preserves direct-style ordinary Zig without exposing a public
  continuation handle

The repo therefore treats runtime code as the last rung of a semantics ladder,
not as the source of truth:

1. law
2. executable reference witness
3. executable reference machine
4. CPS account
5. fiber-backed stackful runtime

The current runtime backend is stackful and supported on `x86_64` and
`aarch64` hosts only. Unsupported hosts fail at compile time; this repo does
not ship a fallback backend.

The current public product claim is:

- `const P = shift.Prompt(.resume_then_transform, InAnswer, OutAnswer, ErrorSet); var prompt = P.init();`
- `shift.reset(&runtime, &prompt, body)`
- `shift.shift(Resume, &prompt, Handler)`
- the handler protocol is selected by `PromptMode` at comptime
- `.resume_or_return` handlers may return `shift.ResumeOrReturn(Resume, OutAnswer)` and still provide `afterResume`
- protocol methods may return either plain values or `ResetError(ErrorSet)!...`

## Semantic Commitments

- static `shift/reset`, not `control/prompt`
- explicit typed prompt values
- comptime-selected handler protocols
- one-shot continuation use
- honest answer-type pressure if the kernel requires it
- typed user errors in the host-language embedding

The first two hard witness families are:

- re-delimitation and static-vs-dynamic extent
- multi-prompt separation

## Build

`zig build test` is the default proof path. It includes the root tests,
transcript-locked witnesses, public-surface size checks, compile-fail misuse
fixtures, the current one-shot survey contract, and exact-output example proof.

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
zig build size-check
zig build compile-fail
zig build one-shot-survey
zig build example-proof
zig build bench
zig build bench-first-suspend
zig build bench-state-effect
```

## Examples

### `direct_return`

```bash
zig build run-early-exit
```

Expected output:

```text
handler-direct-return
final=result=early
```

### `resume_or_return`

```bash
zig build run-resume-or-return
```

Expected output:

```text
branch=return_now
handler-return-now
final=result=early
branch=resume_with
handler-decide-resume
body-after-shift
handler-after-resume
final=answer=42
```

### `resume_then_transform`

```bash
zig build run-nested-workflow
```

Expected output:

```text
workflow=queued
audit=entered
audit=after
approval=publish
workflow=done
result=completed
```

### Extra `resume_then_transform` Example

```bash
zig build run-generator
```

Expected output:

```text
yield=1
yield=2
yield=3
done=3
```

### `state_effect`

```bash
zig build run-state-basic
```

Expected output:

```text
before=5
after=6
final_state=6
value=11
```

## Minimal Example

```zig
const shift = @import("shift");
const std = @import("std");

const DemoError = error{};
const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, DemoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

    const Handle = struct {
        pub fn resumeValue() i32 {
            return 41;
        }

        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };

    fn body() shift.ResetError(DemoError)!i32 {
        const value = try shift.shift(i32, prompt_ptr.?, Handle);
        return value + 1;
    }
};

pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    _ = answer;
}
```

See `src/root.zig` for the public surface, `src/witnesses.zig` for executable
witnesses, `test/witness_corpus_test.zig` and `test/semantic_manifest.zig` for
the locked semantic evidence, and `examples/` for runnable usage.
