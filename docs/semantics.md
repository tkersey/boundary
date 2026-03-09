# Semantics

`shift` currently implements a one-shot, fiber-backed `shift/reset` subset.

## What is true today

- `reset(Tag, Answer, ErrorSet, ...)` runs `body` on a separate stack and installs a dynamic delimiter identified by `Tag`.
- `shift(Resume, Tag, Answer, ErrorSet, handler)` captures to the nearest active delimiter for `Tag` on the current reset frame.
- Calling `Continuation.resumeWith(value)` reinstalls that delimiter and makes the suspended `shift` expression evaluate to `value`.
- Calling `Continuation.discontinue(err)` resumes the suspended frame in error mode and propagates `err`.
- Handlers must consume the continuation exactly once. Returning from a handler without consuming it raises `error.ContinuationNotConsumed`.
- `NoShiftGuard` rejects suspension with `error.ShiftForbidden`.
- `NoShiftGuard.leaveChecked()` returns `error.CrossThread` or `error.AlreadyResolved` on misuse.
- `Runtime.deinitChecked()` returns `error.RuntimeBusy` if called while a reset is active or a guard is still held, and `error.RuntimeDestroyed` on a second teardown or later reuse.
- The public surface exposes `shift.ControlError(ErrorSet)` and `shift.ResetError(ErrorSet)` so user errors stay explicit instead of collapsing to `anyerror`.
- Prompt matching is collision-free per `Tag` type and no longer depends on hashing `@typeName(Tag)`.

## What is intentionally not true yet

- The runtime is still experimental and does not recover from actual guard-page stack overflow faults.

## Operational model

1. `Runtime.init` creates a thread-affine runtime and stack cache.
2. `reset` allocates or reuses a stack, switches to that fiber, and runs `body`.
3. `shift` packages the suspended frame plus handler into a one-shot continuation record and switches back to the parent context.
4. The parent context invokes the handler.
5. `resumeWith` or `discontinue` drives the suspended frame to completion and returns the enclosing `Answer` or error.

## Errors

- `error.AlreadyResolved`: the continuation was consumed already.
- `error.ContinuationNotConsumed`: the handler returned without resuming or discontinuing.
- `error.CrossThread`: the runtime or continuation was used from a different thread.
- `error.MissingPrompt`: `shift` ran without a matching active `reset`.
- `error.RuntimeBusy`: a checked runtime teardown happened while reset execution or guard ownership was still active.
- `error.RuntimeDestroyed`: the runtime was torn down already and can no longer be entered.
- `error.ShiftForbidden`: `shift` ran while a `NoShiftGuard` was active.
