# Semantics

`shift` currently implements one-shot delimited control over managed frames.

- A computation begins on stack.
- If it finishes without suspension, no heap boxing is performed.
- If it suspends, its machine state is boxed and returned as a one-shot continuation.
- Resuming or discarding consumes that continuation state exactly once.
- If you need multiple wrappers to the same suspended continuation, use `clone()` and later `release()` on the extra handles.
- Managed work now hangs off a heap-backed `Session`.
- `close(.graceful)` blocks new root starts but lets already-live continuation chains keep resuming or discarding.
- `close(.cancel)` runs discard hooks for live continuations once and makes later wrapper use return `error.SessionClosed`.
- `destroy()` releases the session owner itself; active continuation handles survive as independent control blocks.
- After `destroy()`, any still-live continuation handle returns `error.SessionDestroyed`.
- Already-resolved handles still return `error.AlreadyResolved` after destroy because terminal state now lives in the continuation control block, not in the session owner.

The library does not claim arbitrary native-stack capture. Participating computations must be written against the `ControlSpec`-generated `ResumeInput` and `Step` contract.
