# Public-Surface Decision Dossier

The repo already runs on a pending-owner-first surface.
This document no longer chooses between live candidates.
Its job is to state which future public breaks remain allowed once the escaped-owner witness and machine derivation are taken as ground truth.

## Problem Frame

- Boundary: `shift` captures to the nearest active `reset` for `Spec.tag`.
- Captured slice: the rest of the current body until that delimiter.
- Reinstatement: ordinary pending resolution and delayed escaped-owner resolution both re-enter the same delimiter.
- Observable witness: escaped-owner delayed resolution can suspend again, proving that advanced delayed escape is still the same control edge, just resolved later.

## Concrete Witness

The API story must explain this trace without lying:

1. `reset` yields `.pending`
2. caller promotes the pending owner with `escape()`
3. caller resumes the escaped owner later
4. resumed work can yield another `.pending`
5. copied aliases and repeated resolutions still fail

Any future public framing that cannot explain that trace is not faithful to the runtime.

## Proposal Constraints

Future public breaks may improve ergonomics, but they must preserve these constraints:

- ordinary use stays pending-owner-first
- delayed resume-later behavior stays explicit through an advanced escaped-owner surface
- `shift.driver` remains additive and derived from the pending-owner path
- user `discontinue` stays distinct from terminal cancellation
- prompt-tagged bubbling and `NoShiftGuard` remain part of the law set
- the warmed benchmark envelope remains a hard gate

## Candidate Pressure

### Legacy token-first framing

Do not revive a public story that makes the advanced delayed escape case look like the everyday control value.

Reason:
- it blurs the difference between ordinary one-shot pending resolution and advanced delayed ownership

### Session-primary surface

Do not make a stable session object the semantic center of the library in the next wave.

Reason:
- it hides the repo’s actual machine split and invites documentation that overstates what is linear, resumable, or clonable

### `control/prompt` or handler-first reframing

Do not retell the repo as a dynamic-extent or handler-primary system.

Reason:
- the shipped runtime, examples, and tests are still reset-delimited and pending-owner-first

## Repository Application

- README and `docs/semantics.md` should keep teaching the ordinary path as `Outcome.pending` plus resolution methods.
- The research packet should keep the escaped-owner witness as the advanced path that constrains future ergonomic layers.
- Examples may add helpers, but those helpers must not become the semantic source of truth.

## Rejected Shortcuts

- Do not add a friendlier wrapper and then backfill the semantics around it.
- Do not collapse cancel and discontinue into one public terminal branch.
- Do not generalize the repo into a broad effects project just because effect-handler examples exist.

## Sources

- `[DC-AC-1990]` Danvy and Filinski, *Abstracting Control*: https://doi.org/10.1145/91556.91622
- `[DC-DYN-2005]` Biernacki, Danvy, and Shan, *On the Dynamic Extent of Delimited Continuations*: https://doi.org/10.1016/j.ipl.2005.04.003
- `[DEF-AGER-2003]` Ager, Biernacki, Danvy, and Midtgaard, *A Functional Correspondence between Evaluators and Abstract Machines*: https://doi.org/10.1145/888251.888254
- `[RT-ONE-SHOT-1996]` Bruggeman, Waddell, and Dybvig, *Representing Control in the Presence of One-Shot Continuations*: https://doi.org/10.1145/231379.231395
