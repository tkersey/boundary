# ATM Witness Ledger

This ledger tracks the non-diagonal answer-type-modifying witness work on the
`rewrite/core-sr-full` branch.

## Active Witnesses

| Witness | InAnswer | OutAnswer | Resume | Expected transcript | Evaluator | Machine | Runtime | Guard |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `atm_resume_transform` | `i32` | `[]const u8` | `i32` | `handler-enter -> body-after-shift -> handler-after-resume -> final=answer=42` | landed | landed | landed | supported |
| unsupported direct completion | `i32` | `[]const u8` | n/a | runtime returns `error.NonDiagonalComplete` | n/a | n/a | landed | fail-closed |

## Branch Rule

No non-diagonal ATM shape may stop failing closed unless:

1. it has a row here,
2. the evaluator transcript is locked,
3. the reference machine transcript is locked,
4. the runtime transcript matches them.
