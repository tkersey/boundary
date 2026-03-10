# CPS Sketch and Defunctionalized Machine

This document does not claim a full proof. It records the machine structure that the current repo already exposes and the minimum CPS/defunctionalization story needed to explain it.

## Working CPS intuition

The current runtime can be read as operating with three layers of continuation structure:

- a current fiber continuation
- a chain of parent fibers that implements prompt search
- a termination mode that distinguishes normal answer, user discontinuation, and terminal cancellation

That means the repo is not just “a callback with a saved stack.” It already behaves like a machine with:

- an explicit current continuation
- an explicit delimiter stack
- explicit control-transfer outcomes

## Defunctionalized machine view

The current runtime already has concrete machine pieces:

- reset frame: the delimited computation plus its result slot and cancellation flag
- suspension record: the pending owner plus resume/discontinue/cancel mode
- fiber base: the current control state, parent link, prompt token, and swap context
- outcome: the caller-visible machine result

The runtime is therefore already partially defunctionalized. The missing research move is not “turn functions into data” in the abstract. The missing move is to state the machine cleanly enough that the public API can be chosen from it.

## Machine states

Use this machine vocabulary:

- `Running(frame)`: executing inside a reset frame
- `Suspended(frame, pending)`: yielded a one-shot owner to the caller
- `DeliverResume(frame, value)`: returning through the pending owner with a resume value
- `DeliverDiscontinue(frame, err)`: returning through the pending owner with a user error
- `DeliverCancel(frame)`: returning through the pending owner with terminal cancellation
- `Complete(answer)`: reset finished normally
- `Failed(err)`: reset finished with a propagated error

## Transition sketch

1. `reset` allocates or reuses a frame and enters `Running(frame)`.
2. `shift` searches upward for the nearest matching prompt token and creates `Suspended(frame, pending)`.
3. Caller chooses exactly one transition from the pending owner:
   - `resumeWith` -> `DeliverResume`
   - `discontinue` -> `DeliverDiscontinue`
   - `cancel` -> `DeliverCancel`
4. The frame runs until it reaches another suspension, completes, or fails.
5. If `DeliverCancel` is active, any attempt to turn that cancellation into a normal answer or another suspension becomes `CancellationRecovered`.

## Correspondence matrix

| Semantic role | Current runtime structure | Why it matters |
|---|---|---|
| Delimiter frame | `ResetFrame(...)` | Delimits capture and stores result/cancellation state |
| Pending owner | `Pending(Spec)` + `EscapedOwner(Spec)` + `SuspensionRecord(Spec)` | Represents one-shot unresolved ownership and explicit delayed escape |
| Prompt identity | `promptToken(Tag)` + `FiberBase.prompt_token` | Explains nested reset bubbling and collision-free matching |
| Current machine state | `FiberBase.state` and `FiberBase.outcome` | Makes suspension/termination explicit |
| Terminal cancel law | `cancellation_required` + `CancellationRecovered` checks | Distinguishes runtime cancellation from user discontinuation |
| Dynamic no-capture region | `NoShiftGuard` + `no_shift_depth` | Encodes forbidden suspension as machine state, not policy prose |

## Why this matters for the next API

This machine read suggests the next public surface should expose two different stories:

- the normal pending-resolution story, which corresponds to `Suspended(frame, pending)`
- the advanced escaped-owner story, which corresponds to persisting the pending machine edge beyond the immediate loop

That is why the follow-on choice is not “token or no token.” The real choice is which machine edge should be first-class for normal users.
