# Public-Surface Decision Dossier

This document chose the next public API direction from the current semantics and machine read. That direction is now the active repo direction.

## Candidates

### Candidate A: refined token-first API

Keep the old `Outcome.token` and `Token(Spec)` model as the main public story, but tighten naming and docs.

Pros:
- Closest to the current runtime
- Preserves delayed-resolution power directly

Cons:
- Keeps the advanced escape case as the everyday user model
- Leaves ordinary linear usage looking more flexible than it really is

Verdict:
- not chosen as the next primary surface

### Candidate B: pending-token primary path with explicit escaped owner

Make the normal public loop revolve around a pending resolution surface, and move delayed resolution into an explicit advanced owner type.

Pros:
- Matches the machine split between ordinary pending resolution and advanced delayed escape
- Preserves current continuation power without forcing every user to think in escape-capability terms
- Gives the cleanest path for compile-time-first linearity pressure in normal code

Cons:
- Breaking public redesign
- Requires careful migration of driver/examples/docs

Verdict:
- chosen

### Candidate C: session-oriented primary API

Reframe the library around a stable session/driver surface and make token ownership secondary or internal.

Pros:
- Potentially friendlier for workflow builders

Cons:
- The current runtime and examples still read token-first
- Risks hiding the repo’s real law set behind a friendlier but less faithful story
- Would be a product pivot before the semantics justify it

Verdict:
- not chosen for the next wave

## Decision

The active breaking public API direction is:

- pending-token-first for normal loops
- explicit escaped-owner for advanced delayed resolution
- driver rebuilt on top of the pending path rather than treated as the semantic center

## Why this wins

- It matches the current law split between ordinary one-shot resolution and advanced escape.
- It preserves the repo’s direct-style identity.
- It supports the desired compile-time-first direction without pretending Zig can make all escaped continuation misuse impossible.
- It keeps the session-object question open for future builder ergonomics without forcing that pivot now.

## Follow-on implementation contract

This implementation wave should:

- replace the everyday `.token` story with a normal pending-resolution story
- keep a named advanced escape surface for resume-later behavior
- preserve user `discontinue` and terminal cancellation as distinct branches
- preserve nested prompt bubbling and `NoShiftGuard`
- keep the current warmed benchmark envelope

## Rejected shortcuts

- Do not jump straight to a session-object primary API because the docs mention workflow builders.
- Do not keep the current token surface untouched just because it is already implemented.
- Do not collapse user discontinuation and terminal cancellation into one public concept.
