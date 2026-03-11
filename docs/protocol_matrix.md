# Protocol Matrix

This matrix records the active comptime handler protocols on
`rewrite/core-sr-full`.

| PromptMode | Required handler methods | Allowed operation | Witnesses | Compile-time misuse checks |
| --- | --- | --- | --- | --- |
| `resume_then_transform` | `pub fn resumeValue() Resume` or `ResetError(ErrorSet)!Resume`; `pub fn afterResume(value: InAnswer) OutAnswer` or `ResetError(ErrorSet)!OutAnswer` | internal one-shot resume followed by answer transformation | `atm_resume_transform`, `static_redelim`, `multi_prompt`, `generator`, `nested_workflow` | missing method, wrong signature, wrong mode |
| `direct_return` | `pub fn directReturn() OutAnswer` or `ResetError(ErrorSet)!OutAnswer` | enclosing answer without exposing a continuation | `early_exit` | missing method, wrong signature, wrong mode |

## Branch Rule

No prompt mode becomes active unless:

1. its row exists here,
2. evaluator, machine, and runtime witnesses exist for that mode,
3. compile-time misuse checks exist for that mode.

See [protocol_closure_matrix.md](protocol_closure_matrix.md) for the active
branch closure scoreboard.
