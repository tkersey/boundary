# shift

`shift` is a Zig 0.15.2 implementation of a temporary same-answer-type direct-style, one-shot, stackful typed `shift/reset` rung.

The live product claim for this rung is:

- `shift.reset(Tag, Answer, ErrorSet, &runtime, body)`
- `shift.shift(Resume, Tag, Answer, ErrorSet, handler)`
- `shift.Continuation(Resume, Tag, Answer, ErrorSet).resumeWith(value)`

The full destination remains a richer typed `shift/reset` kernel with honest ATM if the semantics require it.

The repo currently treats the runtime as the last rung of a semantics ladder:

1. law
2. executable reference witness
3. CPS account
4. defunctionalized machine account
5. optimized stackful runtime

## Semantic Commitments

- static `shift/reset`, not `control/prompt`
- explicit typed prompt tags
- explicit continuation arguments
- one-shot continuation use
- honest answer-type pressure if the kernel requires it
- typed user errors in the host-language embedding

The first two hard witness families are:

- re-delimitation and static-vs-dynamic extent
- multi-prompt separation

## Build

```bash
zig build
zig build test
zig build lint -- --max-warnings 0
zig build size-check
zig build compile-fail
zig build docs-sanity
zig build bench
zig build bench-first-suspend
```

## Examples

```bash
zig build run-generator
zig build run-early-exit
zig build run-nested-workflow
```

Expected outputs:

- `run-generator`: yields `1`, `2`, `3`, then reports `done=3`
- `run-early-exit`: prints `result=early`
- `run-nested-workflow`: prints the locked workflow witness transcript ending in `result=completed`

## Minimal Example

```zig
const shift = @import("shift");
const std = @import("std");

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

See [docs/semantics.md](docs/semantics.md), [docs/research_laws.md](docs/research_laws.md), [docs/research_machine.md](docs/research_machine.md), and [docs/research.md](docs/research.md) for the current ladder.
See [docs/core_sr_sat.md](docs/core_sr_sat.md) for the exact temporary rung claim.
