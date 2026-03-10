# Semantics

`shift` currently implements a one-shot, fiber-backed `shift/reset` subset with explicit pending owners and escaped-owner promotion.

## What is true today

- `reset(Spec, ...)` runs `body` on a separate stack and installs a dynamic delimiter identified by `Spec.tag`.
- `reset(Spec, ...)` returns `shift.Outcome(Spec)`:
  - `.complete`: the body finished with `Spec.Answer`
  - `.pending`: the body hit `shift.shift(Spec, request)` and yielded an owned `shift.Pending(Spec)`
  - `.cancelled`: library-owned terminal cancellation completed
- Calling `shift.shift(Spec, request)` captures to the nearest active delimiter for `Spec.tag`, hands `request` to the pending owner, and later evaluates to the value supplied by `resumeWith`, or completes the payloadless proceed transition when `Spec.Resume` is `void`.
- Calling `Pending.resumeWith(value)` reinstalls the delimiter and makes the suspended `shift(...)` expression evaluate to `value` when `Spec.Resume` is non-`void`; `Pending.proceed()` performs the same transition when `Spec.Resume` is `void`.
- Calling `Pending.discontinue(err)` resumes the suspended frame in user-error mode and propagates `err` through the suspended `shift(...)` site when `Spec.ErrorSet` is non-empty.
- Calling `Pending.cancel()` issues library-owned terminal cancellation.
- Calling `Pending.escape()` promotes the current pending owner into `EscapedOwner`.
- Calling `EscapedOwner.resumeWith(value)` resolves delayed ownership when `Spec.Resume` is non-`void`; `EscapedOwner.proceed()` performs the same delayed transition when `Spec.Resume` is `void`.
- Calling `EscapedOwner.deinit()` auto-cancels unresolved escaped owners.
- Pending owners are one-shot. Reusing the same owner returns `error.AlreadyResolved`.
- Copied escaped-owner aliases fail with `error.OwnerAliased`.
- Cancellation is terminal once issued. If user code attempts to convert cancellation into another pending owner or normal answer, the runtime returns `error.CancellationRecovered`.
- `NoShiftGuard` rejects suspension with `error.ShiftForbidden`.
- `NoShiftGuard.leaveChecked()` returns `error.CrossThread` or `error.AlreadyResolved` on misuse.
- `Runtime.deinitChecked()` returns `error.RuntimeBusy` if reset execution, outstanding pending or escaped ownership, or guard ownership are still active, and `error.RuntimeDestroyed` on a second teardown or later reuse.
- The public surface exposes `shift.ControlError(ErrorSet)` and `shift.ResetError(ErrorSet)` so user errors stay explicit instead of collapsing to `anyerror`.
- Prompt matching is collision-free per `Spec.tag` type and no longer depends on hashing `@typeName`.

## What is intentionally not true yet

- The runtime is still experimental and does not recover from actual guard-page stack overflow faults.
- Continuations are not multi-shot.
- The library does not provide a stable session/driver object as the primary public API.

## Operational Model

1. `Runtime.init` creates a thread-affine runtime and stack cache.
2. `reset(Spec, ...)` acquires a heap-backed reset frame from the runtime-local frame cache (or allocates one on a cold path), switches to that fiber, and runs `body`.
3. `shift(Spec, request)` allocates a one-shot owner record, suspends the current fiber, and returns control to the caller as `Outcome.pending`.
4. The caller owns the returned pending owner and must resolve it or explicitly promote it to `EscapedOwner`.
5. `resumeWith` or `proceed`, `discontinue`, or `cancel` drive the suspended frame until it completes, yields another pending owner, or reaches terminal cancellation.

## Errors

- `error.AlreadyResolved`: the same pending or escaped owner was used already.
- `error.Cancelled`: the runtime injected library-owned cancellation into the suspended site.
- `error.CancellationRecovered`: user code attempted to convert library cancellation into another pending owner or a normal answer.
- `error.CrossThread`: the runtime or owner handle was used from a different thread.
- `error.MissingPrompt`: `shift(...)` ran without a matching active `reset`.
- `error.OutOfMemory`: the runtime could not allocate an owner record.
- `error.RuntimeAliased`: a copied runtime alias attempted to use or tear down state owned by another stable runtime instance.
- `error.RuntimeBusy`: a checked runtime teardown happened while reset execution, pending or escaped ownership, or guard ownership was still active.
- `error.RuntimeDestroyed`: the runtime was torn down already and can no longer be entered.
- `error.ShiftForbidden`: `shift(...)` ran while a `NoShiftGuard` was active.
- `error.OwnerAliased`: a copied escaped-owner alias attempted to resolve a one-shot owner held by a different handle.
