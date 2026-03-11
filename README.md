# shift

## Purpose

`shift` exists to be a semantics-first Zig implementation of direct-style typed
`shift/reset`.

Branch note:
- `rewrite/core-sr-full` currently concludes the plain-Zig compile-time
  one-shot route is `IMPOSSIBLE` under the branch constraints; see
  [docs/impossible_plain_zig.md](docs/impossible_plain_zig.md)

In the repo's current state, that means two things:

- the live implementation is a temporary same-answer-type direct-style,
  one-shot, stackful typed `shift/reset` rung
- the longer-term destination is a fuller typed `shift/reset` kernel with
  honest answer-type modification if the semantics require it

The repo therefore treats runtime code as the last rung of a semantics ladder,
not as the source of truth:

1. law
2. executable reference witness
3. executable reference machine
4. CPS account
5. optimized stackful runtime

The current live product claim for this rung is:

- `const P = shift.Prompt(InAnswer, OutAnswer, ErrorSet); var prompt = P.init();`
- `shift.reset(&runtime, &prompt, body)`
- `shift.shift(Resume, &prompt, handler)`
- `shift.Continuation(Resume, P).resumeWith(value)`

## Semantic Commitments

- static `shift/reset`, not `control/prompt`
- explicit typed prompt values
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
```

Expected outputs:

- `run-generator`: yields `1`, `2`, `3`, then reports `done=3`

## Minimal Example

```zig
const shift = @import("shift");
const std = @import("std");

const DemoError = error{};
const DemoPrompt = shift.Prompt(i32, i32, DemoError);

const demo = struct {
    var prompt_ptr: ?*const DemoPrompt = null;

    fn handle(k: *shift.Continuation(i32, DemoPrompt)) shift.ResetError(DemoError)!i32 {
        return try k.resumeWith(41);
    }

    fn body() shift.ResetError(DemoError)!i32 {
        const value = try shift.shift(i32, prompt_ptr.?, handle);
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

See [docs/semantics.md](docs/semantics.md), [docs/core_sr_full.md](docs/core_sr_full.md), [docs/atm_surface_table.md](docs/atm_surface_table.md), [docs/atm_witness_ledger.md](docs/atm_witness_ledger.md), [docs/research_laws.md](docs/research_laws.md), [docs/research_machine.md](docs/research_machine.md), [docs/research.md](docs/research.md), [docs/closure_ledger.md](docs/closure_ledger.md), and [docs/impossible_plain_zig.md](docs/impossible_plain_zig.md) for the current ladder and branch-closure artifacts.
See [docs/core_sr_sat.md](docs/core_sr_sat.md) for the exact temporary rung claim.
