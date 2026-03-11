# Historical Impossibility Result for the Old Continuation Seam

This document records the earlier `rewrite/core-sr-full` conclusion for the old
public seam that exposed a general continuation-bearing value to ordinary Zig
code.

## Claim

Under the constraints of that seam:

- direct-style prompt-value `shift/reset`
- explicit continuations
- public `Prompt(InAnswer, OutAnswer, ErrorSet)` surface
- one-shot correctness enforced by plain Zig compile-time structure alone
- no hidden verifier
- no alternate authoring model

the branch could not find an ordinary-Zig library encoding that prevents the
core one-shot misuse classes.

## Core Failure Classes

The surveyed families collapsed into two recurring classes:

1. **alias-copy**: wrapper values or capability objects remain copyable, so two
   aliases to the same continuation can coexist
2. **store-escape**: a continuation-bearing value can still be stored or moved
   beyond the intended dynamic use site

These failures are not specific to one prompt encoding. They persisted across:

- typestate-consuming values
- consumed-state wrappers
- prompt-owned borrowed tokens
- split-token resume capabilities
- opaque state capsules
- comptime-generated capability wrappers

## Historical Branch Conclusion

After the planned families and the stop-rule-triggering non-improving
additions, that seam closed as `IMPOSSIBLE` for the plain-Zig route under its
constraint stack.

This is **not** a claim that delimited continuations are impossible in Zig in
general. It is a branch-local conclusion about this stronger goal:

> full direct-style one-shot CoreSR-Full with plain-Zig compile-time one-shot
> enforcement and no hidden external checker

## Repository Consequence Today

- the evidence remains useful as historical branch proof
- it is no longer the active branch truth after the seam rewrite
- the reopened branch must be re-surveyed against the protocol surface before it
  may conclude `IMPOSSIBLE` again
