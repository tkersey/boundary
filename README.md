# shift

`shift` is a Zig 0.15.2 library for one-shot delimited continuations in a managed-frame model.

The current implementation is intentionally explicit:

- Public control families are generated with `ControlSpec` at comptime.
- No-capture starts stay allocation-free.
- Continuations are one-shot handles: `resumeWith()` and `discard()` consume the underlying control state, and copied handles must use `clone()` / `release()` to stay leak-free.
- Session ownership is explicit: `close(mode)` changes continuation semantics and `destroy()` releases the session owner even if copied continuation handles still exist.
- After `Session.destroy()`, outstanding live handles fail cleanly with `error.SessionDestroyed`.
- Managed frames only: the library does not capture arbitrary native Zig stacks.

## Build

```bash
zig build
zig build test
zig build lint -- --fix
zig build lint -- --max-warnings 0
zig build size-check
zig build bench
```

## Examples

```bash
zig build run-effect-state
zig build run-generator
```

## Public Surface

- `shift.ControlSpec`: generates typed prompt, continuation, run-state, and handler helpers.
- `shift.raw.Session`: owns allocator state, close modes, active continuation tracking, and explicit destruction.

See `docs/semantics.md`, `docs/zero_cost.md`, and `docs/research.md` for the current contract.
