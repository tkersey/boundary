# ATM Surface Table

This table is the branch-local anti-drift map for the final public type
surface. Each row names one public type role and the corresponding calculus,
CPS, and runtime meaning it must preserve.

| Surface element | Calculus role | CPS role | Runtime/oracle role | Witness pressure |
| --- | --- | --- | --- | --- |
| `Prompt.Mode` | Selects the legal eliminator for this delimiter | Chooses which continuation eliminator is present in the CPS account | Selects the handler protocol at comptime | protocol misuse survey |
| `Resume` | Type of the hole filled by the captured continuation | Input type to the current continuation | Payload carried into `resumeWith` and back to the suspended `shift(...)` site | static re-delimitation |
| `Prompt.InAnswer` | Answer type of the resumed subcontinuation | Result type of the current continuation after `resumeWith` | Result type produced by `Continuation.resumeWith(...)` | ATM witness |
| `Prompt.OutAnswer` | Enclosing answer type of the delimited computation | Result type of the meta-continuation and handler | Result type of `reset(...)` and handler return | ATM witness |
| `Prompt.ErrorSet` | User-error effect in the host embedding | Error channel threaded through CPS and meta-continuations | `ControlError(ErrorSet)` and `ResetError(ErrorSet)` | typed user-error witness |
| `shift(...)` result | The hole expression result | Input expected by the current continuation | Value reappearing at the suspended site after resumption | static re-delimitation |
| `Handler.resumeValue()` | Chosen resumed input | Input to the current continuation | Value sent into internal `resumeWith(...)` | protocol misuse survey |
| `Handler.afterResume(...)` | Enclosing answer result after resumption | Meta-continuation result after current-continuation completion | Re-delimited resumed path result | ATM witness |
| `Handler.directReturn()` | Enclosing answer result without resumption | Meta-continuation result without current continuation | Direct return path from handler back to `reset(...)` | early-exit witness |
| `reset(...)` return | Delimited computation result | Meta-continuation result | Final runtime answer | practical witnesses |

## Current Runtime Coverage

- full diagonal execution
- witness-backed non-diagonal `resume_then_transform`
- fail-closed unsupported non-diagonal direct completion

## Branch Rule

No survey candidate may claim success unless every row above still has an
explicit representation in:

1. the typed calculus
2. the CPS account
3. the evaluator and reference machine
4. the public Zig surface
