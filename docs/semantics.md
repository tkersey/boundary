# Semantics

`shift` currently implements a one-shot, fiber-backed `shift/reset` subset with explicit linear tokens.

## What is true today

- `reset(Spec, ...)` runs `body` on a separate stack and installs a dynamic delimiter identified by `Spec.tag`.
- `reset(Spec, ...)` returns `shift.Outcome(Spec)`:
  - `.complete`: the body finished with `Spec.Answer`
  - `.token`: the body hit `shift.shift(Spec, request)` and yielded an owned `shift.Token(Spec)`
  - `.cancelled`: library-owned terminal cancellation completed
- Calling `shift.shift(Spec, request)` captures to the nearest active delimiter for `Spec.tag`, hands `request` to the token owner, and later evaluates to the value supplied by `resumeWith`.
- Calling `Token.resumeWith(value)` reinstalls the delimiter and makes the suspended `shift(...)` expression evaluate to `value`.
- Calling `Token.discontinue(err)` resumes the suspended frame in user-error mode and propagates `err` through the suspended `shift(...)` site.
- Calling `Token.cancel()` issues library-owned terminal cancellation.
- Calling `Token.deinit()` auto-cancels unresolved tokens.
- Tokens are one-shot. Reusing the same owner returns `error.AlreadyResolved`.
- Copied token aliases fail with `error.TokenAliased`.
- Cancellation is terminal once issued. If user code attempts to convert cancellation into another token or normal answer, the runtime returns `error.CancellationRecovered`.
- `NoShiftGuard` rejects suspension with `error.ShiftForbidden`.
- `NoShiftGuard.leaveChecked()` returns `error.CrossThread` or `error.AlreadyResolved` on misuse.
- `Runtime.deinitChecked()` returns `error.RuntimeBusy` if reset execution, outstanding token ownership, or guard ownership are still active, and `error.RuntimeDestroyed` on a second teardown or later reuse.
- The public surface exposes `shift.ControlError(ErrorSet)` and `shift.ResetError(ErrorSet)` so user errors stay explicit instead of collapsing to `anyerror`.
- Prompt matching is collision-free per `Spec.tag` type and no longer depends on hashing `@typeName`.

## What is intentionally not true yet

- The runtime is still experimental and does not recover from actual guard-page stack overflow faults.
- Continuations are not multi-shot.
- The library does not provide a stable session/driver object as the primary public API.

## Operational Model

1. `Runtime.init` creates a thread-affine runtime and stack cache.
2. `reset(Spec, ...)` acquires a heap-backed reset frame from the runtime-local frame cache (or allocates one on a cold path), switches to that fiber, and runs `body`.
3. `shift(Spec, request)` allocates a one-shot token record, suspends the current fiber, and returns control to the caller as `Outcome.token`.
4. The caller owns the returned token and must resume, discontinue, cancel, or deinit it.
5. `resumeWith`, `discontinue`, or `cancel` drive the suspended frame until it completes, yields another token, or reaches terminal cancellation.

## Errors

- `error.AlreadyResolved`: the same token owner was used already.
- `error.Cancelled`: the runtime injected library-owned cancellation into the suspended site.
- `error.CancellationRecovered`: user code attempted to convert library cancellation into another token or a normal answer.
- `error.CrossThread`: the runtime or token was used from a different thread.
- `error.MissingPrompt`: `shift(...)` ran without a matching active `reset`.
- `error.OutOfMemory`: the runtime could not allocate a token record.
- `error.RuntimeAliased`: a copied runtime alias attempted to use or tear down state owned by another stable runtime instance.
- `error.RuntimeBusy`: a checked runtime teardown happened while reset execution, token ownership, or guard ownership was still active.
- `error.RuntimeDestroyed`: the runtime was torn down already and can no longer be entered.
- `error.ShiftForbidden`: `shift(...)` ran while a `NoShiftGuard` was active.
- `error.TokenAliased`: a copied token alias attempted to resolve a one-shot token owned by a different handle.
