# CoreSR-SAT

`CoreSR-SAT` is the temporary semantic rung for the current live `shift` milestone.

It is **not** the long-term endpoint for the repo.
The long-term destination remains full direct-style typed static `shift/reset`
with honest answer-type modification when the kernel requires it.

`CoreSR-SAT` keeps:

- direct-style `reset` and `shift`
- explicit typed prompt tags
- explicit continuation arguments
- one-shot continuation use
- typed user errors in the host-language embedding

`CoreSR-SAT` defers:

- answer-type-changing witnesses
- delayed escape
- public cancel or discontinue control branches
- helper-led surfaces

## Current Claim

For this rung, the repo only claims semantic support for witness programs where
the captured continuation returns into the same enclosing answer type.

That restriction exists to let the semantics ladder catch up.
It must never be mistaken for the accepted long-term kernel.

## Hard Witness Families

1. static-vs-dynamic extent, with an explicit `control/prompt` contrast
2. multi-prompt separation

## Practical Witness

The only practical witness in this rung is `generator`.

## Promotion Rule

No new runtime semantics may land until each active witness has:

- a law anchor
- an evaluator case
- a runtime case
- a required transcript
- a forbidden transcript when a nearby operator family must be excluded
