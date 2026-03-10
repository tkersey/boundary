# CPS Sketch and Defunctionalized Machine

This is not a full proof.
It is the smallest evaluator-to-machine story that explains the runtime the repo already ships.

## Problem Frame

- Boundary: the nearest active reset frame for `Spec.tag`.
- Captured slice: the rest of the current body from `shift(...)` to that reset frame.
- Reinstatement: delayed escape still resumes into the same delimiter, so the resumed computation can suspend again instead of bypassing the machine.
- Observable witness: escape one pending owner, resume it later, and observe that the resumed body yields a second pending owner before completion.

## Concrete Witness

Use this shape as the canonical trace:

1. `body` executes `const first = try shift(Spec, 41);`
2. the caller receives `Outcome.pending`, promotes it with `escape()`, and leaves the direct loop
3. the caller later executes `escaped.resumeWith(41)`
4. `body` continues with `const second = try shift(Spec, first + 1);`
5. the caller observes a second `Outcome.pending` with request `42`

What to observe:

- the captured slice is one-shot, because the original pending handle is consumed by `escape()`
- the resumed work is re-delimited, because it can suspend again through the same reset boundary
- the machine story is about a delayed pending edge, not about inventing a new session object

## Semantic Core

The runtime already exposes three continuation layers:

- a current fiber continuation
- a parent-fiber chain that implements prompt search
- a terminal mode split between normal answer, user discontinuation, and terminal cancellation

That means the repo is already machine-shaped:

- it has an explicit current continuation
- it has an explicit delimiter stack
- it has explicit control-transfer outcomes

## Translation or Representation Sketch

The derivation chain is:

```text
definitional evaluator
-> closure conversion where frame and environment links must become explicit
-> CPS for the delimited control path
-> defunctionalized continuation constructors
-> abstract machine states already visible in the runtime
```

For this repo, the minimum trustworthy mapping is:

- higher-order “what to do after `shift`” -> `SuspensionRecord(Spec)` plus its `resolution`
- higher-order delimiter context -> `ResetFrame(...)`
- higher-order search through enclosing delimiters -> `FiberBase.parent_fiber` plus `prompt_token`

Use these machine states:

- `Running(frame)`
- `Suspended(frame, pending)`
- `DeliverResume(frame, value)`
- `DeliverResume(frame)` for payloadless `proceed`
- `DeliverDiscontinue(frame, err)`
- `DeliverCancel(frame)`
- `Complete(answer)`
- `Failed(err)`

## Repository Application

| Semantic role | Current runtime structure | Why it matters |
|---|---|---|
| Delimiter frame | `ResetFrame(...)` | Delimits capture and stores result/cancellation state |
| Pending edge | `Pending(Spec)` + `EscapedOwner(Spec)` + `SuspensionRecord(Spec)` | Represents one-shot unresolved ownership and explicit delayed escape |
| Prompt identity | `promptToken(Tag)` + `FiberBase.prompt_token` | Explains nested reset bubbling and collision-free matching |
| Current machine state | `FiberBase.machine_state` and `FiberBase.machine_signal` | Makes suspension and return-to-parent explicit |
| Resolution dispatcher | `SuspensionRecord(Spec).resolution` | First-orderizes resume, discontinue, and cancel choices |
| Terminal cancel law | `cancellation_required` + `CancellationRecovered` checks | Prevents cancellation from being reinterpreted as ordinary control flow |
| Guarded region | `NoShiftGuard` + `no_shift_depth` | Encodes forbidden suspension as machine state |

The runtime is therefore already partially defunctionalized.
The important move is not “replace closures with data” in the abstract.
The important move is to name the existing first-order artifacts so future API changes stay faithful to them.

## Implementation Tradeoffs

- One-shot ownership keeps the runtime small and direct, but it forbids multi-shot narratives and makes aliasing a semantic error.
- Explicit escaped owners preserve resume-later power, but they keep advanced delayed resolution visible rather than hiding it behind a driver/session object.
- Terminal cancellation makes the runtime law set sharper, but it means the repo cannot flatten cancel and discontinue into one generic error path.

## Proof or Benchmark Next Steps

- Proof obligation: keep the escaped-owner witness executable, including the “resume later, then suspend again” trace.
- Measurement obligation: retain the warmed benchmark envelope while tightening docs and proof, because this machine story is part of the performance contract for the current runtime shape.

## Sources

- `[DC-AC-1990]` Danvy and Filinski, *Abstracting Control* (base `shift/reset` framing): https://doi.org/10.1145/91556.91622
- `[DEF-DN-2001]` Danvy and Nielsen, *Defunctionalization at Work* (whole-program first-orderization): https://doi.org/10.1145/773184.773202
- `[DEF-AGER-2003]` Ager, Biernacki, Danvy, and Midtgaard, *A Functional Correspondence between Evaluators and Abstract Machines* (evaluator-to-machine derivation chain): https://doi.org/10.1145/888251.888254
- `[DEF-REFUNC-2007]` Danvy and Millikin, *Refunctionalization at Work* (moving back from machine structure): https://doi.org/10.1016/j.scico.2007.10.007
- `[RT-ONE-SHOT-1996]` Bruggeman, Waddell, and Dybvig, *Representing Control in the Presence of One-Shot Continuations* (runtime implications of one-shotness): https://doi.org/10.1145/231379.231395
