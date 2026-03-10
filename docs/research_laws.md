# Current Law Set

This document treats the current repo as a semantic object, not just an implementation.

The target is the runtime as it exists today: one-shot, stackful, prompt-tagged, cancellation-aware, and explicitly linear at the pending-owner surface.

## Law set

### 1. Delimited capture is prompt-tagged

`shift(Spec, request)` captures to the nearest active delimiter for `Spec.tag`, not merely the nearest enclosing `reset`. Prompt identity is by per-type marker, so nested resets with different tags can coexist without collisions.

Consequence:
- The runtime supports outer-prompt bubbling through an inner reset when the inner body shifts against an outer tag.

### 2. Suspension produces a one-shot owner

`reset(Spec, ...)` yields either:
- `.complete`
- `.cancelled`
- `.pending`

The `.pending` branch represents a single unresolved continuation owner. A copied escaped alias is not another owner; it is misuse and fails with `error.TokenAliased`.

Consequence:
- The semantic unit is not a reusable continuation value. It is an owned pending decision point.

### 3. User discontinuation is distinct from runtime cancellation

`discontinue(err)` injects a user-owned `Spec.ErrorSet` branch back into the suspended site. The body may catch that branch and continue into another token.

Consequence:
- User discontinuation is recoverable control flow, not terminal teardown.

### 4. Runtime cancellation is terminal

`cancel()` marks the target frame as cancellation-required. If user code tries to convert that cancellation into another token or a normal answer, the runtime produces `error.CancellationRecovered`.

Consequence:
- Cancellation is a monotonic semantic event. It is not “just another error path.”

### 5. Forbidden suspension is explicit

`NoShiftGuard` marks regions where suspension is illegal. `shift(...)` inside such a region fails with `error.ShiftForbidden`.

Consequence:
- The runtime models “do not suspend here” as a semantic boundary, not a comment-level convention.

### 6. Escaped ownership is allowed

The current pending owner can be promoted into an escaped owner and resumed later. That capability is part of the current semantics, even though the owner remains one-shot and thread-affine.

Consequence:
- Any future API that removes delayed resolution is not merely “cleaner”; it is semantically narrower.

## Operator position

The current runtime is closest to a one-shot, stackful refinement of `shift/reset` with two repo-specific extensions:

- explicit linear pending ownership
- library-owned terminal cancellation

It is *not* well described as:

- plain textbook `shift/reset`, because textbook accounts usually do not include the repo’s terminal cancellation law
- `control/prompt`, because the repo’s documented story is still reset-delimited and the current examples rely on that story
- effect handlers as the primary semantic surface, because handlers here are layered on top of pending ownership rather than replacing it

## Minimal state vocabulary

Use this vocabulary when reasoning about the repo:

- delimiter: an active reset frame tagged by `Spec.tag`
- pending owner: an unresolved one-shot token returned to the caller
- resumed branch: a pending owner resolved with a resume value
- discontinued branch: a pending owner resolved with a user error
- cancelled branch: a pending owner resolved by terminal runtime cancellation
- guarded region: a dynamic extent where capture is forbidden

## Questions this law set answers

- Why does the approved job-workflow path prove outer-prompt bubbling?
- Why can rejection recover but cancellation cannot?
- Why is token aliasing a semantic error rather than an implementation footgun?
- Why should a future public API treat “normal pending resolution” and “advanced delayed escape” as different kinds of use?
