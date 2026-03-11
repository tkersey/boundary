# API

`shift` now ships one explicit first-order machine model.

## Core Types

- `shift.Prompt(Request, Resume).init()`
- `shift.Step(Frame, Suspend, Answer)` with union arms:
  - `.complete`
  - `.@"suspend"`
- `shift.Outcome(Machine)` with union arms:
  - `.complete`
  - `.pending`
- `shift.Pending(Machine)`
- `shift.EscapedOwner(Machine)`
- `shift.run(Machine, &runtime, initial_frame)`

## Machine Contract

Each machine defines:

1. `Answer`
2. `Error`
3. `Frame` as a tagged union
4. `Resume` as a tagged union with `start: void`
5. `Suspend` as a tagged union
6. `step(frame, resume)` returning `shift.Step(Frame, Suspend, Answer)`

Each `Suspend` union payload must be a struct with:

- `prompt`
- `request`
- `next`

The matching `Resume` union must include the same tag names as `Suspend`.

## Ordinary Path

1. Call `shift.run(Machine, &runtime, initial_frame)`.
2. If the outcome is `.pending`, inspect `pending.@"suspend"()`.
3. Route on the active suspend arm.
4. Feed the matching resume value back with `pending.@"resume"(...)`.

## Advanced Path

`Pending.escape()` promotes the owned continuation into `EscapedOwner`.
That supports delayed resolution without changing the machine representation.

`EscapedOwner.deinit()` frees owned continuation data directly.

## Runtime Notes

- `Runtime` owns allocator and owner bookkeeping, not stackful continuations.
- `Prompt` identity is per-instance handle identity.
- copied prompt or owner aliases are rejected after first use.
- mismatched resume tags fail with `error.ResumeMismatch`.

## Non-Goals

- no live native-body `reset` / `shift`
- no driver/session surface
- no built-in cancel/discontinue/guard semantics
- no promise that archived experimental materials reflect the live product
