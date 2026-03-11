# shift

## Purpose

`shift` exists to be a semantics-first Zig implementation of direct-style typed
`shift/reset`.

Branch note:
- `rewrite/core-sr-full` now closes as `SUCCESS` on the reopened comptime
  handler protocol seam.
- The old plain-Zig `IMPOSSIBLE` result is historical evidence for the removed
  public continuation seam; see
  [docs/impossible_plain_zig.md](docs/impossible_plain_zig.md).

In the repo's current state, that means two things:

- the live branch surface is prompt-value-based, ATM-bearing, and protocol-driven
- the reopened seam preserves direct-style ordinary Zig without restoring the
  old public continuation handle

The repo therefore treats runtime code as the last rung of a semantics ladder,
not as the source of truth:

1. law
2. executable reference witness
3. executable reference machine
4. CPS account
5. optimized stackful runtime

The current live product claim for this branch is:

- `const P = shift.Prompt(.resume_then_transform, InAnswer, OutAnswer, ErrorSet); var prompt = P.init();`
- `shift.reset(&runtime, &prompt, body)`
- `shift.shift(Resume, &prompt, Handler)`
- the handler protocol is selected by `PromptMode` at comptime
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

See [docs/semantics.md](docs/semantics.md), [docs/core_sr_full.md](docs/core_sr_full.md), [docs/protocol_matrix.md](docs/protocol_matrix.md), [docs/atm_surface_table.md](docs/atm_surface_table.md), [docs/atm_witness_ledger.md](docs/atm_witness_ledger.md), [docs/research_laws.md](docs/research_laws.md), [docs/research_machine.md](docs/research_machine.md), [docs/research.md](docs/research.md), [docs/closure_ledger.md](docs/closure_ledger.md), and [docs/impossible_plain_zig.md](docs/impossible_plain_zig.md) for the current ladder and branch evidence.
See [docs/core_sr_sat.md](docs/core_sr_sat.md) for the exact temporary rung claim.
