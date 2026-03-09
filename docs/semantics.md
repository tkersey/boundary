# Semantics

`shift` currently implements a one-shot, fiber-backed `shift/reset` subset with explicit suspended steps.

## What is true today

- `reset(Spec, ...)` runs `body` on a separate stack and installs a dynamic delimiter identified by `Spec.tag`.
- `reset(Spec, ...)` returns `shift.Step(Spec)`:
  - `.complete`: the body finished with `Spec.Answer`
  - `.suspended`: the body hit `shift.shift(Spec, request)` and yielded a `shift.Suspension(Spec)`
- Calling `shift.shift(Spec, request)` captures to the nearest active delimiter for `Spec.tag`, hands `request` to the caller, and later evaluates to the value supplied by `resumeWith`.
- Calling `Suspension.resumeWith(value)` reinstalls the delimiter and makes the suspended `shift(...)` expression evaluate to `value`.
- Calling `Suspension.discontinue(err)` resumes the suspended frame in error mode and propagates `err` through the suspended `shift(...)` site.
- Suspensions are one-shot. Reusing the same owner handle returns `error.AlreadyResolved`.
- Copied suspension aliases fail with `error.SuspensionAliased`.
- `NoShiftGuard` rejects suspension with `error.ShiftForbidden`.
- `NoShiftGuard.leaveChecked()` returns `error.CrossThread` or `error.AlreadyResolved` on misuse.
- `Runtime.deinitChecked()` returns `error.RuntimeBusy` if reset execution, outstanding suspensions, or guard ownership are still active, and `error.RuntimeDestroyed` on a second teardown or later reuse.
- The public surface exposes `shift.ControlError(ErrorSet)` and `shift.ResetError(ErrorSet)` so user errors stay explicit instead of collapsing to `anyerror`.
- Prompt matching is collision-free per `Spec.tag` type and no longer depends on hashing `@typeName`.

## What is intentionally not true yet

- The runtime is still experimental and does not recover from actual guard-page stack overflow faults.
- Continuations are not multi-shot.
- There is no compatibility bridge for the older callback-based public API.

## Operational Model

1. `Runtime.init` creates a thread-affine runtime and stack cache.
2. `reset(Spec, ...)` acquires a heap-backed reset frame from the runtime-local frame cache (or allocates one on a cold path), switches to that fiber, and runs `body`.
3. `shift(Spec, request)` allocates a one-shot suspension record, suspends the current fiber, and returns control to the caller as `Step.suspended`.
4. The caller stores, resumes, or discontinues the returned `Suspension`.
5. `resumeWith` or `discontinue` drives the suspended frame until it completes or suspends again.

## Errors

- `error.AlreadyResolved`: the same suspension owner was used already.
- `error.CrossThread`: the runtime or suspension was used from a different thread.
- `error.MissingPrompt`: `shift(...)` ran without a matching active `reset`.
- `error.OutOfMemory`: the runtime could not allocate a suspension record.
- `error.RuntimeAliased`: a copied runtime alias attempted to use or tear down state owned by another stable runtime instance.
- `error.RuntimeBusy`: a checked runtime teardown happened while reset execution, suspension ownership, or guard ownership was still active.
- `error.RuntimeDestroyed`: the runtime was torn down already and can no longer be entered.
- `error.ShiftForbidden`: `shift(...)` ran while a `NoShiftGuard` was active.
- `error.SuspensionAliased`: a copied suspension alias attempted to resolve a one-shot suspension owned by a different handle.
