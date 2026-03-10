# Current Law Set

This document treats the repo as a semantic object, not just an implementation.
The witness that anchors the whole research packet is delayed escaped-owner resolution.

## Problem Frame

- Boundary: the nearest active `reset(Spec, ...)` for `Spec.tag`.
- Captured slice: the rest of the current reset-delimited computation from `shift(Spec, request)` to that boundary.
- Reinstatement: `resumeWith`, `proceed`, `discontinue`, and `cancel` all re-enter the same delimiter story; `EscapedOwner` delays the choice without changing one-shot ownership.
- Observable witness: a pending owner can be escaped, resumed later, suspend again inside the same delimiter, and still reject copied aliases or cancellation recovery.

## Concrete Witness

1. A body executes `shift(Spec, 41)` and yields `Outcome.pending`.
2. The caller promotes that pending owner with `escape()`.
3. The caller later resolves the escaped owner with `resumeWith(41)`.
4. The resumed body continues inside the same delimiter and can yield a second pending owner, proving the resumed work is re-delimited rather than detached.
5. Reusing the original pending handle fails with `error.AlreadyResolved`, and resolving a copied escaped alias fails with `error.OwnerAliased`.

This witness is the smallest repo-local trace that separates delayed escape from both a reusable continuation value and a session-style wrapper.

## Semantic Core

### 1. Delimited capture is prompt-tagged

`shift(Spec, request)` captures to the nearest active delimiter for `Spec.tag`, not merely the nearest enclosing `reset`.
Prompt identity is by per-type marker, so nested resets with different tags can coexist without collisions.

Consequence:
- The runtime supports outer-prompt bubbling through an inner reset when the inner body shifts against an outer tag.

### 2. Suspension produces a one-shot owner

`reset(Spec, ...)` yields `.complete`, `.cancelled`, or `.pending`.
The `.pending` branch is a single unresolved owner, not a reusable continuation value.

Consequence:
- The ordinary semantic unit is an owned pending decision point, not a clonable continuation object.

### 3. Escaped ownership is a delayed form of the same one-shot edge

`Pending.escape()` promotes the unresolved pending edge into `EscapedOwner`.
The owner remains one-shot and thread-affine after the promotion.

Consequence:
- Delayed resolution widens when the decision is taken, not what kind of thing is owned.

### 4. User discontinuation is distinct from runtime cancellation

`discontinue(err)` injects a user-owned `Spec.ErrorSet` branch back into the suspended site.
The body may catch that branch and continue into another pending owner.

Consequence:
- User discontinuation is recoverable control flow, not terminal teardown.

### 5. Runtime cancellation is terminal

`cancel()` marks the target frame as cancellation-required.
If user code tries to convert that cancellation into another pending owner or a normal answer, the runtime produces `error.CancellationRecovered`.

Consequence:
- Cancellation is monotonic. It is not another user-owned branch.

### 6. Forbidden suspension is explicit

`NoShiftGuard` marks regions where suspension is illegal.
`shift(...)` inside such a region fails with `error.ShiftForbidden`.

Consequence:
- The runtime models “do not suspend here” as a semantic boundary, not a comment-level convention.

## Operator Position

The current runtime is closest to a one-shot, stackful refinement of `shift/reset` with two repo-specific extensions:

- explicit linear pending ownership
- library-owned terminal cancellation

Inference from the `shift/reset` sources plus the current tests:

- it is not plain textbook `shift/reset`, because the repo gives cancellation its own terminal law rather than collapsing it into a user branch
- it is not `control/prompt`, because the resumed work stays inside the same reset-delimited story and the repo does not center dynamic-extent operators
- it is not effect handlers as a primary semantic surface, because handlers here are layered on top of pending ownership rather than replacing it

## Minimal State Vocabulary

- delimiter: an active reset frame tagged by `Spec.tag`
- pending owner: an unresolved one-shot owner returned to the caller
- escaped owner: the same unresolved edge after delayed promotion
- resumed branch: a pending or escaped owner resolved by `resumeWith(value)` or `proceed()`
- discontinued branch: a pending or escaped owner resolved with a user error
- cancelled branch: a pending or escaped owner resolved by terminal runtime cancellation
- guarded region: a dynamic extent where capture is forbidden

## Repository Application

- The core escaped-owner witness lives in `src/raw_surface.zig` and should remain the first proof lane for any future API argument.
- The outer-prompt bubbling tests explain prompt-tagged capture; the cancellation and discontinue tests explain why the repo cannot flatten all terminal behavior into one branch.
- Any future ergonomic wrapper has to preserve the ordinary/advanced split: normal pending resolution first, explicit delayed escape second.

## Sources

- `[DC-AC-1990]` Danvy and Filinski, *Abstracting Control* (canonical `shift/reset` rule family): https://doi.org/10.1145/91556.91622
- `[DC-DYN-2005]` Biernacki, Danvy, and Shan, *On the Dynamic Extent of Delimited Continuations* (static versus dynamic delimitation): https://doi.org/10.1016/j.ipl.2005.04.003
- `[DC-DIRECT-2002]` Gasbichler and Sperber, *Final shift for call/cc* (direct runtime implementation evidence): https://doi.org/10.1145/581478.581504
- `[RT-ONE-SHOT-1996]` Bruggeman, Waddell, and Dybvig, *Representing Control in the Presence of One-Shot Continuations* (one-shot runtime opportunity): https://doi.org/10.1145/231379.231395
