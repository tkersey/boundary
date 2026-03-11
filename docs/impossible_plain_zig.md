# Branch-Local Impossibility Result

This document records the `rewrite/core-sr-full` branch conclusion for ordinary
Zig authoring without hidden verifiers or alternate languages.

## Claim

Under the constraints of this branch:

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

## Branch Conclusion

After the planned families and the stop-rule-triggering non-improving additions,
the branch therefore closes as `IMPOSSIBLE` for the plain-Zig route under the
current constraints.

This is **not** a claim that delimited continuations are impossible in Zig in
general. It is a branch-local conclusion about this stronger goal:

> full direct-style one-shot CoreSR-Full with plain-Zig compile-time one-shot
> enforcement and no hidden external checker

## Repository Consequence

- the branch keeps the truthful ATM-bearing surface and witness infrastructure
- the branch does not merge this result to `main`
- the Closure Ledger and ATM Witness Ledger are the operational evidence
- the stop rule has fired because the last two added families reproduced only
  already-seen alias-copy failures
