# Closure Ledger

This ledger records each plain-Zig one-shot encoding family attempted on the
`rewrite/core-sr-full` branch and the current evidence for or against it.

The branch may close as `IMPOSSIBLE` only after every planned family has an
entry here with:

- the invariant it was meant to enforce
- the fixture or witness that broke it
- whether the failure is ergonomic, expressive, or fundamental

## Current Seed Survey

| Family | Intended invariant | Current evidence | Verdict |
| --- | --- | --- | --- |
| current prompt-pointer baseline | Alias copies of a continuation should be impossible to type | `test/one_shot_survey/alias_copy_compiles.zig` compiles | open |
| current prompt-pointer baseline | Continuations should not be storable beyond immediate use | `test/one_shot_survey/store_escape_compiles.zig` compiles | open |

## Planned Families

1. Typestate-consuming continuation value
2. Consumed-state wrapper transition
3. Prompt-owned borrowed continuation token
4. Split-token resume capability
5. Opaque state capsule with one-way constructors
6. Comptime-generated capability witness family
