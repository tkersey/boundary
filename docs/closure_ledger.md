# Closure Ledger

This ledger records each plain-Zig one-shot encoding family attempted on the
`rewrite/core-sr-full` branch and the current evidence for or against it.

Historical rows from the old public continuation seam remain below as evidence.
The active branch now uses the protocol seam and resets the survey against that
surface.

## Historical General-Continuation Survey

That historical branch could close as `IMPOSSIBLE` only after every planned
family had an entry here with:

- the invariant it was meant to enforce
- the fixture or witness that broke it
- whether the failure is ergonomic, expressive, or fundamental

### Historical Seed Survey

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

### Historical Stop Rule Outcome

The last two new families:

1. opaque state capsule
2. comptime-generated capability wrapper

only reproduced the existing `alias-copy` failure class. That satisfies the
branch stop rule of two consecutive non-improving new families.

## Active Protocol Survey

| Family | Intended invariant | Current evidence | Verdict |
| --- | --- | --- | --- |
| protocol `resume_then_transform` surface | Supported handler protocol should typecheck cleanly | `test/one_shot_survey/protocol_resume_transform_compiles.zig` compiles | active |
| erroring `resume_then_transform` surface | Typed user errors should remain expressible on the protocol seam | `test/one_shot_survey/protocol_erroring_resume_transform_compiles.zig` compiles | active |
| protocol `direct_return` surface | Supported direct-return protocol should typecheck cleanly | `test/one_shot_survey/protocol_direct_return_compiles.zig` compiles | active |
| erroring `direct_return` surface | Typed user errors should remain expressible for direct-return handlers | `test/one_shot_survey/protocol_erroring_direct_return_compiles.zig` compiles | active |
| missing `afterResume` | Incomplete handler protocol should fail at compile time | `test/one_shot_survey/missing_after_resume_fails.zig` fails to compile | active |
| wrong `afterResume` type | Mismatched protocol signature should fail at compile time | `test/one_shot_survey/wrong_after_resume_type_fails.zig` fails to compile | active |
| mode mismatch | Wrong handler protocol for a prompt mode should fail at compile time | `test/one_shot_survey/direct_return_mode_mismatch_fails.zig` fails to compile | active |
| alias-copy recheck on reopened seam | The old public continuation alias seam should remain unavailable | `test/one_shot_survey/legacy_continuation_alias_recheck_fails.zig` fails to compile | active |
| store-escape recheck on reopened seam | The old public continuation storage seam should remain unavailable | `test/one_shot_survey/legacy_continuation_store_recheck_fails.zig` fails to compile | active |

## Branch Closure

The reopened branch now closes as `SUCCESS` on the protocol seam:

- both active prompt modes are supported
- the semantic witness set is green
- generator, early-exit, and nested-workflow are green
- the seam-correct alias-copy and store-escape rechecks now fail at compile time
- no third prompt mode and no public continuation-bearing value were needed
