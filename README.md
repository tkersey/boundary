# shift

`shift` is a Zig 0.15.2 library for one-shot delimited control with explicit, typed effect interpretation in userland Zig. Managed frames are the implementation boundary, not the headline abstraction.

The current implementation is intentionally explicit:

- `EffectSpec` generates typed effect surfaces at comptime, while `ControlSpec` remains as the lower-level compatibility alias.
- Operations and interpreters stay explicit at the type level instead of disappearing behind a registry.
- No-capture starts stay allocation-free.
- Continuations use linear ownership: `resumeWith()` and `discard()` consume the owner, `alias()` creates extra release-only references, and owner `release()` is reserved for draining non-active tombstones.
- `Session` still names the effect scope lifetime boundary: `close(mode)` changes continuation semantics and `destroy()` releases the scope owner even if copied continuation handles still exist.
- After `Session.destroy()`, outstanding continuations fail cleanly with `error.SessionDestroyed`.
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
zig build run-effect-handlers
```

## Typed Effect Handling

`EffectSpec` is the PL-facing name. The new `effect_handlers` example shows how a single tagged effect surface can be interpreted by a composable chain of environment, state, and trace interpreters without adding a new helper API to `shift` itself.

## Migration

The compatibility `clone()` bridge is gone in the end-state API.

Before:

```zig
var extra = try continuation.clone();
```

After:

```zig
var extra = try continuation.alias();
```

`release()` remains available only for non-active owners and aliases. Active owners must still end in `resumeWith()` or `discard()`.

## Public Surface

- `shift.EffectSpec`: primary PL-facing alias for generating typed effect surfaces.
- `shift.ControlSpec`: compatibility alias for the same low-level primitive.
- `shift.raw.Session`: effect-scope lifetime owner, close modes, active continuation tracking, and explicit destruction.

See `docs/semantics.md`, `docs/zero_cost.md`, and `docs/research.md` for the current contract.
