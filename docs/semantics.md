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

## Contract Matrix

| Spec shape | Pending surface | Escaped surface | Driver surface | Meaning |
|---|---|---|---|---|
| `Resume != void`, non-empty `ErrorSet` | `request`, `resumeWith`, `discontinue`, `cancel`, `escape` | `resumeWith`, `discontinue`, `cancel`, `deinit` | `.resume_value`, `.discontinue`, `.cancel` | Full value-carrying request/response plus user-owned error injection |
| `Resume == void`, non-empty `ErrorSet` | `request`, `proceed`, `discontinue`, `cancel`, `escape` | `proceed`, `discontinue`, `cancel`, `deinit` | `.proceed`, `.discontinue`, `.cancel` | Payloadless resume edge, but user-owned discontinue still exists |
| `Resume != void`, empty `ErrorSet` | `request`, `resumeWith`, `cancel`, `escape` | `resumeWith`, `cancel`, `deinit` | `.resume_value`, `.cancel` | Value-carrying resume without a user-owned error branch |
| `Resume == void`, empty `ErrorSet` | `request`, `proceed`, `cancel`, `escape` | `proceed`, `cancel`, `deinit` | `.proceed`, `.cancel` | Smallest public surface: payloadless resume plus terminal cancellation |

The matrix is part of the contract. Missing methods are deliberate specialization outcomes and are protected by compile-fail and size-check coverage.

## Machine Vocabulary

- delimiter frame: the runtime-owned `ResetFrame(...)` that delimits capture and stores answer, error, and cancellation state
- pending edge: the unresolved `SuspensionRecord(Spec)` that becomes `Outcome.pending`
- machine state: the internal execution state of the active delimiter frame while the runtime is driving it
- machine signal: the internal signal emitted when the active frame suspends back to a parent
- resolution: the terminal choice applied to a pending edge: `resumeWith`/`proceed`, `discontinue`, or `cancel`

## Operational Model

1. `Runtime.init` creates a thread-affine runtime and stack cache.
2. `reset(Spec, ...)` acquires a heap-backed reset frame from the runtime-local frame cache (or allocates one on a cold path), switches to that fiber, and runs `body`.
3. `shift(Spec, request)` allocates a one-shot owner record, suspends the current fiber, and returns control to the caller as `Outcome.pending`.
4. The caller owns the returned pending owner and must resolve it or explicitly promote it to `EscapedOwner`.
5. `resumeWith` or `proceed`, `discontinue`, or `cancel` drive the suspended frame until it completes, yields another pending owner, or reaches terminal cancellation.

## Driver Boundary

- `shift.driver.run(...)` is a helper loop over `shift.Outcome(Spec)`.
- The driver is not a replacement semantic surface for pending ownership.
- The driver must preserve the same cancel/discontinue split as the low-level API.
- The driver must drain an unresolved owner before surfacing a handler-side failure.

## Semantics-To-Proof Matrix

| semantic branch | source of truth | minimum proof |
|---|---|---|
| normal pending resolution | this document + README contract matrix | unit tests for `resumeWith` or `proceed`, plus example coverage |
| user discontinuation | this document + `docs/research_laws.md` | unit test proving `discontinue` propagates user error and can recover into a later pending owner |
| terminal cancellation | this document + `docs/research_laws.md` | unit test proving `cancel()` returns `.cancelled` and cannot recover into another pending owner |
| delayed escape | this document + README | unit tests for `escape`, delayed `resumeWith`/`proceed`, alias rejection, and `deinit()` auto-cancel |
| guarded region | this document + job-workflow docs | unit tests proving `NoShiftGuard` rejects suspension and checked leave rejects misuse |
| additive driver boundary | README + this document + `docs/job_workflow.md` | driver tests for terminal cancel, discontinue propagation, payloadless proceed, repeated pending handling, and handler-failure drain |
| prompt matching and outer bubbling | this document + research docs | tests for prompt-token uniqueness and nested outer-prompt bubbling |
| warmed performance envelope | README + `docs/zero_cost.md` + benchmark proof artifact | `zig build bench`, `zig build bench-first-suspend`, and repeated warmed proof within the documented threshold |

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
