# CoreSR-Full

`CoreSR-Full` is the full direct-style typed static `shift/reset` target for
the `rewrite/core-sr-full` branch.

It supersedes the current `CoreSR-SAT` rung.

## Public Surface Shape

The target public shape is:

- `Prompt(Mode, InAnswer, OutAnswer, ErrorSet)`
- `reset(&runtime, &prompt, body) -> ResetError(ErrorSet)!OutAnswer`
- `shift(Resume, &prompt, Handler) -> ControlError(ErrorSet)!Resume`

The important asymmetry is deliberate:

- `shift(...)` still produces the hole type `Resume`
- the handler protocol runs in the enclosing answer type `OutAnswer`
- `.resume_then_transform` still observes the resumed subcontinuation answer type `InAnswer`

That is the branch’s explicit answer-type-modifying target.

The reopened branch now reaches `SUCCESS` on this protocol seam under the
selected two-mode budget and practical witness bar.

## Relationship to CoreSR-SAT

The current live branch surface is already ATM-bearing, but execution is only
partially non-diagonal:

- `Prompt(.resume_then_transform, InAnswer, OutAnswer, ErrorSet)` and
  `Prompt(.direct_return, InAnswer, OutAnswer, ErrorSet)` now exist in code
- the non-diagonal ATM witness and direct-return semantic witness are implemented
- unsupported non-diagonal paths still fail closed

`CoreSR-Full` removes that diagonal restriction.

## Semantic Commitments

- static `shift/reset`, not `control/prompt`
- first-class prompt values
- comptime-selected handler protocols
- one-shot continuation use
- typed user errors in the host-language embedding
- honest public ATM when the calculus requires it

## Out of Scope

- delayed escape
- public cancel/discontinue branches
- helper-led primary surface
- multi-shot continuations
- alternate authoring models outside ordinary Zig
