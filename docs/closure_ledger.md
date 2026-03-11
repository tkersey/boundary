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
| current prompt-pointer baseline | Alias copies of a continuation should be impossible to type | `test/one_shot_survey/alias_copy_compiles.zig` compiles | fundamental: alias-copy |
| current prompt-pointer baseline | Continuations should not be storable beyond immediate use | `test/one_shot_survey/store_escape_compiles.zig` compiles | fundamental: store-escape |
| typestate-consuming continuation value | Consuming a capability value should prevent duplicate use | `test/one_shot_survey/typestate_consuming_value_compiles.zig` compiles | fundamental: alias-copy |
| consumed-state wrapper transition | State-tagged wrappers should forbid reuse after consumption | `test/one_shot_survey/consumed_state_wrapper_compiles.zig` compiles | fundamental: alias-copy |
| prompt-owned borrowed token | Borrow scoping should prevent storage escape | `test/one_shot_survey/prompt_owned_borrowed_token_compiles.zig` compiles | fundamental: store-escape |
| split-token resume capability | Splitting capability structure should not duplicate resume authority | `test/one_shot_survey/split_token_resume_compiles.zig` compiles | fundamental: alias-copy |
| opaque state capsule | Opaque carrier shape should prevent aliasing | `test/one_shot_survey/opaque_state_capsule_compiles.zig` compiles | non-improving: alias-copy |
| comptime-generated capability wrapper | Generated wrapper families should improve on prior failures | `test/one_shot_survey/comptime_generated_capability_compiles.zig` compiles | non-improving: alias-copy |
| current ATM-bearing prompt surface | Supported non-diagonal execution should be explicit and unsupported direct completion should fail closed | `src/raw.zig` executes `atm_resume_transform` and returns `error.NonDiagonalComplete` on unsupported direct non-diagonal completion | scoped runtime support |

## Survey Stop Rule Outcome

The last two new families:

1. opaque state capsule
2. comptime-generated capability wrapper

only reproduced the existing `alias-copy` failure class. That satisfies the
branch stop rule of two consecutive non-improving new families.

## Branch Closure

This branch now closes as `IMPOSSIBLE` for plain-Zig compile-time one-shot
enforcement under the current CoreSR-Full constraints.

See [impossible_plain_zig.md](impossible_plain_zig.md) for the branch-local
closure package.
