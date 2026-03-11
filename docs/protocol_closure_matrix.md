# Protocol Closure Matrix

This matrix is the active closure scoreboard for `rewrite/core-sr-full`.

| Mode | Semantic witnesses | Practical witnesses | Survey families | Closure status |
| --- | --- | --- | --- | --- |
| `resume_then_transform` | `atm_resume_transform`, `static_redelim`, `multi_prompt` | `generator`, `nested_workflow` | `protocol_resume_transform`, `protocol_erroring_resume_transform`, `missing_after_resume`, `wrong_after_resume_type`, `legacy_alias_recheck`, `legacy_store_recheck` | success |
| `direct_return` | `direct_return` | `early_exit` | `protocol_direct_return`, `protocol_erroring_direct_return`, `direct_return_mode_mismatch` | success |

## Closure Rule

The branch may close as `SUCCESS` only if:

1. every semantic witness listed above is green,
2. every practical witness listed above is green,
3. every survey family listed above has the expected verdict,
4. no third prompt mode is introduced,
5. no public continuation-bearing value is restored.

This branch now satisfies the `SUCCESS` condition on the reopened protocol seam.
