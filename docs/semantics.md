# Semantics

`shift` currently implements one-shot delimited control over managed frames.

- A computation begins on stack.
- If it finishes without suspension, no heap boxing is performed.
- If it suspends, its machine state is boxed and returned as a one-shot continuation.
- Resuming or discarding consumes the owning continuation exactly once.
- If you need extra references to the same suspended continuation, use `alias()` and later `release()` on those aliases.
- `EffectSpec` is the PL-facing name for the primitive; `ControlSpec` remains the lower-level compatibility alias.
- Operations and interpreters stay explicit at the type level instead of disappearing behind a runtime abstraction layer.
- Managed continuations now hang off a heap-backed `Session`.
- `close(.graceful)` blocks new root starts but lets already-live continuation chains keep resuming or discarding.
- `close(.cancel)` runs discard hooks for live continuations once and makes later wrapper use return `error.SessionClosed`.
- `destroy()` releases the scope owner itself; active continuation handles survive as independent continuation cells.
- After `destroy()`, any still-live continuation handle returns `error.SessionDestroyed`.
- Already-resolved handles still return `error.AlreadyResolved` after destroy because terminal state now lives in the continuation control block, not in the session owner.
- Owner `release()` is only valid after the underlying continuation is no longer active; releasing an active owner returns `error.SessionBusy`.
- Alias `release()` is same-thread only and returns `error.CrossThread` when used from the wrong thread.
- `handle()` auto-discards the active owner before propagating a handler error.

The library does not claim arbitrary native-stack capture. Participating computations must be written against the `ControlSpec`-generated `ResumeInput` and `Step` contract.
