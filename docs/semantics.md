# Semantics

`shift` currently claims the `CoreSR-SAT` rung: a same-answer-type direct-style one-shot typed `shift/reset` subset.

The branch target beyond this rung is `CoreSR-Full`, whose prompt surface is
`Prompt(InAnswer, OutAnswer, ErrorSet)`. The currently exercised runtime path
is the diagonal `Prompt(Answer, Answer, ErrorSet)` case.

## What is true today

- `Prompt(InAnswer, OutAnswer, ErrorSet).init()` creates a first-class delimiter value.
- `reset(&runtime, &prompt, ...)` installs that specific prompt value as the active delimiter.
- `shift(Resume, &prompt, handler)` captures to the nearest active reset for that prompt value.
- The handler receives an explicit continuation argument.
- `Continuation.resumeWith(value)` reinstalls the delimiter and makes the suspended `shift(...)` expression evaluate to `value`.
- Handlers may either:
  - resume the continuation exactly once, or
  - return the enclosing `Answer` directly without resuming
- Prompt identity is collision-free per prompt value.
- Two prompt values of the same prompt type are still distinct delimiters.
- User errors remain explicit through `ControlError(ErrorSet)` and `ResetError(ErrorSet)`.
- The public prompt surface now carries both `InAnswer` and `OutAnswer`.

## What is intentionally not true yet

- no delayed escape surface
- no public cancel/discontinue control branches
- no public helper-led control surface
- no claim of multi-shot continuations
- no claim that the current rung is the final kernel
- unsupported non-diagonal paths still fail closed while only witness-backed non-diagonal execution is implemented

## Operational Model

1. `Runtime.init` creates a thread-affine stackful runtime.
2. `reset` allocates or reuses a stack and runs the body on that stack.
3. `shift` captures the current continuation up to the nearest matching prompt value.
4. The handler either resumes the continuation with `resumeWith` or returns an enclosing answer directly.
5. The reset returns the final `Answer` or a typed user error.

## Hard Witness Order

1. re-delimitation and static-vs-dynamic extent
2. multi-prompt separation
3. one-shot double-resume misuse
4. answer-type pressure
5. evaluator-to-machine trace correspondence

The full typed `shift/reset` kernel with honest ATM remains the destination after this rung.

## Errors

- `error.AlreadyResolved`: the continuation was resumed already
- `error.CrossThread`: runtime or continuation use crossed threads
- `error.MissingPrompt`: `shift` ran without a matching active `reset`
- `error.RuntimeBusy`: runtime teardown happened while a reset was active
- `error.RuntimeDestroyed`: the runtime was torn down already
