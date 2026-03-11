# CoreSR-Full

`CoreSR-Full` is the full direct-style typed static `shift/reset` target for
the `rewrite/core-sr-full` branch.

It supersedes the current `CoreSR-SAT` rung.

## Public Surface Shape

The target public shape is:

- `Prompt(InAnswer, OutAnswer, ErrorSet)`
- `reset(&runtime, &prompt, body) -> ResetError(ErrorSet)!OutAnswer`
- `shift(Resume, &prompt, handler) -> ControlError(ErrorSet)!Resume`
- `Continuation(Resume, PromptType).resumeWith(value) -> ResetError(ErrorSet)!InAnswer`

The important asymmetry is deliberate:

- `shift(...)` still produces the hole type `Resume`
- the handler runs in the enclosing answer type `OutAnswer`
- `resumeWith(...)` returns the resumed subcontinuation answer type `InAnswer`

That is the branch’s explicit answer-type-modifying target.

## Relationship to CoreSR-SAT

The current live branch surface is the diagonal case:

- `Prompt(Answer, Answer, ErrorSet)` is the only exercised runtime case
- current `resumeWith(...) -> Answer` is still the `InAnswer == OutAnswer` case

`CoreSR-Full` removes that diagonal restriction.

## Semantic Commitments

- static `shift/reset`, not `control/prompt`
- first-class prompt values
- explicit continuation arguments
- one-shot continuation use
- typed user errors in the host-language embedding
- honest public ATM when the calculus requires it

## Out of Scope

- delayed escape
- public cancel/discontinue branches
- helper-led primary surface
- multi-shot continuations
- alternate authoring models outside ordinary Zig
