# Semantics

`shift` currently exposes an ATM-bearing prompt surface with a reopened public
seam:

- `Prompt(Mode, InAnswer, OutAnswer, ErrorSet)`
- no public `Continuation`
- comptime-selected handler protocols

The reopened branch now closes as `SUCCESS` for this seam under the current
two-mode budget and practical witness bar.

## What is true today

- `Prompt(Mode, InAnswer, OutAnswer, ErrorSet).init()` creates a first-class delimiter value.
- `reset(&runtime, &prompt, ...)` installs that specific prompt value as the active delimiter.
- `shift(Resume, &prompt, Handler)` captures to the nearest active reset for that prompt value.
- `PromptMode.resume_then_transform` requires:
  - `pub fn resumeValue() Resume` or `ResetError(ErrorSet)!Resume`
  - `pub fn afterResume(value: InAnswer) OutAnswer` or `ResetError(ErrorSet)!OutAnswer`
- `PromptMode.direct_return` requires:
  - `pub fn directReturn() OutAnswer` or `ResetError(ErrorSet)!OutAnswer`
- The runtime still holds the raw continuation internally, but it is no longer part of the active public API.
- Prompt identity is collision-free per prompt value.
- Two prompt values of the same prompt type are still distinct delimiters.
- User errors remain explicit through `ControlError(ErrorSet)` and `ResetError(ErrorSet)`.
- The public prompt surface now carries both `InAnswer` and `OutAnswer`.

## What is intentionally not true yet

- no delayed escape surface
- no public cancel/discontinue control branches
- no public helper-led control surface
- no claim of multi-shot continuations
- no claim that the reopened protocol surface is the final universal kernel
- unsupported non-diagonal paths still fail closed while only witness-backed non-diagonal execution is implemented

## Operational Model

1. `Runtime.init` creates a thread-affine stackful runtime.
2. `reset` allocates or reuses a stack and runs the body on that stack.
3. `shift` captures the current continuation up to the nearest matching prompt value.
4. `PromptMode` selects the handler protocol at comptime.
5. For `.resume_then_transform`, the runtime resumes internally with `resumeValue()` and then calls `afterResume(...)`.
6. For `.direct_return`, the runtime returns `directReturn()` without exposing a continuation.
7. The reset returns the final `Answer` or a typed user error.

## Hard Witness Order

1. re-delimitation and static-vs-dynamic extent
2. multi-prompt separation
3. one-shot double-resume misuse
4. answer-type pressure
5. evaluator-to-machine trace correspondence

The full typed `shift/reset` kernel with honest ATM remains the destination after this rung.

## Errors

- `error.CrossThread`: runtime or continuation use crossed threads
- `error.MissingPrompt`: `shift` ran without a matching active `reset`
- `error.RuntimeBusy`: runtime teardown happened while a reset was active
- `error.RuntimeDestroyed`: the runtime was torn down already
