# Whole-program coalescing — specification amendment v2.1

Accepted September 25, 2026. This amendment incorporates the user's subsequent
instruction into the version 2.0 specification supplied in attachment
`76f1c36f-9372-40cc-9466-f61061359f29/pasted-text-1.txt`. It supersedes the conflicting
performance and default-enablement criteria in §§10, 15–17, and 20. All other
semantic, safety, compatibility, ownership and integration requirements remain.

## Default and compatibility

`safe` is the ordinary compiler and final-linker default, including typed
authoring, raw source compilation, standalone linker manifests that omit the
option, and Agent's direct and compiled-tool paths. `off` remains an explicit
diagnostic and measurement control. Open-component emission continues to defer
coalescing until final linking. Codec decoding never implicitly optimizes.

Default enablement does not require a speedup or a minimum real-consumer
reduction. Existing validation, named-capture publication checks, nominal
identities, resource authority and dynamic allocation semantics remain required.
Every selected image must independently admit and be no larger than its baseline.
Work exhaustion must return the original validated baseline, never an intermediate
optimization. Image and checkpoint identity rules remain unchanged.

## Bounded performance work

Make a bounded, measurement-driven attempt, retain verified improvements, report
remaining costs, then proceed with correctness and integration. A speedup is
desirable, not required. Additional substantial tuning is follow-up work.

The current compile-time overhead is accepted for this first round. The existing
Agent census's limited reductions are also accepted: all 18 configurations have
unchanged function/constructor counts and only description savings. The former
§16.2 real-consumer value gate is retired; applications must not be inflated to
manufacture a benefit. Preserve measurements and report unchanged cases honestly.

Performance thresholds in the original specification guide investigation and
reporting rather than requiring indefinite tuning. This does not relax capacity
safety, exact semantic work counts, caller-visible errors, ownership, or any
correctness requirement. Do not claim unmeasured runtime or memory improvements.

## Acceptance and delivery

- Run required correctness checks and preserve the semantic coverage of T01–T42.
- Verify ordinary defaults produce the same bytes as explicit `safe` on fixtures
  with actual sharing; keep explicit `off` controls with their original meaning.
- Complete Boundary and Agent integration against authenticated dependencies.
- Report measurements, commands, remaining costs and qualification limits in the
  [implementation evidence](coalescing.md) and [acceptance inventory](coalescing-acceptance.md).
- Keep the authorized publication as draft PRs until the remaining correctness
  and review work is complete. Performance benefit is not a draft-retention gate.

This amendment changes acceptance policy; it does not certify that any outstanding
correctness or integration check has passed.
